-- Exception-based loss prevention (T9 §4.3): thresholds from the research, one shift per scenario.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- Fixtures (as the owner of the tables): nine shifts on the Nasr City till
insert into app.cashier_shifts (id, tenant_id, branch_id, device_id, staff_id, opened_at)
select ('bbbbbbbb-00f0-0000-0000-00000000050' || n)::uuid, 'bbbbbbbb-0000-0000-0000-000000000000',
       'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
       'bbbbbbbb-0003-0000-0000-000000000005', '2026-10-11 08:00+03'
  from generate_series(1, 9) as n;

insert into app.sales (id, tenant_id, branch_id, device_id, shift_id, staff_id, sale_type, status,
                       subtotal, grand_total, occurred_at, voided_at)
select f.id::uuid, 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
       'bbbbbbbb-0004-0000-0000-000000000001', f.shift::uuid, 'bbbbbbbb-0003-0000-0000-000000000005',
       f.sale_type, f.status, f.amount, f.amount, f.at::timestamptz,
       case when f.status = 'voided' then f.at::timestamptz + interval '5 minutes' end
  from (values
    -- shift 1: unlinked refunds of 60.00 (flag) and 50.00 (no flag)
    ('bbbbbbbb-00f0-0000-0000-000000000601', 'bbbbbbbb-00f0-0000-0000-000000000501', 'return', 'completed',  60.00, '2026-10-11 09:00+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000602', 'bbbbbbbb-00f0-0000-0000-000000000501', 'return', 'completed',  50.00, '2026-10-11 09:10+03'),
    -- shift 2: four unlinked refunds within 59 minutes
    ('bbbbbbbb-00f0-0000-0000-000000000611', 'bbbbbbbb-00f0-0000-0000-000000000502', 'return', 'completed',  10.00, '2026-10-11 09:00+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000612', 'bbbbbbbb-00f0-0000-0000-000000000502', 'return', 'completed',  10.00, '2026-10-11 09:20+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000613', 'bbbbbbbb-00f0-0000-0000-000000000502', 'return', 'completed',  10.00, '2026-10-11 09:40+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000614', 'bbbbbbbb-00f0-0000-0000-000000000502', 'return', 'completed',  10.00, '2026-10-11 09:59+03'),
    -- shift 3: four unlinked refunds spread over three hours
    ('bbbbbbbb-00f0-0000-0000-000000000621', 'bbbbbbbb-00f0-0000-0000-000000000503', 'return', 'completed',  10.00, '2026-10-11 09:00+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000622', 'bbbbbbbb-00f0-0000-0000-000000000503', 'return', 'completed',  10.00, '2026-10-11 10:01+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000623', 'bbbbbbbb-00f0-0000-0000-000000000503', 'return', 'completed',  10.00, '2026-10-11 11:02+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000624', 'bbbbbbbb-00f0-0000-0000-000000000503', 'return', 'completed',  10.00, '2026-10-11 12:03+03'),
    -- shift 4: a voided card sale of 150.00 plus a voided line of 50.01 = 200.01
    ('bbbbbbbb-00f0-0000-0000-000000000631', 'bbbbbbbb-00f0-0000-0000-000000000504', 'sale',   'voided',    150.00, '2026-10-11 09:00+03'),
    ('bbbbbbbb-00f0-0000-0000-000000000632', 'bbbbbbbb-00f0-0000-0000-000000000504', 'sale',   'completed',  10.00, '2026-10-11 09:30+03'),
    -- shift 5: voids worth exactly 200.00
    ('bbbbbbbb-00f0-0000-0000-000000000641', 'bbbbbbbb-00f0-0000-0000-000000000505', 'sale',   'voided',    200.00, '2026-10-11 09:00+03'),
    -- shift 6: a cash sale voided after the drawer fired
    ('bbbbbbbb-00f0-0000-0000-000000000651', 'bbbbbbbb-00f0-0000-0000-000000000506', 'sale',   'voided',     20.00, '2026-10-11 09:00+03'),
    -- shift 9: an unlinked refund of 60.00 under a raised threshold
    ('bbbbbbbb-00f0-0000-0000-000000000661', 'bbbbbbbb-00f0-0000-0000-000000000509', 'return', 'completed',  60.00, '2026-10-11 09:00+03')
  ) as f (id, shift, sale_type, status, amount, at);

