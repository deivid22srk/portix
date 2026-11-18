-- ============================================================================
-- PORTIX — seed sintético dos testes do feed
--
-- Espelha o VOLUME REAL do catálogo (839 jogos, 1.067 ports, 26 plataformas —
-- README.md) e constrói de propósito a armadilha que a Início tinha:
--
--   • `visit_count` é Zipf e favorece os PRIMEIROS índices (o "mais popular de
--     sempre" de sempre), como no catálogo real;
--   • os downloads concluídos RECENTES se concentram em OUTRA faixa de jogos
--     (índices altos, últimos 14 dias). Assim a ordenação por popularidade com
--     decaimento tem de divergir da ordenação por contador acumulado — é
--     exatamente isso que a simulação mede.
--   • um usuário "veterano" com favoritos, biblioteca, downloads e 200
--     impressões recentes, para exercitar afinidade e penalização de repetição.
--
-- Totalmente determinístico (sem `random()`): antes e depois são comparáveis
-- entre execuções.
-- ============================================================================

-- ------------------------------------------------------- catálogo limpo
-- As migrations 0016/0021 semeiam alguns jogos de exemplo. O teste precisa de um
-- volume EXATO e reprodutível, então o seed assume o catálogo do zero (as FKs
-- são `on delete cascade`).
delete from public.ports;
delete from public.downloads;
delete from public.reviews;
delete from public.favorites;
delete from public.library;
delete from public.feed_impressions;
delete from public.games;
delete from public.platforms;
-- `generated always as identity` não reinicia no delete: sem isto os ids vêm
-- 27..52 e o mapeamento `platform_id = (i % 26) + 1` viola a FK.
alter table public.platforms alter column id restart with 1;

-- ---------------------------------------------------------------- plataformas
insert into public.platforms (slug, name, full_name, kind, sort_order)
select
  'plat' || lpad(i::text, 2, '0'),
  'Plataforma ' || i,
  'Plataforma Sintética ' || i,
  case
    when i % 7 = 0 then 'handheld'
    when i % 11 = 0 then 'multi'
    when i % 5 = 0 then 'mobile'
    else 'console'
  end,
  i
from generate_series(1, 26) as i;

-- ---------------------------------------------------------------------- jogos
insert into public.games (
  slug, title, year, genre, description, cover_url, developer,
  platforms, platform_slugs, port_count, visit_count, is_free, needs_rom,
  released_on, last_activity_on, rating_avg, rating_count, created_at
)
select
  'game-' || lpad(i::text, 4, '0'),
  'Jogo ' || i || ' ' || (
    array['Odyssey', 'Legends', 'Quest', 'Rush', 'Tactics', 'Chronicles',
          'Arena', 'Mystery', 'Blitz', 'Saga', 'Trials', 'Frontier']
  )[1 + (i % 12)],
  (1992 + (i % 34))::smallint,
  (
    array['Ação', 'Aventura', 'RPG', 'Plataforma', 'Corrida', 'Luta',
          'Puzzle', 'Estratégia', 'Tiro', 'Esporte', 'Simulação', 'Terror']
  )[1 + (i % 12)],
  'Descrição sintética do jogo ' || i || '.',
  case when i % 12 = 0 then null
       else 'https://cdn.example.test/cover/' || i || '.jpg' end,
  'Dev ' || lpad((((i * 7) % 60) + 1)::text, 2, '0'),
  (
    select array_agg('Plataforma ' || (((i + k) % 26) + 1) order by k)
    from generate_series(0, 2) as k
  ),
  (
    select array_agg('plat' || lpad((((i + k) % 26) + 1)::text, 2, '0') order by k)
    from generate_series(0, 2) as k
  ),
  3,
  -- Zipf: poucos jogos concentram quase toda a visita acumulada.
  greatest(1, (250000.0 / power(i::numeric, 1.15))::bigint),
  (i % 9 = 0),
  (i % 5 = 0),
  -- 1 em cada 7 é "novidade" (saiu nos últimos 90 dias).
  case
    when i % 7 = 0 then current_date - (i % 90)
    else date '2015-01-01' + ((i * 13) % 5000)
  end,
  -- 1 em cada 11 teve atividade recente.
  case
    when i % 11 = 0 then current_date - (i % 45)
    else date '2020-01-01' + ((i * 29) % 1500)
  end,
  case
    when i % 3 = 0 then 4.60
    when i % 3 = 1 then 3.80
    else 2.90
  end::numeric(3, 2),
  greatest(1, (3000.0 / power(i::numeric, 0.8))::int),
  current_timestamp - make_interval(days => (i % 700))
from generate_series(1, 839) as i;

-- ---------------------------------------------------------------------- ports
insert into public.ports (
  port_key, game_id, platform_id, project, source, url, developer, version,
  last_update, date_added, needs_game_files, works, controller_support,
  visits, sort_index
)
select
  'port-' || lpad(i::text, 4, '0'),
  g.id,
  ((i % 26) + 1)::smallint,
  'Projeto ' || i,
  'fonte-' || (i % 5),
  'https://cdn.example.test/port/' || i,
  'Dev ' || lpad((((i * 3) % 60) + 1)::text, 2, '0'),
  'v' || (1 + (i % 5)) || '.' || (i % 10),
  current_date - (i % 500),
  current_date - (i % 900),
  (i % 4 = 0),
  (array['yes', 'no', 'untested', 'bug', 'partial'])[1 + (i % 5)],
  (array['full', 'partial'])[1 + (i % 2)],
  (i % 200),
  (i % 5)
from generate_series(1, 1067) as i
join public.games g
  on g.slug = 'game-' || lpad((((i - 1) % 839) + 1)::text, 4, '0');

-- ---------------------------------------------------------------------- contas
insert into auth.users (id, email, created_at) values
  ('11111111-1111-1111-1111-111111111111', 'veterano@example.test',
   current_timestamp - interval '400 days'),
  ('22222222-2222-2222-2222-222222222222', 'outro@example.test',
   current_timestamp - interval '200 days');

insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'Veterano'),
  ('22222222-2222-2222-2222-222222222222', 'Outro')
