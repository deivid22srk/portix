-- ============================================================================
-- PORTIX — 0012: feedback unificado (avaliação + como roda) com FPS
--
-- Unifica `reviews` e `compat_reports` num único fluxo:
--   * reviews ganha veredito, FPS e dados do aparelho;
--   * só contas reais podem enviar;
--   * agregados e lista pública passam a ler de reviews;
--   * `game_compat_reports` devolve nota, texto, FPS e aparelho (sem user_id).
-- Idempotente.
-- ============================================================================

alter table public.reviews add column if not exists verdict text;
update public.reviews set verdict = 'good' where verdict is null;
alter table public.reviews alter column verdict set default 'good';
alter table public.reviews alter column verdict set not null;

alter table public.reviews drop constraint if exists reviews_verdict_check;
alter table public.reviews
  add constraint reviews_verdict_check
  check (verdict in ('perfect', 'good', 'stutter', 'unplayable', 'not_run'));

alter table public.reviews add column if not exists fps smallint;
alter table public.reviews add column if not exists brand text;
alter table public.reviews add column if not exists model text;
alter table public.reviews add column if not exists soc text;
alter table public.reviews add column if not exists gpu text;
alter table public.reviews add column if not exists ram_gb integer;

alter table public.reviews drop constraint if exists reviews_fps_check;
alter table public.reviews
  add constraint reviews_fps_check
  check (fps is null or (fps between 0 and 120));

create index if not exists reviews_soc_idx on public.reviews (soc);

-- Só conta real envia feedback (sessão anônima não).
drop policy if exists reviews_insert_own on public.reviews;
create policy reviews_insert_own on public.reviews
  for insert to authenticated
  with check (
    auth.uid() = user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists reviews_update_own on public.reviews;
create policy reviews_update_own on public.reviews
  for update to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

-- -------------------------------------------------- resumo a partir de reviews
create or replace function public.compat_summary(p_game uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'perfect',    count(*) filter (where verdict = 'perfect'),
    'good',       count(*) filter (where verdict = 'good'),
    'stutter',    count(*) filter (where verdict = 'stutter'),
    'unplayable', count(*) filter (where verdict = 'unplayable'),
    'not_run',    count(*) filter (where verdict = 'not_run'),
    'total',      count(*)
  )
  from public.reviews
  where game_id = p_game;
$$;

grant execute on function public.compat_summary(uuid) to anon, authenticated;

-- ------------------------------- lista pública unificada (sem user_id/nota)
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
      r.rating,
      r.body,
      r.verdict as status,
      r.fps,
      r.brand, r.model, r.soc, r.gpu, r.ram_gb,
      r.created_at
    from public.reviews r
    left join public.profiles pr on pr.id = r.user_id
    where r.game_id = p_game
    order by r.created_at desc
    limit 500
  ) x;
$$;

grant execute on function public.game_compat_reports(uuid) to anon, authenticated;

-- --------------------------------- game_detail com os campos do feedback
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
             coalesce(pr.display_name, 'Jogador') as author
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