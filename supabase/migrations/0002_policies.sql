-- ============================================================================
-- PORTIX — RLS
-- Catálogo: leitura pública, escrita negada (nenhuma policy de INSERT/UPDATE).
-- Dados de usuário: somente o dono, sempre via auth.uid().
-- ============================================================================

alter table public.platforms  enable row level security;
alter table public.games      enable row level security;
alter table public.ports      enable row level security;
alter table public.profiles   enable row level security;
alter table public.reviews    enable row level security;
alter table public.favorites  enable row level security;
alter table public.library    enable row level security;
alter table public.downloads  enable row level security;

grant select on public.profiles to anon;

-- ------------------------------------------------------------------ catálogo
drop policy if exists "platforms_public_read" on public.platforms;
create policy "platforms_public_read" on public.platforms
  for select to anon, authenticated using (true);

drop policy if exists "games_public_read" on public.games;
create policy "games_public_read" on public.games
  for select to anon, authenticated using (true);

drop policy if exists "ports_public_read" on public.ports;
create policy "ports_public_read" on public.ports
  for select to anon, authenticated using (true);

-- ------------------------------------------------------------------- perfis
drop policy if exists "profiles_public_read" on public.profiles;
create policy "profiles_public_read" on public.profiles
  for select to anon, authenticated using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- --------------------------------------------------------------- avaliações
drop policy if exists "reviews_public_read" on public.reviews;
create policy "reviews_public_read" on public.reviews
  for select to anon, authenticated using (true);

drop policy if exists "reviews_insert_own" on public.reviews;
create policy "reviews_insert_own" on public.reviews
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "reviews_update_own" on public.reviews;
create policy "reviews_update_own" on public.reviews
  for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "reviews_delete_own" on public.reviews;
create policy "reviews_delete_own" on public.reviews
  for delete to authenticated using (auth.uid() = user_id);

-- ---------------------------------------------------------------- favoritos
drop policy if exists "favorites_own" on public.favorites;
create policy "favorites_own" on public.favorites
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- --------------------------------------------------------------- biblioteca
drop policy if exists "library_own" on public.library;
create policy "library_own" on public.library
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------- downloads
drop policy if exists "downloads_own" on public.downloads;
create policy "downloads_own" on public.downloads
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
