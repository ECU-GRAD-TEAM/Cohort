-- Foundation for the Cohort database (paper sections 6.4 to 6.6).
-- Extensions, the private helper schema, default privileges and shared trigger functions.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists vector with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- Row-level security helpers live in "private". The schema is not exposed through the
-- Data API, so clients can only reach these functions indirectly, through policies.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;
alter default privileges for role postgres in schema private
  grant execute on functions to authenticated, service_role;

-- Nothing is readable without signing in, and functions are granted explicitly
-- instead of being executable by everyone.
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
alter default privileges for role postgres revoke execute on functions from public;
-- TRUNCATE ignores row-level security, so signed-in users never get it.
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from authenticated;

create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Attached as a BEFORE UPDATE OR DELETE trigger to tables that are evidence:
-- audit and access logs, consent records, risk scores.
create function private.reject_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only: % is not allowed', tg_table_name, lower(tg_op)
    using errcode = 'insufficient_privilege';
end;
$$;
