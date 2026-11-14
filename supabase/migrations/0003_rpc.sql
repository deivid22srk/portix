-- ============================================================================
-- PORTIX — consultas de leitura (uma chamada por tela, agregadas no banco)
-- Todas devolvem jsonb para manter o cliente simples e o payload enxuto.
-- ============================================================================

create or replace view public.game_cards
with (security_invoker = true) as
select
  g.id, g.slug, g.title, g.year, g.genre, g.developer, g.cover_url,
  g.platforms, g.platform_slugs, g.port_count, g.visit_count, g.is_free,
  g.needs_rom, g.released_on, g.rating_avg, g.rating_count
from public.games g;

grant select on public.game_cards to anon, authenticated;

-- ------------------------------------------------------------------- home
create or replace function public.home_feed(p_limit int default 10)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select jsonb_build_object(
  'trending', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.rating_avg, c.rating_count, c.is_free
      from public.game_cards c
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'recent', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.rating_avg, c.rating_count, c.is_free
      from public.game_cards c
      where c.released_on is not null
      order by c.released_on desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'free', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.rating_avg, c.rating_count, c.is_free
      from public.game_cards c
      where c.is_free
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'classics', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.rating_avg, c.rating_count, c.is_free
      from public.game_cards c
      where c.year is not null and c.year <= 2000
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'platforms', (
    select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from (
      select pl.slug, pl.name, pl.full_name, pl.kind, pl.sort_order,
             count(po.id)::int as port_count
      from public.platforms pl
      left join public.ports po on po.platform_id = pl.id
      group by pl.id, pl.slug, pl.name, pl.full_name, pl.kind, pl.sort_order
      order by pl.sort_order asc, pl.name asc
    ) p
  ),
  'genres', (
    select coalesce(jsonb_agg(to_jsonb(gg)), '[]'::jsonb) from (
      select g.genre as name, count(*)::int as game_count
      from public.games g
      where coalesce(g.genre, '') <> ''
      group by g.genre
      order by count(*) desc, g.genre asc
      limit 16
    ) gg
  ),
  'stats', jsonb_build_object(
    'games', (select count(*) from public.games),
    'ports', (select count(*) from public.ports),
    'platforms', (select count(*) from public.platforms)
  )
);
$$;

-- ------------------------------------------------------------------- busca
create or replace function public.search_games(
  p_query      text    default null,
  p_platform   text    default null,
  p_genre      text    default null,
  p_free_only  boolean default false,
  p_needs_rom  boolean default false,
  p_sort       text    default 'relevance',
  p_limit      int     default 24,
  p_offset     int     default 0
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with q as (
  select nullif(trim(coalesce(p_query, '')), '') as term
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(to_jsonb(t) - 'total_count' - 'score'), '[]'::jsonb),
  'total', coalesce(max(t.total_count), 0)
)
from (
  select c.*,
         count(*) over() as total_count,
         case when (select term from q) is not null
              then extensions.similarity(c.title, (select term from q))
              else 0 end as score
  from public.game_cards c, q
  where (
      q.term is null
      or c.title ilike '%' || q.term || '%'
      or coalesce(c.developer, '') ilike '%' || q.term || '%'
      or coalesce(c.genre, '') ilike '%' || q.term || '%'
    )
    and (p_platform is null or p_platform = any(c.platform_slugs))
    and (p_genre is null or c.genre = p_genre)
    and (not coalesce(p_free_only, false) or c.is_free)
    and (not coalesce(p_needs_rom, false) or c.needs_rom)
  order by
    (case when p_sort = 'az' then c.title end) asc,
    (case when p_sort = 'recent' then c.released_on end) desc nulls last,
    (case when p_sort = 'year' then c.year end) desc nulls last,
    (case when p_sort = 'trending' then c.visit_count end) desc nulls last,
    score desc,
    c.visit_count desc,
    c.title asc
  limit least(greatest(p_limit, 1), 60)
  offset greatest(p_offset, 0)
) t;
$$;