on conflict (id) do nothing;

insert into auth.users (id, email, created_at)
select
  ('00000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  'user' || i || '@example.test',
  current_timestamp - make_interval(days => i)
from generate_series(1, 60) as i;

-- ------------------------------------------------------- downloads concluídos
-- Trigger desligado: o backfill no fim refaz a contagem de uma vez só
-- (11 mil updates por linha deixariam o seed lentíssimo).
alter table public.downloads disable trigger downloads_refresh_count;

with pairs as (
  select
    u.id as user_id,
    g.id as game_id,
    g.num,
    (
      (
        hashtextextended(g.id::text, u.uidx) % 1000000
      ) + 1000000
    ) % 1000000 as h
  from (
    select id, row_number() over (order by id)::bigint as uidx
    from auth.users
    where email like 'user%@example.test'
  ) u
  cross join (
    select
      id,
      coalesce((substring(slug from '([0-9]+)$'))::int, 0) as num
    from public.games
  ) g
)
insert into public.downloads (
  user_id, game_id, status, progress, created_at, updated_at
)
select
  p.user_id,
  p.game_id,
  'done',
  100,
  -- Recentes (0–13 dias) para a faixa alta do catálogo; antigos (0–89) para o
  -- resto. É o que faz a popularidade COM decaimento divergir do acumulado.
  current_timestamp - make_interval(
    days => (case when p.num > 700 then (p.h % 14) else (p.h % 90) end)::int
  ),
  current_timestamp - make_interval(
    days => (case when p.num > 700 then (p.h % 14) else (p.h % 90) end)::int
  )
from pairs p
where p.h % 2 = 0
  and (p.num > 700 or p.h % 3 = 0);

alter table public.downloads enable trigger downloads_refresh_count;

-- ----------------------------------------------------------- histórico do seed
-- Veterano: afinidade clara em RPG/Plataforma/Ação.
insert into public.favorites (user_id, game_id)
select '11111111-1111-1111-1111-111111111111'::uuid, id
from public.games where genre = 'RPG' order by slug limit 30;

insert into public.library (user_id, game_id)
select '11111111-1111-1111-1111-111111111111'::uuid, id
from public.games where genre = 'Plataforma' order by slug limit 15;

insert into public.downloads (user_id, game_id, status, progress, created_at, updated_at)
select
  '11111111-1111-1111-1111-111111111111'::uuid, id, 'done', 100,
  current_timestamp - make_interval(days => rn::int),
  current_timestamp
from (
  select id, row_number() over (order by slug) as rn
  from public.games where genre = 'Ação' order by slug limit 25
) t;

-- 200 impressões espalhadas em 20 dias (penalização de repetição).
insert into public.feed_impressions (user_id, game_id, section, session_id, seen_at)
select
  '11111111-1111-1111-1111-111111111111'::uuid,
  id,
  'trending',
  'sess-antiga',
  current_timestamp - make_interval(days => (rn % 20)::int)
from (
  select id, row_number() over (order by slug) as rn
  from public.games order by slug limit 200
) t;

-- ------------------------------------------------------------------ avaliações
with pairs as (
  select
    g.id as game_id,
    u.id as user_id,
    ((g.num * 31 + u.uidx * 17) % 50000) as k
  from (
    select id, coalesce((substring(slug from '([0-9]+)$'))::int, 0) as num
    from public.games
  ) g
  cross join (
    select id, row_number() over (order by id) as uidx from auth.users
  ) u
)
insert into public.reviews (game_id, user_id, rating, body, created_at)
select
  p.game_id,
  p.user_id,
  1 + (p.k % 5),
  'Comentário sintético ' || p.k,
  current_timestamp - make_interval(days => (p.k % 200)::int)
from pairs p
where p.k < 500;

-- --------------------------------------------------- contagem real de downloads
update public.games g
   set download_count = (
     select count(*) from public.downloads d
     where d.game_id = g.id and d.status = 'done'
   );

-- Ajusta a nota média a partir das avaliações semeadas (como o app faz).
update public.games g
   set rating_avg = coalesce(r.avg_rating, g.rating_avg),
       rating_count = coalesce(r.qty, g.rating_count)
from (
  select game_id, round(avg(rating)::numeric, 2) as avg_rating, count(*)::int as qty
  from public.reviews group by game_id
) r
where r.game_id = g.id;

analyze public.games;
analyze public.ports;
analyze public.downloads;
analyze public.feed_impressions;
analyze public.reviews;
analyze public.favorites;
analyze public.library;
