-- ============================================================================
-- PORTIX — 0011: contas, perfil com capa e feedback de compatibilidade v2
--
-- * profiles: capa do perfil (cover_url) + leitura do próprio perfil.
-- * compat_reports: veredito ampliado + dados do aparelho (marca, modelo,
--   processador/soc, gpu, ram) e escrita só para contas reais (não anônimas).
-- * RPCs: submit_compat_report v2 e game_compat_reports (lista pública sem
--   expor user_id/nota) para a comunidade ver como roda por aparelho.
-- Idempotente.
-- ============================================================================

-- ------------------------------------------------------------- perfis
alter table public.profiles add column if not exists cover_url text;
alter table public.profiles
  drop constraint if exists profiles_cover_url_len;
alter table public.profiles
  add constraint profiles_cover_url_len check (cover_url is null or char_length(cover_url) <= 500);

-- o dono pode ler o próprio perfil (antes removemos a leitura pública)
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (auth.uid() = id);

grant select on public.profiles to authenticated;

-- -------------------------------------------------- compat_reports v2
alter table public.compat_reports add column if not exists brand   text;
alter table public.compat_reports add column if not exists model   text;
alter table public.compat_reports add column if not exists soc     text;
alter table public.compat_reports add column if not exists gpu     text;
alter table public.compat_reports add column if not exists ram_gb  integer;

-- migra vereditos antigos para o novo conjunto (remove o check antigo antes)
alter table public.compat_reports drop constraint if exists compat_reports_status_check;

update public.compat_reports set status = 'good'    where status = 'works';
update public.compat_reports set status = 'stutter' where status = 'patch';
update public.compat_reports set status = 'not_run' where status = 'broken';

alter table public.compat_reports
  add constraint compat_reports_status_check
  check (status in ('perfect', 'good', 'stutter', 'unplayable', 'not_run'));

create index if not exists compat_reports_soc_idx on public.compat_reports (soc);

-- escrita só para contas reais (sessão anônima não envia feedback)
drop policy if exists compat_write_own on public.compat_reports;
create policy compat_write_own on public.compat_reports
  for all to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

-- --------------------------------------------------------- RPCs: resumo
create or replace function public.compat_summary(p_game uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'perfect',   count(*) filter (where status = 'perfect'),
    'good',      count(*) filter (where status = 'good'),
    'stutter',   count(*) filter (where status = 'stutter'),
    'unplayable',count(*) filter (where status = 'unplayable'),
    'not_run',   count(*) filter (where status = 'not_run'),
    'total',     count(*)
  )
  from public.compat_reports
  where game_id = p_game;
$$;

grant execute on function public.compat_summary(uuid) to anon, authenticated;

-- ------------------------------------------- RPC: enviar feedback (real)
drop function if exists public.submit_compat_report(uuid, text);
create or replace function public.submit_compat_report(
  p_game   uuid,
  p_status text,
  p_brand  text default null,
  p_model  text default null,
  p_soc    text default null,
  p_gpu    text default null,
  p_ram_gb integer default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  anon boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
begin
  if uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if anon then
    raise exception 'ACCOUNT_REQUIRED';
  end if;
  if p_status not in ('perfect', 'good', 'stutter', 'unplayable', 'not_run') then
    raise exception 'INVALID_STATUS';
  end if;

  insert into public.compat_reports
    (game_id, user_id, status, brand, model, soc, gpu, ram_gb, updated_at)
  values
    (p_game, uid, p_status,
     left(p_brand, 60), left(p_model, 80), left(p_soc, 120), left(p_gpu, 120),
     case when p_ram_gb is null then null else greatest(0, least(p_ram_gb, 1024)) end,
     now())
  on conflict (game_id, user_id) do update
    set status = excluded.status,
        brand = excluded.brand,
        model = excluded.model,
        soc = excluded.soc,
        gpu = excluded.gpu,
        ram_gb = excluded.ram_gb,
        updated_at = now();
  return true;
end;
$$;

grant execute on function public.submit_compat_report(uuid, text, text, text, text, text, integer)
  to authenticated;

-- -------------------------------- RPC: lista pública (sem user_id/nota)
create or replace function public.game_compat_reports(p_game uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  from (
    select
      coalesce(pr.display_name, 'Jogador') as author,
      nullif(pr.cover_url, '') as author_cover,
      cr.status,
      cr.brand, cr.model, cr.soc, cr.gpu, cr.ram_gb,
      cr.created_at
    from public.compat_reports cr
    left join public.profiles pr on pr.id = cr.user_id
    where cr.game_id = p_game
    order by cr.created_at desc
    limit 200
  ) x;
$$;

grant execute on function public.game_compat_reports(uuid) to anon, authenticated;
