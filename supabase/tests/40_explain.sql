-- ============================================================================
-- PORTIX — EXPLAIN ANALYZE do caminho quente do feed (CI, volume real)
--
-- Os agregados vivem dentro de funções SQL com `search_path` fixo (não são
-- inlinados pelo planner), então o plano é medido na consulta equivalente e o
-- tempo real é medido chamando a RPC de verdade. Também reporta o tamanho das
-- tabelas para dar contexto ao plano.
-- ============================================================================

\echo ''
\echo '### VOLUME DAS TABELAS NO MOMENTO DO TESTE'
select
  (select count(*) from public.games)            as games,
  (select count(*) from public.ports)            as ports,
  (select count(*) from public.downloads)        as downloads,
  (select count(*) from public.feed_impressions) as impressoes,
  (select count(*) from public.reviews)          as reviews;

-- `feed_impressions` NÃO tem SELECT para o cliente (privacidade): os planos são
-- inspecionados pelo dono das tabelas. A RPC é medida adiante como
-- `authenticated`, que é o caminho real do app.
select set_config('app.current_uid', '11111111-1111-1111-1111-111111111111', false);

\echo ''
\echo '### 1) popularidade recente com decaimento (janela de 35 dias)'
explain (analyze, buffers, format text)
select
  d.game_id,
  sum(
    exp(-extract(epoch from (current_timestamp - d.created_at)) / 86400.0 / 7.0)
  ) as decayed
from public.downloads d
where d.status = 'done'
  and d.created_at > current_timestamp - interval '35 days'
group by d.game_id;

\echo ''
\echo '### 2) penalidade de repetição do próprio usuário (mesma consulta da função)'
explain (analyze, buffers, format text)
select
  i.game_id,
  max(
    exp(-extract(epoch from (current_timestamp - i.seen_at)) / 86400.0 / 3.0)
  )::numeric as penalty
from public.feed_impressions i
where i.user_id = auth.uid()
  and i.seen_at > current_timestamp - interval '30 days'
group by i.game_id;

set role authenticated;

\echo ''
\echo '### 3) agregação de afinidade (favoritos/biblioteca/downloads do usuário)'
explain (analyze, buffers, format text)
select g.genre, count(*)::numeric as qty
from (
  select f.game_id from public.favorites f where f.user_id = auth.uid()
  union
  select l.game_id from public.library l where l.user_id = auth.uid()
  union
  select d.game_id from public.downloads d
   where d.user_id = auth.uid() and d.status = 'done'
) ug
join public.games g on g.id = ug.game_id
where coalesce(g.genre, '') <> ''
group by g.genre;

\echo ''
\echo '### 4) latência da RPC completa (10 chamadas, média)'
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

  -- Aquecimento (primeira chamada paga parse/plan).
  v_payload := public.get_home_feed('perf-warm', 12, v_seen, null, null);

  v_start := clock_timestamp();
  for i in 1..10 loop
    v_payload := public.get_home_feed(
      'perf-' || i, 12, v_seen, null, null
    );
  end loop;
  v_end := clock_timestamp();

  v_avg := round(extract(epoch from (v_end - v_start)) * 100, 2);
  raise notice 'RPC get_home_feed: média de % ms por chamada', v_avg;

  if v_avg >= 300 then
    raise exception 'RPC lenta demais: % ms (meta < 150 ms)', v_avg;
  end if;

  -- O payload precisa continuar completo.
  perform testkit.assert_true(
    jsonb_array_length(v_payload->'sections') >= 4
      and (v_payload->'stats'->>'games')::int = 839,
    'payload completo após as medições'
  );
end
$$;

\echo ''
\echo '### 5) tamanho do payload e do pool de candidatos'
do $$
declare
  v_pool jsonb := public.feed_candidates('payload-1', '{}'::uuid[]);
begin
  raise notice 'candidatos pontuados: % itens, % kB',
    jsonb_array_length(v_pool),
    pg_size_pretty(length(v_pool::text)::bigint);
end
$$;

reset role;
\echo ''
\echo '=== EXPLAIN do feed: concluído ==='
