-- ============================================================================
-- PORTIX — assertivas da limpeza de contas anônimas (CI)
--
-- Garante que a limpeza: (1) só olha conta sem e-mail E anônima; (2) NUNCA toca
-- em conta com e-mail nem em anônima que vinculou e-mail; (3) é dry-run por
-- padrão; (4) respeita o lote; (5) cascateia os dados do usuário; (6) não é
-- executável pelo cliente.
-- ============================================================================

-- ------------------------------------------------------------------ cenário
do $$
declare
  v_anon_a uuid := 'aaaa0000-0000-0000-0000-000000000001';
  v_anon_b uuid := 'aaaa0000-0000-0000-0000-000000000002';
  v_anon_c uuid := 'aaaa0000-0000-0000-0000-000000000003';
  -- anônima que DEPOIS vinculou e-mail: tem e-mail, não pode ser apagada.
  v_linked uuid := 'aaaa0000-0000-0000-0000-000000000004';
  -- conta sem e-mail, mas com identidade contendo e-mail: não pode ser apagada.
  v_identity_only uuid := 'aaaa0000-0000-0000-0000-000000000005';
  v_real   uuid := 'aaaa0000-0000-0000-0000-000000000006';
  v_game   uuid;
begin
  select id into v_game from public.games order by slug limit 1;

  insert into auth.users (id, email, is_anonymous, raw_app_meta_data, created_at)
  values
    (v_anon_a, null, true, '{"provider":"anonymous"}'::jsonb, current_timestamp - interval '90 days'),
    (v_anon_b, null, true, '{"provider":"anonymous"}'::jsonb, current_timestamp - interval '60 days'),
    (v_anon_c, null, true, '{"provider":"anonymous"}'::jsonb, current_timestamp - interval '30 days'),
    (v_linked, 'vinculado@example.test', false, '{"provider":"anonymous"}'::jsonb, current_timestamp - interval '100 days'),
    (v_identity_only, null, false, '{}'::jsonb, current_timestamp - interval '110 days'),
    (v_real, 'real@example.test', false, '{}'::jsonb, current_timestamp - interval '120 days');

  insert into auth.identities (user_id, provider, identity_data)
  values (v_identity_only, 'email', jsonb_build_object('email', 'so-identidade@example.test'));

  -- dados de usuário nas duas anônimas (têm de sumir em cascata)
  insert into public.favorites (user_id, game_id) values (v_anon_a, v_game), (v_anon_b, v_game);
  insert into public.feed_impressions (user_id, game_id, section)
  values (v_anon_a, v_game, 'teste');
end
$$;

\echo '=== contas anônimas: dry-run relata e NÃO apaga ==='
do $$
declare
  v_before bigint;
  v_after bigint;
  v_report jsonb;
begin
  select count(*) into v_before from auth.users;

  -- padrão é dry-run
  v_report := public.purge_anonymous_accounts();

  select count(*) into v_after from auth.users;

  perform testkit.assert_true(
    (v_report->>'dry_run')::boolean is true,
    'dry-run é o padrão'
  );
  perform testkit.assert_true(
    (v_report->>'candidates')::bigint = 3,
    '3 candidatas (as 6 contas sem e-mail exceto a que tem identidade com e-mail)'
  );
  perform testkit.assert_true(
    (v_report->>'deleted')::int = 0 and v_after = v_before,
    'dry-run não apaga nada'
  );
  perform testkit.assert_true(
    jsonb_array_length(v_report->'sample') = 3,
    'dry-run devolve a amostra das candidatas'
  );
end
$$;

\echo '=== contas anônimas: o lote é respeitado ==='
do $$
declare
  v_report jsonb;
begin
  v_report := public.purge_anonymous_accounts(false, 1);
  perform testkit.assert_true(
    (v_report->>'deleted')::int = 1,
    'p_limit=1 apaga exatamente uma conta'
  );
end
$$;

\echo '=== contas anônimas: apaga o resto e preserva quem tem e-mail ==='
do $$
declare
  v_report jsonb;
  v_left int;
  v_linked int;
  v_identity int;
  v_real int;
  v_favorites int;
begin
  v_report := public.purge_anonymous_accounts(false, 5000);

  perform testkit.assert_true(
    (v_report->>'deleted')::int = 2,
    'apaga as 2 anônimas restantes'
  );
  perform testkit.assert_true(
    (v_report->>'remaining')::int = 0,
    'não sobrou candidata'
  );

  select count(*) into v_left from public.anonymous_account_ids(10);
  perform testkit.assert_true(v_left = 0, 'universo de anônimas ficou vazio');

  select count(*) into v_linked
    from auth.users where email = 'vinculado@example.test';
  select count(*) into v_real
    from auth.users where email = 'real@example.test';
  select count(*) into v_identity
    from auth.users where id = 'aaaa0000-0000-0000-0000-000000000005';

  perform testkit.assert_true(v_linked = 1, 'anônima que vinculou e-mail foi preservada');
  perform testkit.assert_true(v_real = 1, 'conta real foi preservada');
  perform testkit.assert_true(
    v_identity = 1,
    'conta sem e-mail mas com identidade de e-mail foi preservada'
  );

  -- cascata: os dados das anônimas sumiram
  select count(*) into v_favorites
    from public.favorites
   where user_id in (
     'aaaa0000-0000-0000-0000-000000000001',
     'aaaa0000-0000-0000-0000-000000000002',
     'aaaa0000-0000-0000-0000-000000000003'
   );
  perform testkit.assert_true(v_favorites = 0, 'favoritos das apagadas sumiram (cascata)');
end
$$;

\echo '=== contas anônimas: rodar de novo é inofensivo ==='
do $$
declare
  v_report jsonb;
begin
  v_report := public.purge_anonymous_accounts(false, 5000);
  perform testkit.assert_true(
    (v_report->>'candidates')::bigint = 0 and (v_report->>'deleted')::int = 0,
    'segunda execução não encontra nada'
  );
end
$$;

\echo '=== contas anônimas: cliente não executa ==='
set role authenticated;
do $$
begin
  begin
    perform public.purge_anonymous_accounts(true, 10);
    raise exception 'SEGURANÇA FUROU: authenticated conseguiu chamar a limpeza';
  exception when insufficient_privilege then
    raise notice 'OK: authenticated não executa a limpeza';
  end;

  begin
    perform count(*) from public.anonymous_account_ids(5);
    raise exception 'SEGURANÇA FUROU: authenticated conseguiu listar contas anônimas';
  exception when insufficient_privilege then
    raise notice 'OK: authenticated não lista contas anônimas';
  end;
end
$$;
reset role;

\echo '=== assertivas da limpeza de contas: TODAS PASSARAM ==='
