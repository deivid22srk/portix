-- ============================================================================
-- PORTIX — assertivas do feed (CI)
--
-- Cada bloco falha alto (raise exception). Cobre: contrato dos pesos, variação
-- entre seeds, estabilidade dentro da mesma seed, diversidade por seção,
-- ausência de duplicatas entre seções, cold start, paginação por cursor,
-- penalização de repetição, impressões (RLS + RPC + retenção) e o fallback
-- legado. Roda DEPOIS das migrations e do seed.
-- ============================================================================

\echo '=== 1. volume do catálogo semeado ==='
do $$
declare
  v_games int;
  v_ports int;
  v_plats int;
begin
  select count(*) into v_games from public.games;
  select count(*) into v_ports from public.ports;
  select count(*) into v_plats from public.platforms;
  perform testkit.assert_true(v_games = 839, 'seed com 839 jogos (obtido: ' || v_games || ')');
  perform testkit.assert_true(v_ports = 1067, 'seed com 1067 ports (obtido: ' || v_ports || ')');
  perform testkit.assert_true(v_plats = 26, 'seed com 26 plataformas (obtido: ' || v_plats || ')');
end
$$;

\echo '=== 2. pesos publicados ==='
do $$
declare
  v jsonb := public.feed_weights();
begin
  perform testkit.assert_true(v ? 'popularity', 'peso de popularidade publicado');
  perform testkit.assert_true(v ? 'explore', 'peso de exploração publicado');
  perform testkit.assert_true(
    (v->>'download_half_life_days')::numeric = 7,
    'meia-vida de downloads = 7 dias'
  );
  perform testkit.assert_true(
    (v->>'explore_min_share')::numeric = 0.25,
    'cota mínima de exploração = 25%'
  );
  perform testkit.assert_true(
    (v->>'max_per_developer')::int = 2 and (v->>'max_per_genre')::int = 3,
    'diversidade: ≤2 por desenvolvedor e ≤3 por gênero'
  );
end
$$;

\echo '=== 3. estabilidade dentro da mesma seed e variação entre seeds ==='
do $$
declare
  v_a uuid[];
  v_b uuid[];
  v_c uuid[];
  v_union uuid[] := '{}'::uuid[];
  v_overlap numeric;
  i int;
begin
  -- Mesma seed, duas chamadas: ordem idêntica (o feed não "pula" sozinho).
  v_a := testkit.feed_ids_new(
    public.get_home_feed('seed-fixa', 12, '{}'::uuid[], null, null), 1000);
  v_b := testkit.feed_ids_new(
    public.get_home_feed('seed-fixa', 12, '{}'::uuid[], null, null), 1000);
  perform testkit.assert_true(v_a = v_b, 'mesma seed devolve exatamente a mesma ordem');

  -- Seeds diferentes: outra ordem.
  v_c := testkit.feed_ids_new(
    public.get_home_feed('seed-outra', 12, '{}'::uuid[], null, null), 1000);
  perform testkit.assert_true(v_a <> v_c, 'seed diferente muda a ordem do feed');

  -- Rotação real: 5 seeds somam bem mais itens do que uma só.
  for i in 1..5 loop
    v_union := v_union || testkit.feed_ids_new(
      public.get_home_feed('rot-' || i, 12, '{}'::uuid[], null, null), 1000);
  end loop;
  perform testkit.assert_true(
    (select count(distinct x) from unnest(v_union) x) >= 25,
    '5 aberturas distintas expõem ≥25 itens (rotação de verdade)'
  );

  -- Sobreposição do topo entre duas seeds fica longe de 100%.
  select count(*)::numeric / greatest(array_length(v_a, 1), 1)
    into v_overlap
  from unnest(v_a) x where x = any (v_c);
  perform testkit.assert_true(
    v_overlap < 0.7,
    'duas seeds diferentes sobrepõem menos de 70% do feed (obtido: '
      || round(v_overlap * 100, 1) || '%)'
  );
end
$$;

