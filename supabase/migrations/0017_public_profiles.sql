-- ============================================================================
-- PORTIX — 0017: perfis públicos, @handle e busca por usuários
--
-- * profiles.handle: único (case-insensitive) e com formato validado.
-- * set_handle(): o usuário define/limpa o próprio @.
-- * search_users(): busca por handle/nome (só quem tem @).
-- * profile_public(id): perfil público (nome, @, capa, nível, biblioteca).
-- * Feedback passa a incluir author_id/author_handle/author_cover (avatar).
-- Idempotente.
-- ============================================================================

alter table public.profiles add column if not exists handle text;

create unique index if not exists profiles_handle_unique
  on public.profiles (lower(handle)) where handle is not null;

alter table public.profiles drop constraint if exists profiles_handle_format;
alter table public.profiles
  add constraint profiles_handle_format
  check (handle is null or handle ~ '^[a-z0-9_]{3,20}$');

-- --------------------------------------------------------------- set_handle
create or replace function public.set_handle(p_handle text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  h text := lower(regexp_replace(trim(coalesce(p_handle, '')), '^@', ''));
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if h = '' then
    update public.profiles set handle = null where id = auth.uid();
    return null;
  end if;
  if h !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'INVALID_HANDLE';
  end if;
  begin
    update public.profiles set handle = h where id = auth.uid();
  exception when unique_violation then
    raise exception 'HANDLE_TAKEN';
  end;
  return h;
end;
$$;

grant execute on function public.set_handle(text) to authenticated;

-- ------------------------------------------------------------- search_users
create or replace function public.search_users(
  p_query  text default null,
  p_limit  int default 20,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select jsonb_build_object(
      'items', coalesce(jsonb_agg(to_jsonb(t) - 'total_count'), '[]'::jsonb),
      'total', coalesce(max(t.total_count), 0)
    )
    from (
      select p.id, p.display_name, p.handle, nullif(p.cover_url, '') as cover_url,
             public.admin_role_level(p.id) as level,
             count(*) over() as total_count
      from public.profiles p
      where coalesce(p.handle, '') <> ''
        and (
          coalesce(trim(p_query), '') = ''
          or p.handle ilike '%' || trim(p_query) || '%'
          or p.display_name ilike '%' || trim(p_query) || '%'
        )
      order by p.handle asc
      limit least(greatest(p_limit, 1), 50)
      offset greatest(p_offset, 0)
    ) t
  );
end;
$$;

grant execute on function public.search_users(text, int, int) to anon, authenticated;

-- ----------------------------------------------------------- profile_public
create or replace function public.profile_public(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select jsonb_build_object(
      'id', p.id,
      'display_name', p.display_name,
      'handle', p.handle,
      'cover_url', nullif(p.cover_url, ''),
      'level', public.admin_role_level(p.id),
      'library', (
        select coalesce(jsonb_agg(to_jsonb(c) - 'total_count'), '[]'::jsonb) from (
          select gc.id, gc.slug, gc.title, gc.year, gc.genre, gc.cover_url,
                 gc.platforms, gc.port_count, gc.visit_count, gc.rating_avg,
                 gc.rating_count, gc.is_free
          from public.library l
          join public.game_cards gc on gc.id = l.game_id
          where l.user_id = p.id
          order by l.created_at desc
          limit 60
        ) c
      )
    )
    from public.profiles p
    where p.id = p_id
  );
end;
$$;

grant execute on function public.profile_public(uuid) to anon, authenticated;

-- ------------------------------- feedback com avatar/handle (sem e-mail)
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
      r.user_id as author_id,
      coalesce(pr.display_name, 'Jogador') as author,
      pr.handle as author_handle,
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
      select r.id, r.user_id as author_id, r.rating, r.body, r.created_at, r.verdict, r.fps,
             r.brand, r.model, r.soc, r.gpu, r.ram_gb,
             coalesce(pr.display_name, 'Jogador') as author,
             pr.handle as author_handle,
             nullif(pr.cover_url, '') as author_cover,
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
