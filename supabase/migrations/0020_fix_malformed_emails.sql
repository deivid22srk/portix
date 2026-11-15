-- ============================================================================
-- PORTIX — 0020: corrige e-mails sem TLD no Supabase Auth
--
-- Contas antigas foram criadas com o domínio incompleto (ex.: "fulano@gmail"
-- em vez de "fulano@gmail.com"). Como o login usa o e-mail exato, a conta
-- ficava inacessível depois que o app passou a exigir domínio com ponto.
--
-- Esta migration completa o domínio com ".com" quando ele não tem nenhum
-- ponto, tanto em auth.users quanto em auth.identities (inclui o JSON
-- identity_data). O e-mail corrigido não sobrescreve uma conta já existente.
-- Idempotente: rodar novamente não altera nada.
-- ============================================================================

-- ------------------------------------------------------------- auth.users
update auth.users u
set email      = u.email || '.com',
    updated_at = now()
where u.email ~ '^[^@[:space:]]+@[A-Za-z0-9-]+$'
  and not exists (
    select 1
    from auth.users other
    where other.id <> u.id
      and other.email = u.email || '.com'
  );

-- -------------------------------------------------------- auth.identities
update auth.identities i
set identity_data = jsonb_set(
      i.identity_data,
      '{email}',
      to_jsonb((i.identity_data ->> 'email') || '.com'),
      true
    ),
    updated_at = now()
where i.provider = 'email'
  and i.identity_data ->> 'email' ~ '^[^@[:space:]]+@[A-Za-z0-9-]+$';
