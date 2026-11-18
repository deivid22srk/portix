-- ============================================================================
-- PORTIX — bootstrap do ambiente de banco para os testes do feed no CI
--
-- As migrations reais rodam no Supabase, que já tem: roles `anon`,
-- `authenticated` e `service_role`, o schema `auth` (com `auth.uid()` e
-- `auth.jwt()`), a tabela `auth.users`/`auth.identities` e o schema
-- `extensions` (destino do pg_trgm).
--
-- Este arquivo reproduz o mínimo disso em um Postgres vanilla para que as
-- migrations possam ser aplicadas e exercitadas de verdade (RLS incluída).
-- NÃO é migration: nunca é aplicado em produção.
-- ============================================================================

create schema if not exists extensions;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role noinherit bypassrls;
  end if;
end
$$;

create schema if not exists auth;

create table if not exists auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               text,
  is_anonymous        boolean not null default false,
  raw_user_meta_data  jsonb not null default '{}'::jsonb,
  raw_app_meta_data   jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table if not exists auth.identities (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  provider      text not null default 'email',
  identity_data jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- `auth.uid()` como no Supabase, mais um atalho `app.current_uid` para os
-- testes simularem a sessão de um usuário sem montar um JWT.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('app.current_uid', true), '')::uuid,
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  );
$$;

create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant select on auth.users to anon, authenticated, service_role;
grant select, insert, update, delete on auth.users, auth.identities
  to service_role;
