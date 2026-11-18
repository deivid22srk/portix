-- ============================================================================
-- PORTIX — 0023: feed da Início com ranking, diversidade e seed por sessão
--
-- CAUSA RAIZ RESOLVIDA AQUI
-- A RPC `home_feed` (0003 → 0004 → 0018) devolvia cinco listas com ordenação
-- determinística sobre métricas ACUMULADAS e GLOBAIS:
--   trending/free/classics: `order by visit_count desc` — visit_count é um
--   bigint monotônico que nunca decai, então o "mais popular de sempre" ficava
--   cravado no topo para todo mundo, para sempre. Sem parâmetro de usuário, de
--   sessão ou de seed, e sem histórico de exibição, não havia como rotacionar.
-- O cache do cliente amplificava: repintava o mesmo payload a cada abertura e a
-- revalidação devolvia o mesmo resultado, porque o RPC é determinístico.
--
-- O QUE ESTA MIGRATION ENTREGA
--   • Tabela leve de impressões (`feed_impressions`), sem SELECT público.
--   • `get_home_feed(seed, limit, seen, cursor, sections)`: ranking por
--     popularidade COM DECAIMENTO TEMPORAL, frescor, qualidade, afinidade,
--     penalização de repetição e exploração determinística por seed.
--   • Diversidade por seção (≤2 por desenvolvedor, ≤3 por gênero, ≤60% de itens
--     "familiares") e nenhum item repetido entre seções.
--   • Paginação por cursor (keyset) na seção de descoberta, sem offset.
--   • `record_feed_impressions` (escrita) e `purge_feed_impressions` (retenção).
--   • A RPC legada `home_feed` fica INTACTA como fallback do cliente.
-- Fórmula, pesos e como ajustar: docs/feed-algorithm.md. Idempotente.
-- ============================================================================

-- --------------------------------------------------------------- impressões
create table if not exists public.feed_impressions (
  id         bigserial primary key,
  user_id    uuid references auth.users(id) on delete cascade,
  anon_id    uuid,
  game_id    uuid not null references public.games(id) on delete cascade,
  section    text,
  session_id text,
  seen_at    timestamptz not null default now(),
  -- Minimização: ou é de um usuário autenticado, ou de uma instalação anônima.
  constraint feed_impressions_owner_check
    check ((user_id is not null) or (anon_id is not null))
);

comment on table public.feed_impressions is
  'Impressões do feed (card realmente visto na tela). Retenção alvo: 30 dias via public.purge_feed_impressions(). Sem SELECT para o cliente; escrita somente pela RPC record_feed_impressions.';

create index if not exists feed_impressions_anon_idx
  on public.feed_impressions (anon_id, seen_at desc) where anon_id is not null;
create index if not exists feed_impressions_user_idx
  on public.feed_impressions (user_id, seen_at desc) where user_id is not null;
create index if not exists feed_impressions_game_idx
  on public.feed_impressions (game_id, seen_at desc);
create index if not exists feed_impressions_seen_idx
  on public.feed_impressions (seen_at);

alter table public.feed_impressions enable row level security;

-- Sem policy de SELECT/UPDATE/DELETE: a escrita passa pela RPC (security
-- definer). A RLS fica ligada como defesa em profundidade.
drop policy if exists feed_impressions_insert_own on public.feed_impressions;
create policy feed_impressions_insert_own on public.feed_impressions
  for insert to anon, authenticated
  with check (
    (user_id is not null and user_id = auth.uid())
    or (user_id is null and anon_id is not null)
  );

revoke all on public.feed_impressions from anon, authenticated;

-- ------------------------------------------------- índices do caminho quente
-- `top_rated` ordenava por rating_avg sem índice; `download_count` (0018) e
-- `last_activity_on` também caíam em sort. A popularidade com decaimento lê a
-- janela recente de downloads (índice parcial por created_at).
create index if not exists games_rating_idx
  on public.games (rating_avg desc, rating_count desc);
create index if not exists games_download_idx
  on public.games (download_count desc);
create index if not exists games_activity_idx
  on public.games (last_activity_on desc nulls last);
create index if not exists downloads_recent_idx
  on public.downloads (created_at desc) where status = 'done';
create index if not exists downloads_game_recent_idx
  on public.downloads (game_id, created_at desc) where status = 'done';

