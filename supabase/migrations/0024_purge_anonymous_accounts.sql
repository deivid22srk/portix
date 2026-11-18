-- ============================================================================
-- PORTIX — 0024: limpeza das contas sem e-mail (anônimas)
--
-- CAUSA DO PASSIVO
-- O app chamava `signInAnonymously()` no boot de toda instalação
-- (`lib/core/providers.dart`), então CADA instalação/reinstalação criava uma
-- linha em `auth.users` sem e-mail. A chamada foi removida; esta migration
-- traz a ferramenta para limpar o que já foi criado.
--
-- SEGURANÇA
--   • apaga APENAS conta sem e-mail E marcada como anônima pelo GoTrue;
--   • nunca apaga conta que tenha QUALQUER identidade com e-mail (cobre o caso
--     de uma conta anônima que depois vinculou e-mail);
--   • DRY-RUN por padrão (`p_dry_run = true`): só relata;
--   • lote limitado (`p_limit`), ordenado da mais antiga para a mais nova;
--   • `security definer` com `search_path` vazio, revogada de anon/authenticated
--     — só o dono/service_role executa;
--   • é IRREVERSÍVEL: rode o dry-run, confira a amostra, então execute.
-- Idempotente (rodar de novo não acha mais nada).
-- ============================================================================

-- Universo elegível, em um lugar só (o filtro é usado três vezes).
create or replace function public.anonymous_account_ids(
  p_limit int default 5000
)
returns table (id uuid, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.created_at
  from auth.users u
  where coalesce(nullif(btrim(u.email), ''), '') = ''
    -- `to_jsonb(u)` em vez de `u.is_anonymous`: não quebra se a coluna não
    -- existir na versão do GoTrue do projeto.
    and (
      coalesce((to_jsonb(u) ->> 'is_anonymous')::boolean, false)
      or coalesce(u.raw_app_meta_data ->> 'provider', '') = 'anonymous'
    )
    and not exists (
      select 1
      from auth.identities i
      where i.user_id = u.id
        and coalesce(nullif(btrim(i.identity_data ->> 'email'), ''), '') <> ''
    )
  order by u.created_at
  limit greatest(coalesce(p_limit, 5000), 1);
$$;

comment on function public.anonymous_account_ids(int) is
  'Contas sem e-mail marcadas como anônimas pelo GoTrue, sem nenhuma identidade com e-mail. Da mais antiga para a mais nova.';

revoke all on function public.anonymous_account_ids(int) from public, anon, authenticated;

-- Limpeza em si. Dry-run por padrão.
create or replace function public.purge_anonymous_accounts(
  p_dry_run boolean default true,
  p_limit int default 5000
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit   int := least(greatest(coalesce(p_limit, 5000), 1), 50000);
  v_total   bigint;
  v_deleted int := 0;
  v_sample  uuid[];
  v_oldest  timestamptz;
  v_newest  timestamptz;
begin
  select
    count(*)::bigint,
    min(a.created_at),
    max(a.created_at)
  into v_total, v_oldest, v_newest
  from public.anonymous_account_ids(50000) a;

  select coalesce(array_agg(a.id), '{}'::uuid[])
    into v_sample
  from (select id from public.anonymous_account_ids(5)) a;

  if p_dry_run or v_total = 0 then
    return jsonb_build_object(
      'dry_run', true,
      'candidates', v_total,
      'oldest', v_oldest,
      'newest', v_newest,
      'deleted', 0,
      'sample', to_jsonb(v_sample)
    );
  end if;

  with alvo as (
    select a.id from public.anonymous_account_ids(v_limit) a
  ),
  apagadas as (
    delete from auth.users u
    using alvo a
    where u.id = a.id
    returning u.id
  )
  select count(*)::int into v_deleted from apagadas;

  return jsonb_build_object(
    'dry_run', false,
    'candidates', v_total,
    'deleted', v_deleted,
    'remaining', greatest(v_total - v_deleted, 0),
    'oldest', v_oldest,
    'newest', v_newest,
    'sample', to_jsonb(v_sample)
  );
end;
$$;

comment on function public.purge_anonymous_accounts(boolean, int) is
  'Apaga contas anônimas sem e-mail (dry-run por padrão). As FKs em cascata removem perfil, favoritos, biblioteca, downloads, avaliações e impressões. Irreversível: rode o dry-run antes.';

-- Só o dono/service_role: o cliente do app nunca executa isto.
revoke all on function public.purge_anonymous_accounts(boolean, int)
  from public, anon, authenticated;
