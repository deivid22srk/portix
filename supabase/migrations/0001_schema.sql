-- ============================================================================
-- PORTIX — schema base
-- Modelado a partir dos campos reais de napl_android_port_catalog.json:
--   games[] (name, slug, year, coverUrl, genre, description, platforms, ports[])
--   ports[] (portId, project, platform, link, url, dataUrl, developer, version,
--            lastUpdate, dateAdded, needsGameFiles, works, controllerSupport,
--            notes, sourceRowIndex)
-- Popularidade vem de sourceRows[].VISITAS (o JSON processado não traz visitas).
-- ============================================================================

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------- plataformas
create table if not exists public.platforms (
  id          smallint generated always as identity primary key,
  slug        text not null unique,
  name        text not null,
  full_name   text,
  kind        text not null default 'console'
              check (kind in ('console', 'handheld', 'mobile', 'multi', 'other')),
  sort_order  smallint not null default 100
);

-- --------------------------------------------------------------------- jogos
create table if not exists public.games (
  id               uuid primary key default gen_random_uuid(),
  slug             text not null unique,
  title            text not null,
  year             smallint,
  genre            text,
  description      text not null default '',
  cover_url        text,
  developer        text,
  platforms        text[] not null default '{}',
  platform_slugs   text[] not null default '{}',
  port_count       integer not null default 0,
  visit_count      bigint not null default 0,
  is_free          boolean not null default false,
  needs_rom        boolean not null default false,
  released_on      date,
  last_activity_on date,
  rating_avg       numeric(3, 2) not null default 0,
  rating_count     integer not null default 0,
  created_at       timestamptz not null default now()
);

-- --------------------------------------------------------------------- ports
create table if not exists public.ports (
  id                    uuid primary key default gen_random_uuid(),
  port_key              text not null unique,
  game_id               uuid not null references public.games(id) on delete cascade,
  platform_id           smallint not null references public.platforms(id),
  project               text,
  source                text,
  url                   text,
  data_url              text,
  developer             text,
  version               text,
  last_update           date,
  date_added            date,
  needs_game_files      boolean not null default false,
  needs_game_files_note text,
  works                 text check (works is null or works in ('yes', 'no', 'untested', 'bug', 'partial')),
  controller_support    text,
  notes                 text,
  visits                integer not null default 0,
  sort_index            integer not null default 0
);

-- -------------------------------------------------------------------- perfis
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Jogador',
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------- avaliações
create table if not exists public.reviews (
  id         uuid primary key default gen_random_uuid(),
  game_id    uuid not null references public.games(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  rating     smallint not null check (rating between 1 and 5),
  body       text not null default '' check (char_length(body) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, user_id)
);

-- ------------------------------------------------------------------ favoritos
create table if not exists public.favorites (
  user_id    uuid not null references auth.users(id) on delete cascade,
  game_id    uuid not null references public.games(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, game_id)
);

-- ------------------------------------------------------------------ biblioteca
create table if not exists public.library (
  user_id    uuid not null references auth.users(id) on delete cascade,
  game_id    uuid not null references public.games(id) on delete cascade,
  status     text not null default 'installed' check (status in ('installed', 'playing', 'finished')),
  created_at timestamptz not null default now(),
  primary key (user_id, game_id)
);

-- ------------------------------------------------------------------- downloads
create table if not exists public.downloads (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  game_id    uuid not null references public.games(id) on delete cascade,
  port_key   text,
  status     text not null default 'queued'
             check (status in ('queued', 'downloading', 'paused', 'done', 'failed')),
  progress   smallint not null default 0 check (progress between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, game_id)
);

-- --------------------------------------------------------------------- índices
create index if not exists games_trending_idx       on public.games (visit_count desc, title);
create index if not exists games_release_idx        on public.games (released_on desc nulls last);
create index if not exists games_genre_idx          on public.games (genre) where genre is not null;
create index if not exists games_year_idx           on public.games (year desc nulls last);
create index if not exists games_free_idx           on public.games (is_free);
create index if not exists games_platform_slugs_idx on public.games using gin (platform_slugs);
create index if not exists games_title_trgm_idx     on public.games using gin (title extensions.gin_trgm_ops);
create index if not exists games_developer_trgm_idx on public.games using gin (developer extensions.gin_trgm_ops);
create index if not exists ports_game_idx           on public.ports (game_id);
create index if not exists ports_platform_idx       on public.ports (platform_id);
create index if not exists reviews_game_idx         on public.reviews (game_id, created_at desc);
create index if not exists favorites_user_idx       on public.favorites (user_id, created_at desc);
create index if not exists library_user_idx         on public.library (user_id, created_at desc);
create index if not exists downloads_user_idx       on public.downloads (user_id, updated_at desc);

-- -------------------------------------------------- atualiza nota agregada
create or replace function public.refresh_game_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.game_id, old.game_id);
begin
  update public.games g
     set rating_avg   = coalesce((select round(avg(r.rating)::numeric, 2) from public.reviews r where r.game_id = target), 0),
         rating_count = (select count(*) from public.reviews r where r.game_id = target)
   where g.id = target;
  return null;
end;
$$;

drop trigger if exists reviews_refresh_rating on public.reviews;
create trigger reviews_refresh_rating
after insert or update or delete on public.reviews
for each row execute function public.refresh_game_rating();

-- ------------------------------------------------ perfil criado no cadastro
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Jogador'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------ grants
grant usage on schema public to anon, authenticated;
grant select on public.platforms, public.games, public.ports to anon, authenticated;
grant select, insert, update, delete on public.profiles, public.reviews,
  public.favorites, public.library, public.downloads to authenticated;
grant select on public.reviews to anon;
