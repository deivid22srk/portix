-- ============================================================================
-- PORTIX — 0013: hierarquia de administradores e estatísticas
--
-- * admin_roles: papéis (root/admin/moderator) com permissões por chave.
-- * Bootstrap do root pelo e-mail psvstore01@gmail.com no login.
-- * RPCs (SECURITY DEFINER): admin_bootstrap, admin_me, admin_stats,
--   admin_list, admin_grant, admin_revoke e helpers de permissão.
-- * Moderação: quem tiver 'moderate_reviews' pode apagar qualquer avaliação.
-- * Selo público de ADM nos relatos (author_role), sem expor o user_id.
-- Idempotente.
-- ============================================================================

create table if not exists public.admin_roles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  level       text not null default 'moderator'
              check (level in ('root', 'admin', 'moderator')),
  permissions jsonb not null default '{}'::jsonb,
  granted_by  uuid,
  created_at  timestamptz not null default now()
);

alter table public.admin_roles enable row level security;
revoke all on public.admin_roles from public, anon, authenticated;

-- --------------------------------------------------------------- helpers
create or replace function public.admin_role_level(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select level from public.admin_roles where user_id = p_user;
$$;

grant execute on function public.admin_role_level(uuid) to anon, authenticated;

create or replace function public.admin_has_permission(p_perm text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when level = 'root' then true
      else coalesce((permissions ->> p_perm)::boolean, false)
    end
    from public.admin_roles
    where user_id = auth.uid()
  ), false);
$$;

grant execute on function public.admin_has_permission(text) to authenticated;

-- ------------------------------------------------------------- identidade
create or replace function public.admin_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  mail text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if uid is null then
    return null;
  end if;
  if mail = 'psvstore01@gmail.com' then
    insert into public.admin_roles (user_id, level, permissions)
    values (uid, 'root', '{}'::jsonb)
    on conflict (user_id) do update set level = 'root';
  end if;
  return (
    select jsonb_build_object('level', level, 'permissions', permissions)
    from public.admin_roles where user_id = uid
  );
end;
$$;

grant execute on function public.admin_bootstrap() to authenticated;

create or replace function public.admin_me()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('level', level, 'permissions', permissions)
  from public.admin_roles where user_id = auth.uid();
$$;

grant execute on function public.admin_me() to authenticated;

-- ----------------------------------------------------------- estatísticas
create or replace function public.admin_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.admin_roles where user_id = auth.uid()) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return jsonb_build_object(
    'games',     (select count(*) from public.games),
    'ports',     (select count(*) from public.ports),
    'platforms', (select count(*) from public.platforms),
    'users',     (select count(*) from auth.users),
    'admins',    (select count(*) from public.admin_roles),
    'reviews',   (select count(*) from public.reviews),
    'favorites', (select count(*) from public.favorites),
    'library',   (select count(*) from public.library),
    'downloads', (select count(*) from public.downloads),
    'feedback',  (select count(*) from public.reviews),
    'recent_reviews', (
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
        select r.id, r.rating, r.verdict, r.fps, r.body, r.created_at,
               g.title as game, coalesce(pr.display_name, 'Jogador') as author,
               public.admin_role_level(r.user_id) as author_role
        from public.reviews r
        join public.games g on g.id = r.game_id
        left join public.profiles pr on pr.id = r.user_id
        order by r.created_at desc
        limit 20
      ) x
    )
  );
end;
$$;

grant execute on function public.admin_stats() to authenticated;

-- ------------------------------------------------------- gestão de ADMs
create or replace function public.admin_list()
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
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb) from (
      select ar.user_id, u.email, ar.level, ar.permissions, ar.created_at
      from public.admin_roles ar
      join auth.users u on u.id = ar.user_id
    ) x
  );
end;
$$;

grant execute on function public.admin_list() to authenticated;

create or replace function public.admin_grant(
  p_email       text,
  p_level       text,
  p_permissions jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target uuid;
begin
  if public.admin_role_level(auth.uid()) is distinct from 'root' then
    raise exception 'ROOT_REQUIRED';
  end if;
  if p_level not in ('root', 'admin', 'moderator') then
    raise exception 'INVALID_LEVEL';
  end if;

  select id into target from auth.users where lower(email) = lower(p_email);
  if target is null then
    raise exception 'USER_NOT_FOUND';
  end if;

  insert into public.admin_roles (user_id, level, permissions, granted_by)
  values (target, p_level, coalesce(p_permissions, '{}'::jsonb), auth.uid())
  on conflict (user_id) do update
    set level = excluded.level,
        permissions = excluded.permissions,
        granted_by = auth.uid();
  return true;
end;
$$;

grant execute on function public.admin_grant(text, text, jsonb) to authenticated;

create or replace function public.admin_revoke(p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.admin_role_level(auth.uid()) is distinct from 'root' then
    raise exception 'ROOT_REQUIRED';
  end if;
  if p_user = auth.uid() then
    raise exception 'CANNOT_REVOKE_SELF';
  end if;
  delete from public.admin_roles where user_id = p_user and level <> 'root';
  return true;
end;
$$;

grant execute on function public.admin_revoke(uuid) to authenticated;

-- ------------------------------------------------ moderação de avaliações
drop policy if exists reviews_delete_moderator on public.reviews;
create policy reviews_delete_moderator on public.reviews
  for delete to authenticated
  using (public.admin_has_permission('moderate_reviews'));

-- ------------------------------- selo de ADM nos relatos (sem user_id)
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
      public.admin_role_level(r.user_id) as author_role,
      r.rating, r.body, r.verdict as status, r.fps,
      r.brand, r.model, r.soc, r.gpu, r.ram_gb, r.created_at
    from public.reviews r
    left join public.profiles pr on pr.id = r.user_id
    where r.game_id = p_game
    order by r.created_at desc
    limit 500
  ) x;
$$;

grant execute on function public.game_compat_reports(uuid) to anon, authenticated;

create or replace function public.game_detail(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
select jsonb_build_object(
  'game', to_jsonb(g),
  'ports', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_index asc), '[]'::jsonb) from (
      select po.id, po.port_key, po.project, po.source, po.url, po.data_url,
             po.developer, po.version, po.last_update, po.date_added,
             po.needs_game_files, po.needs_game_files_note, po.works,
             po.controller_support, po.notes, po.visits, po.sort_index,
             pl.slug as platform_slug, pl.name as platform_name, pl.kind as platform_kind
      from public.ports po
      join public.platforms pl on pl.id = po.platform_id
      where po.game_id = g.id
    ) x
  ),
  'reviews', (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) from (
      select r.id, r.rating, r.body, r.created_at, r.verdict, r.fps,
             r.brand, r.model, r.soc, r.gpu, r.ram_gb,
             coalesce(pr.display_name, 'Jogador') as author,
             public.admin_role_level(r.user_id) as author_role
      from public.reviews r
      left join public.profiles pr on pr.id = r.user_id
      where r.game_id = g.id
      order by r.created_at desc
      limit 500
    ) x
  ),
  'related', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url,
             c.rating_avg, c.rating_count, c.visit_count
      from public.game_cards c
      where c.id <> g.id
        and (
          (coalesce(g.genre, '') <> '' and c.genre = g.genre)
          or c.platform_slugs && g.platform_slugs
        )
      order by (c.genre = g.genre) desc, c.visit_count desc
      limit 8
    ) x
  ),
  'compat', public.compat_summary(g.id)
)
from public.games g
where g.slug = p_slug;
$$;

grant execute on function public.game_detail(text) to anon, authenticated;
