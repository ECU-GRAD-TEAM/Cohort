-- The login role the API connects as. It is NOINHERIT, so it holds no privileges of its own:
-- each request switches to "authenticated" (SET LOCAL ROLE) and runs under that role's grants
-- and row-level security. A request that fails to switch can read and write nothing, so the
-- API fails closed.
--
-- This creates the role without a password. Set one per environment, outside version control:
--   alter role cohort_api with password '...';

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'cohort_api') then
    create role cohort_api login noinherit;
  end if;
end;
$$;

grant authenticated to cohort_api;
