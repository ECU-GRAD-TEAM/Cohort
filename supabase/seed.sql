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

-- ---------------------------------------------------------------------------
-- Catalog (prices are net of VAT, EGP)
-- ---------------------------------------------------------------------------
insert into app.product_categories (id, tenant_id, name_en, name_ar) values
  ('aaaaaaaa-0009-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'Dairy',     'ألبان'),
  ('aaaaaaaa-0009-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000000', 'Beverages', 'مشروبات'),
  ('bbbbbbbb-0009-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'Dairy',     'ألبان'),
  ('bbbbbbbb-0009-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'Pantry',    'بقالة'),
  ('bbbbbbbb-0009-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000', 'Produce',   'خضروات'),
  ('bbbbbbbb-0009-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000000', 'Bakery',    'مخبوزات');

insert into app.products (id, tenant_id, category_id, sku, name_en, name_ar, unit_of_measure, is_weighed, is_perishable, base_price, eta_item_code, eta_item_type) values
  ('aaaaaaaa-0005-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0009-0000-0000-000000000001', 'ALP-MILK-1L',  'Fresh Milk 1L',    'لبن طازج ١ لتر',     'unit', false, true,  33.00, '06221000000010', 'GS1'),
  ('aaaaaaaa-0005-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0009-0000-0000-000000000002', 'ALP-WATER-15', 'Mineral Water 1.5L','مياه معدنية ١.٥ لتر', 'unit', false, false,  8.00, '06222000000017', 'GS1'),
  ('bbbbbbbb-0005-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0009-0000-0000-000000000001', 'NIL-MILK-1L',  'Fresh Milk 1L',    'لبن طازج ١ لتر',     'unit', false, true,  32.00, '06221000000010', 'GS1'),
  ('bbbbbbbb-0005-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0009-0000-0000-000000000002', 'NIL-RICE-5KG', 'Egyptian Rice 5kg','أرز مصري ٥ كجم',     'unit', false, false, 89.50, '06221000000027', 'GS1'),
  ('bbbbbbbb-0005-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0009-0000-0000-000000000003', 'NIL-TOMATO',   'Tomatoes (per kg)','طماطم (بالكيلو)',    'kg',   true,  true,  18.00, 'EG-EGS-TOMATO',  'EGS'),
  ('bbbbbbbb-0005-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0009-0000-0000-000000000004', 'NIL-BREAD',    'Baladi Bread x5',  'عيش بلدي ٥ أرغفة',   'unit', false, true,   5.00, '06221000000041', 'GS1');

insert into app.product_barcodes (tenant_id, product_id, barcode, kind) values
  ('aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0005-0000-0000-000000000001', '06221000000010', 'gtin'),
  ('aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0005-0000-0000-000000000002', '06222000000017', 'gtin'),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', '06221000000010', 'gtin'),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002', '06221000000027', 'gtin'),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000003', '4087',           'plu'),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000004', '06221000000041', 'gtin');

insert into app.branch_prices (tenant_id, branch_id, product_id, price) values
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0005-0000-0000-000000000002', 95.00);

-- ---------------------------------------------------------------------------
-- Inventory: suppliers, batches and opening stock (through the ledger)
-- ---------------------------------------------------------------------------
insert into app.suppliers (id, tenant_id, name, lead_time_days, lead_time_stddev_days) values
  ('aaaaaaaa-0008-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'Maadi Wholesale',          2, 0.5),
  ('bbbbbbbb-0008-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'Cairo Foods Distribution', 3, 1.0);

insert into app.supplier_products (tenant_id, supplier_id, product_id, pack_size, min_order_quantity, unit_cost) values
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0008-0000-0000-000000000001', 'bbbbbbbb-0005-0000-0000-000000000001', 12, 24, 24.00),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0008-0000-0000-000000000001', 'bbbbbbbb-0005-0000-0000-000000000002',  4,  8, 70.00);

insert into app.stock_batches (id, tenant_id, product_id, supplier_id, batch_code, expiry_date, unit_cost, received_at) values
  ('aaaaaaaa-0006-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0005-0000-0000-000000000002', 'aaaaaaaa-0008-0000-0000-000000000001', 'W-2610', null,         5.5000, '2026-10-01 09:00+03'),
  ('aaaaaaaa-0006-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0005-0000-0000-000000000001', 'aaaaaaaa-0008-0000-0000-000000000001', 'M-2610', '2026-10-24', 25.0000, '2026-10-05 09:00+03'),
  ('bbbbbbbb-0006-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002', 'bbbbbbbb-0008-0000-0000-000000000001', 'R-2609', null,         70.0000, '2026-09-28 09:00+03'),
  ('bbbbbbbb-0006-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', 'bbbbbbbb-0008-0000-0000-000000000001', 'M-2610A', '2026-10-25', 24.0000, '2026-10-04 09:00+03'),
  ('bbbbbbbb-0006-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', 'bbbbbbbb-0008-0000-0000-000000000001', 'M-2610B', '2026-11-05', 24.5000, '2026-10-08 09:00+03'),
  ('bbbbbbbb-0006-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', 'bbbbbbbb-0008-0000-0000-000000000001', 'M-2610C', '2026-10-30', 24.0000, '2026-10-06 09:00+03');

insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                             to_location_id, to_branch_id, quantity, move_type, occurred_at)
select b.tenant_id, b.product_id, b.id,
       app.location_id(r.branch_id, 'supplier'), r.branch_id,
       app.location_id(r.branch_id, 'storage'), r.branch_id,
       r.quantity, 'receipt', b.received_at
  from (values ('aaaaaaaa-0006-0000-0000-000000000001'::uuid, 'aaaaaaaa-0002-0000-0000-000000000001'::uuid, 100),
               ('aaaaaaaa-0006-0000-0000-000000000002',       'aaaaaaaa-0002-0000-0000-000000000001',        40),
               ('bbbbbbbb-0006-0000-0000-000000000001',       'bbbbbbbb-0002-0000-0000-000000000001',        50),
               ('bbbbbbbb-0006-0000-0000-000000000002',       'bbbbbbbb-0002-0000-0000-000000000004',       120),
               ('bbbbbbbb-0006-0000-0000-000000000003',       'bbbbbbbb-0002-0000-0000-000000000004',       120),
               ('bbbbbbbb-0006-0000-0000-000000000004',       'bbbbbbbb-0002-0000-0000-000000000001',        30)
       ) as r (batch_id, branch_id, quantity)
  join app.stock_batches b on b.id = r.batch_id;