-- ------------------------------------------------------------ por plataforma
create or replace function public.games_by_platform(
  p_platform text,
  p_limit    int default 24,
  p_offset   int default 0
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select jsonb_build_object(
  'items', coalesce(jsonb_agg(to_jsonb(t) - 'total_count'), '[]'::jsonb),
  'total', coalesce(max(t.total_count), 0)
)
from (
  select c.*, count(*) over() as total_count
  from public.game_cards c
  where p_platform = any(c.platform_slugs)
  order by c.visit_count desc, c.title asc
  limit least(greatest(p_limit, 1), 60)
  offset greatest(p_offset, 0)
) t;
$$;

-- ------------------------------------------------------------------ facetas
create or replace function public.catalog_facets()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select jsonb_build_object(
  'platforms', (
    select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) from (
      select pl.slug, pl.name, pl.kind, count(po.id)::int as port_count
      from public.platforms pl
      left join public.ports po on po.platform_id = pl.id
      group by pl.id, pl.slug, pl.name, pl.kind, pl.sort_order
      order by pl.sort_order asc, pl.name asc
    ) p
  ),
  'genres', (
    select coalesce(jsonb_agg(to_jsonb(gg)), '[]'::jsonb) from (
      select g.genre as name, count(*)::int as game_count
      from public.games g
      where coalesce(g.genre, '') <> ''
      group by g.genre
      order by count(*) desc, g.genre asc
    ) gg
  )
);
$$;

-- ---------------------------------------------------------------- detalhes
create or replace function public.game_detail(p_slug text)
returns jsonb
language sql
stable
security invoker
set search_path = public
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
      select r.id, r.rating, r.body, r.created_at, r.user_id,
             coalesce(pr.display_name, 'Jogador') as author
      from public.reviews r
      left join public.profiles pr on pr.id = r.user_id
      where r.game_id = g.id
      order by r.created_at desc
      limit 30
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
  )
)
from public.games g
where g.slug = p_slug;
$$;

-- ----------------------------------------------------- favoritos / biblioteca
create or replace function public.toggle_favorite(p_game uuid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  removed boolean;
begin
  if uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  delete from public.favorites f
   where f.user_id = uid and f.game_id = p_game
  returning true into removed;
  if removed then
    return false;
  end if;
  insert into public.favorites (user_id, game_id) values (uid, p_game)
  on conflict do nothing;
  return true;
end;
$$;

create or replace function public.toggle_library(p_game uuid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  removed boolean;
begin
  if uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  delete from public.library l
   where l.user_id = uid and l.game_id = p_game
  returning true into removed;
  if removed then
    return false;
  end if;
  insert into public.library (user_id, game_id) values (uid, p_game)
  on conflict do nothing;
  return true;
end;
$$;

-- ------------------------------------------------- coleções do usuário atual
create or replace function public.my_collections()
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select jsonb_build_object(
  'favorites', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url,
             c.platforms, c.port_count, c.visit_count, c.rating_avg, c.rating_count
      from public.favorites f
      join public.game_cards c on c.id = f.game_id
      where f.user_id = auth.uid()
      order by f.created_at desc
    ) x
  ),
  'library', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url,
             c.platforms, c.port_count, c.visit_count, c.rating_avg, c.rating_count,
             l.status, l.created_at as added_at
      from public.library l
      join public.game_cards c on c.id = l.game_id
      where l.user_id = auth.uid()
      order by l.created_at desc
    ) x
  ),
  'downloads', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select d.id, d.game_id, d.port_key, d.status, d.progress, d.updated_at,
             c.title, c.slug, c.cover_url
      from public.downloads d
      join public.game_cards c on c.id = d.game_id
      where d.user_id = auth.uid()
      order by d.updated_at desc
    ) x
  )
);
$$;

-- -------------------------------------------------------------------- grants
grant execute on function public.home_feed(int)                                   to anon, authenticated;
grant execute on function public.search_games(text, text, text, boolean, boolean, text, int, int) to anon, authenticated;
grant execute on function public.games_by_platform(text, int, int)                 to anon, authenticated;
grant execute on function public.catalog_facets()                                  to anon, authenticated;
grant execute on function public.game_detail(text)                                 to anon, authenticated;
grant execute on function public.toggle_favorite(uuid)                             to authenticated;
grant execute on function public.toggle_library(uuid)                              to authenticated;
grant execute on function public.my_collections()                                  to authenticated;
