-- Authority over the business itself (spec §3.4): who may grant roles, manage staff and
-- configure the tenant is enforced by the database, so a backend authorization bug cannot let
-- a cashier take over accounts, grant itself more power or switch off loss prevention.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

set local role market_backend;

-- A Maadi cashier at the Maadi till tries to take over
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000006',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
select throws_ok(
  $$ insert into app.staff_assignments (tenant_id, staff_id, role_id, scope)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0003-0000-0000-000000000006',
             (select id from app.roles where tenant_id is null and code = 'owner'), 'tenant') $$,
  '42501', null, 'a cashier cannot make itself owner');
select throws_ok(
  $$ insert into app.roles (tenant_id, code, name)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'night_owner', 'Night owner') $$,
  '42501', null, 'a cashier cannot create roles');
select throws_ok(
  $$ insert into app.loss_prevention_settings (tenant_id, unlinked_refund_amount)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 100000.00) $$,
  '42501', null, 'a cashier cannot raise the loss-prevention thresholds');
update app.staff set auth_user_id = 'eeeeeeee-0003-0000-0000-0000000000ff'
 where id = 'bbbbbbbb-0003-0000-0000-000000000001';
update app.staff set pin_hash = 'known-to-the-cashier'
 where id = 'bbbbbbbb-0003-0000-0000-000000000004';
update app.branches set name = 'Hijacked' where id = 'bbbbbbbb-0002-0000-0000-000000000003';
update app.tenants set status = 'suspended' where id = 'bbbbbbbb-0000-0000-0000-000000000000';

reset role;
select is((select auth_user_id from app.staff where id = 'bbbbbbbb-0003-0000-0000-000000000001'),
  'eeeeeeee-0003-0000-0000-000000000011'::uuid, 'a cashier cannot move the owner''s login to its own account');
select is((select pin_hash from app.staff where id = 'bbbbbbbb-0003-0000-0000-000000000004'), null,
  'a cashier cannot set the branch manager''s till PIN');
select is((select name from app.branches where id = 'bbbbbbbb-0002-0000-0000-000000000003'), 'Nile Smouha',
  'a cashier cannot reconfigure a branch');
select is((select status from app.tenants where id = 'bbbbbbbb-0000-0000-0000-000000000000'), 'active',
  'a cashier cannot suspend the whole market');

-- The Cairo regional manager may manage staff in the Cairo region, never beyond its own power
set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000002');
select lives_ok(
  $$ insert into app.staff_assignments (tenant_id, staff_id, role_id, scope, branch_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0003-0000-0000-000000000006',
             (select id from app.roles where tenant_id is null and code = 'stock_clerk'), 'branch',
             'bbbbbbbb-0002-0000-0000-000000000002') $$,
  'a regional manager can give a Maadi cashier stock duties in Maadi');
select throws_ok(
  $$ insert into app.staff_assignments (tenant_id, staff_id, role_id, scope, branch_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0003-0000-0000-000000000006',
             (select id from app.roles where tenant_id is null and code = 'branch_manager'), 'branch',
             'bbbbbbbb-0002-0000-0000-000000000002') $$,
  '42501', null, 'a regional manager cannot grant a role holding permissions it lacks (selling, discounts)');
select throws_ok(
  $$ insert into app.staff_assignments (tenant_id, staff_id, role_id, scope, branch_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0003-0000-0000-000000000006',
             (select id from app.roles where tenant_id is null and code = 'stock_clerk'), 'branch',
             'bbbbbbbb-0002-0000-0000-000000000003') $$,
  '42501', null, 'a Cairo regional manager cannot assign anyone in Alexandria');
select throws_ok(
  $$ insert into app.staff_assignments (tenant_id, staff_id, role_id, scope)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0003-0000-0000-000000000006',
             (select id from app.roles where tenant_id is null and code = 'stock_clerk'), 'tenant') $$,
  '42501', null, 'only tenant-wide authority grants tenant-wide roles');
update app.staff set pin_hash = 'set-by-regional-manager' where id = 'bbbbbbbb-0003-0000-0000-000000000006';
update app.staff set pin_hash = 'set-by-regional-manager' where id = 'bbbbbbbb-0003-0000-0000-000000000001';

reset role;
select is((select pin_hash from app.staff where id = 'bbbbbbbb-0003-0000-0000-000000000006'), 'set-by-regional-manager',
  'a regional manager can reset the PIN of staff who work only in its region');
select is((select pin_hash from app.staff where id = 'bbbbbbbb-0003-0000-0000-000000000001'), null,
  'a regional manager cannot touch the owner''s account');

-- The owner keeps full authority
set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select lives_ok(
  $$ insert into app.regions (tenant_id, name, code) values ('bbbbbbbb-0000-0000-0000-000000000000', 'Delta', 'DLT') $$,
  'the owner can add a region');
select lives_ok(
  $$ insert into app.staff_assignments (tenant_id, staff_id, role_id, scope, branch_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0003-0000-0000-000000000006',
             (select id from app.roles where tenant_id is null and code = 'branch_manager'), 'branch',
             'bbbbbbbb-0002-0000-0000-000000000002') $$,
  'the owner can promote the Maadi cashier to branch manager');
select lives_ok(
  $$ insert into app.loss_prevention_settings (tenant_id, unlinked_refund_amount)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 100.00) $$,
  'the owner can tune the loss-prevention thresholds');

-- A branch time zone decides local dates in analytics and the transit expiry guard
select throws_ok($$ update app.branches set timezone = 'Cairo' where id = 'bbbbbbbb-0002-0000-0000-000000000003' $$,
  '22023', null, 'a branch time zone must be one Postgres knows');
select lives_ok($$ update app.branches set timezone = 'Africa/Cairo' where id = 'bbbbbbbb-0002-0000-0000-000000000003' $$,
  'a real IANA zone is accepted');
reset role;

select * from finish();
rollback;