\echo '=== 4. diversidade por seção e ausência de repetição entre seções ==='
do $$
declare
  v_payload jsonb;
  v_sec jsonb;
  v_item jsonb;
  v_seen uuid[] := '{}'::uuid[];
  v_max_dev int;
  v_max_genre int;
begin
  -- Como o usuário "veterano": afinidade alta é o pior caso para diversidade.
  perform set_config('app.current_uid', '11111111-1111-1111-1111-111111111111', true);
  v_payload := public.get_home_feed('div-1', 12, '{}'::uuid[], null, null);

  perform testkit.assert_true(
    jsonb_array_length(v_payload->'sections') >= 4,
    'feed personalizado traz pelo menos 4 seções'
  );

  for v_sec in select value from jsonb_array_elements(v_payload->'sections') loop
    select coalesce(max(c), 0) into v_max_dev from (
      select count(*) as c
      from jsonb_array_elements(v_sec->'items') it
      group by it->>'developer'
    ) t;
    perform testkit.assert_true(
      v_max_dev <= 2,
      'seção ' || (v_sec->>'key') || ': ≤2 itens por desenvolvedor (obtido ' || v_max_dev || ')'
    );

    select coalesce(max(c), 0) into v_max_genre from (
      select count(*) as c
      from jsonb_array_elements(v_sec->'items') it
      group by it->>'genre'
    ) t;
    perform testkit.assert_true(
      v_max_genre <= 3,
      'seção ' || (v_sec->>'key') || ': ≤3 itens por gênero (obtido ' || v_max_genre || ')'
    );

    perform testkit.assert_true(
      jsonb_array_length(v_sec->'items') > 0,
      'seção ' || (v_sec->>'key') || ' não vem vazia'
    );

    for v_item in select value from jsonb_array_elements(v_sec->'items') loop
      perform testkit.assert_true(
        not ((v_item->>'id')::uuid = any (v_seen)),
        'item ' || (v_item->>'slug') || ' não se repete em duas seções'
      );
      v_seen := v_seen || (v_item->>'id')::uuid;
    end loop;
  end loop;
end
$$;

\echo '=== 5. cold start (anônimo) ==='
set role anon;
do $$
declare
  v_payload jsonb;
  v_keys text[];
begin
  perform set_config('app.current_uid', '', true);
  v_payload := public.get_home_feed('cold-1', 12, '{}'::uuid[], null, null);

  perform testkit.assert_true(
    (v_payload->>'personalized')::boolean is false,
    'anônimo é tratado como cold start (sem personalização)'
  );

  select array_agg(s->>'key') into v_keys
  from jsonb_array_elements(v_payload->'sections') s;

  perform testkit.assert_true(
    not ('for_you' = any (v_keys)),
    'cold start não inventa seção "para você"'
  );
  perform testkit.assert_true(
    'trending' = any (v_keys) and 'new_releases' = any (v_keys)
      and 'discover' = any (v_keys),
    'cold start entrega em alta + novidades + descubra'
  );
  perform testkit.assert_true(
    jsonb_array_length(v_payload->'genres') > 0
      and jsonb_array_length(v_payload->'platforms') > 0,
    'chips de gênero e plataforma continuam no payload'
  );
end
$$;

\echo '=== 6. paginação por cursor (keyset) sem duplicatas ==='
do $$
declare
  v_p1 jsonb;
  v_p2 jsonb;
  v_ids1 uuid[];
  v_ids2 uuid[];
  v_cursor jsonb;
