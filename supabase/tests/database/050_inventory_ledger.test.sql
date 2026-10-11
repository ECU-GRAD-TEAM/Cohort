-- Double-entry stock ledger (ADR-005): locations, batches, FEFO, transfers, oversells.
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');

-- Every branch gets its accounts
select is((select count(*)::int from app.stock_locations where branch_id = 'bbbbbbbb-0002-0000-0000-000000000001'), 7,
  'a store gets storage, shelf and the five virtual locations');
select is((select count(*)::int from app.stock_locations where branch_id = 'bbbbbbbb-0002-0000-0000-000000000004'), 6,
  'a warehouse gets storage and the five virtual locations');
select is((select kind from app.stock_locations
            where id = app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit')),
  'transit', 'location_id finds a branch''s transit account');

-- REQ-INV-01: perishable batches carry an expiry date
select throws_ok(
  $$ insert into app.stock_batches (tenant_id, product_id, unit_cost)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', 24) $$,
  'P0001', null, 'a perishable batch without an expiry date is rejected');

-- FEFO fixture: three milk batches received into Smouha storage
insert into app.stock_batches (id, tenant_id, product_id, expiry_date, unit_cost, received_at) values
  ('bbbbbbbb-0006-0000-0000-0000000000a1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', '2026-10-20', 24, '2026-10-01'),
  ('bbbbbbbb-0006-0000-0000-0000000000b1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', '2026-11-04', 24, '2026-10-02'),
  ('bbbbbbbb-0006-0000-0000-0000000000c1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', '2026-10-10', 24, '2026-09-20');
insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                             to_location_id, to_branch_id, quantity, move_type)
select 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', r.batch_id::uuid,
       app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'supplier'), 'bbbbbbbb-0002-0000-0000-000000000003',
       app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000003',
       r.qty, 'receipt'
  from (values ('bbbbbbbb-0006-0000-0000-0000000000a1', 3),
               ('bbbbbbbb-0006-0000-0000-0000000000b1', 10),
               ('bbbbbbbb-0006-0000-0000-0000000000c1', 5)) as r (batch_id, qty);

select is((select quantity from app.stock_levels
            where location_id = app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'storage')
              and batch_id = 'bbbbbbbb-0006-0000-0000-0000000000a1'),
  3.000, 'a receipt raises the storage balance by the received quantity');
select is((select sum(quantity) from app.stock_levels
            where location_id = app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'supplier')),
  -18.000, 'the supplier account is credited with everything received');

select results_eq(
  $$ select batch_id, take_quantity
       from app.fefo_pick(app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'storage'),
                          'bbbbbbbb-0005-0000-0000-000000000001', 5, '2026-10-15') $$,
  $$ values ('bbbbbbbb-0006-0000-0000-0000000000a1'::uuid, 3::numeric),
            ('bbbbbbbb-0006-0000-0000-0000000000b1'::uuid, 2::numeric) $$,
  'FEFO takes 3 from the earliest-expiring batch and the remaining 2 from the next');
select is((select sum(take_quantity)
             from app.fefo_pick(app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'storage'),
                                'bbbbbbbb-0005-0000-0000-000000000001', 20, '2026-10-15')),
  13.000, 'FEFO hands back only what is sellable when stock is short');
select is((select count(*)::int
             from app.fefo_pick(app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'storage'),
                                'bbbbbbbb-0005-0000-0000-000000000001', 20, '2026-10-15')
            where batch_id = 'bbbbbbbb-0006-0000-0000-0000000000c1'),
  0, 'expired batches are never picked');

-- The ledger is append-only and balances are derived
select ok(not has_table_privilege('market_backend', 'app.stock_moves', 'UPDATE'), 'the backend cannot update ledger rows');
select ok(not has_table_privilege('market_backend', 'app.stock_moves', 'DELETE'), 'the backend cannot delete ledger rows');
select ok(not has_table_privilege('market_backend', 'app.stock_levels', 'INSERT'), 'balances cannot be inserted directly');
select ok(not has_table_privilege('market_backend', 'app.stock_levels', 'UPDATE'), 'balances cannot be edited directly');

