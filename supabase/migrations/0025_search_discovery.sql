-- ============================================================================
-- PORTIX — 0025: busca tolerante (unaccent + pg_trgm), ranking por relevância,
-- paginação por cursor (keyset) e feed agregado da Explorar.
--
-- CAUSA RAIZ RESOLVIDA AQUI (linha de base medida, Postgres 17 local, 839 jogos)
-- A RPC `search_games` (0003) filtra com `ilike '%termo%'` sobre título,
-- desenvolvedor e gênero:
--   • `ilike` é sensível a ACENTO: "Simulacao" devolve 0 resultados, mesmo com
--     70 jogos de gênero "Simulação";
--   • não há tolerância a TYPO: "Jgo 479 Frontier", "Frontir" e "Arenna"
--     devolvem 0 resultados — `extensions.similarity` só pontua, nunca filtra;
--   • paginação por OFFSET: se o catálogo muda entre páginas, resultados se
--     duplicam ou pulam;
--   • `count(*) over()` reconta o total em TODA página;
--   • a Explorar não tinha modo descoberta: nenhuma RPC agregada para seções.
--
-- O QUE ESTA MIGRATION ENTREGA
--   • `extensions.f_unaccent`/`extensions.f_norm` (wrapper IMMUTABLE de
--     unaccent) + índices GIN de trigramas sobre o texto NORMALIZADO de
--     título/desenvolvedor/gênero (case/acento-insensíveis e indexáveis);
--   • `search_games_v2`: filtro tolerante (substring normalizado OU trigramas),
--     ranking em camadas (exato > prefixo > parcial > similaridade) com
--     desempate por popularidade, paginação keyset por cursor (sem duplicata),
--     total contado só na 1ª página e sugestão "Você quis dizer…?" quando não
--     há resultados;
--   • `search_suggest`: sugestões instantâneas (jogos, gêneros, devs,
--     plataformas) numa única chamada;
--   • `explore_feed`: seções da Explorar agregadas (uma chamada por tela,
--     convenção do app): Em alta, Novidades, Mais avaliados, Grátis e
--     "Em alta nas buscas" (decisão conservadora: não existe tabela de termos
--     de busca; usamos views/downloads recentes como proxy — ver client).
--   • RLS: nada muda — tudo SECURITY INVOKER sobre `game_cards` (view
--     security_invoker): as policies de `games` continuam valendo.
--   • As RPCs legadas `search_games`/`home_feed` ficam INTACTAS (fallback).
-- Idempotente.
-- ============================================================================

-- ------------------------------------------------------------------ unaccent
create extension if not exists unaccent with schema extensions;

-- `unaccent()` é STABLE (olha o dicionário); índice exige IMMUTABLE. O wrapper
-- declara imutabilidade — o dicionário é estático em runtime. `f_norm`:
-- minúsculas + sem acento, o mesmo normalizador do lado do filtro e do índice.
create or replace function extensions.f_unaccent(t text)
returns text
language sql
immutable
parallel safe
strict
set search_path = extensions
as $$
  select extensions.unaccent('unaccent'::regdictionary, t)
$$;

create or replace function extensions.f_norm(t text)
returns text
language sql
immutable
parallel safe
strict
set search_path = extensions
as $$
  select lower(extensions.f_unaccent(t))
$$;

-- ------------------------------------------------- índices do texto normalizado
-- GIN de trigramas sobre a MESMA expressão usada no filtro (ilike '%…%' e o
-- operador % de similaridade usam o índice — nenhum seq scan no caminho
-- principal). O índice antigo de title/developer (0001) permanece.
create index if not exists games_title_norm_trgm_idx
  on public.games using gin (extensions.f_norm(title) extensions.gin_trgm_ops);
create index if not exists games_developer_norm_trgm_idx
  on public.games using gin (extensions.f_norm(developer) extensions.gin_trgm_ops)
  where developer is not null;
create index if not exists games_genre_norm_trgm_idx
  on public.games using gin (extensions.f_norm(genre) extensions.gin_trgm_ops)
  where genre is not null;
-- Ordenações keyset (cursor) sem sort em disco nos conjuntos grandes.
create index if not exists games_rating_rank_idx
  on public.games (rating_avg desc, rating_count desc);
create index if not exists games_visit_rank_idx
  on public.games (visit_count desc, id desc);

