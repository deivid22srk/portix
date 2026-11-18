-- ============================================================================
-- PORTIX — teste de ESCALA do caminho quente (CI)
--
-- O volume real do catálogo é pequeno (839 jogos), mas o histórico de downloads
-- e de impressões cresce sem parar. Este teste infla as duas tabelas para
-- ~2 milhões de downloads antigos + ~250 mil impressões antigas e exige que:
--   • a janela recente de popularidade use o índice parcial de `downloads`;
--   • a penalidade de repetição use o índice de `feed_impressions`;
--   • a RPC continue abaixo da meta de latência mesmo com o histórico grande.
-- É o teste que separa "tem índice" de "o plano realmente usa o índice".
-- ============================================================================

\echo ''
\echo '### INFLANDO O HISTÓRICO (dados ANTIGOS, fora das janelas do feed)'

insert into auth.users (id, email)
select
  ('00000000-0001-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  'bulk' || i || '@example.test'
from generate_series(1, 2400) as i;

alter table public.downloads disable trigger downloads_refresh_count;

insert into public.downloads (user_id, game_id, status, progress, created_at, updated_at)
select
  u.id,
  g.id,
  'done',
  100,
  current_timestamp - make_interval(days => (100 + (u.uidx % 400))::int),
  current_timestamp - make_interval(days => (100 + (u.uidx % 400))::int)
from (
  select id, row_number() over (order by id) as uidx
  from auth.users
  where email like 'bulk%@example.test'
) u
cross join (select id from public.games) g;

alter table public.downloads enable trigger downloads_refresh_count;

insert into public.feed_impressions (user_id, game_id, section, seen_at)
select
  u.id,
  g.id,
  'historico',
  current_timestamp - make_interval(days => (40 + (u.uidx % 300))::int)
from (
  select id, row_number() over (order by id) as uidx
  from auth.users
  where email like 'bulk%@example.test'
) u
cross join (select id from public.games) g
where (hashtextextended(g.id::text, u.uidx) % 8) = 0;

analyze public.downloads;
analyze public.feed_impressions;

\echo ''
\echo '### TAMANHO DAS TABELAS APÓS A CARGA'
select
  (select count(*) from public.downloads)          as downloads,
  (select count(*) from public.feed_impressions)   as impressoes,
  pg_size_pretty(pg_relation_size('public.downloads'))        as downloads_tam,
  pg_size_pretty(pg_relation_size('public.feed_impressions')) as impressoes_tam;

set role authenticated;
select set_config('app.current_uid', '11111111-1111-1111-1111-111111111111', false);

\echo ''
\echo '### PLANO: janela recente de popularidade (deve usar índice parcial)'
do $$
declare
  r      record;
  v_plan text := '';
begin
  for r in execute $q$
    explain (analyze, buffers, format text)
    select
      d.game_id,
      sum(
        exp(
          -extract(epoch from (current_timestamp - d.created_at))
          / 86400.0 / 7.0
        )
      ) as decayed
    from public.downloads d
    where d.status = 'done'
      and d.created_at > current_timestamp - interval '35 days'
    group by d.game_id
  $q$ loop
    v_plan := v_plan || r."QUERY PLAN" || E'\n';
  end loop;

  raise notice E'\n%', v_plan;
  perform testkit.assert_true(
    v_plan not like '%Seq Scan on downloads%',
    'janela de popularidade não faz seq scan em downloads (2M de linhas)'
  );
  perform testkit.assert_true(
    v_plan like '%downloads_recent_idx%',
    'janela de popularidade usa downloads_recent_idx'
  );
end
$$;

\echo ''
\echo '### PLANO: penalidade de repetição (deve usar índice de feed_impressions)'
do $$
declare
  r      record;
  v_plan text := '';
begin
  for r in execute $q$
    explain (analyze, buffers, format text)
    select
      i.game_id,
      max(
        exp(
          -extract(epoch from (current_timestamp - i.seen_at)) / 86400.0 / 3.0
        )
      )::numeric as penalty
    from public.feed_impressions i
    where i.user_id = auth.uid()
      and i.seen_at > current_timestamp - interval '30 days'
    group by i.game_id
  $q$ loop
    v_plan := v_plan || r."QUERY PLAN" || E'\n';
  end loop;

  raise notice E'\n%', v_plan;
  perform testkit.assert_true(
    v_plan not like '%Seq Scan on feed_impressions%',
    'penalidade de repetição não faz seq scan em feed_impressions (250k linhas)'
  );
end
$$;

\echo ''
\echo '### LATÊNCIA DA RPC COM O HISTÓRICO INFLADO (10 chamadas, média)'
do $$
declare
  v_start timestamptz;
  v_end   timestamptz;
  v_payload jsonb;
  v_avg   numeric;
  v_seen  uuid[];
  i       int;
begin
  select coalesce(array_agg(s.game_id), '{}'::uuid[])
    into v_seen
  from public.feed_seen_recent() s;

  v_payload := public.get_home_feed('scale-warm', 12, v_seen, null, null);

  v_start := clock_timestamp();
  for i in 1..10 loop
    v_payload := public.get_home_feed(
      'scale-' || i, 12, v_seen, null, null
    );
  end loop;
  v_end := clock_timestamp();

  v_avg := round(extract(epoch from (v_end - v_start)) * 100, 2);
  raise notice 'RPC get_home_feed com histórico inflado: média de % ms', v_avg;

  perform testkit.assert_true(
    v_avg < 300,
    'RPC abaixo de 300 ms com 2M de downloads (obtido ' || v_avg || ' ms)'
  );
  perform testkit.assert_true(
    jsonb_array_length(v_payload->'sections') >= 4,
    'feed continua completo com histórico inflado'
  );
end
$$;

reset role;
\echo ''
\echo '=== ESCALA: concluído ==='
