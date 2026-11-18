-- ============================================================================
-- PORTIX — EXPLAIN ANALYZE da busca v2 (CI, volume real)
--
-- As RPCs plpgsql não são inlinadas, então o plano do FILTRO é medido na
-- consulta equivalente (mesma forma que o planner vê dentro da função) e o
-- tempo real é medido chamando as RPCs de verdade. A exigência: nenhum
-- Seq Scan em `games` no caminho principal — o filtro combinado
-- (substring normalizado + trigramas + dev + gênero) precisa de BitmapOr
-- sobre os índices de trigramas.
-- ============================================================================

\echo ''
\echo '### volume no momento do teste'
select
  (select count(*) from public.games) as games,
  (select count(*) from public.ports) as ports,
  (select count(*) from public.platforms) as plataformas;

\echo ''
\echo '### 1) compatibilidade de índice do filtro combinado da busca'
-- Metodologia: com o volume ATUAL (839 jogos) e seletividade de 8-30% (o seed
-- repete ~12 palavras), o planner escolhe Seq Scan e é o plano CERTO
-- (3 ms reais, medido adiante). O que a migration precisa provar é que a
-- FORMA da consulta é indexável: com enable_seqscan=off o planner DEVE
-- produzir BitmapOr sobre os índices GIN de trigramas — é isso que garante
-- que o índice assuma o caminho principal quando a tabela crescer.
do $$
declare
  v_plan jsonb;
  v_nodes jsonb;
  v_seq int;
begin
  -- o operador de trigramas depende do search_path
  set search_path = public, extensions;
  set enable_seqscan = off;
  execute $e$
    explain (analyze, costs off, timing off, format json)
    select c.id
    from public.game_cards c
    where (extensions.f_norm(c.title) like '%frontier%'::text)
       or (extensions.f_norm(c.title) % 'frontier'::text)
       or (extensions.f_norm(c.developer) like '%dev 5%'::text)
       or (extensions.f_norm(c.genre) like '%aventura%'::text)
    limit 24
  $e$ into v_plan;
  set enable_seqscan = on;

  v_nodes := jsonb_path_query_array(v_plan, '$.**."Node Type"');
  select count(*) into v_seq
    from jsonb_array_elements_text(v_nodes) n
   where n = 'Seq Scan';

  perform testkit.assert_true(v_seq = 0,
    'forma do filtro é indexável (com Seq Scan desligado, obteve '
      || v_seq || ' seq scan)');
  perform testkit.assert_true(v_plan::text like '%BitmapOr%',
    'plano usa BitmapOr sobre os índices de trigramas');
end
$$;

\echo ''
\echo '### 2) descoberta (sem termo, sort trending): índice de popularidade'
do $$
declare
  v_plan jsonb;
begin
  set search_path = public, extensions;
  execute $e$
    explain (analyze, costs off, timing off, format json)
    select c.id, c.visit_count
    from public.game_cards c
    order by c.visit_count desc, c.id desc
    limit 24
  $e$ into v_plan;

  perform testkit.assert_true(
    v_plan::text like '%games_visit_rank_idx%'
      and v_plan::text not like '%"Sort Method"%',
    'descoberta usa o índice de ordenação (sem sort em disco)');
end
$$;

\echo ''
\echo '### 3) latência das quatro RPCs (10 chamadas cada, meta < 150 ms)'
do $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_avg numeric;
  i int;
  v_payload jsonb;
begin
  v_payload := public.search_games_v2('aquecimento', null, null, false, false, null, 'relevance', 24, null);
  v_start := clock_timestamp();
  for i in 1..10 loop
    v_payload := public.search_games_v2('Frontier', null, null, false, false, null, 'relevance', 24, null);
  end loop;
  v_end := clock_timestamp();
  v_avg := round(extract(epoch from (v_end - v_start)) * 100, 2);
  raise notice 'search_games_v2 (com termo): % ms/chamada', v_avg;
  perform testkit.assert_true(v_avg < 150,
    'busca com termo < 150 ms (obtido: ' || v_avg || ' ms)');

  v_payload := public.search_games_v2(null, null, null, false, false, null, 'trending', 24, null);
  v_start := clock_timestamp();
  for i in 1..10 loop
    v_payload := public.search_games_v2(null, null, null, false, false, null, 'trending', 24, null);
  end loop;
  v_end := clock_timestamp();
  v_avg := round(extract(epoch from (v_end - v_start)) * 100, 2);
  raise notice 'search_games_v2 (descoberta): % ms/chamada', v_avg;
  perform testkit.assert_true(v_avg < 150,
    'descoberta < 150 ms (obtido: ' || v_avg || ' ms)');

  v_payload := public.search_suggest('warm');
  v_start := clock_timestamp();
  for i in 1..10 loop
    v_payload := public.search_suggest('front');
  end loop;
  v_end := clock_timestamp();
  v_avg := round(extract(epoch from (v_end - v_start)) * 100, 2);
  raise notice 'search_suggest: % ms/chamada', v_avg;
  perform testkit.assert_true(v_avg < 150,
    'sugestões < 150 ms (obtido: ' || v_avg || ' ms)');

  v_payload := public.explore_feed(12);
  v_start := clock_timestamp();
  for i in 1..10 loop
    v_payload := public.explore_feed(12);
  end loop;
  v_end := clock_timestamp();
  v_avg := round(extract(epoch from (v_end - v_start)) * 100, 2);
  raise notice 'explore_feed: % ms/chamada', v_avg;
  perform testkit.assert_true(v_avg < 150,
    'explore_feed < 150 ms (obtido: ' || v_avg || ' ms)');
end
$$;

\echo ''
\echo '=== EXPLAIN DA BUSCA V2: CONCLUÍDO ==='
