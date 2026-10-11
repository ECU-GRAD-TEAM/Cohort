-- Foundation: schemas, extensions, application roles, request-context readers and
-- shared trigger helpers. Runs on Supabase as the non-superuser `postgres`.

create schema if not exists extensions;
create extension if not exists vector with schema extensions;

create schema if not exists app;
create schema if not exists analytics;
create schema if not exists biometric;
create schema if not exists app_private;

comment on schema app is
  'Market SaaS business data. Reached only by the backend role market_backend; not exposed through the Supabase Data API.';
comment on schema analytics is
  'Governed read-only views for NL-to-SQL. Queried as market_ai_reader.';
comment on schema biometric is
  'Face Pay templates, kept apart from identity data (PDPL Law 151/2020). Only market_biometric may enter.';
comment on schema app_private is
  'Secrets used by the app''s own functions. No role but the owner may enter.';

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

-- market_backend is deliberately not a member of market_ai_reader: model-generated SQL runs
-- only through analytics.run_query, never after a SET ROLE it could undo.
-- On Supabase the migrating role (postgres) is not a superuser: it needs membership to hand
-- objects to these roles and to SET ROLE into them for tests (Supabase docs: grant the
-- custom role to postgres).
grant market_backend, market_ai_reader, market_analytics_owner, market_biometric to current_user;

revoke all on schema app, analytics, biometric, app_private from public;
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
      execute format('revoke all on schema app, analytics, biometric, app_private from %I', api_role);
    end if;
  end loop;
end $$;

alter role market_backend set search_path = app, extensions, public;
alter role market_biometric set search_path = biometric, extensions, public;

-- Request context (ADR-004). The backend sets it per transaction through app.set_context(),
-- which also stores a seal: a keyed hash over the values and the transaction they belong to.
-- Every reader checks the seal, so a value changed any other way (set_config, SET) raises
-- instead of being trusted, and SQL the backend runs on behalf of an LLM cannot rewrite its
-- own context. Unset values read as NULL, so policies match nothing.
create table app_private.context_key (
  singleton boolean primary key default true check (singleton),
  inner_key bytea not null check (length(inner_key) = 64),
  outer_key bytea not null check (length(outer_key) = 64)
);
-- No policies: nobody but the owner (through set_context and context_is_sealed) reads it.
alter table app_private.context_key enable row level security;
-- Two independent random 64-byte keys (four UUIDv4s each), generated once per database.
insert into app_private.context_key (inner_key, outer_key)
select decode(replace(gen_random_uuid()::text || gen_random_uuid()::text
                      || gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex'),
       decode(replace(gen_random_uuid()::text || gen_random_uuid()::text
                      || gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'hex');

-- sha256(outer || sha256(inner || message)), the NMAC construction HMAC is built on. The
-- message binds the values to this backend process and transaction, so a seal cannot be
-- replayed in a later transaction.
create function app_private.context_seal(p_values text[]) returns text
language sql stable parallel restricted
set search_path = ''
as $$
  select pg_catalog.encode(pg_catalog.sha256(k.outer_key || pg_catalog.sha256(k.inner_key || pg_catalog.convert_to(
           pg_catalog.jsonb_build_array(pg_catalog.pg_backend_pid(),
                                        extract(epoch from pg_catalog.transaction_timestamp()),
                                        p_values)::text, 'UTF8'))), 'hex')
    from app_private.context_key k
$$;
revoke execute on function app_private.context_seal(text[]) from public;

-- True when the context is empty or was set by app.set_context in this transaction; raises
-- when any context value was changed some other way.
create function app.context_is_sealed() returns boolean
language plpgsql stable parallel restricted
security definer
set search_path = ''
as $$
declare
  v_values text[] := array[
    coalesce(pg_catalog.current_setting('app.current_tenant_id', true), ''),
    coalesce(pg_catalog.current_setting('app.current_branch_id', true), ''),
    coalesce(pg_catalog.current_setting('app.current_staff_id', true), ''),
    coalesce(pg_catalog.current_setting('app.current_device_id', true), ''),
    coalesce(pg_catalog.current_setting('app.current_customer_id', true), ''),
    coalesce(pg_catalog.current_setting('app.current_system_actor', true), '')];
begin
  if pg_catalog.array_to_string(v_values, '') = '' then
    return true;
  end if;
  if pg_catalog.current_setting('app.context_seal', true) is distinct from app_private.context_seal(v_values) then
    raise exception 'the request context was not set by app.set_context' using errcode = '42501';
  end if;
  return true;
end
$$;

create or replace function app.current_tenant_id() returns uuid
language sql stable parallel restricted
as $$ select case when app.context_is_sealed() then nullif(pg_catalog.current_setting('app.current_tenant_id', true), '')::uuid end $$;

create or replace function app.current_branch_id() returns uuid
language sql stable parallel restricted
as $$ select case when app.context_is_sealed() then nullif(pg_catalog.current_setting('app.current_branch_id', true), '')::uuid end $$;

create or replace function app.current_staff_id() returns uuid
language sql stable parallel restricted
as $$ select case when app.context_is_sealed() then nullif(pg_catalog.current_setting('app.current_staff_id', true), '')::uuid end $$;

create or replace function app.current_device_id() returns uuid
language sql stable parallel restricted
as $$ select case when app.context_is_sealed() then nullif(pg_catalog.current_setting('app.current_device_id', true), '')::uuid end $$;

create or replace function app.current_customer_id() returns uuid
language sql stable parallel restricted
as $$ select case when app.context_is_sealed() then nullif(pg_catalog.current_setting('app.current_customer_id', true), '')::uuid end $$;

create or replace function app.current_system_actor() returns text
language sql stable parallel restricted
as $$ select case when app.context_is_sealed() then nullif(pg_catalog.current_setting('app.current_system_actor', true), '') end $$;

-- Internal = acting for the business (staff, till or background job) inside a tenant.
-- One seal check, then the raw values (each reader would check again).
create or replace function app.is_internal() returns boolean
language sql stable parallel restricted
as $$
  select app.context_is_sealed()
     and nullif(pg_catalog.current_setting('app.current_tenant_id', true), '') is not null
     and (nullif(pg_catalog.current_setting('app.current_staff_id', true), '') is not null
          or nullif(pg_catalog.current_setting('app.current_device_id', true), '') is not null
          or nullif(pg_catalog.current_setting('app.current_system_actor', true), '') is not null)
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
