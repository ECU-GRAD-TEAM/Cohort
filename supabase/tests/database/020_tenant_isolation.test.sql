-- Tenant isolation (REQ-SECU-01): without context nothing is visible; with context only
-- the caller's tenant is; writes and references cannot cross tenants.
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

set local role market_backend;

select is((select count(*)::int from app.tenants), 0, 'no tenant is visible without context');
select is((select count(*)::int from app.branches), 0, 'no branch is visible without context');
select is((select count(*)::int from app.staff), 0, 'no staff is visible without context');
select is((select count(*)::int from app.pos_devices), 0, 'no device is visible without context');
select is((select count(*)::int from app.customers), 0, 'no customer is visible without context');

-- Nile owner
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select is((select count(*)::int from app.branches), 4, 'Nile owner sees the four Nile branches');
select is((select count(*)::int from app.branches where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000000'), 0,
  'Nile owner cannot see Alpha branches even when asking for them');
select is((select count(*)::int from app.tenants), 1, 'Nile owner sees only the Nile tenant row');
select is((select count(*)::int from app.staff where tenant_id <> 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'Nile owner sees no staff of other tenants');
select is((select count(*)::int from app.pos_devices), 2, 'Nile owner sees the two Nile tills');
select is((select count(*)::int from app.regions), 2, 'Nile owner sees the two Nile regions');

select throws_ok(
  $$ insert into app.branches (tenant_id, kind, name, code)
     values ('aaaaaaaa-0000-0000-0000-000000000000', 'store', 'Injected', 'INJ') $$,
  '42501', null, 'a branch cannot be created inside another tenant');

select throws_ok(
  $$ insert into app.staff_assignments (tenant_id, staff_id, role_id, scope, branch_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0003-0000-0000-000000000005',
             (select id from app.roles where code = 'cashier' and tenant_id is null),
             'branch', 'aaaaaaaa-0002-0000-0000-000000000001') $$,
  '23503', null, 'an assignment cannot point at another tenant''s branch');

update app.branches set name = 'Hijacked' where id = 'aaaaaaaa-0002-0000-0000-000000000001';

-- set_context refuses identities that do not belong together
select throws_ok(
  $$ select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                            p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001') $$,
  '42501', null, 'staff of another tenant are rejected');
select throws_ok(
  $$ select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                            p_device_id => 'aaaaaaaa-0004-0000-0000-000000000001') $$,
  '42501', null, 'a device of another tenant is rejected');
select throws_ok(
  $$ select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                            p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001',
                            p_branch_id => 'bbbbbbbb-0002-0000-0000-000000000002') $$,
  '42501', null, 'a branch other than the device''s own branch is rejected');
select throws_ok(
  $$ select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                            p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001',
                            p_branch_id => 'aaaaaaaa-0002-0000-0000-000000000001') $$,
  '42501', null, 'a branch of another tenant is rejected');
select throws_ok(
  $$ select app.set_context(p_staff_id => 'bbbbbbbb-0003-0000-0000-000000000001') $$,
  '42501', null, 'staff context without a tenant is rejected');

-- A shopper browsing the Nile storefront sees the store directory, nothing internal
select app.set_context(p_tenant_id   => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.branches), 4, 'a shopper can read the store directory');
select is((select count(*)::int from app.staff), 0, 'a shopper cannot read staff');
select is((select count(*)::int from app.pos_devices), 0, 'a shopper cannot read devices');
select is((select count(*)::int from app.regions), 0, 'a shopper cannot read the regional structure');
select is((select count(*)::int from app.customers), 1, 'a shopper reads only their own customer row');

-- Alpha owner
select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select is((select count(*)::int from app.branches), 1, 'Alpha owner sees its single store');
select is((select count(*)::int from app.pos_devices), 1, 'Alpha owner sees its single till');

-- A context value written around set_context is rejected instead of trusted
select set_config('app.current_tenant_id', 'bbbbbbbb-0000-0000-0000-000000000000', true);
select throws_ok($$ select count(*) from app.branches $$, '42501', null,
  'another tenant''s id written with set_config raises instead of switching tenant');

reset role;
select is((select name from app.branches where id = 'aaaaaaaa-0002-0000-0000-000000000001'), 'Alpha Maadi',
  'an update aimed at another tenant''s branch changed nothing');

select * from finish();
rollback;
