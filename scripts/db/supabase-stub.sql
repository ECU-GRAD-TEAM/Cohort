-- Stand-ins for the Supabase pieces the migrations rely on, so the schema can be built on plain
-- PostgreSQL for tests: the API roles, the "auth" and "extensions" schemas, auth.users,
-- auth.uid(), auth.jwt() and the default privileges Supabase gives new objects.
-- Never run this against a Supabase project; Supabase already provides all of it.
--
-- Roles belong to the whole cluster, not to one database, so this can run more than once.

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
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin nologin;
  end if;
end;
$$;

-- Supabase lets the postgres role switch to each API role; the smoke test relies on it.
grant anon, authenticated, service_role to postgres;

create schema if not exists extensions;
create schema if not exists auth;
grant usage on schema extensions to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_app_meta_data jsonb default '{}',
  raw_user_meta_data jsonb default '{}',
  created_at timestamptz default now()
);

-- Defined as Supabase defines them: the claims come from the request settings that PostgREST
-- (and the API) set for each request.
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

grant usage on schema public to anon, authenticated, service_role;

-- Supabase grants everything on new public objects to the API roles; the foundation migration
-- then takes some of it back and row-level security does the rest.
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to anon, authenticated, service_role;