insert into app.sale_lines (tenant_id, branch_id, sale_id, line_no, product_id, quantity, unit_price, vat_rate,
                            line_total, voided_at)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000632', 1, 'bbbbbbbb-0005-0000-0000-000000000002', 1, 50.01, 0, 50.01,
        '2026-10-11 09:29+03'),
       ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000632', 2, 'bbbbbbbb-0005-0000-0000-000000000004', 2, 5.00, 0, 10.00, null);

insert into app.sale_payments (tenant_id, branch_id, sale_id, method, provider, amount, tendered, change_given) values
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-00f0-0000-0000-000000000631', 'card', 'geidea', 150.00, null,  0),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-00f0-0000-0000-000000000641', 'card', 'geidea', 200.00, null,  0),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-00f0-0000-0000-000000000651', 'cash', null,      20.00, 20.00, 0);

-- Drawer openings: shift 7 has four manual ones, shift 8 three manual and one for a sale
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select app.append_audit('DRAWER_OPEN', '{"reason": "manual"}', 'bbbbbbbb-0002-0000-0000-000000000001', null,
                        'bbbbbbbb-00f0-0000-0000-000000000507')
  from generate_series(1, 4);
select app.append_audit('DRAWER_OPEN', '{"reason": "manual"}', 'bbbbbbbb-0002-0000-0000-000000000001', null,
                        'bbbbbbbb-00f0-0000-0000-000000000508')
  from generate_series(1, 3);
select app.append_audit('DRAWER_OPEN', '{"reason": "sale"}', 'bbbbbbbb-0002-0000-0000-000000000001', null,
                        'bbbbbbbb-00f0-0000-0000-000000000508');

-- Detection, as the Nasr City branch manager
set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000004');

select results_eq(
  $$ select rule, subject_id from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000501') $$,
  $$ values ('UNLINKED_REFUND_AMOUNT'::text, 'bbbbbbbb-00f0-0000-0000-000000000601'::uuid) $$,
  'an unlinked refund above EGP 50 is flagged; one of exactly EGP 50 is not');
select results_eq(
  $$ select rule, subject_id from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000502') $$,
  $$ values ('UNLINKED_REFUND_FREQUENCY'::text, 'bbbbbbbb-00f0-0000-0000-000000000502'::uuid) $$,
  'four unlinked refunds within an hour flag the shift');
select is((select details ->> 'max_in_one_hour' from app.fraud_flags
            where subject_id = 'bbbbbbbb-00f0-0000-0000-000000000502'),
  '4', 'the frequency flag records how many refunds fell into one hour');
select is_empty(
  $$ select * from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000503') $$,
  'four unlinked refunds spread over three hours are not flagged');
select results_eq(
  $$ select rule, subject_id from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000504') $$,
  $$ values ('VOID_AMOUNT'::text, 'bbbbbbbb-00f0-0000-0000-000000000504'::uuid) $$,
  'voided sales and lines worth EGP 200.01 flag the shift');
select is_empty(
  $$ select * from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000505') $$,
  'voids worth exactly EGP 200.00 are not flagged');
select results_eq(
  $$ select rule, subject_id from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000506') $$,
  $$ values ('POST_CLOSE_VOID'::text, 'bbbbbbbb-00f0-0000-0000-000000000651'::uuid) $$,
  'voiding a cash sale after the drawer fired is flagged');
select results_eq(
  $$ select rule, subject_id from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000507') $$,
  $$ values ('MANUAL_DRAWER_OPENS'::text, 'bbbbbbbb-00f0-0000-0000-000000000507'::uuid) $$,
  'four manual drawer openings flag the shift');
select is_empty(
  $$ select * from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000508') $$,
  'three manual openings (plus one for a sale) are not flagged');

select is_empty(
  $$ select * from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000501') $$,
  'running detection again raises nothing new');
select is((select count(*)::int from app.fraud_flags where shift_id = 'bbbbbbbb-00f0-0000-0000-000000000501'), 1,
  'the earlier flag is not duplicated');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
insert into app.loss_prevention_settings (tenant_id, unlinked_refund_amount)
values ('bbbbbbbb-0000-0000-0000-000000000000', 100.00);
select is_empty(
  $$ select * from app.detect_shift_exceptions('bbbbbbbb-00f0-0000-0000-000000000509') $$,
  'a tenant that raises the refund threshold to EGP 100 is not alerted at EGP 60');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000006',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
select is((select count(*)::int from app.fraud_flags), 0, 'Maadi staff cannot see Nasr City flags');

select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select is((select count(*)::int from app.fraud_flags), 0, 'another tenant never sees Nile flags');

select * from finish();
rollback;
