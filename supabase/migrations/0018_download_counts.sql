-- ============================================================================
-- PORTIX — 0018: contagem real de downloads
--
-- Substitui a exibição da "popularidade" por uma contagem verdadeira de
-- downloads concluídos por jogo (tabela downloads, status='done').
-- O `visit_count` continua existindo apenas para ordenação interna.
-- Idempotente.
-- ============================================================================

alter table public.games add column if not exists download_count integer not null default 0;

create or replace function public.refresh_game_downloads()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target uuid := coalesce(new.game_id, old.game_id);
begin
  update public.games g
     set download_count = (
       select count(*) from public.downloads d
       where d.game_id = target and d.status = 'done'
     )
   where g.id = target;
  return null;
end;
$$;

drop trigger if exists downloads_refresh_count on public.downloads;
create trigger downloads_refresh_count
after insert or update or delete on public.downloads
for each row execute function public.refresh_game_downloads();

-- backfill
update public.games g
   set download_count = (
     select count(*) from public.downloads d
     where d.game_id = g.id and d.status = 'done'
   );

-- ---------------------------------------------- view com a nova coluna
create or replace view public.game_cards
with (security_invoker = true) as
select
  g.id, g.slug, g.title, g.year, g.genre, g.developer, g.cover_url,
  g.platforms, g.platform_slugs, g.port_count, g.visit_count, g.is_free,
  g.needs_rom, g.released_on, g.rating_avg, g.rating_count, g.download_count
from public.games g;

grant select on public.game_cards to anon, authenticated;

-- --------------------------------------------------------------- home_feed
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
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'recent', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.released_on is not null
      order by c.released_on desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'top_rated', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.rating_count > 0
      order by c.rating_avg desc, c.rating_count desc, c.visit_count desc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'free', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.is_free
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
  'classics', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.download_count, c.rating_avg,
             c.rating_count, c.is_free
      from public.game_cards c
      where c.year is not null and c.year <= 2000
      order by c.visit_count desc, c.title asc
      limit least(greatest(p_limit, 1), 20)
    ) x
  ),
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

grant execute on function public.home_feed(int) to anon, authenticated;

-- --------------------------------------------------------------- news_feed
create or replace function public.news_feed(p_limit int default 20, p_offset int default 0)
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
  select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
         c.port_count, c.visit_count, c.download_count, c.rating_avg,
         c.rating_count, c.is_free, c.needs_rom, c.released_on,
         case when g.last_activity_on is not null then 'updated' else 'added' end as kind,
         coalesce(g.last_activity_on, g.released_on) as event_on,
         count(*) over() as total_count
  from public.games g
  join public.game_cards c on c.id = g.id
  where g.last_activity_on is not null or g.released_on is not null
  order by coalesce(g.last_activity_on, g.released_on) desc nulls last,
           c.visit_count desc, c.title asc
  limit least(greatest(p_limit, 1), 60)
  offset greatest(p_offset, 0)
) t;
$$;

grant execute on function public.news_feed(int, int) to anon, authenticated;

-- --------------------------------------------------------- game_detail (related)
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
             c.rating_avg, c.rating_count, c.visit_count, c.download_count
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

-- ------------------------------------------------------- my_collections
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
             c.platforms, c.port_count, c.visit_count, c.download_count,
             c.rating_avg, c.rating_count
      from public.favorites f
      join public.game_cards c on c.id = f.game_id
      where f.user_id = auth.uid()
      order by f.created_at desc
    ) x
  ),
  'library', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url,
             c.platforms, c.port_count, c.visit_count, c.download_count,
             c.rating_avg, c.rating_count, l.status, l.created_at as added_at
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

grant execute on function public.my_collections() to authenticated;