select throws_ok(
  $$ insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                                  to_location_id, to_branch_id, quantity, move_type)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001',
             'bbbbbbbb-0006-0000-0000-0000000000a1',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'shelf'), 'bbbbbbbb-0002-0000-0000-000000000003',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000003',
             1, 'sale') $$,
  'P0001', null, 'a sale must go to the customer account, not back into storage');

-- Transfer Nasr City → Maadi: dispatch to transit, then receive (REQ-INVN-01)
insert into app.stock_transfers (id, tenant_id, from_branch_id, to_branch_id, expected_arrival_at) values
  ('bbbbbbbb-00f0-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000000',
   'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000002', now() + interval '1 day');

select throws_ok(
  $$ insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                                  to_location_id, to_branch_id, quantity, move_type)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002',
             'bbbbbbbb-0006-0000-0000-000000000001',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000001',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit'), 'bbbbbbbb-0002-0000-0000-000000000001',
             10, 'transfer_dispatch') $$,
  'P0001', null, 'a dispatch must reference its transfer');

insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                             to_location_id, to_branch_id, quantity, move_type, reference_type, reference_id)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002',
        'bbbbbbbb-0006-0000-0000-000000000001',
        app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000001',
        app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit'), 'bbbbbbbb-0002-0000-0000-000000000001',
        10, 'transfer_dispatch', 'transfer', 'bbbbbbbb-00f0-0000-0000-000000000001');
select is((select quantity from app.stock_levels
            where location_id = app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit')
              and batch_id = 'bbbbbbbb-0006-0000-0000-000000000001'),
  10.000, 'dispatched stock sits in the sender''s transit account');

insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                             to_location_id, to_branch_id, quantity, move_type, reference_type, reference_id)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002',
        'bbbbbbbb-0006-0000-0000-000000000001',
        app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit'), 'bbbbbbbb-0002-0000-0000-000000000001',
        app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000002',
        10, 'transfer_receive', 'transfer', 'bbbbbbbb-00f0-0000-0000-000000000001');
select is((select quantity from app.stock_levels
            where location_id = app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit')
              and batch_id = 'bbbbbbbb-0006-0000-0000-000000000001'),
  0.000, 'received stock leaves transit, so nothing dangles');
select is((select quantity from app.stock_levels
            where location_id = app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'storage')
              and batch_id = 'bbbbbbbb-0006-0000-0000-000000000001'),
  10.000, 'the receiving branch gains what was dispatched');

-- A receipt can only bring in what its transfer dispatched (REQ-INVN-01)
select throws_ok(
  $$ insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                                  to_location_id, to_branch_id, quantity, move_type, reference_type, reference_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002',
             'bbbbbbbb-0006-0000-0000-000000000001',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit'), 'bbbbbbbb-0002-0000-0000-000000000001',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000002',
             1, 'transfer_receive', 'transfer', 'bbbbbbbb-00f0-0000-0000-000000000001') $$,
  'P0001', null, 'a transfer cannot deliver more than it dispatched');
insert into app.stock_transfers (id, tenant_id, from_branch_id, to_branch_id, expected_arrival_at) values
  ('bbbbbbbb-00f0-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000000',
   'bbbbbbbb-0002-0000-0000-000000000003', 'bbbbbbbb-0002-0000-0000-000000000002', now() + interval '1 day');
select throws_ok(
  $$ insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                                  to_location_id, to_branch_id, quantity, move_type, reference_type, reference_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002',
             'bbbbbbbb-0006-0000-0000-000000000001',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000003', 'transit'), 'bbbbbbbb-0002-0000-0000-000000000003',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000002',
             500, 'transfer_receive', 'transfer', 'bbbbbbbb-00f0-0000-0000-000000000003') $$,
  'P0001', null, 'a transfer that dispatched nothing cannot deliver anything');

-- 48-hour guard on perishable transfers (REQ-INV-03), judged in the destination's time zone
insert into app.stock_transfers (id, tenant_id, from_branch_id, to_branch_id, expected_arrival_at) values
  ('bbbbbbbb-00f0-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000000',
   'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0002-0000-0000-000000000002', '2026-10-18 10:00 Africa/Cairo');
