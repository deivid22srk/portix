-- ============================================================================
-- PORTIX — 0015: remover atualização pelo painel ADM
--
-- * admin_updates passa a devolver o id (para remover uma específica).
-- * admin_delete_update(p_id): ADM raiz remove um aviso de atualização.
-- Idempotente.
-- ============================================================================

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
      select id, version, message, url, active, created_at
      from public.app_updates
      order by created_at desc
      limit 30
    ) x
  );
end;
$$;

grant execute on function public.admin_updates() to authenticated;

create or replace function public.admin_delete_update(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.admin_role_level(auth.uid()) is distinct from 'root' then
    raise exception 'ROOT_REQUIRED';
  end if;
  delete from public.app_updates where id = p_id;
  return true;
end;
$$;

grant execute on function public.admin_delete_update(uuid) to authenticated;
