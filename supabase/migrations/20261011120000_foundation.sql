-- Foundation: schemas, extensions, application roles, request-context readers and
-- shared trigger helpers. Runs on Supabase as the non-superuser `postgres`.

create schema if not exists extensions;
create extension if not exists vector with schema extensions;

create schema if not exists app;
create schema if not exists analytics;
create schema if not exists biometric;

comment on schema app is
  'Market SaaS business data. Reached only by the backend role market_backend; not exposed through the Supabase Data API.';
comment on schema analytics is
  'Governed read-only views for NL-to-SQL. Queried as market_ai_reader.';
comment on schema biometric is
  'Face Pay templates, kept apart from identity data (PDPL Law 151/2020). Only market_biometric may enter.';

-- Roles are created without login; passwords are set by hand (supabase/README.md).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'market_backend') then
    create role market_backend nologin nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'market_ai_reader') then
    create role market_ai_reader nologin nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'market_analytics_owner') then
    create role market_analytics_owner nologin nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'market_biometric') then
    create role market_biometric nologin nobypassrls;
  end if;
end $$;

grant market_ai_reader to market_backend;
-- On Supabase the migrating role (postgres) is not a superuser: it needs membership to hand
-- objects to these roles and to SET ROLE into them for tests (Supabase docs: grant the
-- custom role to postgres).
grant market_backend, market_ai_reader, market_analytics_owner, market_biometric to current_user;

revoke all on schema app, analytics, biometric from public;
grant usage on schema app to market_backend, market_analytics_owner;
grant usage on schema analytics to market_ai_reader;
grant usage on schema biometric to market_biometric;
-- No grant on the extensions schema: Supabase may not let postgres give it away, so code that
-- needs pgvector's operators runs as security definer instead.

-- Supabase's API roles must never reach these schemas, whatever the project defaults are.
do $$
declare
  api_role text;
begin
  foreach api_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = api_role) then
      execute format('revoke all on schema app, analytics, biometric from %I', api_role);
    end if;
  end loop;
end $$;

alter role market_backend set search_path = app, extensions, public;
alter role market_biometric set search_path = biometric, extensions, public;

-- Request context (ADR-004). The backend sets these per transaction through
-- app.set_context(); unset values read as NULL so policies match nothing.
create or replace function app.current_tenant_id() returns uuid
language sql stable parallel safe
as $$ select nullif(pg_catalog.current_setting('app.current_tenant_id', true), '')::uuid $$;

create or replace function app.current_branch_id() returns uuid
language sql stable parallel safe
as $$ select nullif(pg_catalog.current_setting('app.current_branch_id', true), '')::uuid $$;

create or replace function app.current_staff_id() returns uuid
language sql stable parallel safe
as $$ select nullif(pg_catalog.current_setting('app.current_staff_id', true), '')::uuid $$;

create or replace function app.current_device_id() returns uuid
language sql stable parallel safe
as $$ select nullif(pg_catalog.current_setting('app.current_device_id', true), '')::uuid $$;

create or replace function app.current_customer_id() returns uuid
language sql stable parallel safe
as $$ select nullif(pg_catalog.current_setting('app.current_customer_id', true), '')::uuid $$;

create or replace function app.current_system_actor() returns text
language sql stable parallel safe
as $$ select nullif(pg_catalog.current_setting('app.current_system_actor', true), '') $$;

-- Internal = acting for the business (staff, till or background job) inside a tenant.
create or replace function app.is_internal() returns boolean
language sql stable parallel safe
as $$
  select app.current_tenant_id() is not null
     and (app.current_staff_id() is not null
          or app.current_device_id() is not null
          or app.current_system_actor() is not null)
$$;

create or replace function app.set_updated_at() returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create or replace function app.prevent_mutation() returns trigger
language plpgsql
as $$
begin
  raise exception 'append-only table: % on %.% is not allowed', tg_op, tg_table_schema, tg_table_name;
end
$$;

create or replace function app.prevent_delete() returns trigger
language plpgsql
as $$
begin
  raise exception 'rows in %.% are permanent records and cannot be deleted', tg_table_schema, tg_table_name;
end
$$;

-- GS1 mod-10 check for a normalised GTIN-14 (text, so leading zeros survive).
create or replace function app.is_valid_gtin14(p_code text) returns boolean
language plpgsql immutable parallel safe
as $$
declare
  v_sum int := 0;
begin
  if p_code is null or p_code !~ '^[0-9]{14}$' then
    return false;
  end if;
  for i in 1..13 loop
    v_sum := v_sum + substr(p_code, i, 1)::int * (case when i % 2 = 1 then 3 else 1 end);
  end loop;
  return (10 - v_sum % 10) % 10 = substr(p_code, 14, 1)::int;
end
$$;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend, market_analytics_owner;
