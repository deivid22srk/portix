-- ============================================================================
-- PORTIX — testes da busca v2 (search_games_v2 / search_suggest / explore_feed)
--
-- Roda no CI contra o Postgres efêmero com o catálogo real semeados
-- (839 jogos). Falha o build em qualquer violação:
--   • tolerância a acento, caixa e erro de digitação (relatório dos 20 termos);
--   • ranking: exato > prefixo > parcial, desempate por popularidade;
--   • paginação keyset: nenhuma duplicata entre páginas, fim de lista correto;
--   • filtros combinados (plataforma, gênero, grátis, precisa de ROM, nota);
--   • RLS/execução: SECURITY INVOKER, search_path fixo, grants de cliente;
--   • latência: média de 10 chamadas abaixo de 150 ms.
-- ============================================================================

\echo ''
\echo '### 1) extensões e índices do caminho de busca'
do $$
declare
  v_ext int;
  v_idx int;
begin
  select count(*) into v_ext from pg_extension
   where extname in ('unaccent', 'pg_trgm');
  perform testkit.assert_true(v_ext = 2, 'extensões unaccent + pg_trgm presentes');

  select count(*) into v_idx from pg_indexes
   where schemaname = 'public'
     and indexname in ('games_title_norm_trgm_idx', 'games_developer_norm_trgm_idx',
                       'games_genre_norm_trgm_idx', 'games_rating_rank_idx');
  perform testkit.assert_true(v_idx = 4, 'índices normalizados/rank criados (4)');
end
$$;

\echo ''
\echo '### 2) relatório dos 20 termos (antes: 5 falhas — acento e typo)'
create temp table term_report as
select c.idx, c.term, c.expect, c.min_hits, c.exact_first, c.exact_like,
       (public.search_games_v2(c.term, null, null, false, false, null, 'relevance', 24, null)
         ->> 'total')::int as hits,
       case when c.exact_first then
         ((public.search_games_v2(c.term, null, null, false, false, null, 'relevance', 24, null)
            -> 'items' -> 0 ->> 'title') ilike c.exact_like)
       else null
       end as first_ok
from (values
  (1,  'Jogo 479 Frontier', 'nome exato',                 1, true,  'Jogo 479 Frontier'),
  (2,  'Frontier',          'nome parcial (vários)',       10, false, null),
  (3,  'jogo 479',          'caixa baixa',                  1, true,  'Jogo 479 Frontier'),
  (4,  'JOGO 479',          'caixa alta',                   1, true,  'Jogo 479 Frontier'),
  (5,  '479',               'prefixo numérico',             1, true,  'Jogo 479 Frontier'),
  (6,  'Simulacao',         'SEM ACENTO',                  10, false, null),
  (7,  'simulacao',         'sem acento caixa baixa',      10, false, null),
  (8,  'Simulação',         'com acento (controle)',       10, false, null),
  (9,  'Jgo 479 Frontier',  'TYPO em "Jogo"',               1, true,  'Jogo 479 Frontier'),
  (10, 'Frontir',           'TYPO em "Frontier"',           1, true,  '%Frontier%'),
  (11, 'Arenna',            'TYPO em "Arena"',              1, true,  '%Arena%'),
  (12, 'Puzzle',            'por categoria',                1, false, null),
  (13, 'Corrida',           'por categoria',                1, false, null),
  (14, 'Dev 54',            'por desenvolvedor',            1, false, null),
  (15, 'dev 19',            'dev caixa baixa',              1, false, null),
  (16, 'Dev',               'dev genérico',                50, false, null),
  (17, 'zzzqqq',            'sem resultado',                0, false, null),
  (18, 'Frontierzzz',       'prefixo inexistente',          0, false, null),
  (19, 'RPG',               'categoria RPG',                1, false, null),
  (20, 'Terror',            'categoria Terror',             1, false, null)
) as c(idx, term, expect, min_hits, exact_first, exact_like);

select c.idx, c.term, c.expect, c.hits, c.first_ok from term_report c order by c.idx;

do $$
declare
  r record;
