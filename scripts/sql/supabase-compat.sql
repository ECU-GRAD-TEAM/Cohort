-- Supabase compatibility shim for plain PostgreSQL test databases.
-- A real Supabase project already has all of this; every statement is idempotent,
-- so it is also harmless against `supabase start`.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

create schema if not exists extensions;
grant usage on schema extensions to public;
create extension if not exists vector with schema extensions;
create extension if not exists pgtap with schema extensions;

-- Supabase hands its API roles the public schema by default.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;

do $$
begin
  execute format('alter database %I set search_path = "$user", public, extensions', current_database());
end $$;
