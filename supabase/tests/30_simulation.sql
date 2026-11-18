-- ============================================================================
-- PORTIX — simulação do feed: 20 aberturas, antes × depois (CI)
--
-- Mede o que a missão exige:
--   • % de repetição no top 10 entre aberturas CONSECUTIVAS
--   • cobertura do catálogo em 20 aberturas (itens distintos) e o ganho vs a
--     linha de base (RPC legada)
--   • distribuição por categoria/desenvolvedor
--   • relevância preservada (score médio do topo vs média do catálogo)
-- Roda falhando o CI se as metas não forem atingidas.
-- ============================================================================

create temp table sim (
  cenario        text not null,
  perfil         text not null,
  avg_rep        numeric,
  distinct_items int,
  top5_dev       numeric,
  distinct_genres int,
  avg_rating     numeric,
  avg_score      numeric
);

grant insert, select on sim to anon, authenticated;

\echo ''
\echo '### CENÁRIO A — usuário NOVO (anônimo, cold start)'
set role anon;
select set_config('app.current_uid', '', false);
insert into sim
  select 'A - novo' as cenario, 'antes' as perfil, s.*
  from testkit.simulate('before', 20, 10) s;
insert into sim
  select 'A - novo', 'depois', s.*
  from testkit.simulate('after', 20, 10) s;
reset role;

\echo ''
\echo '### CENÁRIO B — usuário COM HISTÓRICO (30 favoritos, 15 biblioteca, 25 downloads, 200 impressões)'
set role authenticated;
select set_config('app.current_uid', '11111111-1111-1111-1111-111111111111', false);
insert into sim
  select 'B - veterano', 'antes', s.*
  from testkit.simulate('before', 20, 10) s;
insert into sim
  select 'B - veterano', 'depois', s.*
  from testkit.simulate('after', 20, 10) s;
reset role;

\echo ''
\echo '### RELATÓRIO — 20 aberturas, top 10 por abertura'
select
  cenario,
  perfil,
  avg_rep          as repeticao_top10_pct,
  distinct_items   as itens_distintos_em_20_aberturas,
  top5_dev         as share_top5_devs_pct,
  distinct_genres  as generos_distintos,
  avg_rating       as nota_media_topo,
  avg_score        as score_medio_topo
from sim
order by cenario, perfil;

\echo ''
\echo '### COBERTURA — ganho em relação à linha de base (legada)'
select
  cenario,
  max(distinct_items) filter (where perfil = 'antes')  as antes_itens,
  max(distinct_items) filter (where perfil = 'depois') as depois_itens,
  round(
    max(distinct_items) filter (where perfil = 'depois')::numeric
    / greatest(max(distinct_items) filter (where perfil = 'antes'), 1),
    2
  ) as ganho_x
from sim
group by cenario
order by cenario;

\echo ''
\echo '### LINHA DE BASE da RPC legada (uso interno)'
select public.home_feed(10) ? 'trending' as legada_ok;

-- ------------------------------------------------------------------ metas
do $$
declare
  v_rep_after    numeric;
  v_rep_before   numeric;
  v_cov_a        numeric;
  v_cov_b        numeric;
  v_score_after  numeric;
  v_score_cat    numeric;
  v_rating       numeric;
  v_genres       int;
begin
  select max(avg_rep) into v_rep_after from sim where perfil = 'depois';
  select max(avg_rep) into v_rep_before from sim where perfil = 'antes';
  select max(avg_score) into v_score_after from sim where perfil = 'depois';
  select min(avg_rating) into v_rating from sim where perfil = 'depois';
  select min(distinct_genres) into v_genres from sim where perfil = 'depois';

  select round(
    max(distinct_items) filter (where perfil = 'depois')::numeric
    / greatest(max(distinct_items) filter (where perfil = 'antes'), 1),
    2
  )
  into v_cov_a
  from sim where cenario = 'A - novo';

  select round(
    max(distinct_items) filter (where perfil = 'depois')::numeric
    / greatest(max(distinct_items) filter (where perfil = 'antes'), 1),
    2
  )
  into v_cov_b
  from sim where cenario = 'B - veterano';

  -- Média do score no catálogo inteiro: se o topo não for bem acima disso, o
  -- feed virou sorteio.
  select avg((e->>'score')::numeric) into v_score_cat
  from jsonb_array_elements(public.feed_candidates('catalogo', '{}'::uuid[])) e;

  raise notice 'repetição top10: antes % %% → depois % %%', v_rep_before, v_rep_after;
  raise notice 'cobertura: A % x | B % x', v_cov_a, v_cov_b;
  raise notice 'score médio do topo % vs média do catálogo %',
    v_score_after, round(v_score_cat, 4);

  perform testkit.assert_true(
    v_rep_after < 30,
    'META repetição no top 10 < 30% (obtido ' || v_rep_after || '%)'
  );
  perform testkit.assert_true(
    v_rep_before > v_rep_after,
    'o feed antigo repetia mais que o novo (antes ' || v_rep_before
      || '% vs depois ' || v_rep_after || '%)'
  );
  perform testkit.assert_true(
    v_cov_a >= 3 and v_cov_b >= 3,
    'META cobertura ≥3x a linha de base (A ' || v_cov_a || 'x, B ' || v_cov_b || 'x)'
  );
  perform testkit.assert_true(
    v_score_after >= v_score_cat * 1.5,
    'relevância preservada: score do topo ≥1,5x a média do catálogo ('
      || v_score_after || ' vs ' || round(v_score_cat, 4) || ')'
  );
  perform testkit.assert_true(
    v_rating >= 3.0,
    'topo do feed não é lixo: nota média ≥3,0 (obtido ' || v_rating || ')'
  );
  perform testkit.assert_true(
    v_genres >= 4,
    'topo do feed cobre pelo menos 4 gêneros (obtido ' || v_genres || ')'
  );
end
$$;

\echo ''
\echo '=== simulação do feed: METAS ATINGIDAS ==='