-- ------------------------------------------------------------- pesos do feed
-- Fonte única dos pesos: a documentação e a simulação leem daqui.
create or replace function public.feed_weights()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'popularity',              1.00,
    'freshness',               0.55,
    'quality',                 0.45,
    'affinity',                0.60,
    'explore',                 0.45,
    'repetition',              0.90,
    -- Janela da popularidade recente: ~5 meias-vidas (7 dias). Além disso a
    -- contribuição de cada download é <2%, então encurtar a janela não muda o
    -- ranking e mantém a leitura no índice parcial de `downloads`.
    'popularity_window_days',  35,
    'download_half_life_days', 7,
    'release_half_life_days',  21,
    'activity_half_life_days', 10,
    'seen_half_life_days',     3,
    'seen_direct_weight',      0.75,
    'rating_prior_count',      5,
    'rating_prior_mean',       3.5,
    'explore_min_share',       0.25,
    -- Tamanho da BANDA de relevância por seção: a seção é montada com os
    -- melhores `band_factor x limit` itens por score e, dentro dessa banda, a
    -- ordem vem do ruído da seed. É o que garante rotação real entre sessões
    -- sem abrir mão da relevância (nunca sai da faixa de melhores).
    'band_factor',             4.0,
    'max_per_developer',       2,
    'max_per_genre',           3,
    'max_familiar_share',      0.60
  );
$$;

comment on function public.feed_weights() is
  'Pesos e constantes do ranking do feed. Ajustar aqui e em docs/feed-algorithm.md; a simulação do CI mede o efeito de cada mudança.';

