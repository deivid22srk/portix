-- ============================================================================
-- PORTIX — 0009: timestamps só do servidor (corrige bypass do rate limit)
--
-- Sinal do Atacante: como `created_at` é gravável pelo cliente, dava para
-- inserir linhas retroativas (ex.: created_at=2000-01-01) que nunca entram na
-- janela do rate limit.
--
-- Causa raiz: timestamps controlados pelo cliente. Correção: triggers que
-- sobrescrevem created_at/updated_at com now() no servidor. Os triggers de
-- carimbo são nomeados `a_*` para rodarem antes dos de rate limit (`r_*`),
-- pois o Postgres dispara triggers BEFORE em ordem alfabética.
-- Idempotente.
-- ============================================================================

create or replace function public.stamp_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.created_at := now();
  return new;
end;
$$;

create or replace function public.stamp_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ------------------------------------------------------------- reviews
drop trigger if exists a_created on public.reviews;
drop trigger if exists a_updated on public.reviews;
drop trigger if exists r_rate_limit on public.reviews;
create trigger a_created before insert on public.reviews
  for each row execute function public.stamp_created();
create trigger a_updated before insert or update on public.reviews
  for each row execute function public.stamp_updated();
create trigger r_rate_limit before insert on public.reviews
  for each row execute function public.rate_limit_reviews();

-- ------------------------------------------------------ compat_reports
drop trigger if exists a_created on public.compat_reports;
drop trigger if exists a_updated on public.compat_reports;
drop trigger if exists r_rate_limit on public.compat_reports;
create trigger a_created before insert on public.compat_reports
  for each row execute function public.stamp_created();
create trigger a_updated before insert or update on public.compat_reports
  for each row execute function public.stamp_updated();
create trigger r_rate_limit before insert on public.compat_reports
  for each row execute function public.rate_limit_compat();

-- ------------------------------------------------------------- downloads
drop trigger if exists a_created on public.downloads;
drop trigger if exists a_updated on public.downloads;
create trigger a_created before insert on public.downloads
  for each row execute function public.stamp_created();
create trigger a_updated before insert or update on public.downloads
  for each row execute function public.stamp_updated();

-- ----------------------------------------------- favorites / library
drop trigger if exists a_created on public.favorites;
create trigger a_created before insert on public.favorites
  for each row execute function public.stamp_created();

drop trigger if exists a_created on public.library;
create trigger a_created before insert on public.library
  for each row execute function public.stamp_created();

-- os triggers de carimbo rodam como definer; ninguém precisa de EXECUTE
revoke execute on function public.stamp_created() from public, anon, authenticated;
revoke execute on function public.stamp_updated() from public, anon, authenticated;

-- Repara linhas obviamente retrodatadas (sem tocar no histórico legítimo).
update public.compat_reports set created_at = now() where created_at < timestamptz '2020-01-01';
update public.reviews        set created_at = now() where created_at < timestamptz '2020-01-01';
update public.downloads      set created_at = now() where created_at < timestamptz '2020-01-01';
update public.favorites      set created_at = now() where created_at < timestamptz '2020-01-01';
update public.library        set created_at = now() where created_at < timestamptz '2020-01-01';
