-- Security baseline: schemas, roles, RLS coverage, context defaults, GTIN-14 validation.
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

select has_schema('app');
select has_schema('analytics');
select has_schema('biometric');
select has_extension('vector');

select has_role('market_backend');
select has_role('market_ai_reader');
select has_role('market_analytics_owner');
select has_role('market_biometric');

select is((select rolbypassrls from pg_roles where rolname = 'market_backend'), false,
  'market_backend is subject to row level security');
select is((select rolcanlogin from pg_roles where rolname = 'market_backend'), false,
  'migrations never create a login (passwords are set by hand)');
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'app' and pg_get_userbyid(c.relowner) = 'market_backend'),
  0, 'market_backend owns nothing in app, so RLS is never bypassed by ownership');
select ok(not pg_has_role('market_backend', 'market_ai_reader', 'MEMBER'),
  'market_backend cannot turn into market_ai_reader; model SQL runs through analytics.run_query');
select ok(not pg_has_role('market_backend', 'market_biometric', 'MEMBER'),
  'market_backend cannot reach biometric templates');

select ok(not has_schema_privilege('anon', 'app', 'USAGE'), 'anon cannot reach app');
select ok(not has_schema_privilege('anon', 'analytics', 'USAGE'), 'anon cannot reach analytics');
select ok(not has_schema_privilege('anon', 'biometric', 'USAGE'), 'anon cannot reach biometric');
select ok(not has_schema_privilege('authenticated', 'app', 'USAGE'), 'authenticated cannot reach app');
select ok(not has_schema_privilege('authenticated', 'analytics', 'USAGE'), 'authenticated cannot reach analytics');
select ok(not has_schema_privilege('authenticated', 'biometric', 'USAGE'), 'authenticated cannot reach biometric');
select ok(not has_schema_privilege('market_backend', 'app_private', 'USAGE'),
  'the backend cannot reach the key that seals the request context');
select ok(not has_schema_privilege('market_ai_reader', 'app_private', 'USAGE'),
  'LLM-generated SQL cannot reach that key either');
select ok(not has_schema_privilege('anon', 'app_private', 'USAGE')
          and not has_schema_privilege('authenticated', 'app_private', 'USAGE'),
  'nor can the API roles');

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('app', 'app_private', 'biometric') and c.relkind in ('r', 'p') and not c.relrowsecurity),
  0, 'every table in app, app_private and biometric has row level security enabled');

select ok(app.is_valid_gtin14('00012345678905'), 'GTIN-14 with a valid check digit');
select ok(app.is_valid_gtin14('05901234123457'), 'EAN-13 padded to GTIN-14 with a valid check digit');
select ok(not app.is_valid_gtin14('00012345678906'), 'wrong check digit is rejected');
select ok(not app.is_valid_gtin14('12345'), 'short codes are rejected');
select ok(not app.is_valid_gtin14('0001234567890A'), 'non-digit codes are rejected');

select is(app.current_tenant_id(), null, 'no tenant without context');
select is(app.current_branch_id(), null, 'no branch without context');
select is(app.current_staff_id(), null, 'no staff without context');
select is(app.current_device_id(), null, 'no device without context');
select is(app.current_customer_id(), null, 'no customer without context');
select is(app.current_system_actor(), null, 'no system actor without context');
select is(app.is_internal(), false, 'nothing is internal without context');

select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000', p_system_actor => 'eta_worker');
select is(app.is_internal(), true, 'tenant plus system actor is an internal context');
select set_config('app.current_tenant_id', '', true);
select throws_ok($$ select app.is_internal() $$, '42501', null,
  'a context value changed outside set_context raises instead of being trusted');

select * from finish();
rollback;
