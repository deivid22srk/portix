-- ============================================================================
-- PORTIX — 0026: banner dos destaques (carrossel da Início).
--
-- CONTEXTO
--   O carrossel da Início usava a capa (retrato) recortada num card 16:9 —
--   zoom feio e título colidindo com o selo de plataforma. Esta migration
--   cria o campo `banner_url` em `games` (arte 16:9 horizontal, só para os
--   jogos destacados no carrossel) e o repassa por todo o pipeline do feed:
--   `game_cards` → `feed_candidates` → `feed_card` (RPC nova) e `home_feed`
--   (legada, fallback). O app cai para a capa quando o banner é nulo.
-- Idempotente.
-- ============================================================================

alter table public.games add column if not exists banner_url text;

-- ------------------------------------------------------------------ game_cards
-- CREATE OR REPLACE VIEW não permite ADICIONAR colunas; drop + recria
-- (nenhuma outra view depende de game_cards — verificado em pg_depend).
drop view if exists public.game_cards;
create view public.game_cards with (security_invoker = true) as
select
    id,
    slug,
    title,
    year,
    genre,
    developer,
    cover_url,
    banner_url,
    platforms,
    platform_slugs,
    port_count,
    visit_count,
    is_free,
    needs_rom,
    released_on,
    rating_avg,
    rating_count,
    download_count
  FROM games g;

grant select on public.game_cards to anon, authenticated, service_role;