begin
  perform set_config('app.current_uid', '', true);
  v_p1 := public.get_home_feed('page-1', 10, '{}'::uuid[], null, array['discover']);
  v_ids1 := testkit.feed_ids_new(v_p1, 100);
  v_cursor := v_p1->'sections'->0->'cursor';

  perform testkit.assert_true(v_cursor is not null, 'página 1 devolve cursor');
  perform testkit.assert_true(
    array_length(v_ids1, 1) = 10,
    'página 1 traz 10 itens (obtido ' || coalesce(array_length(v_ids1, 1), 0) || ')'
  );

  v_p2 := public.get_home_feed('page-1', 10, '{}'::uuid[], v_cursor, array['discover']);
  v_ids2 := testkit.feed_ids_new(v_p2, 100);

  perform testkit.assert_true(
    array_length(v_ids2, 1) = 10,
    'página 2 traz 10 itens (obtido ' || coalesce(array_length(v_ids2, 1), 0) || ')'
  );
  perform testkit.assert_true(
    (select count(*) from unnest(v_ids1) a join unnest(v_ids2) b on a = b) = 0,
    'página 2 não repete nenhum item da página 1'
  );
end
$$;
reset role;

\echo '=== 7. penalização de repetição (item já visto perde pontos) ==='
do $$
declare
  v_seen_game uuid;
  v_rep numeric;
  v_rep_outro numeric;
begin
  select game_id into v_seen_game
  from public.feed_impressions
  where user_id = '11111111-1111-1111-1111-111111111111'
  order by seen_at desc
  limit 1;

  perform set_config('app.current_uid', '11111111-1111-1111-1111-111111111111', true);
  select (e->>'repetition')::numeric into v_rep
  from jsonb_array_elements(public.feed_candidates('rep-1', '{}'::uuid[])) e
  where (e->>'id')::uuid = v_seen_game;

  perform set_config('app.current_uid', '22222222-2222-2222-2222-222222222222', true);
  select (e->>'repetition')::numeric into v_rep_outro
  from jsonb_array_elements(public.feed_candidates('rep-1', '{}'::uuid[])) e
  where (e->>'id')::uuid = v_seen_game;

  perform testkit.assert_true(
    coalesce(v_rep, 0) > 0.1,
    'jogo já visto pelo usuário recebe penalidade de repetição (obtido '
      || coalesce(v_rep, 0) || ')'
  );
  perform testkit.assert_true(
    coalesce(v_rep, 0) > coalesce(v_rep_outro, 0),
    'quem viu o jogo é penalizado mais do que quem não viu'
  );

  -- A lista que o cliente manda (p_seen) também penaliza.
  select (e->>'repetition')::numeric into v_rep
  from jsonb_array_elements(
    public.feed_candidates('rep-2', array[v_seen_game])
  ) e
  where (e->>'id')::uuid = v_seen_game;
  perform testkit.assert_true(
    coalesce(v_rep, 0) > 0.5,
    'p_seen (histórico local do cliente) aplica penalidade cheia (obtido '
      || coalesce(v_rep, 0) || ')'
  );
end
$$;

\echo '=== 8. afinidade respeita a RLS (anônimo não personaliza) ==='
set role anon;
do $$
declare
  v_aff numeric;
  v_any_aff boolean;
begin
  perform set_config('app.current_uid', '', true);
  select bool_or((e->>'affinity')::numeric > 0) into v_any_aff
  from jsonb_array_elements(public.feed_candidates('aff-1', '{}'::uuid[])) e;
  perform testkit.assert_true(
    coalesce(v_any_aff, false) is false,
    'anônimo não recebe afinidade (RLS de favoritos/biblioteca/downloads vale)'
  );
end
$$;
reset role;

\echo '=== 9. impressões: RLS, RPC e retenção ==='
set role anon;
do $$
declare
  v_game uuid;
  v_anon uuid := '33333333-3333-3333-3333-333333333333';
  v_n int;
  v_batch jsonb := '[]'::jsonb;
  i int;
