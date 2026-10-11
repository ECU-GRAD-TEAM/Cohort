-- Offline sync inbox and sales (T2 paper, proposal §3.4): idempotent ingestion, financial
-- integrity, and who can read a sale.
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

set local role market_backend;

-- Nasr City cashier at the Nasr City till
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000005',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');

insert into app.cashier_shifts (id, tenant_id, branch_id, device_id, staff_id, opening_float)
values ('bbbbbbbb-00f0-0000-0000-000000000101', 'bbbbbbbb-0000-0000-0000-000000000000',
        'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
        'bbbbbbbb-0003-0000-0000-000000000005', 500.00);

-- The same event uploaded twice (connection dropped before the ack) is stored once
insert into app.sync_events (id, tenant_id, branch_id, device_id, event_type, sequence_no, payload, occurred_at)
select 'bbbbbbbb-00f0-0000-0000-000000000201', 'bbbbbbbb-0000-0000-0000-000000000000',
       'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
       'TRANSACTION_COMPLETED', 1, '{"sale_id": "bbbbbbbb-00f0-0000-0000-000000000301"}', '2026-10-11 12:00+03'
  from generate_series(1, 2)
on conflict (id) do nothing;
select is((select count(*)::int from app.sync_events where id = 'bbbbbbbb-00f0-0000-0000-000000000201'), 1,
  'a re-sent event is stored once');
select throws_ok(
  $$ insert into app.sync_events (id, tenant_id, branch_id, device_id, event_type, sequence_no, payload, occurred_at)
     values ('bbbbbbbb-00f0-0000-0000-000000000202', 'bbbbbbbb-0000-0000-0000-000000000000',
             'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
             'TRANSACTION_COMPLETED', 1, '{}', now()) $$,
  '23505', null, 'a till cannot reuse a sequence number');
select lives_ok(
  $$ update app.sync_events set status = 'applied', applied_at = now()
      where id = 'bbbbbbbb-00f0-0000-0000-000000000201' $$,
  'the backend records that an event was applied');
select throws_ok(
  $$ update app.sync_events set payload = '{}' where id = 'bbbbbbbb-00f0-0000-0000-000000000201' $$,
  '42501', null, 'the uploaded payload cannot be rewritten');
select throws_ok(
  $$ delete from app.sync_events where id = 'bbbbbbbb-00f0-0000-0000-000000000201' $$,
  '42501', null, 'uploaded events cannot be deleted');

-- Mona's sale: 3 milk at 32.00, multibuy discount 6.00, VAT 14% on 90.00
insert into app.sales (id, tenant_id, branch_id, device_id, shift_id, staff_id, customer_id, receipt_number,
                       subtotal, discount_total, tax_total, grand_total, is_offline, sync_event_id, occurred_at)
select 'bbbbbbbb-00f0-0000-0000-000000000301', 'bbbbbbbb-0000-0000-0000-000000000000',
       'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
       'bbbbbbbb-00f0-0000-0000-000000000101', 'bbbbbbbb-0003-0000-0000-000000000005',
       'cccccccc-0007-0000-0000-000000000001', 'NSR-REG-01-000001',
       96.00, 6.00, 12.60, 102.60, true, 'bbbbbbbb-00f0-0000-0000-000000000201', '2026-10-11 12:00+03'
  from generate_series(1, 2)
on conflict (id) do nothing;
select is((select count(*)::int from app.sales where id = 'bbbbbbbb-00f0-0000-0000-000000000301'), 1,
  'a sale retried by the sync worker is posted once');

insert into app.sale_lines (tenant_id, branch_id, sale_id, line_no, product_id, barcode, quantity, unit_price,
                            discount_amount, vat_rate, tax_amount, line_total)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000301', 1, 'bbbbbbbb-0005-0000-0000-000000000001', '06221000000010',
        3, 32.00, 6.00, 14.00, 12.60, 102.60);
insert into app.sale_payments (tenant_id, branch_id, sale_id, method, amount, tendered, change_given)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000301', 'cash', 102.60, 110.00, 7.40);
insert into app.sale_discounts (tenant_id, branch_id, sale_id, promotion_id, amount)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000301', 'bbbbbbbb-000a-0000-0000-000000000001', 6.00);

-- Karim's sale at the same till, paid by card
insert into app.sales (id, tenant_id, branch_id, device_id, shift_id, staff_id, customer_id,
                       subtotal, discount_total, tax_total, grand_total, occurred_at)