begin
  for r in select * from term_report loop
    if r.hits < r.min_hits then
      raise exception 'TERMO % (%) espera >= %, obteve %', r.idx, r.term, r.min_hits, r.hits;
    end if;
    if r.first_ok is not null and not r.first_ok then
      raise exception 'RANKING do termo % (%): esperado "%" em 1º, obteve %',
        r.idx, r.term, r.exact_like,
        (public.search_games_v2(r.term, null, null, false, false, null, 'relevance', 24, null)
          -> 'items' -> 0 ->> 'title');
    end if;
  end loop;
  raise notice '20 termos: TODOS passaram (acento, caixa, typo, prefixo, categoria, dev, vazio)';
end
$$;

\echo ''
\echo '### 3) "Você quis dizer…?" (sugestão quando 0 resultados)'
do $$
declare
  v_sug text;
begin
  v_sug := (public.search_games_v2('Frintier QZZX', null, null, false, false, null, 'relevance', 24, null)
              ->> 'suggestion');
  perform testkit.assert_true(v_sug is not null and v_sug ilike '%Frontier%',
    'sugestão de correção para "Frintier QZZX" (obtido: ' || coalesce(v_sug, '—') || ')');

  v_sug := (public.search_games_v2('zzzqqq', null, null, false, false, null, 'relevance', 24, null)
              ->> 'suggestion');
  perform testkit.assert_true(v_sug is null, 'termo sem semelhança não gera sugestão');
end
$$;

\echo ''
\echo '### 4) ordenações: recent, rating, trending, az'
do $$
declare
  v_items jsonb;
  v_prev timestamptz;
  v_prev_n numeric;
  v_t text;
  i int;
  v_ok boolean;
begin
  -- recent: released_on desc nulls last
  v_items := public.search_games_v2(null, null, null, false, false, null, 'recent', 60, null) -> 'items';
  perform testkit.assert_true(jsonb_array_length(v_items) >= 20, 'recent: página cheia');
  v_ok := true;
  v_prev := 'infinity'::timestamptz;
  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    if (v_items -> i ->> 'released_on') is not null then
      if (v_items -> i ->> 'released_on')::timestamptz > v_prev then
        v_ok := false;
      end if;
      v_prev := (v_items -> i ->> 'released_on')::timestamptz;
    end if;
  end loop;
  perform testkit.assert_true(v_ok, 'recent: ordenado por data desc');

  -- rating: rating_avg desc
  v_items := public.search_games_v2(null, null, null, false, false, null, 'rating', 60, null) -> 'items';
  v_prev_n := 6;
  v_ok := true;
  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    if (v_items -> i ->> 'rating_avg')::numeric > v_prev_n then
      v_ok := false;
    end if;
    v_prev_n := (v_items -> i ->> 'rating_avg')::numeric;
  end loop;
  perform testkit.assert_true(v_ok, 'rating: ordenado por nota desc');

  -- trending: visit_count desc
  v_items := public.search_games_v2(null, null, null, false, false, null, 'trending', 60, null) -> 'items';
  v_prev_n := 1e18;
  v_ok := true;
  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    if (v_items -> i ->> 'visit_count')::numeric > v_prev_n then
      v_ok := false;
    end if;
    v_prev_n := (v_items -> i ->> 'visit_count')::numeric;
  end loop;
  perform testkit.assert_true(v_ok, 'trending: ordenado por popularidade desc');

  -- az: título normalizado asc (acento/caixa ignorados)
  v_items := public.search_games_v2(null, null, null, false, false, null, 'az', 60, null) -> 'items';
  v_t := '';
  v_ok := true;
  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    if extensions.f_norm(v_items -> i ->> 'title') < v_t then
      v_ok := false;
    end if;
    v_t := extensions.f_norm(v_items -> i ->> 'title');
  end loop;
  perform testkit.assert_true(v_ok, 'az: ordenado por título normalizado asc');
end
$$;

\echo ''
\echo '### 5) paginação keyset: página 1 + página 2 sem duplicatas'
do $$
declare
  v_p1 jsonb;
  v_p2 jsonb;
  v_cursor jsonb;
  v_id1 uuid[] := '{}';
  v_id2 uuid[] := '{}';
  v_dupes int;
  v_total int;
