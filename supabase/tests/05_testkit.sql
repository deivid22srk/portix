-- ============================================================================
-- PORTIX — kit de teste do feed (apenas CI)
--
-- Funções de apoio que NÃO são migration: existem só para exercitar o feed com
-- o mesmo comportamento do cliente (topo do feed, 20 aberturas) e para medir a
-- simulação. Ficam em um schema próprio, `testkit`.
-- ============================================================================

create schema if not exists testkit;

-- Topo do feed NOVO: primeiro item da primeira seção, na ordem de exibição.
create or replace function testkit.feed_ids_new(p jsonb, p_limit int default 10)
returns uuid[]
language sql
immutable
as $$
  select coalesce(array_agg(t.id order by t.ord), '{}'::uuid[])
  from (
    select (x->>'id')::uuid as id, row_number() over () as ord
    from jsonb_array_elements(coalesce(p->'sections', '[]'::jsonb)) s,
         jsonb_array_elements(s->'items') x
    limit greatest(coalesce(p_limit, 10), 1)
  ) t;
$$;

-- Topo do feed LEGADO: trending → recent → top_rated → free → classics, que é
-- exatamente a ordem em que a Início antiga pintava a tela.
create or replace function testkit.feed_ids_legacy(p jsonb, p_limit int default 10)
returns uuid[]
language sql
immutable
as $$
  select coalesce(array_agg(t.id order by t.ord), '{}'::uuid[])
  from (
    select (x->>'id')::uuid as id, row_number() over () as ord
    from jsonb_array_elements(
      coalesce(p->'trending', '[]'::jsonb)
      || coalesce(p->'recent', '[]'::jsonb)
      || coalesce(p->'top_rated', '[]'::jsonb)
      || coalesce(p->'free', '[]'::jsonb)
      || coalesce(p->'classics', '[]'::jsonb)
    ) x
    limit greatest(coalesce(p_limit, 10), 1)
  ) t;
$$;

create or replace function testkit.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if p_condition is not true then
    raise exception 'ASSERT FALHOU: %', p_message;
  end if;
  raise notice 'OK: %', p_message;
end;
$$;

-- Simula N aberturas do app e devolve as métricas que o CRÍTICO cobra.
--   p_mode = 'before' → RPC legada `home_feed` (determinística)
--   p_mode = 'after'  → `get_home_feed` com seed novo a cada abertura
-- Roda com os direitos de quem chamou (security invoker implícito), então a RLS
-- e a afinidade de `auth.uid()` valem como no app.
create or replace function testkit.simulate(
  p_mode text,
  p_openings int default 20,
  p_limit int default 10
)
returns table (
  avg_repetition_pct numeric,
  distinct_items int,
  top5_dev_share_pct numeric,
  distinct_genres int,
  avg_rating numeric,
  avg_score numeric
)
language plpgsql
stable
as $$
declare
  v_seen       uuid[] := '{}'::uuid[];
  v_ids        uuid[];
  v_prev       uuid[];
  v_all        uuid[] := '{}'::uuid[];
  v_reps       numeric[] := '{}'::numeric[];
  v_ratings    numeric[] := '{}'::numeric[];
  v_scores     numeric[] := '{}'::numeric[];
  v_devs       text[] := '{}'::text[];
  v_genres     text[] := '{}'::text[];
  v_payload    jsonb;
  v_total_devs numeric := 0;
  v_top5_devs  numeric := 0;
  i            int;
begin
  if p_mode = 'after' then
    select coalesce(array_agg(s.game_id), '{}'::uuid[])
      into v_seen
    from public.feed_seen_recent() s;
  end if;

  for i in 1..greatest(coalesce(p_openings, 20), 1) loop
    if p_mode = 'after' then
      v_payload := public.get_home_feed(
        'sim-' || lpad(i::text, 3, '0'),
        p_limit,
        v_seen,
        null,
        null
      );
      v_ids := testkit.feed_ids_new(v_payload, p_limit);
    else
      v_payload := public.home_feed(p_limit);
      v_ids := testkit.feed_ids_legacy(v_payload, p_limit);
    end if;

    if i > 1 then
      v_reps := v_reps || (
        select round(
          (
            select count(*)::numeric
            from unnest(v_ids) a
            join unnest(v_prev) b on a = b
          ) / greatest(p_limit, 1) * 100,
          1
        )
      );
    end if;

    -- Rating/score/desenvolvedor/gênero do topo desta abertura.
    select
      v_ratings || coalesce(array_agg(g.rating_avg::numeric), '{}'::numeric[]),
      v_devs || coalesce(array_agg(g.developer), '{}'::text[]),
      v_genres || coalesce(array_agg(g.genre), '{}'::text[])
    into v_ratings, v_devs, v_genres
    from public.games g
    where g.id = any (v_ids);

    if p_mode = 'after' then
      select v_scores || coalesce(array_agg((x->>'score')::numeric), '{}'::numeric[])
        into v_scores
      from jsonb_array_elements(v_payload->'sections') s,
           jsonb_array_elements(s->'items') x
      where (x->>'id')::uuid = any (v_ids);
    end if;

    v_all := v_all || v_ids;
    v_prev := v_ids;
  end loop;

  select
    coalesce(sum(c), 0),
    coalesce(sum(c) filter (where rn <= 5), 0)
  into v_total_devs, v_top5_devs
  from (
    select count(*) as c, row_number() over (order by count(*) desc) as rn
    from unnest(v_devs) d
    group by d
  ) t;

  return query
  select
    coalesce(round((select avg(r) from unnest(v_reps) r), 1), 0),
    (select count(distinct x)::int from unnest(v_all) x),
    round(v_top5_devs / greatest(v_total_devs, 1) * 100, 1),
    (select count(distinct gg)::int from unnest(v_genres) gg),
    coalesce(round((select avg(r) from unnest(v_ratings) r), 2), 0),
    coalesce(round((select avg(s) from unnest(v_scores) s), 4), 0);
end;
$$;

grant usage on schema testkit to anon, authenticated, service_role;
grant execute on all functions in schema testkit to anon, authenticated, service_role;