-- ------------------------------------------------------------------- busca v2
create or replace function public.search_games_v2(
  p_query      text    default null,
  p_platform   text    default null,
  p_genre      text    default null,
  p_free_only  boolean default false,
  p_needs_rom  boolean default false,
  p_min_rating numeric default null,
  p_sort       text    default 'relevance',
  p_limit      int     default 24,
  p_cursor     jsonb   default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
set pg_trgm.similarity_threshold = '0.30'
as $$
declare
  v_term  text := nullif(trim(coalesce(p_query, '')), '');
  v_norm  text := nullif(extensions.f_norm(coalesce(v_term, '')), '');
  v_like  text;         -- padrão LIKE com %/_ escapados
  v_pre   text;         -- prefixo LIKE com %/_ escapados
  v_limit int  := least(greatest(p_limit, 1), 60);
  v_id0   uuid := '00000000-0000-0000-0000-000000000000'::uuid;
  v_has_cursor boolean := p_cursor is not null
    and jsonb_typeof(p_cursor) = 'object' and p_cursor->>'id' is not null;
  v_cur_id uuid := coalesce(nullif(p_cursor->>'id', '')::uuid, v_id0);
  v_cur_a  numeric := coalesce((p_cursor->>'a')::numeric, 0);
  v_cur_b  numeric := coalesce((p_cursor->>'b')::numeric, 0);
  v_cur_t  text    := coalesce(p_cursor->>'t', '');
  v_items  jsonb;
  v_total  bigint  := 0;
  v_cursor jsonb   := null;
  v_suggestion text := null;
  v_more  boolean := false;
begin
  v_like := '%' || replace(replace(replace(v_norm, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  v_pre  := replace(replace(replace(v_norm, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  if p_sort = 'az' then
    -- A–Z: keyset em (título normalizado asc, id asc) — tupla com texto.
    with scored as (
      select c.*,
             case
               when v_norm is null then 0
               when extensions.f_norm(c.title) = v_norm then 3.0
               when extensions.f_norm(c.title) like v_pre then 2.0
               when extensions.f_norm(c.title) like v_like then 1.2
               else extensions.similarity(extensions.f_norm(c.title), v_norm)
             end
             + case when extensions.f_norm(coalesce(c.developer, '')) = v_norm then 0.3
                    when extensions.f_norm(coalesce(c.developer, '')) like v_pre then 0.15
                    else 0 end
             + case when extensions.f_norm(coalesce(c.genre, '')) = v_norm then 0.25
                    else 0 end as score
      from public.game_cards c
      where
        (p_platform is null or p_platform = any(c.platform_slugs))
        and (p_genre is null or c.genre = p_genre)
        and (not coalesce(p_free_only, false) or c.is_free)
        and (not coalesce(p_needs_rom, false) or c.needs_rom)
        and (p_min_rating is null or c.rating_avg >= p_min_rating)
        and (
          v_norm is null
          or extensions.f_norm(c.title) like v_like
          or extensions.f_norm(c.title) % v_norm
          or extensions.f_norm(c.developer) like v_like
          or extensions.f_norm(c.genre) like v_like
        )
    ),
    page as (
      select s.*, extensions.f_norm(s.title) as t_norm,
             case when v_has_cursor then null else count(*) over() end as total_count
      from scored s
      where (not v_has_cursor)
         or (extensions.f_norm(s.title), s.id) > (v_cur_t, v_cur_id)
      order by extensions.f_norm(s.title) asc, s.id asc
      limit v_limit + 1
    ),
    items as (
      select * from page order by t_norm asc, id asc limit v_limit
    )
    select
      coalesce(jsonb_agg(to_jsonb(i) - 'total_count' - 'score' - 't_norm'
                         order by i.t_norm asc, i.id asc), '[]'::jsonb),
      coalesce(max(i.total_count), 0),
      (select count(*) from page) > v_limit,
      (select jsonb_build_object('k', 'az', 't', l.t_norm, 'id', l.id)
         from items l order by l.t_norm asc, l.id asc offset v_limit - 1 limit 1)
    into v_items, v_total, v_more, v_cursor
    from items i;
  else
    with scored as (
      select c.*,
             case
               when v_norm is null then 0
               when extensions.f_norm(c.title) = v_norm then 3.0
               when extensions.f_norm(c.title) like v_pre then 2.0
               when extensions.f_norm(c.title) like v_like then 1.2
               else extensions.similarity(extensions.f_norm(c.title), v_norm)
             end
             + case when extensions.f_norm(coalesce(c.developer, '')) = v_norm then 0.3
                    when extensions.f_norm(coalesce(c.developer, '')) like v_pre then 0.15
                    else 0 end
             + case when extensions.f_norm(coalesce(c.genre, '')) = v_norm then 0.25
                    else 0 end as score
      from public.game_cards c
      where
        (p_platform is null or p_platform = any(c.platform_slugs))
        and (p_genre is null or c.genre = p_genre)
        and (not coalesce(p_free_only, false) or c.is_free)
        and (not coalesce(p_needs_rom, false) or c.needs_rom)
        and (p_min_rating is null or c.rating_avg >= p_min_rating)
        and (
          v_norm is null
          or extensions.f_norm(c.title) like v_like
          or extensions.f_norm(c.title) % v_norm
          or extensions.f_norm(c.developer) like v_like
          or extensions.f_norm(c.genre) like v_like
        )
    ),
    ranked as (
      select s.*,
             case p_sort
               when 'trending' then coalesce(s.visit_count::numeric, 0)
               when 'recent'   then coalesce(extract(epoch from s.released_on)::numeric, 0)
               when 'year'     then coalesce(s.year::numeric, 0)
               when 'rating'   then coalesce(s.rating_avg, 0)
               -- score vem de similarity() (double): arredonda para o cursor
               -- keyset ser EXATO (float na fronteira gerava duplicata).
               else                 round(coalesce(s.score, 0)::numeric, 6) -- relevance
             end as r1,
             case p_sort
               when 'relevance' then coalesce(s.visit_count::numeric, 0)
               when 'rating'    then coalesce(s.rating_count::numeric, 0)
               else 0
             end as r2
      from scored s
    ),
    page as (
      select r.*, case when v_has_cursor then null else count(*) over() end as total_count
      from ranked r
      where (not v_has_cursor)
         or (r.r1, r.r2, r.id) < (v_cur_a, v_cur_b, v_cur_id)
      order by r.r1 desc, r.r2 desc, r.id desc
      limit v_limit + 1
    ),
    items as (
      select * from page order by r1 desc, r2 desc, id desc limit v_limit
    )
    select
      coalesce(jsonb_agg(to_jsonb(i) - 'total_count' - 'score' - 'r1' - 'r2'
                         order by i.r1 desc, i.r2 desc, i.id desc), '[]'::jsonb),
      coalesce(max(i.total_count), 0),
      (select count(*) from page) > v_limit,
      (select jsonb_build_object('k', p_sort, 'a', l.r1, 'b', l.r2, 'id', l.id)
         from items l order by l.r1 desc, l.r2 desc, l.id desc offset v_limit - 1 limit 1)
    into v_items, v_total, v_more, v_cursor
    from items i;
  end if;

  -- "Você quis dizer…?": só na 1ª página, sem resultados, com termo. Compara
  -- PALAVRA a palavra (uma palavra ≥4 letras da busca com palavra do título):
  -- pega "Frintier" → "Frontier" mesmo quando a string inteira não passa.
  if v_norm is not null and not v_has_cursor
     and jsonb_array_length(v_items) = 0 then
    select c.title into v_suggestion
    from public.game_cards c
    where exists (
      select 1
      from unnest(string_to_array(extensions.f_norm(c.title), ' ')) tw,
           unnest(string_to_array(v_norm, ' ')) qw
      where length(qw) >= 4
        and extensions.similarity(tw, qw) >= 0.42
    )
    order by extensions.similarity(extensions.f_norm(c.title), v_norm) desc,
             c.visit_count desc
    limit 1;
  end if;

  return jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'cursor', v_cursor,
    'suggestion', v_suggestion
  );
end;
$$;

-- --------------------------------------------------------------- sugestões
create or replace function public.search_suggest(
  p_query text default null,
  p_limit int default 8
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, extensions
set pg_trgm.similarity_threshold = '0.30'
as $$
declare
  v_term  text := nullif(trim(coalesce(p_query, '')), '');
  v_norm  text := nullif(extensions.f_norm(coalesce(v_term, '')), '');
  v_like  text;
  v_games int;
  v_rest  int;
begin
  v_games := least(greatest(p_limit, 1), 10);
  v_rest  := greatest(v_games / 3, 2);   -- gêneros/devs/plataformas
  v_like  := replace(replace(replace(v_norm, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return jsonb_build_object(
    'games', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.score desc, x.visit_count desc)
      from (
        select c.id, c.slug, c.title, c.year, c.genre, c.developer,
               c.cover_url, c.visit_count,
               case
                 when extensions.f_norm(c.title) = v_norm then 3.0
                 when extensions.f_norm(c.title) like v_like then 2.0
                 else extensions.similarity(extensions.f_norm(c.title), v_norm)
               end as score
        from public.game_cards c
        where v_norm is not null
          and (extensions.f_norm(c.title) like v_like
               or extensions.f_norm(c.title) % v_norm)
        order by score desc, c.visit_count desc
        limit v_games
      ) x
    ), '[]'::jsonb),
    'genres', coalesce((
      select jsonb_agg(to_jsonb(gg) order by gg.game_count desc)
      from (
        select g.genre as name, count(*)::int as game_count
        from public.games g
        where v_norm is not null and g.genre is not null
          and extensions.f_norm(g.genre) like v_like
        group by g.genre
        order by count(*) desc, g.genre asc
        limit v_rest
      ) gg
    ), '[]'::jsonb),
    'developers', coalesce((
      select jsonb_agg(to_jsonb(dd) order by dd.game_count desc)
      from (
        select g.developer as name, count(*)::int as game_count
        from public.games g
        where v_norm is not null and g.developer is not null
          and extensions.f_norm(g.developer) like v_like
        group by g.developer
        order by count(*) desc, g.developer asc
        limit v_rest
      ) dd
    ), '[]'::jsonb),
    'platforms', coalesce((
      select jsonb_agg(to_jsonb(pp) - 'sort_order' order by pp.sort_order asc)
      from (
        select pl.slug, pl.name, pl.kind, pl.sort_order
        from public.platforms pl
        where v_norm is not null
          and (extensions.f_norm(pl.name) like v_like
               or extensions.f_norm(coalesce(pl.full_name, '')) like v_like)
        order by pl.sort_order asc
        limit v_rest
      ) pp
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------- feed agregado da Explorar
-- Uma chamada por tela (convenção do app). Seções vazias voltam como listas
-- vazias e o cliente simplesmente não renderiza.
create or replace function public.explore_feed(p_limit int default 12)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select jsonb_build_object(
  'trending', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.developer, c.cover_url,
             c.platforms, c.platform_slugs, c.port_count, c.visit_count,
             c.is_free, c.needs_rom, c.released_on, c.rating_avg, c.rating_count
      from public.game_cards c
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'new_releases', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.developer, c.cover_url,
             c.platforms, c.platform_slugs, c.port_count, c.visit_count,
             c.is_free, c.needs_rom, c.released_on, c.rating_avg, c.rating_count
      from public.game_cards c
      where c.released_on is not null
      order by c.released_on desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'top_rated', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.developer, c.cover_url,
             c.platforms, c.platform_slugs, c.port_count, c.visit_count,
             c.is_free, c.needs_rom, c.released_on, c.rating_avg, c.rating_count
      from public.game_cards c
      where c.rating_count > 0 and c.rating_avg > 0
      order by c.rating_avg desc, c.rating_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'free', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.developer, c.cover_url,
             c.platforms, c.platform_slugs, c.port_count, c.visit_count,
             c.is_free, c.needs_rom, c.released_on, c.rating_avg, c.rating_count
      from public.game_cards c
      where c.is_free
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  -- "Em alta nas buscas": não existe registro de termos de busca; a opção
  -- mais conservadora é usar a popularidade (views/downloads) como proxy.
  -- Exclui os jogos já exibidos em "Em alta" para não duplicar a seção.
  'popular_searches', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.visit_count
      from public.game_cards c
      where c.id not in (
        select t.id from (
          select g.id from public.game_cards g
          order by g.visit_count desc, g.title asc
          limit least(greatest(p_limit, 1), 20)
        ) t
      )
      order by c.visit_count desc, c.title asc
      limit 10
    ) x
  ),
  'genres', (
    select coalesce(jsonb_agg(to_jsonb(gg)), '[]'::jsonb) from (
      select g.genre as name, count(*)::int as game_count
      from public.games g
      where coalesce(g.genre, '') <> ''
      group by g.genre
      order by count(*) desc, g.genre asc
      limit 16
    ) gg
  ),
  'stats', jsonb_build_object(
    'games', (select count(*) from public.games),
    'ports', (select count(*) from public.ports),
    'platforms', (select count(*) from public.platforms)
  )
);
$$;

-- -------------------------------------------------------------------- grants
grant execute on function public.search_games_v2(text, text, text, boolean, boolean, numeric, text, int, jsonb)
  to anon, authenticated;
grant execute on function public.search_suggest(text, int) to anon, authenticated;
grant execute on function public.explore_feed(int) to anon, authenticated;