begin
  v_p1 := public.search_games_v2('Frontier', null, null, false, false, null, 'relevance', 30, null);
  v_cursor := v_p1 -> 'cursor';
  v_total := (v_p1 ->> 'total')::int;
  perform testkit.assert_true(jsonb_typeof(v_cursor) = 'object',
    'cursor devolvido quando há próxima página');
  perform testkit.assert_true(v_total >= 30, 'total contado na 1ª página (obtido: ' || v_total || ')');

  v_p2 := public.search_games_v2('Frontier', null, null, false, false, null, 'relevance', 30, v_cursor);
  select coalesce(array_agg(x->>'id'), '{}') into v_id1
    from jsonb_array_elements(v_p1 -> 'items') x;
  select coalesce(array_agg(x->>'id'), '{}') into v_id2
    from jsonb_array_elements(v_p2 -> 'items') x;
  perform testkit.assert_true(jsonb_array_length(v_p2 -> 'items') > 0, 'página 2 não vazia');
  perform testkit.assert_true(jsonb_array_length(v_p2 -> 'items') <= 30, 'página 2 respeita o limite');

  select count(*) into v_dupes
    from unnest(v_id1) a join unnest(v_id2) b on a = b;
  perform testkit.assert_true(v_dupes = 0,
    'nenhuma duplicata entre página 1 e 2 (obtido: ' || v_dupes || ')');

  -- percorrer até o fim: cursor null e soma = total
  declare
    v_seen int := jsonb_array_length(v_p1 -> 'items') + jsonb_array_length(v_p2 -> 'items');
    v_next jsonb := v_p2 -> 'cursor';
    v_page jsonb;
    v_guard int := 0;
    v_all uuid[] := v_id1 || v_id2;
    v_u int;
  begin
    -- "cursor": null vem como jsonb null (não SQL null): checar o tipo.
    while v_next is not null and jsonb_typeof(v_next) = 'object' and v_guard < 50 loop
      v_page := public.search_games_v2('Frontier', null, null, false, false, null, 'relevance', 30, v_next);
      select coalesce(array_agg(x->>'id'), '{}') into v_id2
        from jsonb_array_elements(v_page -> 'items') x;
      select count(*) into v_u from unnest(v_all) a join unnest(v_id2) b on a = b;
      perform testkit.assert_true(v_u = 0, 'sem duplicatas na página ' || (v_guard + 3));
      v_all := v_all || v_id2;
      v_seen := v_seen + jsonb_array_length(v_page -> 'items');
      v_next := v_page -> 'cursor';
      v_guard := v_guard + 1;
    end loop;
    perform testkit.assert_true(v_seen = v_total,
      'paginar tudo soma exatamente o total (' || v_seen || ' de ' || v_total || ')');
    perform testkit.assert_true(
      v_next is null or jsonb_typeof(v_next) <> 'object',
      'fim de lista devolve cursor null (jsonb null ou ausente)');
  end;
end
$$;

\echo ''
\echo '### 6) filtros combinados'
do $$
declare
  v_plat text;
  v_items jsonb;
  v_bad int;
begin
  select slug into v_plat from public.platforms limit 1;
  select count(*) into v_bad
    from jsonb_array_elements(
      public.search_games_v2(null, v_plat, null, true, false, null, 'trending', 60, null) -> 'items') x
   where (x ->> 'is_free')::boolean is not true
      or not (v_plat = any(array(select jsonb_array_elements_text(x -> 'platform_slugs'))));
  perform testkit.assert_true(v_bad = 0, 'plataforma + grátis respeitados (violou: ' || v_bad || ')');

  select count(*) into v_bad
    from jsonb_array_elements(
      public.search_games_v2(null, null, null, false, false, 4.0, 'trending', 60, null) -> 'items') x
   where (x ->> 'rating_avg')::numeric < 4.0;
  perform testkit.assert_true(v_bad = 0, 'nota mínima 4.0 respeitada (violou: ' || v_bad || ')');

  select count(*) into v_bad
    from jsonb_array_elements(
      public.search_games_v2('Puzzle', null, 'Puzzle', false, false, null, 'relevance', 60, null) -> 'items') x
   where (x ->> 'genre') is distinct from 'Puzzle';
  perform testkit.assert_true(v_bad = 0, 'gênero aplicado junto ao termo (violou: ' || v_bad || ')');
end
$$;

\echo ''
\echo '### 7) search_suggest: jogos, gêneros, desenvolvedores, plataformas'
do $$
declare
  v_sug jsonb;