-- --------------------------------------------- diversidade (unidade pura)
-- Regras de diversidade isoladas e testáveis: não toca tabela, só seleciona de
-- um pool já pontuado, respeitando os tetos e a cota de exploração.
create or replace function public.feed_diversify(
  p_items jsonb,
  p_limit int,
  p_used uuid[] default '{}',
  p_max_developer int default 2,
  p_max_genre int default 3,
  p_max_familiar_share numeric default 0.60,
  p_band_factor numeric default 1.0
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_pool         jsonb;
  v_out          jsonb := '[]'::jsonb;
  v_used         uuid[] := coalesce(p_used, '{}');
  v_dev          jsonb := '{}'::jsonb;
  v_genre        jsonb := '{}'::jsonb;
  v_limit        int := greatest(coalesce(p_limit, 0), 0);
  v_familiar_cap int;
  v_familiar     int := 0;
  v_item         jsonb;
  v_id           uuid;
  v_dev_name     text;
  v_genre_name   text;
  v_affinity     numeric;
begin
  if v_limit = 0 then
    return v_out;
  end if;

  v_familiar_cap :=
    floor(v_limit * least(greatest(coalesce(p_max_familiar_share, 0), 0), 1));

  -- Banda de relevância: pega os melhores `band_factor x limit` por score que
  -- chegaram aqui e reordena pelo ruído da seed. O que o usuário vê continua
  -- sendo o topo do ranking; o que muda entre sessões é QUEM do topo aparece.
  if coalesce(p_band_factor, 1.0) > 1.0 then
    select coalesce(
      jsonb_agg(t.e order by (t.e->>'noise')::numeric desc, t.e->>'id'),
      '[]'::jsonb
    )
    into v_pool
    from (
      select value as e
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
      limit greatest(ceil(v_limit * p_band_factor)::int, v_limit)
    ) t;
  else
    v_pool := coalesce(p_items, '[]'::jsonb);
  end if;

  for v_item in
    select value from jsonb_array_elements(v_pool)
  loop
    exit when jsonb_array_length(v_out) >= v_limit;

    v_id := (v_item->>'id')::uuid;
    continue when v_id = any (v_used);

    v_dev_name := coalesce(nullif(v_item->>'developer', ''), '—');
    v_genre_name := coalesce(nullif(v_item->>'genre', ''), '—');

    continue when coalesce((v_dev->>v_dev_name)::int, 0) >= p_max_developer;
    continue when coalesce((v_genre->>v_genre_name)::int, 0) >= p_max_genre;

    v_affinity := coalesce((v_item->>'affinity')::numeric, 0);

    -- Cota de exploração: no máximo `max_familiar_share` da seção vem da zona
    -- de conforto do usuário; o resto entra por score puro (com ruído da seed).
    continue when v_affinity > 0 and v_familiar >= v_familiar_cap;

    v_out := v_out || jsonb_build_array(v_item);
    v_used := array_append(v_used, v_id);
    v_dev := jsonb_set(
      v_dev,
      array[v_dev_name],
      to_jsonb(coalesce((v_dev->>v_dev_name)::int, 0) + 1),
      true
    );
    v_genre := jsonb_set(
      v_genre,
      array[v_genre_name],
      to_jsonb(coalesce((v_genre->>v_genre_name)::int, 0) + 1),
      true
    );
    if v_affinity > 0 then
      v_familiar := v_familiar + 1;
    end if;
  end loop;

  return v_out;
end;
$$;

-- ------------------------------------- histórico do PRÓPRIO usuário (repetição)
-- SECURITY DEFINER justificado: `feed_impressions` não tem SELECT para o
-- cliente (privacidade). Esta função lê apenas as linhas de `auth.uid()` e não
-- aceita identidade como parâmetro, então não serve para ler histórico alheio.
-- search_path vazio e todos os nomes qualificados.
create or replace function public.feed_seen_recent()
returns table (game_id uuid, penalty numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select
    i.game_id,
    max(
      exp(
        -extract(epoch from (current_timestamp - i.seen_at))
        / 86400.0
        / 3.0
      )
    )::numeric as penalty
  from public.feed_impressions i
  where i.user_id = auth.uid()
    and i.seen_at > current_timestamp - interval '30 days'
  group by i.game_id;
$$;

comment on function public.feed_seen_recent() is
  'Penalidade de repetição do próprio usuário (decaimento de 3 dias, janela de 30). Lê auth.uid() internamente; não aceita identidade de terceiros.';

revoke all on function public.feed_seen_recent() from public;
grant execute on function public.feed_seen_recent() to anon, authenticated;

-- ------------------------------------- popularidade global (agregado puro)
-- SECURITY DEFINER justificado: `downloads` tem SELECT só para `authenticated`
-- (privilégio mínimo, 0005). Esta função devolve apenas a soma decaída POR JOGO
-- — um agregado, nunca uma linha de usuário — então o feed anônimo continua
-- funcionando sem abrir a tabela.
create or replace function public.feed_popularity(
  p_days int default 35,
  p_half_life numeric default 7
)
returns table (game_id uuid, decayed numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select
    d.game_id,
    sum(
      exp(
        -extract(epoch from (current_timestamp - d.created_at))
        / 86400.0
        / greatest(coalesce(p_half_life, 7), 0.5)
      )
    )::numeric as decayed
  from public.downloads d
  where d.status = 'done'
    and d.created_at
        > current_timestamp - make_interval(days => greatest(coalesce(p_days, 35), 1))
  group by d.game_id;
$$;

comment on function public.feed_popularity(int, numeric) is
  'Popularidade recente por jogo (downloads concluídos com decaimento). Agregado puro, para que o feed funcione para anônimo sem dar SELECT em downloads.';

-- ------------------------------------------- preferências do PRÓPRIO usuário
-- SECURITY DEFINER justificado (mesmo motivo acima: favoritos, biblioteca e
-- downloads são só de `authenticated`). Lê apenas `auth.uid()` — não aceita
-- identidade como parâmetro — e devolve shares normalizados + marcadores, nunca
-- as linhas cruas do histórico.
create or replace function public.feed_user_preferences()
returns table (dimension text, value text, share numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with ug as (
    select f.game_id from public.favorites f where f.user_id = auth.uid()
    union
    select l.game_id from public.library l where l.user_id = auth.uid()
    union
    select d.game_id from public.downloads d
     where d.user_id = auth.uid() and d.status = 'done'
  ),
  gp as (
    select g.genre as v, count(*)::numeric as c
    from ug
    join public.games g on g.id = ug.game_id
    where coalesce(g.genre, '') <> ''
    group by g.genre
  ),
  dp as (
    select g.developer as v, count(*)::numeric as c
    from ug
    join public.games g on g.id = ug.game_id
    where coalesce(g.developer, '') <> ''
    group by g.developer
  )
  select
    'has_history',
    '',
    case when exists (select 1 from ug) then 1 else 0 end
  union all
  select 'top_genre', t.v, 1
  from (select v, c from gp order by c desc, v limit 1) t
  union all
  select 'genre', gp.v, gp.c / (select greatest(max(c), 1) from gp) from gp
  union all
  select 'developer', dp.v, dp.c / (select greatest(max(c), 1) from dp) from dp;
$$;

comment on function public.feed_user_preferences() is
  'Afinidade do próprio usuário: shares de gênero/desenvolvedor normalizados em (0,1], mais has_history e o gênero dominante. Lê auth.uid() internamente.';

revoke all on function public.feed_popularity(int, numeric) from public;
revoke all on function public.feed_user_preferences() from public;
grant execute on function public.feed_popularity(int, numeric) to anon, authenticated;
grant execute on function public.feed_user_preferences() to anon, authenticated;

-- ------------------------------------------------------------- candidatos
-- Pontua o catálogo inteiro uma vez por sessão e devolve um array jsonb
-- ordenado por score. Com 839 jogos a agregação em memória é mais barata e
-- sempre fresca que materialized view + cron (justificativa em docs).
create or replace function public.feed_candidates(
  p_seed text default '',
  p_seen uuid[] default '{}',
  p_guard int default 2000
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
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
-- Popularidade e afinidade vêm de funções SECURITY DEFINER que só devolvem
-- agregados do próprio usuário (as tabelas de histórico são `authenticated`).
recent_downloads as (
  select p.game_id, p.decayed
  from public.feed_popularity(
    (select pop_days from c),
    (select dl_half from c)
  ) p
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
      0.65 * case when b.released_on is not null then
        exp(
          -extract(epoch from (current_timestamp - b.released_on::timestamptz))
          / 86400.0 / (select rel_half from c)
        )
      else 0 end
      + 0.35 * case when b.last_activity_on is not null then
        exp(
          -extract(epoch from (current_timestamp - b.last_activity_on::timestamptz))
          / 86400.0 / (select act_half from c)
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
$$;

comment on function public.feed_candidates(text, uuid[], int) is
  'Pontua o catálogo inteiro para uma sessão (seed) e devolve o pool ordenado por score, com os componentes separados para auditoria.';

grant execute on function public.feed_candidates(text, uuid[], int)
  to anon, authenticated;

-- ------------------------------------------------------ projeção do card
-- O pool interno carrega os componentes do score (auditoria, montagem das
-- seções). O cliente recebe só o necessário para desenhar o card.
create or replace function public.feed_card(p jsonb)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id',             p->'id',
    'slug',           p->'slug',
    'title',          p->'title',
    'year',           p->'year',
    'genre',          p->'genre',
    'cover_url',      p->'cover_url',
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
$$;

create or replace function public.feed_projection(p_items jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(
    jsonb_agg(public.feed_card(value)),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb));
$$;

-- ------------------------------------------------------------- feed da Início
create or replace function public.get_home_feed(
  p_seed text default null,
  p_limit int default 12,
  p_seen uuid[] default '{}',
  p_cursor jsonb default null,
  p_sections text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_w          jsonb := public.feed_weights();
  v_seed       text := coalesce(nullif(left(coalesce(p_seed, ''), 64), ''), 'default');
  v_limit      int := least(greatest(coalesce(p_limit, 12), 4), 30);
  v_pool       jsonb;
  v_used       uuid[] := '{}';
  v_sections   jsonb := '[]'::jsonb;
  v_personal   boolean;
  v_reason     jsonb;
  v_genres     text[] := '{}';
  v_items      jsonb;
  v_cursor     jsonb := null;
  v_want       text[] := p_sections;
  v_max_dev    int := (v_w['max_per_developer'])::int;
  v_max_genre  int := (v_w['max_per_genre'])::int;
  v_familiar   numeric := (v_w['max_familiar_share'])::numeric;
  v_band       numeric := (v_w['band_factor'])::numeric;
  v_cursor_sc  numeric;
  v_cursor_id  uuid;
  r_genre      text;
begin
  -- Personalização só existe com histórico de uso. O agregado vem de função
  -- SECURITY DEFINER: as tabelas de histórico têm SELECT só para `authenticated`
  -- e a Início precisa funcionar também para anônimo.
  select coalesce(
    (
      select pr.share
      from public.feed_user_preferences() pr
      where pr.dimension = 'has_history'
    ),
    0
  ) = 1
  into v_personal;

  v_pool := public.feed_candidates(v_seed, coalesce(p_seen, '{}'::uuid[]), 2000);

  if v_want is null then
    v_want := array['featured', 'for_you', 'trending', 'new_releases',
                    'recently_updated', 'discover', 'by_category'];
  end if;

  -- Microcopy da personalização: gênero dominante do histórico do usuário.
  if v_personal then
    select jsonb_build_object('kind', 'genre', 'value', pr.value)
      into v_reason
    from public.feed_user_preferences() pr
    where pr.dimension = 'top_genre';
  end if;

  -- ---------------------------------------------------------------- destaque
  if 'featured' = any (v_want) then
    select public.feed_projection(public.feed_diversify(
      coalesce(
        jsonb_agg(t.e order by (t.e->>'score')::numeric desc, t.e->>'id'),
        '[]'::jsonb
      ),
      least(6, v_limit), v_used, v_max_dev, v_max_genre, v_familiar, v_band
    ))
    into v_items
    from jsonb_array_elements(v_pool) as t(e);

    select v_used || coalesce(
      array_agg((i->>'id')::uuid),
      '{}'::uuid[]
    )
    into v_used
    from jsonb_array_elements(v_items) as x(i);

    v_sections := v_sections || jsonb_build_array(jsonb_build_object(
      'key', 'featured', 'kind', 'hero', 'reason', null,
      'cursor', null, 'items', v_items
    ));
  end if;

  -- --------------------------------------------------------------- para você
  if v_personal and 'for_you' = any (v_want) then
    select public.feed_projection(public.feed_diversify(
      coalesce(
        jsonb_agg(
          t.e order by
            (t.e->>'affinity')::numeric * 0.45
            + (t.e->>'score')::numeric * 0.55 desc,
            t.e->>'id'
        ),
        '[]'::jsonb
      ),
      v_limit, v_used, v_max_dev, v_max_genre, v_familiar, v_band
    ))
    into v_items
    from jsonb_array_elements(v_pool) as t(e)
    where (t.e->>'affinity')::numeric > 0;

    if jsonb_array_length(v_items) > 0 then
      select v_used || coalesce(array_agg((i->>'id')::uuid), '{}'::uuid[])
      into v_used
      from jsonb_array_elements(v_items) as x(i);

      v_sections := v_sections || jsonb_build_array(jsonb_build_object(
        'key', 'for_you', 'kind', 'row', 'reason', v_reason,
        'cursor', null, 'items', v_items
      ));
    end if;
  end if;

  -- ----------------------------------------------------------------- em alta
  if 'trending' = any (v_want) then
    select public.feed_projection(public.feed_diversify(
      coalesce(
        jsonb_agg(
          t.e order by
            (t.e->>'pop_score')::numeric desc,
            (t.e->>'score')::numeric desc,
            t.e->>'id'
        ),
        '[]'::jsonb
      ),
      v_limit, v_used, v_max_dev, v_max_genre, v_familiar, v_band
    ))
    into v_items
    from jsonb_array_elements(v_pool) as t(e);

    select v_used || coalesce(array_agg((i->>'id')::uuid), '{}'::uuid[])
    into v_used
    from jsonb_array_elements(v_items) as x(i);

    v_sections := v_sections || jsonb_build_array(jsonb_build_object(
      'key', 'trending', 'kind', 'row', 'reason', null,
      'cursor', null, 'items', v_items
    ));
  end if;

  -- ---------------------------------------------------------------- novidades
  if 'new_releases' = any (v_want) then
    select public.feed_projection(public.feed_diversify(
      coalesce(
        jsonb_agg(
          t.e order by
            (t.e->>'released_on') desc nulls last,
            (t.e->>'score')::numeric desc,
            t.e->>'id'
        ),
        '[]'::jsonb
      ),
      v_limit, v_used, v_max_dev, v_max_genre, v_familiar, v_band
    ))
    into v_items
    from jsonb_array_elements(v_pool) as t(e)
    where (t.e->>'is_new')::boolean;

    if jsonb_array_length(v_items) > 0 then
      select v_used || coalesce(array_agg((i->>'id')::uuid), '{}'::uuid[])
      into v_used
      from jsonb_array_elements(v_items) as x(i);

      v_sections := v_sections || jsonb_build_array(jsonb_build_object(
        'key', 'new_releases', 'kind', 'row', 'reason', null,
        'cursor', null, 'items', v_items
      ));
    end if;
  end if;

  -- ------------------------------------------------- atualizados recentemente
  if 'recently_updated' = any (v_want) then
    select public.feed_projection(public.feed_diversify(
      coalesce(
        jsonb_agg(
          t.e order by
            (t.e->>'last_activity_on') desc nulls last,
            (t.e->>'score')::numeric desc,
            t.e->>'id'
        ),
        '[]'::jsonb
      ),
      v_limit, v_used, v_max_dev, v_max_genre, v_familiar, v_band
    ))
    into v_items
    from jsonb_array_elements(v_pool) as t(e)
    where (t.e->>'is_updated')::boolean;

    if jsonb_array_length(v_items) > 0 then
      select v_used || coalesce(array_agg((i->>'id')::uuid), '{}'::uuid[])
      into v_used
      from jsonb_array_elements(v_items) as x(i);

      v_sections := v_sections || jsonb_build_array(jsonb_build_object(
        'key', 'recently_updated', 'kind', 'row', 'reason', null,
        'cursor', null, 'items', v_items
      ));
    end if;
  end if;

  -- ------------------------------------------------------------------ descubra
  -- Exploração: itens fora da zona de conforto do usuário. Pagina por cursor
  -- (keyset em score+id), então não há duplicata entre páginas.
  if 'discover' = any (v_want) then
    if p_cursor is not null then
      v_cursor_sc := coalesce((p_cursor->>'score')::numeric, 0);
      v_cursor_id := coalesce((p_cursor->>'id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
    end if;

    select public.feed_projection(public.feed_diversify(
      coalesce(
        jsonb_agg(t.e order by (t.e->>'score')::numeric desc, t.e->>'id'),
        '[]'::jsonb
      ),
      -- Descubra NÃO usa banda: a paginação por cursor exige ordem estável por
      -- (score, id) dentro da seed. A rotação aqui vem do próprio score (que já
      -- carrega o ruído da sessão), não de embaralhar a faixa.
      v_limit, v_used, v_max_dev, v_max_genre, v_familiar, 1.0
    ))
    into v_items
    from jsonb_array_elements(v_pool) as t(e)
    where (not v_personal or not (t.e->>'in_comfort')::boolean)
      and (
        p_cursor is null
        or (t.e->>'score')::numeric < v_cursor_sc
        or (
          (t.e->>'score')::numeric = v_cursor_sc
          and (t.e->>'id')::uuid < v_cursor_id
        )
      );

    if jsonb_array_length(v_items) > 0 then
      select v_used || coalesce(array_agg((i->>'id')::uuid), '{}'::uuid[])
      into v_used
      from jsonb_array_elements(v_items) as x(i);

      -- Cursor da próxima página: o último item emitido, na mesma ordenação.
      v_cursor := jsonb_build_object(
        'score', (v_items->-1->>'score')::numeric,
        'id', v_items->-1->>'id'
      );

      v_sections := v_sections || jsonb_build_array(jsonb_build_object(
        'key', 'discover', 'kind', 'grid', 'reason', null,
        'cursor', v_cursor, 'items', v_items
      ));
    end if;
  end if;

  -- --------------------------------------------------------------- categoria
  if 'by_category' = any (v_want) then
    for r_genre in
      select g.genre
      from public.games g
      where coalesce(g.genre, '') <> ''
      group by g.genre
      order by count(*) desc, g.genre
      limit 2
    loop
      select public.feed_projection(public.feed_diversify(
        coalesce(
          jsonb_agg(t.e order by (t.e->>'score')::numeric desc, t.e->>'id'),
          '[]'::jsonb
        ),
        least(8, v_limit), v_used, v_max_dev, v_max_genre, v_familiar, v_band
      ))
      into v_items
      from jsonb_array_elements(v_pool) as t(e)
      where t.e->>'genre' = r_genre;

      continue when jsonb_array_length(v_items) = 0;

      select v_used || coalesce(array_agg((i->>'id')::uuid), '{}'::uuid[])
      into v_used
      from jsonb_array_elements(v_items) as x(i);

      v_sections := v_sections || jsonb_build_array(jsonb_build_object(
        'key', 'category:' || r_genre, 'kind', 'row',
        'title', r_genre, 'reason', null, 'cursor', null, 'items', v_items
      ));
    end loop;
  end if;

  -- ------------------------------------------------------------------ retorno
  return jsonb_build_object(
    'seed', v_seed,
    'personalized', v_personal,
    'generated_at', to_jsonb(current_timestamp),
    'sections', v_sections,
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
end;
$$;

comment on function public.get_home_feed(text, int, uuid[], jsonb, text[]) is
  'Feed da Início: ranking com decaimento, afinidade, repetição e exploração por seed; diversidade por seção; paginação por cursor na seção discover.';

grant execute on function public.get_home_feed(text, int, uuid[], jsonb, text[])
  to anon, authenticated;

-- ------------------------------------------------------- registrar impressões
-- SECURITY DEFINER justificado: a tabela não tem grant algum para o cliente —
-- a escrita passa por aqui, com validação de identidade e limite de volume.
create or replace function public.record_feed_impressions(
  p_anon uuid,
  p_items jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_key    uuid := coalesce(v_uid, p_anon);
  v_recent int;
  v_count  int := 0;
begin
  if v_key is null or p_items is null or jsonb_typeof(p_items) <> 'array' then
    return 0;
  end if;

  -- Antídoto de spam: teto de 5.000 impressões por chave em 24h.
  select count(*) into v_recent
  from public.feed_impressions i
  where i.seen_at > current_timestamp - interval '24 hours'
    and (
      (v_uid is not null and i.user_id = v_uid)
      or (v_uid is null and i.anon_id = p_anon)
    );

  if v_recent >= 5000 then
    return 0;
  end if;

  insert into public.feed_impressions (user_id, anon_id, game_id, section, session_id)
  select
    v_uid,
    case when v_uid is null then p_anon else null end,
    (e->>'game_id')::uuid,
    left(coalesce(e->>'section', ''), 32),
    left(coalesce(e->>'session_id', ''), 64)
  from jsonb_array_elements(p_items) as x(e)
  where (e->>'game_id') is not null
  limit 50;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.record_feed_impressions(uuid, jsonb) is
  'Registra impressões do feed (máx. 50 por chamada, 5.000 por chave/dia). Uma impressão só deve ser enviada quando o card ficou realmente visível.';

revoke all on function public.record_feed_impressions(uuid, jsonb) from public;
grant execute on function public.record_feed_impressions(uuid, jsonb)
  to anon, authenticated;

-- --------------------------------------------------------------- retenção
-- Sem dependência de pg_cron: a função existe e pode ser agendada pelo projeto
-- (pg_cron, se disponível, ou cron externo). Chamável só por service_role.
create or replace function public.purge_feed_impressions(p_days int default 30)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 365);
  v_count int;
begin
  delete from public.feed_impressions
   where seen_at < current_timestamp - make_interval(days => v_days);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.purge_feed_impressions(int) from public, anon, authenticated;

-- O cliente não lê a tabela: mantém o privilégio mínimo.
revoke all on sequence public.feed_impressions_id_seq from anon, authenticated;

-- ------------------------------------------------------------ privilégio mínimo
-- `grant execute ... to public` é o padrão do Postgres para funções novas.
-- Revogamos e concedemos apenas a `anon`/`authenticated` (o que o app usa), com
-- as funções SECURITY DEFINER de manutenção fora do alcance do cliente.
revoke all on function public.feed_weights() from public;
revoke all on function public.feed_card(jsonb) from public;
revoke all on function public.feed_projection(jsonb) from public;
revoke all on function public.feed_diversify(
  jsonb, integer, uuid[], integer, integer, numeric, numeric
) from public;
revoke all on function public.feed_candidates(text, uuid[], integer) from public;
revoke all on function public.get_home_feed(
  text, integer, uuid[], jsonb, text[]
) from public;

grant execute on function public.feed_weights() to anon, authenticated;
grant execute on function public.feed_card(jsonb) to anon, authenticated;
grant execute on function public.feed_projection(jsonb) to anon, authenticated;
grant execute on function public.feed_diversify(
  jsonb, integer, uuid[], integer, integer, numeric, numeric
) to anon, authenticated;
grant execute on function public.feed_candidates(text, uuid[], integer)
  to anon, authenticated;
grant execute on function public.get_home_feed(
  text, integer, uuid[], jsonb, text[]
) to anon, authenticated;
