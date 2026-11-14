-- ============================================================================
-- PORTIX — 0014: atualizações publicadas pelo ADM raiz
--
-- Permite que o ADM raiz envie um aviso de atualização para o app PORTIX.
-- O app lê o último aviso ativo pela RPC pública `latest_update`.
-- Idempotente.
-- ============================================================================

create table if not exists public.app_updates (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  version    text not null,
  message    text not null default '',
  url        text,
  active     boolean not null default true,
  created_by uuid
);

alter table public.app_updates enable row level security;
revoke all on public.app_updates from public, anon, authenticated;

-- ------------------------------------------------ leitura pública (1 aviso)
create or replace function public.latest_update()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(x) from (
    select version, message, url, created_at
    from public.app_updates
    where active
    order by created_at desc
    limit 1
  ) x;
$$;

grant execute on function public.latest_update() to anon, authenticated;

-- --------------------------------------------- publicar (só o ADM raiz)
create or replace function public.admin_publish_update(
  p_version text,
  p_message text,
  p_url     text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.admin_role_level(auth.uid()) is distinct from 'root' then
    raise exception 'ROOT_REQUIRED';
  end if;
  if coalesce(trim(p_version), '') = '' then
    raise exception 'INVALID_VERSION';
  end if;

  update public.app_updates set active = false where active;

  insert into public.app_updates (version, message, url, created_by)
  values (
    left(trim(p_version), 40),
    left(coalesce(p_message, ''), 500),
    nullif(left(coalesce(p_url, ''), 500), ''),
    auth.uid()
  );
  return true;
end;
$$;

grant execute on function public.admin_publish_update(text, text, text) to authenticated;

-- --------------------------------------------- histórico (só o ADM raiz)
create or replace function public.admin_updates()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.admin_role_level(auth.uid()) is distinct from 'root' then
    raise exception 'ROOT_REQUIRED';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) from (
      select version, message, url, active, created_at
      from public.app_updates
      order by created_at desc
      limit 30
    ) x
  );
end;
$$;

grant execute on function public.admin_updates() to authenticated;
