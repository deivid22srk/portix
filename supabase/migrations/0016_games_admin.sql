-- ============================================================================
-- PORTIX — 0016: gerenciamento de jogos pelo painel ADM
--
-- RPCs protegidas pela permissão `manage_games` (root sempre pode):
--   * admin_platforms()        -> lista de plataformas p/ seleção
--   * admin_search_games(...)  -> busca paginada no catálogo
--   * admin_upsert_game(...)   -> cria ou atualiza um jogo
--   * admin_delete_game(id)    -> remove um jogo (cascata em ports etc.)
-- Idempotente.
-- ============================================================================

create or replace function public.admin_platforms()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.admin_has_permission('manage_games') then
    raise exception 'FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order), '[]'::jsonb) from (
      select slug, name, kind, sort_order
      from public.platforms
      order by sort_order, name
    ) x
  );
end;
$$;

grant execute on function public.admin_platforms() to authenticated;

create or replace function public.admin_search_games(
  p_query  text default null,
  p_limit  int default 30,
  p_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.admin_has_permission('manage_games') then
    raise exception 'FORBIDDEN';
  end if;
  return (
    select jsonb_build_object(
      'items', coalesce(jsonb_agg(to_jsonb(t) - 'total_count'), '[]'::jsonb),
      'total', coalesce(max(t.total_count), 0)
    )
    from (
      select g.id, g.slug, g.title, g.year, g.genre, g.developer, g.cover_url,
             g.description, g.platforms, g.platform_slugs, g.is_free, g.needs_rom,
             g.released_on, g.port_count,
             count(*) over() as total_count
      from public.games g
      where coalesce(trim(p_query), '') = ''
         or g.title ilike '%' || trim(p_query) || '%'
         or g.slug ilike '%' || trim(p_query) || '%'
         or coalesce(g.developer, '') ilike '%' || trim(p_query) || '%'
      order by g.title asc
      limit least(greatest(p_limit, 1), 100)
      offset greatest(p_offset, 0)
    ) t
  );
end;
$$;

grant execute on function public.admin_search_games(text, int, int) to authenticated;

create or replace function public.admin_upsert_game(
  p_id             uuid,
  p_title          text,
  p_slug           text,
  p_year           int,
  p_genre          text,
  p_developer      text,
  p_cover_url      text,
  p_description    text,
  p_platform_slugs text[],
  p_is_free        boolean,
  p_needs_rom      boolean,
  p_released_on    text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  names text[];
  saved public.games;
begin
  if not public.admin_has_permission('manage_games') then
    raise exception 'FORBIDDEN';
  end if;
  if coalesce(trim(p_title), '') = '' then
    raise exception 'INVALID_TITLE';
  end if;
  if coalesce(trim(p_slug), '') = '' then
    raise exception 'INVALID_SLUG';
  end if;

  select coalesce(array_agg(pl.name order by pl.sort_order), '{}') into names
  from public.platforms pl
  where pl.slug = any(coalesce(p_platform_slugs, '{}'::text[]));

  if p_id is null then
    insert into public.games (
      slug, title, year, genre, developer, cover_url, description,
      platforms, platform_slugs, is_free, needs_rom, released_on
    ) values (
      trim(p_slug), trim(p_title), p_year,
      nullif(trim(coalesce(p_genre, '')), ''),
      nullif(trim(coalesce(p_developer, '')), ''),
      nullif(trim(coalesce(p_cover_url, '')), ''),
      coalesce(p_description, ''),
      names, coalesce(p_platform_slugs, '{}'::text[]),
      coalesce(p_is_free, false), coalesce(p_needs_rom, false),
      case when coalesce(trim(p_released_on), '') = '' then null else trim(p_released_on)::date end
    ) returning * into saved;
  else
    update public.games set
      slug           = trim(p_slug),
      title          = trim(p_title),
      year           = p_year,
      genre          = nullif(trim(coalesce(p_genre, '')), ''),
      developer      = nullif(trim(coalesce(p_developer, '')), ''),
      cover_url      = nullif(trim(coalesce(p_cover_url, '')), ''),
      description    = coalesce(p_description, ''),
      platforms      = names,
      platform_slugs = coalesce(p_platform_slugs, '{}'::text[]),
      is_free        = coalesce(p_is_free, false),
      needs_rom      = coalesce(p_needs_rom, false),
      released_on    = case when coalesce(trim(p_released_on), '') = '' then null else trim(p_released_on)::date end
    where id = p_id
    returning * into saved;

    if saved.id is null then
      raise exception 'NOT_FOUND';
    end if;
  end if;

  return jsonb_build_object('id', saved.id, 'slug', saved.slug, 'title', saved.title);
end;
$$;

grant execute on function public.admin_upsert_game(uuid, text, text, int, text, text, text, text, text[], boolean, boolean, text)
  to authenticated;

create or replace function public.admin_delete_game(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.admin_has_permission('manage_games') then
    raise exception 'FORBIDDEN';
  end if;
  delete from public.games where id = p_id;
  return true;
end;
$$;

grant execute on function public.admin_delete_game(uuid) to authenticated;
