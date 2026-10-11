-- Tenant → region → branch hierarchy and spatial RBAC (REQ-PERF-02, access-control paper §3).
begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

set local role market_backend;

-- Branch reach per actor
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select is(cardinality(app.accessible_branch_ids()), 4, 'the owner reaches every Nile branch');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000002');
select is(app.accessible_branch_ids(),
  array['bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000002',
        'bbbbbbbb-0002-0000-0000-000000000004']::uuid[],
  'the Cairo regional manager reaches Nasr City, Maadi and the Cairo warehouse');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000003');
select is(app.accessible_branch_ids(), array['bbbbbbbb-0002-0000-0000-000000000003']::uuid[],
  'the Alexandria regional manager reaches only Smouha');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000004');
select is(app.accessible_branch_ids(), array['bbbbbbbb-0002-0000-0000-000000000001']::uuid[],
  'the Nasr City branch manager reaches only Nasr City');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000005',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
select is(app.accessible_branch_ids(), array['bbbbbbbb-0002-0000-0000-000000000001']::uuid[],
  'a cashier at their own till reaches that till''s branch');
select is(app.current_branch_id(), 'bbbbbbbb-0002-0000-0000-000000000001'::uuid,
  'a till context pins the active branch to the till''s branch');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000005',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
select is(cardinality(app.accessible_branch_ids()), 0,
  'a Nasr City cashier at the Maadi till reaches nothing');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001',
                       p_branch_id => 'bbbbbbbb-0002-0000-0000-000000000002');
select is(app.accessible_branch_ids(), array['bbbbbbbb-0002-0000-0000-000000000002']::uuid[],
  'an active branch narrows even the owner to that branch');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
select is(app.accessible_branch_ids(), array['bbbbbbbb-0002-0000-0000-000000000002']::uuid[],
  'a till on its own reaches only its branch');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000', p_system_actor => 'eta_worker');
select is(cardinality(app.accessible_branch_ids()), 4, 'a background job acts for the whole tenant');

select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is(cardinality(app.accessible_branch_ids()), 0, 'a shopper has no branch reach');

-- Role permissions bounded by space
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000004');
select ok(app.has_permission('REFUND_UNLINKED', 'bbbbbbbb-0002-0000-0000-000000000001'),
  'the branch manager may approve unlinked refunds in Nasr City');
select ok(not app.has_permission('REFUND_UNLINKED', 'bbbbbbbb-0002-0000-0000-000000000002'),
  'the branch manager may not refund in Maadi');
select ok(not app.has_permission('STAFF_MANAGE', null), 'the branch manager cannot manage staff tenant-wide');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000005',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
select ok(app.has_permission('REFUND_LINKED', 'bbbbbbbb-0002-0000-0000-000000000001'),
  'a cashier may refund against a receipt');
select ok(not app.has_permission('REFUND_UNLINKED', 'bbbbbbbb-0002-0000-0000-000000000001'),
  'a cashier needs a manager override for unlinked refunds');
select ok(not app.has_permission('PRICE_OVERRIDE', 'bbbbbbbb-0002-0000-0000-000000000001'),
  'a cashier needs a manager override for price overrides');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000002');
select ok(app.has_permission('PRICE_MANAGE', 'bbbbbbbb-0002-0000-0000-000000000002'),
  'the Cairo regional manager may manage Maadi prices');
select ok(not app.has_permission('PRICE_MANAGE', 'bbbbbbbb-0002-0000-0000-000000000003'),
  'the Cairo regional manager has no authority in Smouha');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select ok(app.has_permission('STAFF_MANAGE', null), 'the owner manages staff tenant-wide');
select ok(not app.has_permission('REFUND_UNLINKED', 'aaaaaaaa-0002-0000-0000-000000000001'),
  'tenant-wide authority never extends to another tenant''s branch');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
select ok(not app.has_permission('REFUND_UNLINKED', 'bbbbbbbb-0002-0000-0000-000000000002'),
  'at a till even the owner acts only on that till''s branch');

-- Lookups the backend runs before any context exists
select app.set_context();
select results_eq(
  $$ select tenant_id, branch_id from app.authenticate_device('bbbbbbbb-0004-0000-0000-000000000001', 'dev-key-REG-01-NSR') $$,
  $$ values ('bbbbbbbb-0000-0000-0000-000000000000'::uuid, 'bbbbbbbb-0002-0000-0000-000000000001'::uuid) $$,
  'a till authenticates with its API key');
select is_empty(
  $$ select * from app.authenticate_device('bbbbbbbb-0004-0000-0000-000000000001', 'dev-key-REG-01-MAA') $$,
  'another till''s key is rejected');
select results_eq(
  $$ select tenant_id from app.staff_memberships('eeeeeeee-0003-0000-0000-000000000011') $$,
  $$ values ('bbbbbbbb-0000-0000-0000-000000000000'::uuid) $$,
  'a signed-in owner finds the tenants they work for');
select is(app.customer_id_for_auth_user('eeeeeeee-0007-0000-0000-000000000001'),
  'cccccccc-0007-0000-0000-000000000001'::uuid, 'a signed-in shopper maps to their customer row');

create temp table registered as
  select app.register_customer('Sara Adel', '+201000000099') as id;
select is(app.register_customer('Sara A.', '+201000000099'), (select id from registered),
  'registering the same phone twice returns the same customer');
select is(app.register_customer('Karim Mostafa', '+201112223334', null, 'eeeeeeee-0007-0000-0000-000000000002'),
  'cccccccc-0007-0000-0000-000000000002'::uuid,
  'a shopper first enrolled at a till is linked to their new app account');
select is(app.customer_id_for_auth_user('eeeeeeee-0007-0000-0000-000000000002'),
  'cccccccc-0007-0000-0000-000000000002'::uuid, 'the linked account now resolves to that customer');
select throws_ok(
  $$ select app.register_customer('Impostor', '+201001234567', null, 'eeeeeeee-0007-0000-0000-000000000099') $$,
  '23505', null, 'a phone already linked to another account cannot be claimed');

-- Self-service onboarding (UC-01)
create temp table provisioned as
  select app.provision_tenant('Delta Grocery', 'Dina Owner', 'eeeeeeee-0003-0000-0000-000000000099') as tenant_id;
select app.set_context(
  p_tenant_id => (select tenant_id from provisioned),
  p_staff_id  => (select staff_id from app.staff_memberships('eeeeeeee-0003-0000-0000-000000000099')));
select ok(app.has_permission('STAFF_MANAGE', null), 'a newly provisioned owner can manage staff');
select is((select count(*)::int from app.tenants), 1, 'a newly provisioned owner sees their own tenant');

select * from finish();
rollback;
