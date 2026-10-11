-- Demo and test data: two canary tenants with fixed, readable UUIDs.
--   aaaaaaaa-…  Alpha Mini Market (one store, no regions)
--   bbbbbbbb-…  Nile Hypermarket (Cairo + Alexandria regions, 3 stores, 1 warehouse)
--   cccccccc-…  global shoppers
-- UUID layout: TTTTTTTT-EEEE-0000-0000-00000000000N, EEEE = entity type
--   0000 tenant, 0001 region, 0002 branch, 0003 staff, 0004 device, 0005 product,
--   0006 batch, 0007 customer, 0008 supplier, 0009 category.
-- Loaded by `supabase db reset` and scripts/db-test.sh. Never load it into production.

-- ---------------------------------------------------------------------------
-- Tenants, regions, branches
-- ---------------------------------------------------------------------------
insert into app.tenants (id, name, legal_name, tax_registration_number, eta_activity_code, default_language) values
  ('aaaaaaaa-0000-0000-0000-000000000000', 'Alpha Mini Market', 'Alpha Trading LLC',     '100200300', '4711', 'ar'),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'Nile Hypermarket',  'Nile Retail Group SAE', '200300400', '4711', 'ar');

insert into app.regions (id, tenant_id, name, code) values
  ('bbbbbbbb-0001-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'Greater Cairo', 'CAI'),
  ('bbbbbbbb-0001-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'Alexandria',    'ALX');

insert into app.branches (id, tenant_id, region_id, kind, name, code, eta_branch_code, governorate, city) values
  ('aaaaaaaa-0002-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', null,
   'store', 'Alpha Maadi', 'ALP', '0', 'Cairo', 'Maadi'),
  ('bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0001-0000-0000-000000000001',
   'store', 'Nile Nasr City', 'NSR', '1', 'Cairo', 'Nasr City'),
  ('bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0001-0000-0000-000000000001',
   'store', 'Nile Maadi', 'MAA', '2', 'Cairo', 'Maadi'),
  ('bbbbbbbb-0002-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0001-0000-0000-000000000002',
   'store', 'Nile Smouha', 'SMO', '3', 'Alexandria', 'Smouha'),
  ('bbbbbbbb-0002-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0001-0000-0000-000000000001',
   'warehouse', 'Nile Cairo Warehouse', 'CWH', '4', 'Cairo', '10th of Ramadan');

-- ---------------------------------------------------------------------------
-- Staff (auth ids eeeeeeee-0003-… are Supabase Auth users; cashiers sign in by PIN)
-- ---------------------------------------------------------------------------
insert into app.staff (id, tenant_id, auth_user_id, full_name, email) values
  ('aaaaaaaa-0003-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'eeeeeeee-0003-0000-0000-000000000001', 'Adel Owner',      'adel@alpha.example'),
  ('aaaaaaaa-0003-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000000', null,                                   'Amr Cashier',     null),
  ('bbbbbbbb-0003-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'eeeeeeee-0003-0000-0000-000000000011', 'Nadia Owner',     'nadia@nile.example'),
  ('bbbbbbbb-0003-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'eeeeeeee-0003-0000-0000-000000000012', 'Hany Cairo RM',   'hany@nile.example'),
  ('bbbbbbbb-0003-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000', 'eeeeeeee-0003-0000-0000-000000000013', 'Laila Alex RM',   'laila@nile.example'),
  ('bbbbbbbb-0003-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000000', 'eeeeeeee-0003-0000-0000-000000000014', 'Omar Nasr BM',    'omar@nile.example'),
  ('bbbbbbbb-0003-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-000000000000', null,                                   'Salma Cashier',   null),
  ('bbbbbbbb-0003-0000-0000-000000000006', 'bbbbbbbb-0000-0000-0000-000000000000', null,                                   'Youssef Cashier', null),
  ('bbbbbbbb-0003-0000-0000-000000000007', 'bbbbbbbb-0000-0000-0000-000000000000', null,                                   'Tarek Clerk',     null);

insert into app.staff_assignments (tenant_id, staff_id, role_id, scope, region_id, branch_id)
select a.tenant_id, a.staff_id, r.id, a.scope, a.region_id, a.branch_id
  from (values
    ('aaaaaaaa-0000-0000-0000-000000000000'::uuid, 'aaaaaaaa-0003-0000-0000-000000000001'::uuid, 'owner',            'tenant', null::uuid,                              null::uuid),
    ('aaaaaaaa-0000-0000-0000-000000000000',       'aaaaaaaa-0003-0000-0000-000000000002',       'cashier',          'branch', null,                                    'aaaaaaaa-0002-0000-0000-000000000001'),
    ('bbbbbbbb-0000-0000-0000-000000000000',       'bbbbbbbb-0003-0000-0000-000000000001',       'owner',            'tenant', null,                                    null),
    ('bbbbbbbb-0000-0000-0000-000000000000',       'bbbbbbbb-0003-0000-0000-000000000002',       'regional_manager', 'region', 'bbbbbbbb-0001-0000-0000-000000000001',  null),
    ('bbbbbbbb-0000-0000-0000-000000000000',       'bbbbbbbb-0003-0000-0000-000000000003',       'regional_manager', 'region', 'bbbbbbbb-0001-0000-0000-000000000002',  null),
    ('bbbbbbbb-0000-0000-0000-000000000000',       'bbbbbbbb-0003-0000-0000-000000000004',       'branch_manager',   'branch', null,                                    'bbbbbbbb-0002-0000-0000-000000000001'),
    ('bbbbbbbb-0000-0000-0000-000000000000',       'bbbbbbbb-0003-0000-0000-000000000005',       'cashier',          'branch', null,                                    'bbbbbbbb-0002-0000-0000-000000000001'),
    ('bbbbbbbb-0000-0000-0000-000000000000',       'bbbbbbbb-0003-0000-0000-000000000006',       'cashier',          'branch', null,                                    'bbbbbbbb-0002-0000-0000-000000000002'),
    ('bbbbbbbb-0000-0000-0000-000000000000',       'bbbbbbbb-0003-0000-0000-000000000007',       'stock_clerk',      'branch', null,                                    'bbbbbbbb-0002-0000-0000-000000000004')
  ) as a (tenant_id, staff_id, role_code, scope, region_id, branch_id)
  join app.roles r on r.tenant_id is null and r.code = a.role_code;

-- ---------------------------------------------------------------------------
-- Tills (dev-only API keys: dev-key-<device code>-<branch code>)
-- ---------------------------------------------------------------------------
insert into app.pos_devices (id, tenant_id, branch_id, code, hardware_serial, eta_pos_serial) values
  ('aaaaaaaa-0004-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0002-0000-0000-000000000001', 'REG-01', 'HW-ALP-01', 'ETA-ALP-01'),
  ('bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'REG-01', 'HW-NSR-01', 'ETA-NSR-01'),
  ('bbbbbbbb-0004-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'REG-01', 'HW-MAA-01', 'ETA-MAA-01');

insert into app.pos_device_secrets (device_id, tenant_id, branch_id, api_key_hash)
select d.id, d.tenant_id, d.branch_id,
       encode(sha256(convert_to('dev-key-' || d.code || '-' || b.code, 'UTF8')), 'hex')
  from app.pos_devices d
  join app.branches b on b.id = d.branch_id;

-- ---------------------------------------------------------------------------
-- Shoppers (global). Karim was enrolled at a till and has no app account yet.
-- ---------------------------------------------------------------------------
insert into app.customers (id, auth_user_id, full_name, phone, email, preferred_language) values
  ('cccccccc-0007-0000-0000-000000000001', 'eeeeeeee-0007-0000-0000-000000000001', 'Mona Hassan',   '+201001234567', 'mona@example.com', 'ar'),
  ('cccccccc-0007-0000-0000-000000000002', null,                                   'Karim Mostafa', '+201112223334', null,               'ar');

insert into app.customer_payment_methods (customer_id, provider, provider_token, brand, last4, exp_month, exp_year, is_default) values
  ('cccccccc-0007-0000-0000-000000000001', 'paymob', 'tok_test_mona_visa', 'visa', '4242', 12, 2029, true);