values ('bbbbbbbb-00f0-0000-0000-000000000302', 'bbbbbbbb-0000-0000-0000-000000000000',
        'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000101', 'bbbbbbbb-0003-0000-0000-000000000005',
        'cccccccc-0007-0000-0000-000000000002', 89.50, 0, 12.53, 102.03, '2026-10-11 12:05+03');
insert into app.sale_payments (tenant_id, branch_id, sale_id, method, provider, amount, card_last4)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000302', 'card', 'geidea', 102.03, '1881');

-- Financial integrity
select throws_ok(
  $$ insert into app.sales (tenant_id, branch_id, subtotal, discount_total, tax_total, grand_total, occurred_at)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             10.00, 0, 1.40, 11.00, now()) $$,
  '23514', null, 'a sale whose total does not add up is rejected');
select throws_ok(
  $$ insert into app.sale_payments (tenant_id, branch_id, sale_id, method, amount, tendered, change_given)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-00f0-0000-0000-000000000302', 'cash', 11.40, 20.00, 5.00) $$,
  '23514', null, 'cash change must equal tendered minus amount');
select throws_ok(
  $$ insert into app.sales (tenant_id, branch_id, sale_type, original_sale_id, subtotal, grand_total, occurred_at)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'sale',
             'bbbbbbbb-00f0-0000-0000-000000000302', 1.00, 1.00, now()) $$,
  '23514', null, 'only returns may point at an original sale');
select throws_ok(
  $$ update app.sales set grand_total = 1.00 where id = 'bbbbbbbb-00f0-0000-0000-000000000302' $$,
  '42501', null, 'amounts of a posted sale cannot be edited');
select throws_ok(
  $$ delete from app.sales where id = 'bbbbbbbb-00f0-0000-0000-000000000302' $$,
  '42501', null, 'the backend cannot delete a sale');
select throws_ok(
  $$ update app.sales set status = 'voided' where id = 'bbbbbbbb-00f0-0000-0000-000000000302' $$,
  '23514', null, 'a void must record when it happened');
select lives_ok(
  $$ update app.sales set status = 'voided', voided_at = now(), voided_by = 'bbbbbbbb-0003-0000-0000-000000000004',
            void_approved_by = 'bbbbbbbb-0003-0000-0000-000000000004', void_reason = 'customer changed mind'
      where id = 'bbbbbbbb-00f0-0000-0000-000000000302' $$,
  'a sale can be voided with its approver');

-- A till's events must come from its own branch
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select throws_ok(
  $$ insert into app.sync_events (id, tenant_id, branch_id, device_id, event_type, sequence_no, payload, occurred_at)
     values ('bbbbbbbb-00f0-0000-0000-000000000203', 'bbbbbbbb-0000-0000-0000-000000000000',
             'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0004-0000-0000-000000000001',
             'TRANSACTION_COMPLETED', 2, '{}', now()) $$,
  '23503', null, 'an event must carry its till''s own branch');

-- Shoppers read their own receipts across markets, nobody else's
select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.sales), 1, 'Mona sees her own sale');
select is((select count(*)::int from app.sales where customer_id = 'cccccccc-0007-0000-0000-000000000002'), 0,
  'Mona cannot see Karim''s sale');
select is((select count(*)::int from app.sale_lines), 1, 'Mona sees the lines of her sale');
select is((select count(*)::int from app.sale_payments), 1, 'Mona sees how she paid');
select is((select count(*)::int from app.sale_discounts), 1, 'Mona sees the discount she received');
select throws_ok(
  $$ insert into app.sales (tenant_id, branch_id, subtotal, grand_total, occurred_at)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 1.00, 1.00, now()) $$,
  '42501', null, 'a shopper cannot post sales');

select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000002');
select is((select count(*)::int from app.sales), 1, 'Karim sees only his own sale');
select is((select count(*)::int from app.sale_payments), 1, 'Karim sees only his own payment');

-- Branch staff see their own branch only
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000006',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
select is((select count(*)::int from app.sales where branch_id = 'bbbbbbbb-0002-0000-0000-000000000001'), 0,
  'the Maadi cashier cannot see Nasr City sales');
select is((select count(*)::int from app.sync_events), 0, 'the Maadi till cannot see Nasr City events');

reset role;
select throws_like($$ delete from app.sales $$, '%cannot be deleted%',
  'sales are permanent records, even for the table owner');

select * from finish();
rollback;
