-- ============================================================================
-- PORTIX — 0005: endurecimento de segurança (least privilege)
--
-- Achados da auditoria:
--   1. `anon`/`authenticated` herdaram ACLs padrão com INSERT/UPDATE/DELETE/
--      TRUNCATE/REFERENCES/TRIGGER em TODAS as tabelas de public. O RLS barra
--      DML sem policy, mas TRUNCATE não passa por RLS — privilégio excessivo.
--   2. Todas as funções de public tinham EXECUTE para PUBLIC (padrão); as
--      funções de trigger SECURITY DEFINER ficavam expostas.
--   3. `compat_reports` tinha SELECT público, vazando user_id/nota de todos.
--   4. Não existia o canal `breach_signal` do jogo.
--
-- Correções (mínimas, preservando o comportamento do app):
--   * least privilege por tabela/role;
--   * EXECUTE revogado de PUBLIC e reconcedido só a quem precisa;
--   * `compat_summary` vira SECURITY DEFINER (agregado sem vazar linhas) e o
--     SELECT direto em compat_reports é revogado de anon;
--   * funções SECURITY DEFINER com search_path = '';
--   * cria `breach_signal` (insert-only para clientes de baixo privilégio).
-- Idempotente.
-- ============================================================================

-- ------------------------------------------------------ canal do jogo
create table if not exists public.breach_signal (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  vector     text not null check (char_length(vector) between 1 and 200),
  proof      text not null default '' check (char_length(proof) <= 4000),
  reporter   uuid default auth.uid(),
  resolved   boolean not null default false,
  notes      text
);

alter table public.breach_signal enable row level security;

drop policy if exists breach_signal_insert on public.breach_signal;
create policy breach_signal_insert on public.breach_signal
  for insert to anon, authenticated with check (true);

drop policy if exists breach_signal_select_own on public.breach_signal;
create policy breach_signal_select_own on public.breach_signal
  for select to anon, authenticated using (reporter = auth.uid());

-- ----------------------------------------------- least privilege: tabelas
revoke all on public.platforms, public.games, public.ports,
  public.profiles, public.reviews, public.favorites, public.library,
  public.downloads, public.compat_reports, public.game_cards,
  public.breach_signal
  from public, anon, authenticated;

-- catálogo: somente leitura para todos
grant select on public.platforms, public.games, public.ports, public.game_cards
  to anon, authenticated;

-- perfis e avaliações: leitura pública; escrita só do dono (RLS)
grant select on public.profiles, public.reviews to anon, authenticated;
grant select, insert, update, delete
  on public.profiles, public.reviews to authenticated;

-- coleções do usuário: só autenticado (RLS por dono)
grant select, insert, update, delete
  on public.favorites, public.library, public.downloads to authenticated;

-- relatos de compatibilidade: anon não lê linha alguma; agregado vem por RPC
grant select, insert, update, delete on public.compat_reports to authenticated;

-- canal do jogo: clientes só inserem (e leem o próprio sinal)
grant insert, select on public.breach_signal to anon, authenticated;

-- ------------------------------------------ least privilege: funções
revoke execute on all functions in schema public from public, anon, authenticated;

-- leitura pública (catálogo)
grant execute on function public.home_feed(integer)                        to anon, authenticated;
grant execute on function public.search_games(text, text, text, boolean, boolean, text, integer, integer)
  to anon, authenticated;
grant execute on function public.games_by_platform(text, integer, integer) to anon, authenticated;
grant execute on function public.catalog_facets()                          to anon, authenticated;
grant execute on function public.game_detail(text)                         to anon, authenticated;
grant execute on function public.news_feed(integer, integer)               to anon, authenticated;
grant execute on function public.compat_summary(uuid)                      to anon, authenticated;

-- só autenticado (RLS/auth.uid() por dentro)
grant execute on function public.my_collections()                          to authenticated;
grant execute on function public.toggle_favorite(uuid)                     to authenticated;
grant execute on function public.toggle_library(uuid)                       to authenticated;
grant execute on function public.submit_compat_report(uuid, text)          to authenticated;

-- ------------------------------- compat_summary sem vazar linhas (definer)
create or replace function public.compat_summary(p_game uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
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

grant execute on function public.compat_summary(uuid) to anon, authenticated;

-- ----------------------------- SECURITY DEFINER com search_path vazio
create or replace function public.refresh_game_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
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

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Jogador'))
  on conflict (id) do nothing;
  return new;
end;
$$;