begin
  select id into v_game from public.games order by slug limit 1;

  begin
    perform count(*) from public.feed_impressions;
    raise exception 'RLS FUROU: anon conseguiu LER feed_impressions';
  exception when insufficient_privilege then
    raise notice 'OK: anon não lê feed_impressions';
  end;

  begin
    insert into public.feed_impressions (anon_id, game_id)
    values (v_anon, v_game);
    raise exception 'RLS FUROU: anon conseguiu INSERIR direto em feed_impressions';
  exception when insufficient_privilege then
    raise notice 'OK: anon não escreve direto em feed_impressions';
  end;

  -- A escrita pela RPC funciona...
  v_n := public.record_feed_impressions(
    v_anon,
    jsonb_build_array(jsonb_build_object(
      'game_id', v_game::text, 'section', 'discover', 'session_id', 'sess-1'
    ))
  );
  perform testkit.assert_true(v_n = 1, 'RPC de impressões grava 1 item (obtido ' || v_n || ')');

  -- ...e satura em 50 por chamada.
  for i in 1..60 loop
    v_batch := v_batch || jsonb_build_array(jsonb_build_object(
      'game_id', v_game::text, 'section', 'discover', 'session_id', 'sess-2'
    ));
  end loop;
  v_n := public.record_feed_impressions(v_anon, v_batch);
  perform testkit.assert_true(
    v_n <= 50, 'RPC de impressões limita a 50 por chamada (obtido ' || v_n || ')'
  );
end
$$;
reset role;

\echo '=== 10. retenção: purge remove só o que passou da janela ==='
do $$
declare
  v_n int;
  v_game uuid;
begin
  -- Nada no seed é mais velho que 30 dias.
  v_n := public.purge_feed_impressions(30);
  perform testkit.assert_true(
    v_n = 0, 'purge(30) não toca impressões recentes (obtido ' || v_n || ')'
  );

  select id into v_game from public.games order by slug limit 1;
  insert into public.feed_impressions (anon_id, game_id, seen_at)
  values ('44444444-4444-4444-4444-444444444444', v_game,
          current_timestamp - interval '40 days');

  v_n := public.purge_feed_impressions(30);
  perform testkit.assert_true(
    v_n = 1, 'purge(30) remove a impressão de 40 dias (obtido ' || v_n || ')'
  );
end
$$;

\echo '=== 11. fallback legado continua vivo ==='
set role anon;
do $$
declare
  v jsonb := public.home_feed(10);
begin
  perform testkit.assert_true(
    jsonb_array_length(v->'trending') > 0
      and jsonb_array_length(v->'recent') > 0
      and jsonb_array_length(v->'top_rated') > 0,
    'RPC legada home_feed segue funcional como fallback'
  );
end
$$;
reset role;

\echo '=== 12. diversidade: unidade pura respeita os tetos ==='
do $$
declare
  v_items jsonb;
  v_out jsonb;
  v_max_dev int;
  v_max_genre int;
begin
  -- 12 itens do MESMO desenvolvedor e gênero: o teto tem de cortar.
  v_items := (
    select jsonb_agg(jsonb_build_object(
      'id', g.id, 'slug', g.slug, 'developer', 'Dev Único',
      'genre', 'Gênero Único', 'affinity', 0.5))
    from (select id, slug from public.games order by slug limit 12) g
  );

  v_out := public.feed_diversify(v_items, 12, '{}'::uuid[], 2, 3, 1.0);

  select coalesce(max(c), 0) into v_max_dev from (
    select count(*) as c from jsonb_array_elements(v_out) it
    group by it->>'developer'
  ) t;
  select coalesce(max(c), 0) into v_max_genre from (
    select count(*) as c from jsonb_array_elements(v_out) it
    group by it->>'genre'
  ) t;

  perform testkit.assert_true(
    v_max_dev <= 2, 'feed_diversify corta em 2 por desenvolvedor (obtido ' || v_max_dev || ')'
  );
  perform testkit.assert_true(
    v_max_genre <= 3, 'feed_diversify corta em 3 por gênero (obtido ' || v_max_genre || ')'
  );

  -- Com 12 itens idênticos, o teto de gênero deixa no máximo 3 entrarem.
  perform testkit.assert_true(
    jsonb_array_length(v_out) <= 3,
    'unidade de diversidade não deixa passar mais que o teto (obtido '
      || jsonb_array_length(v_out) || ')'
  );
end
$$;

\echo '=== assertivas do feed: TODAS PASSARAM ==='
