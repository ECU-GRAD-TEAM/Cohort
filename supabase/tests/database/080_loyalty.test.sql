-- Loyalty: tenant-scoped memberships of global shoppers, append-only points, and the
-- cross paths that let shoppers and staff see each other only where they do business.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

set local role market_backend;

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select throws_ok(
  $$ insert into app.loyalty_ledger (tenant_id, account_id, customer_id, entry_type, points)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-000d-0000-0000-000000000002',
             'cccccccc-0007-0000-0000-000000000002', 'earn', -5) $$,
  '23514', null, 'earning negative points is rejected');
insert into app.loyalty_ledger (tenant_id, account_id, customer_id, branch_id, entry_type, points) values
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-000d-0000-0000-000000000002',
   'cccccccc-0007-0000-0000-000000000002', 'bbbbbbbb-0002-0000-0000-000000000001', 'earn', 100),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-000d-0000-0000-000000000002',
   'cccccccc-0007-0000-0000-000000000002', 'bbbbbbbb-0002-0000-0000-000000000001', 'redeem', -30);
select is((select points from app.loyalty_balances where account_id = 'bbbbbbbb-000d-0000-0000-000000000002'), 70,
  'earning 100 then redeeming 30 leaves 70 points');
select throws_ok(
  $$ insert into app.loyalty_ledger (tenant_id, account_id, customer_id, entry_type, points)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-000d-0000-0000-000000000002',
             'cccccccc-0007-0000-0000-000000000001', 'earn', 10) $$,
  '23503', null, 'points cannot be booked to someone else''s account');
select is((select count(*)::int from app.customers), 2, 'Nile staff see their two loyalty members');

select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select is((select count(*)::int from app.customers), 1, 'Alpha staff see only their member Mona');
select is((select count(*)::int from app.loyalty_ledger where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'Alpha staff never see Nile points');

-- Karim buys at Alpha without joining its programme
insert into app.sales (id, tenant_id, branch_id, customer_id, subtotal, grand_total, occurred_at)
values ('aaaaaaaa-00f0-0000-0000-000000000301', 'aaaaaaaa-0000-0000-0000-000000000000',
        'aaaaaaaa-0002-0000-0000-000000000001', 'cccccccc-0007-0000-0000-000000000002', 8.00, 8.00, now());
select is((select count(*)::int from app.customers where id = 'cccccccc-0007-0000-0000-000000000002'), 1,
  'after a purchase, Alpha staff can see the buyer');

select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000002');
select is((select name from app.tenants where id = 'aaaaaaaa-0000-0000-0000-000000000000'), 'Alpha Mini Market',
  'a shopper can read the name of a market they bought from');
select is((select name from app.branches where id = 'aaaaaaaa-0002-0000-0000-000000000001'), 'Alpha Maadi',
  'a shopper can read the branch on their receipt');
select is((select count(*)::int from app.loyalty_accounts), 1, 'Karim sees his single membership');

select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.loyalty_accounts), 2, 'Mona sees her memberships at Nile and Alpha');
select is((select count(*)::int from app.loyalty_accounts where customer_id = 'cccccccc-0007-0000-0000-000000000002'), 0,
  'Mona cannot see Karim''s membership');
select is((select count(*)::int from app.tenants), 2, 'Mona can read both markets she belongs to');
select is((select points from app.loyalty_balances where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 420,
  'Mona sees her Nile points balance');
select is((select count(*)::int from app.loyalty_ledger where customer_id = 'cccccccc-0007-0000-0000-000000000002'), 0,
  'Mona cannot see Karim''s points history');
select is((select count(*)::int from app.branches where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 4,
  'a member can list the branches of their market');

-- Inside one market's storefront, a shopper's other markets stay out of view
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.loyalty_accounts), 1, 'in the Nile storefront Mona sees only her Nile membership');
select is((select count(*)::int from app.branches where tenant_id <> 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'in the Nile storefront no other market''s branches appear');
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_customer_id => 'cccccccc-0007-0000-0000-000000000002');
select is((select count(*)::int from app.sales where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000000'), 0,
  'in the Nile storefront Karim''s Alpha purchases stay out of view');

-- Joining from the app, inside the Alpha storefront
select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_customer_id => 'cccccccc-0007-0000-0000-000000000002');
select lives_ok(
  $$ insert into app.loyalty_accounts (tenant_id, program_id, customer_id)
     values ('aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-000c-0000-0000-000000000001',
             'cccccccc-0007-0000-0000-000000000002') $$,
  'a shopper can join a market''s loyalty programme');
select throws_ok(
  $$ insert into app.loyalty_accounts (tenant_id, program_id, customer_id)
     values ('aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-000c-0000-0000-000000000001',
             'cccccccc-0007-0000-0000-000000000001') $$,
  '42501', null, 'a shopper cannot enrol someone else');
select throws_ok(
  $$ insert into app.loyalty_ledger (tenant_id, account_id, customer_id, entry_type, points)
     select tenant_id, id, customer_id, 'earn', 1000 from app.loyalty_accounts
      where tenant_id = 'aaaaaaaa-0000-0000-0000-000000000000' and customer_id = 'cccccccc-0007-0000-0000-000000000002' $$,
  '42501', null, 'a shopper cannot award themselves points');

reset role;
select throws_like($$ update app.loyalty_ledger set points = 1 $$, '%append-only%',
  'points history cannot be rewritten');
select throws_like($$ delete from app.loyalty_ledger $$, '%append-only%',
  'points history cannot be deleted');

select * from finish();
rollback;