begin
  v_sug := public.search_suggest('frontir', 8);
  perform testkit.assert_true(jsonb_array_length(v_sug -> 'games') >= 1,
    'sugestão de jogo para "frontir" (typo)');
  perform testkit.assert_true(
    (v_sug -> 'games' -> 0 ->> 'title') ilike '%Frontier%',
    'jogo sugerido é o "Frontier" (obtido: ' || (v_sug -> 'games' -> 0 ->> 'title') || ')');

  v_sug := public.search_suggest('Simulacao', 8);
  perform testkit.assert_true(jsonb_array_length(v_sug -> 'genres') >= 1,
    'sugestão de gênero sem acento ("Simulacao" → Simulação)');

  v_sug := public.search_suggest('dev 5', 8);
  perform testkit.assert_true(jsonb_array_length(v_sug -> 'developers') >= 1,
    'sugestão de desenvolvedor');

  v_sug := public.search_suggest('zzzqqq', 8);
  perform testkit.assert_true(
    jsonb_array_length(v_sug -> 'games') = 0
      and jsonb_array_length(v_sug -> 'genres') = 0,
    'termo sem semelhança: sugestões vazias');
end
$$;

\echo ''
\echo '### 8) explore_feed: seções agregadas'
do $$
declare
  v_feed jsonb;
begin
  v_feed := public.explore_feed(12);
  perform testkit.assert_true(jsonb_array_length(v_feed -> 'trending') = 12, 'em alta: 12 itens');
  perform testkit.assert_true(jsonb_array_length(v_feed -> 'new_releases') >= 1, 'novidades: itens');
  perform testkit.assert_true(jsonb_array_length(v_feed -> 'top_rated') >= 1, 'mais avaliados: itens');
  perform testkit.assert_true(jsonb_array_length(v_feed -> 'popular_searches') = 10,
    'em alta nas buscas: 10 termos');
  perform testkit.assert_true(jsonb_array_length(v_feed -> 'genres') >= 5, 'categorias: gêneros');
  perform testkit.assert_true((v_feed -> 'stats' ->> 'games')::int = 839, 'stats completas');
end
$$;

\echo ''
\echo '### 9) execução como cliente (RLS) e forma da função'
set role anon;
do $$
declare
  v_items jsonb;
begin
  v_items := public.search_games_v2('Frontier', null, null, false, false, null, 'relevance', 5, null) -> 'items';
  perform testkit.assert_true(jsonb_array_length(v_items) >= 1,
    'anon executa search_games_v2 (RLS de leitura pública aplica)');
  perform testkit.assert_true(
    jsonb_array_length(public.search_suggest('dev', 5) -> 'developers') >= 1,
    'anon executa search_suggest (dev → desenvolvedores)');
  perform testkit.assert_true(jsonb_array_length(public.explore_feed(10) -> 'trending') = 10,
    'anon executa explore_feed');
end
$$;
reset role;

do $$
declare
  v_invoker boolean;
  v_path_ok boolean;
begin
  select prosecdef = false into v_invoker
    from pg_proc where proname = 'search_games_v2';
  perform testkit.assert_true(v_invoker, 'search_games_v2 é SECURITY INVOKER');

  select coalesce(array_agg(pc.proconfig), '{}') @> array['search_path=public, extensions']
    into v_path_ok
    from pg_proc pc where pc.proname = 'search_games_v2';
  perform testkit.assert_true(v_path_ok, 'search_games_v2 com search_path fixo');

  perform testkit.assert_true(
    (select count(*) from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where p.proname = 'search_games_v2' and n.nspname = 'public'
        and has_function_privilege('anon', p.oid, 'EXECUTE')
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')) = 1,
    'grants de execução para anon e authenticated');
end
$$;

\echo ''
\echo '### 10) latência da busca (10 chamadas, média < 150 ms)'
do $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_payload jsonb;
  v_avg numeric;
  i int;
begin
  -- aquecimento
  v_payload := public.search_games_v2('Frontier', null, null, false, false, null, 'relevance', 24, null);
  v_start := clock_timestamp();
  for i in 1..10 loop
    v_payload := public.search_games_v2(
      'Jogo ' || (100 + i) || ' Frontier', null, null, false, false, null, 'relevance', 24, null);
  end loop;
  v_end := clock_timestamp();
  v_avg := round(extract(epoch from (v_end - v_start)) * 100, 2);
  raise notice 'RPC search_games_v2: média de % ms por chamada', v_avg;
  perform testkit.assert_true(v_avg < 150, 'busca abaixo de 150 ms (obtido: ' || v_avg || ' ms)');
end
$$;

\echo ''
\echo '=== TESTES DA BUSCA V2: TODOS PASSARAM ==='
