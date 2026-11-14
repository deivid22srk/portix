-- ============================================================================
-- PORTIX — 0008: privacidade de reviews/profiles e rate limit
--
-- Sinais do Atacante tratados:
--   * `profiles`/`reviews` com SELECT público (USING true) deixavam qualquer
--     cliente anônimo listar UUIDs de auth.users, display_name e o corpo de
--     todas as avaliações.
--   * cadastro anônimo sem limite permitia criar contas e injetar conteúdo.
--
-- Causa raiz: leitura direta de tabelas que só precisam ser consumidas via RPC
-- e ausência de limite de escrita.
--
-- Correções (preservando o app):
--   * `game_detail` passa a SECURITY DEFINER (search_path vazio) e continua
--     entregando reviews + autor; o cliente deixa de ler as tabelas direto.
--   * SELECT direto em `profiles` revogado; em `reviews` fica só do dono.
--   * Triggers de rate limit por usuário em `reviews` e `compat_reports`.
-- Idempotente.
-- ============================================================================

-- --------------------------------------------------- profiles: sem leitura direta
drop policy if exists profiles_public_read on public.profiles;
revoke select on public.profiles from anon, authenticated;
-- escrita do próprio perfil segue permitida (RLS)
grant insert, update on public.profiles to authenticated;

-- --------------------------------------------------- reviews: leitura só do dono
drop policy if exists reviews_public_read on public.reviews;
drop policy if exists reviews_own_read on public.reviews;
create policy reviews_own_read on public.reviews
  for select to authenticated using (auth.uid() = user_id);
revoke select on public.reviews from anon;

-- ------------------------------------- game_detail definer (reviews + autor)
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
      select r.id, r.rating, r.body, r.created_at,
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

-- ------------------------------------------------------------- rate limit
create or replace function public.rate_limit_reviews()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent int;
begin
  select count(*) into recent
    from public.reviews
   where user_id = new.user_id and created_at > now() - interval '10 minutes';
  if recent >= 10 then
    raise exception 'RATE_LIMIT_REVIEWS';
  end if;
  return new;
end;
$$;

drop trigger if exists reviews_rate_limit on public.reviews;
create trigger reviews_rate_limit
before insert on public.reviews
for each row execute function public.rate_limit_reviews();

create or replace function public.rate_limit_compat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent int;
begin
  select count(*) into recent
    from public.compat_reports
   where user_id = new.user_id and created_at > now() - interval '10 minutes';
  if recent >= 30 then
    raise exception 'RATE_LIMIT_COMPAT';
  end if;
  return new;
end;
$$;

drop trigger if exists compat_rate_limit on public.compat_reports;
create trigger compat_rate_limit
before insert on public.compat_reports
for each row execute function public.rate_limit_compat();

-- os triggers rodam como definer; ninguém precisa de EXECUTE direto
revoke execute on function public.rate_limit_reviews() from public, anon, authenticated;
revoke execute on function public.rate_limit_compat() from public, anon, authenticated;