insert into app.stock_batches (id, tenant_id, product_id, expiry_date, unit_cost) values
  ('bbbbbbbb-0006-0000-0000-0000000000d1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', '2026-10-20', 24),
  ('bbbbbbbb-0006-0000-0000-0000000000e1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', '2026-10-21', 24);
insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                             to_location_id, to_branch_id, quantity, move_type)
select 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001', b::uuid,
       app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'supplier'), 'bbbbbbbb-0002-0000-0000-000000000001',
       app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000001',
       5, 'receipt'
  from unnest(array['bbbbbbbb-0006-0000-0000-0000000000d1', 'bbbbbbbb-0006-0000-0000-0000000000e1']) as b;

select throws_ok(
  $$ insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                                  to_location_id, to_branch_id, quantity, move_type, reference_type, reference_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001',
             'bbbbbbbb-0006-0000-0000-0000000000d1',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000001',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit'), 'bbbbbbbb-0002-0000-0000-000000000001',
             5, 'transfer_dispatch', 'transfer', 'bbbbbbbb-00f0-0000-0000-000000000002') $$,
  'P0001', null, 'milk expiring within 48 hours of arrival cannot be dispatched');
select lives_ok(
  $$ insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                                  to_location_id, to_branch_id, quantity, move_type, reference_type, reference_id)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000001',
             'bbbbbbbb-0006-0000-0000-0000000000e1',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000001',
             app.location_id('bbbbbbbb-0002-0000-0000-000000000001', 'transit'), 'bbbbbbbb-0002-0000-0000-000000000001',
             5, 'transfer_dispatch', 'transfer', 'bbbbbbbb-00f0-0000-0000-000000000002') $$,
  'milk that outlives the 48-hour window can be dispatched');

-- Two offline tills sell the last loaf: the ledger records both and surfaces the oversell
insert into app.stock_batches (id, tenant_id, product_id, expiry_date, unit_cost) values
  ('bbbbbbbb-0006-0000-0000-0000000000f1', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000004', '2026-10-14', 3);
insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                             to_location_id, to_branch_id, quantity, move_type)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000004', 'bbbbbbbb-0006-0000-0000-0000000000f1',
        app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'supplier'), 'bbbbbbbb-0002-0000-0000-000000000002',
        app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000002',
        1, 'receipt');
insert into app.stock_moves (tenant_id, product_id, batch_id, from_location_id, from_branch_id,
                             to_location_id, to_branch_id, quantity, move_type)
select 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000004', 'bbbbbbbb-0006-0000-0000-0000000000f1',
       app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'storage'), 'bbbbbbbb-0002-0000-0000-000000000002',
       app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'customer'), 'bbbbbbbb-0002-0000-0000-000000000002',
       1, 'sale'
  from generate_series(1, 2);
select is((select quantity from app.stock_levels
            where location_id = app.location_id('bbbbbbbb-0002-0000-0000-000000000002', 'storage')
              and batch_id = 'bbbbbbbb-0006-0000-0000-0000000000f1'),
  -1.000, 'both offline sales are kept and the balance goes negative');
select is((select count(*)::int from app.stock_discrepancies where batch_id = 'bbbbbbbb-0006-0000-0000-0000000000f1'),
  1, 'the oversell is listed as a discrepancy');

-- What the receiving branch can see
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000006',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
select is((select count(*)::int from app.stock_transfers where id = 'bbbbbbbb-00f0-0000-0000-000000000001'), 1,
  'the receiving branch sees the incoming transfer');
select is((select count(*)::int from app.stock_moves where reference_id = 'bbbbbbbb-00f0-0000-0000-000000000001'), 1,
  'the receiving branch sees the leg that reached it, not the sender''s internal leg');
select is((select count(*)::int from app.stock_levels where branch_id = 'bbbbbbbb-0002-0000-0000-000000000001'), 0,
  'the receiving branch cannot see the sender''s stock');

select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select is((select count(*)::int from app.stock_levels where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'another tenant never sees Nile stock');

reset role;
select throws_like($$ update app.stock_moves set quantity = 1 $$, '%append-only%',
  'ledger rows cannot be changed, even by the table owner');
select throws_like($$ delete from app.stock_moves $$, '%append-only%',
  'ledger rows cannot be deleted, even by the table owner');

select * from finish();
rollback;
