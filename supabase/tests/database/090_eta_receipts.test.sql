-- ETA B2C e-receipts (T7): per-device SHA-256 chain, buyer rules, returns, batch limits.
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');

-- Sales to issue receipts for (Nasr City till n1–n5, Maadi till m1–m2)
insert into app.sales (id, tenant_id, branch_id, device_id, sale_type, original_sale_id,
                       subtotal, discount_total, tax_total, grand_total, occurred_at, customer_id) values
  ('bbbbbbbb-00f0-0000-0000-0000000004a1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'sale',   null, 90.00,     0, 12.60, 102.60,    '2026-10-11 10:00+03', 'cccccccc-0007-0000-0000-000000000001'),
  ('bbbbbbbb-00f0-0000-0000-0000000004a2', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'sale',   null, 150000.00, 0, 0,     150000.00, '2026-10-11 10:05+03', null),
  ('bbbbbbbb-00f0-0000-0000-0000000004a3', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'sale',   null, 149999.99, 0, 0,     149999.99, '2026-10-11 10:10+03', null),
  ('bbbbbbbb-00f0-0000-0000-0000000004a4', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'sale',   null, 10.00,     0, 1.40,  11.40,     '2026-10-11 10:15+03', null),
  ('bbbbbbbb-00f0-0000-0000-0000000004a5', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 'return', 'bbbbbbbb-00f0-0000-0000-0000000004a1', 90.00, 0, 12.60, 102.60, '2026-10-12 09:00+03', null),
  ('bbbbbbbb-00f0-0000-0000-0000000004b1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0004-0000-0000-000000000002', 'sale',   null, 10.00,     0, 1.40,  11.40,     now() - interval '25 hours', null),
  ('bbbbbbbb-00f0-0000-0000-0000000004b2', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0004-0000-0000-000000000002', 'sale',   null, 20.00,     0, 2.80,  22.80,     now() - interval '1 hour', null);

-- Genesis receipt of the Nasr City till
insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                              total_amount, tax_total, issued_at, document)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-0000000004a1', 'sale', 'NSR-1', lpad('a1', 64, '0'),
        102.60, 12.60, '2026-10-11 10:00+03', '{"header": {"receiptNumber": "NSR-1"}}');

-- Buyer identification rules
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, buyer_type, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a4', 'sale', 'NSR-2', lpad('a4', 64, '0'), lpad('a1', 64, '0'),
             'B', 11.40, 1.40, '2026-10-11 10:15+03', '{}') $$,
  '23514', null, 'a business buyer must be identified');
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, buyer_type, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a2', 'sale', 'NSR-2', lpad('a2', 64, '0'), lpad('a1', 64, '0'),
             'P', 150000.00, 0, '2026-10-11 10:05+03', '{}') $$,
  '23514', null, 'a person buying for EGP 150,000 must be identified');
select lives_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, buyer_type, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a3', 'sale', 'NSR-2', lpad('a3', 64, '0'), lpad('a1', 64, '0'),
             'P', 149999.99, 0, '2026-10-11 10:10+03', '{}') $$,
  'a person buying for EGP 149,999.99 may stay anonymous');
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a4', 'sale', 'NSR-3', lpad('a4', 64, '0'), lpad('a3', 64, '0'),
             99.00, 1.40, '2026-10-11 10:15+03', '{}') $$,
  'P0001', null, 'a receipt must carry its sale''s totals');

-- The chain stays linear: one genesis, one successor, same device only
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a4', 'sale', 'NSR-3', lpad('a4', 64, '0'),
             11.40, 1.40, '2026-10-11 10:15+03', '{}') $$,
  '23505', null, 'a till has exactly one genesis receipt');
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a4', 'sale', 'NSR-3', lpad('a4', 64, '0'), lpad('a1', 64, '0'),
             11.40, 1.40, '2026-10-11 10:15+03', '{}') $$,
  '23505', null, 'a receipt cannot be chained after one that already has a successor');

insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                              total_amount, tax_total, issued_at, document)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0004-0000-0000-000000000002',
        'bbbbbbbb-00f0-0000-0000-0000000004b1', 'sale', 'MAA-1', lpad('b1', 64, '0'),
        11.40, 1.40, now() - interval '25 hours', '{}');
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a4', 'sale', 'NSR-3', lpad('a4', 64, '0'), lpad('b1', 64, '0'),
             11.40, 1.40, '2026-10-11 10:15+03', '{}') $$,
  'P0001', null, 'a receipt cannot chain onto another till''s receipt');

-- Returns reference the original receipt, for up to 540 days
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a5', 'return', 'NSR-3', lpad('a5', 64, '0'), lpad('a3', 64, '0'),
             102.60, 12.60, '2026-10-12 09:00+03', '{}') $$,
  '23514', null, 'a return receipt must reference the original receipt');
select throws_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, reference_uuid, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a5', 'return', 'NSR-3', lpad('a5', 64, '0'), lpad('a3', 64, '0'),
             lpad('a1', 64, '0'), 102.60, 12.60, '2026-10-11 10:00+03'::timestamptz + interval '541 days', '{}') $$,
  'P0001', null, 'a return 541 days after the sale is refused');
select lives_ok(
  $$ insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                                   previous_uuid, reference_uuid, total_amount, tax_total, issued_at, document)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-0000000004a5', 'return', 'NSR-3', lpad('a5', 64, '0'), lpad('a3', 64, '0'),
             lpad('a1', 64, '0'), 102.60, 12.60, '2026-10-11 10:00+03'::timestamptz + interval '540 days', '{}') $$,
  'a return 540 days after the sale is accepted');

-- Issued receipts are immutable apart from their submission status
select throws_ok(
  $$ update app.eta_receipts set uuid = lpad('ff', 64, '0') where uuid = lpad('a1', 64, '0') $$,
  '42501', null, 'the backend cannot rewrite a receipt''s UUID');
select lives_ok(
  $$ update app.eta_receipts set status = 'submitted', submitted_at = now() where uuid = lpad('a1', 64, '0') $$,
  'the backend can record a submission status');
select throws_ok(
  $$ delete from app.eta_receipts where uuid = lpad('a5', 64, '0') $$,
  '42501', null, 'the backend cannot delete a receipt');

-- Submission batches: at most 500 receipts or 1.5 MB
select throws_ok(
  $$ insert into app.eta_submissions (tenant_id, branch_id, device_id, receipt_count, payload_bytes)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0004-0000-0000-000000000001', 501, 1000) $$,
  '23514', null, 'a batch holds at most 500 receipts');
select throws_ok(
  $$ insert into app.eta_submissions (tenant_id, branch_id, device_id, receipt_count, payload_bytes)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0004-0000-0000-000000000001', 10, 1572865) $$,
  '23514', null, 'a batch is at most 1.5 MB');
select lives_ok(
  $$ insert into app.eta_submissions (tenant_id, branch_id, device_id, receipt_count, payload_bytes)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0004-0000-0000-000000000001', 500, 1572864) $$,
  'a full-size batch is accepted');

-- 24-hour submission deadline
insert into app.eta_receipts (tenant_id, branch_id, device_id, sale_id, receipt_type, receipt_number, uuid,
                              previous_uuid, total_amount, tax_total, issued_at, document)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0004-0000-0000-000000000002',
        'bbbbbbbb-00f0-0000-0000-0000000004b2', 'sale', 'MAA-2', lpad('b2', 64, '0'), lpad('b1', 64, '0'),
        22.80, 2.80, now() - interval '1 hour', '{}');
select is((select array_agg(receipt_number) from app.eta_overdue_receipts
            where device_id = 'bbbbbbbb-0004-0000-0000-000000000002'),
  array['MAA-1'], 'only the receipt issued more than 24 hours ago is overdue');

-- The shopper on the receipt can read it; nobody else can
select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.eta_receipts), 1, 'a shopper can read the e-receipt of their purchase');

reset role;
select throws_like($$ update app.eta_receipts set total_amount = 1 where uuid = lpad('a1', 64, '0') $$,
  '%cannot change%', 'issued receipts cannot change, even for the table owner');
select throws_like($$ delete from app.eta_receipts $$, '%cannot be deleted%',
  'issued receipts cannot be deleted, even by the table owner');

select * from finish();
rollback;
