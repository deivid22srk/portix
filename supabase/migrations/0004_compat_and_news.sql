-- ============================================================================
-- PORTIX — 0004: relatos de compatibilidade e feed de notícias
-- Adiciona:
--   * tabela compat_reports (relatos por aparelho), com RLS por dono;
--   * RPC submit_compat_report(p_game, p_status);
--   * RPC compat_summary(p_game) -> contagens por status;
--   * game_detail passa a devolver o resumo de compatibilidade;
--   * RPC news_feed(p_limit, p_offset) para a aba Notícias.
-- Idempotente: pode ser aplicada mais de uma vez sem duplicar dados.
-- ============================================================================

-- ------------------------------------------------------ relatos de compat.
create table if not exists public.compat_reports (
  id         uuid primary key default gen_random_uuid(),
  game_id    uuid not null references public.games(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  status     text not null check (status in ('works', 'patch', 'broken')),
  note       text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, user_id)
);

create index if not exists compat_reports_game_idx on public.compat_reports (game_id, status);

alter table public.compat_reports enable row level security;

drop policy if exists "compat_public_read" on public.compat_reports;
create policy "compat_public_read" on public.compat_reports
  for select to anon, authenticated using (true);

drop policy if exists "compat_write_own" on public.compat_reports;
create policy "compat_write_own" on public.compat_reports
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select on public.compat_reports to anon, authenticated;
grant select, insert, update, delete on public.compat_reports to authenticated;

-- --------------------------------------------------- gravar/atualizar relato
create or replace function public.submit_compat_report(p_game uuid, p_status text)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_status not in ('works', 'patch', 'broken') then
    raise exception 'INVALID_STATUS';
  end if;
  insert into public.compat_reports (game_id, user_id, status, updated_at)
  values (p_game, uid, p_status, now())
  on conflict (game_id, user_id)
  do update set status = excluded.status, updated_at = now();
  return true;
end;
$$;

-- ------------------------------------------------------ resumo de compat.
create or replace function public.compat_summary(p_game uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'works',  count(*) filter (where status = 'works'),
    'patch',  count(*) filter (where status = 'patch'),
    'broken', count(*) filter (where status = 'broken'),
    'total',  count(*)
  )
  from public.compat_reports
  where game_id = p_game;
$$;

-- ---------------------------------------------------------------- notícias
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
  select g.id, g.slug, g.title, g.year, g.genre, g.cover_url, g.platforms,
         g.port_count, g.visit_count, g.rating_avg, g.rating_count, g.is_free,
         g.needs_rom, g.released_on,
         case when g.last_activity_on is not null then 'updated' else 'added' end as kind,
         coalesce(g.last_activity_on, g.released_on) as event_on,
         count(*) over() as total_count
  from public.games g
  where g.last_activity_on is not null or g.released_on is not null
  order by coalesce(g.last_activity_on, g.released_on) desc nulls last,
           g.visit_count desc, g.title asc
  limit least(greatest(p_limit, 1), 60)
  offset greatest(p_offset, 0)
) t;
$$;

-- ------------------------------------------- home com seção "mais bem avaliados"
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
  'top_rated', (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.slug, c.title, c.year, c.genre, c.cover_url, c.platforms,
             c.port_count, c.visit_count, c.rating_avg, c.rating_count, c.is_free
      from public.game_cards c
      where c.rating_count > 0
      order by c.rating_avg desc, c.rating_count desc, c.visit_count desc
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

-- ------------------------------------------- game_detail com compatibilidade
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
  ),
  'compat', public.compat_summary(g.id)
)
from public.games g
where g.slug = p_slug;
$$;

-- -------------------------------------------------------------------- grants
grant execute on function public.submit_compat_report(uuid, text) to authenticated;
grant execute on function public.compat_summary(uuid)              to anon, authenticated;
grant execute on function public.news_feed(int, int)               to anon, authenticated;
grant execute on function public.home_feed(int)                    to anon, authenticated;
grant execute on function public.game_detail(text)                 to anon, authenticated;