-- ------------------------------------------------------------ feed_candidates
CREATE OR REPLACE FUNCTION public.feed_candidates(p_seed text DEFAULT ''::text, p_seen uuid[] DEFAULT '{}'::uuid[], p_guard integer DEFAULT 2000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
with cfg as (
  select public.feed_weights() as j
),
c as (
  select
    (j->>'popularity')::numeric              as w_pop,
    (j->>'freshness')::numeric               as w_fresh,
    (j->>'quality')::numeric                 as w_qual,
    (j->>'affinity')::numeric                as w_aff,
    (j->>'explore')::numeric                 as w_explore,
    (j->>'repetition')::numeric              as w_rep,
    (j->>'popularity_window_days')::int      as pop_days,
    (j->>'download_half_life_days')::numeric as dl_half,
    (j->>'release_half_life_days')::numeric  as rel_half,
    (j->>'activity_half_life_days')::numeric as act_half,
    (j->>'seen_direct_weight')::numeric      as seen_direct,
    (j->>'rating_prior_count')::numeric      as prior_c,
    (j->>'rating_prior_mean')::numeric       as prior_m
  from cfg
),
-- Popularidade recente: cada download concluído vale menos conforme envelhece
-- (meia-vida de 7 dias). A janela curta mantém a leitura no índice parcial.
-- Popularidade: valor mantido por trigger em `games` com o decaimento
-- restante aplicado aqui (nenhuma varredura de `downloads` na leitura).
recent_downloads as (
  select
    g2.id as game_id,
    g2.recent_pop * exp(
      -greatest(
        extract(epoch from (current_timestamp - g2.recent_pop_at)),
        0
      ) / 86400.0 / (select dl_half from c)
    ) as decayed
  from public.games g2
),
prefs as (
  select * from public.feed_user_preferences()
),
genre_pref as (
  select pr.value as genre, pr.share as share
  from prefs pr where pr.dimension = 'genre'
),
dev_pref as (
  select pr.value as developer, pr.share as share
  from prefs pr where pr.dimension = 'developer'
),
seen_hist as (
  select h.game_id, h.penalty from public.feed_seen_recent() h
),
seen_direct as (
  select unnest(coalesce(p_seen, '{}'::uuid[])) as game_id
),
base as (
  select
    c2.id,
    c2.slug,
    c2.title,
    c2.year,
    c2.genre,
    c2.cover_url,
    c2.banner_url,
    c2.platforms,
    c2.port_count,
    c2.visit_count,
    c2.download_count,
    c2.rating_avg,
    c2.rating_count,
    c2.is_free,
    c2.needs_rom,
    c2.released_on,
    g2.last_activity_on,
    g2.developer,
    coalesce(rd.decayed, 0) as decayed_downloads,
    ((c2.rating_avg * c2.rating_count + (select prior_c from c) * (select prior_m from c))
      / (c2.rating_count + (select prior_c from c))) as bayes_rating,
    case
      when c2.visit_count > 0
      then least(c2.download_count::numeric / c2.visit_count, 1)
      else 0
    end as conversion,
    coalesce(gp.share, 0) as genre_share,
    coalesce(dp.share, 0) as dev_share,
    coalesce(sh.penalty, 0) as seen_penalty,
    exists (select 1 from seen_direct sd where sd.game_id = c2.id) as seen_direct
  from public.game_cards c2
  join public.games g2 on g2.id = c2.id
  left join recent_downloads rd on rd.game_id = c2.id
  left join genre_pref gp on gp.genre = c2.genre
  left join dev_pref dp on dp.developer = g2.developer
  left join seen_hist sh on sh.game_id = c2.id
),
parts as (
  select
    b.*,
    -- Popularidade: janela recente com decaimento (60%) + volume histórico
    -- suavizado por log (25% downloads, 15% visitas). Tudo normalizado em
    -- [0,1) por x/(1+x), então nenhum sinal satura o score sozinho.
    (
      0.60 * (b.decayed_downloads / (1 + b.decayed_downloads))
      + 0.25 * (
        ln((1 + b.download_count)::numeric)
        / (1 + ln((1 + b.download_count)::numeric))
      )
      + 0.15 * (
        ln((1 + b.visit_count)::numeric)
        / (1 + ln((1 + b.visit_count)::numeric))
      )
    ) as pop_score,
    (
      -- `greatest(idade, 0)`: data no futuro (pré-venda ou dado sujo) vale como
      -- "agora" e não faz o exp() explodir — sem isso um jogo anunciado para
      -- 2029 dominava o feed inteiro com score astronômico.
      0.65 * case when b.released_on is not null then
        exp(
          -greatest(
            extract(epoch from (current_timestamp - b.released_on::timestamptz)),
            0
          ) / 86400.0 / (select rel_half from c)
        )
      else 0 end
      + 0.35 * case when b.last_activity_on is not null then
        exp(
          -greatest(
            extract(epoch from (current_timestamp - b.last_activity_on::timestamptz)),
            0
          ) / 86400.0 / (select act_half from c)
        )
      else 0 end
    ) as fresh_score,
    (
      0.70 * (b.bayes_rating / 5.0)
      + 0.30 * (b.conversion / (1 + b.conversion))
    ) as quality_score,
    (
      0.55 * b.genre_share + 0.45 * b.dev_share
    ) as affinity,
    -- Ruído DETERMINÍSTICO em [0,1): a mesma seed dá a mesma ordem dentro da
    -- sessão; uma seed nova dá outra ordem. Não é aleatoriedade solta — ele
    -- entra como JITTER MULTIPLICATIVO sobre o score (ver `final`), então um
    -- jogo fraco não pula na frente de um forte só por sorte.
    (
      (
        (
          hashtextextended(
            b.id::text,
            hashtextextended(coalesce(nullif(p_seed, ''), 'default'), 0)
          )
          % 1000000
        ) + 1000000
      ) % 1000000
    )::numeric / 1000000.0 as noise
  from base b
),
scored as (
  select
    p.*,
    greatest(
      case when p.seen_direct then (select seen_direct from c) else 0 end,
      p.seen_penalty
    ) as repetition,
    (p.genre_share > 0 or p.dev_share > 0) as in_comfort
  from parts p
),
final as (
  select
    s.id,
    s.slug,
    s.title,
    s.year,
    s.genre,
    s.cover_url,
    s.banner_url,
    s.platforms,
    s.port_count,
    s.visit_count,
    s.download_count,
    s.rating_avg,
    s.rating_count,
    s.is_free,
    s.needs_rom,
    s.released_on,
    s.last_activity_on,
    s.developer,
    -- Componentes do score ficam no pool interno (auditoria e seções); o
    -- payload do cliente passa por public.feed_card() e sai enxuto.
    s.in_comfort,
    s.affinity,
    s.pop_score,
    s.fresh_score,
    s.quality_score,
    s.noise,
    s.repetition,
    round(
      (
        greatest(
          (select w_pop from c) * s.pop_score
          + (select w_fresh from c) * s.fresh_score
          + (select w_qual from c) * s.quality_score
          + (select w_aff from c) * s.affinity
          - (select w_rep from c) * s.repetition,
          0
        )
        * (1 + (select w_explore from c) * (2 * s.noise - 1))
      )::numeric,
      4
    ) as score,
    (s.released_on is not null
      and s.released_on >= (current_date - 120)) as is_new,
    (s.last_activity_on is not null
      and s.last_activity_on >= (current_date - 60)) as is_updated
  from scored s
  order by score desc, id
  limit greatest(least(coalesce(p_guard, 2000), 5000), 1)
)
select coalesce(jsonb_agg(to_jsonb(f) order by f.score desc, f.id), '[]'::jsonb)
from final f;
$function$;

-- ------------------------------------------------------------------ feed_card
CREATE OR REPLACE FUNCTION public.feed_card(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select jsonb_build_object(
    'id',             p->'id',
    'slug',           p->'slug',
    'title',          p->'title',
    'year',           p->'year',
    'genre',          p->'genre',
    'cover_url',      p->'cover_url',
    'banner_url',     p->'banner_url',
    'platforms',      p->'platforms',
    'port_count',     p->'port_count',
    'visit_count',    p->'visit_count',
    'download_count', p->'download_count',
    'rating_avg',     p->'rating_avg',
    'rating_count',   p->'rating_count',
    'is_free',        p->'is_free',
    'needs_rom',      p->'needs_rom',
    'released_on',    p->'released_on',
    'developer',      p->'developer',
    'score',          p->'score',
    'is_new',         p->'is_new',
    'is_updated',     p->'is_updated'
  );
$function$;

-- ----------------------------------------------------------------- home_feed
CREATE OR REPLACE FUNCTION public.home_feed(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
select jsonb_build_object(
  'trending', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.banner_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'recent', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.banner_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.released_on is not null
      order by c.released_on desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'top_rated', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.banner_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.rating_count > 0
      order by c.rating_avg desc, c.rating_count desc, c.visit_count desc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'free', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.banner_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.is_free
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'classics', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.banner_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.year is not null and c.year <= 2000
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'platforms', (
    select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from (
      select pl.slug, pl.name, pl.kind, count(po.id)::int as port_count
      from public.platforms pl
      left join public.ports po on po.platform_id = pl.id
      group by pl.id, pl.slug, pl.name, pl.kind, pl.sort_order
      order by pl.sort_order asc, pl.name asc
    ) p
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
$function$;

-- Recarrega o cache de schema do PostgREST para as novas colunas/RPCs.
notify pgrst, 'reload schema';
