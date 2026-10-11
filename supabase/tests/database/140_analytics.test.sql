-- Analytics semantic layer for NL-to-SQL (Dual-RAG §2.8, addendum §3.3): LLM-generated SQL
-- runs as market_ai_reader, sees only governed views, and RLS still bounds every row.
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

-- Fixtures (as the table owner)
insert into app.sales (id, tenant_id, branch_id, device_id, sale_type, original_sale_id,
                       subtotal, discount_total, tax_total, grand_total, occurred_at) values
  ('bbbbbbbb-00f0-0000-0000-000000000801', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002',
   'bbbbbbbb-0004-0000-0000-000000000002', 'sale', null, 100.00, 10.00, 12.60, 102.60, '2026-10-11 23:30+00'),
  ('bbbbbbbb-00f0-0000-0000-000000000802', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002',
   'bbbbbbbb-0004-0000-0000-000000000002', 'return', 'bbbbbbbb-00f0-0000-0000-000000000801', 20.00, 0, 2.80, 22.80,
   '2026-10-12 10:00 Africa/Cairo'),
  ('bbbbbbbb-00f0-0000-0000-000000000803', 'bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
   'bbbbbbbb-0004-0000-0000-000000000001', 'sale', null, 50.00, 0, 7.00, 57.00, '2026-10-12 12:00 Africa/Cairo'),
  ('aaaaaaaa-00f0-0000-0000-000000000801', 'aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0002-0000-0000-000000000001',
   'aaaaaaaa-0004-0000-0000-000000000001', 'sale', null, 8.00, 0, 1.12, 9.12, '2026-10-12 12:00 Africa/Cairo');
insert into app.sale_lines (tenant_id, branch_id, sale_id, line_no, product_id, quantity, unit_price,
                            discount_amount, vat_rate, tax_amount, line_total) values
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-00f0-0000-0000-000000000801', 1,
   'bbbbbbbb-0005-0000-0000-000000000002', 1, 100.00, 10.00, 14, 12.60, 102.60),
  ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-00f0-0000-0000-000000000802', 1,
   'bbbbbbbb-0005-0000-0000-000000000004', 4, 5.00, 0, 14, 2.80, 22.80);

-- The analytics assistant, asking for the Nile owner
set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
set local role market_ai_reader;

select throws_ok($$ select count(*) from app.sales $$, '42501', null,
  'LLM-generated SQL cannot touch raw tables');
select throws_ok(
  $$ select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000', p_system_actor => 'llm') $$,
  '42501', null, 'LLM-generated SQL cannot switch itself to another tenant');

-- Nor can prompt-injected SQL rewrite the context it was given
select set_config('app.current_tenant_id', 'aaaaaaaa-0000-0000-0000-000000000000', true);
select throws_ok($$ select count(*) from analytics.sales_daily $$, '42501', null,
  'LLM-generated SQL cannot move its own context to another tenant with set_config');
reset role;
set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
set local role market_ai_reader;

select results_eq(
  $$ select transactions, gross_sales, discounts, returns, net_revenue, tax_collected, average_basket
       from analytics.sales_daily
      where branch_id = 'bbbbbbbb-0002-0000-0000-000000000002' and sales_date = '2026-10-12' $$,
  $$ values (1::bigint, 100.00::numeric, 10.00::numeric, 20.00::numeric, 70.00::numeric, 9.80::numeric, 102.60::numeric) $$,
  'Maadi''s day: a sale at 23:30 UTC counts on the Cairo date, and returns come off net revenue');
select is((select count(*)::int from analytics.sales_daily
            where branch_id = 'bbbbbbbb-0002-0000-0000-000000000002' and sales_date = '2026-10-11'),
  0, 'nothing lands on the UTC date');
select is((select net_revenue from analytics.product_sales_daily
            where branch_id = 'bbbbbbbb-0002-0000-0000-000000000002' and sales_date = '2026-10-12'
              and product_id = 'bbbbbbbb-0005-0000-0000-000000000002'),
  90.00, 'product revenue is net of discount and VAT');
select is((select quantity from analytics.product_sales_daily
            where branch_id = 'bbbbbbbb-0002-0000-0000-000000000002' and sales_date = '2026-10-12'
              and product_id = 'bbbbbbbb-0005-0000-0000-000000000004'),
  -4.000, 'returned units count against the product');
select is((select stock_value from analytics.stock_on_hand
            where branch_id = 'bbbbbbbb-0002-0000-0000-000000000001' and product_id = 'bbbbbbbb-0005-0000-0000-000000000002'),
  3500.0000000, 'stock is valued at batch purchase cost (50 × 70.00)');
select is((select count(*)::int from analytics.sales_daily where tenant_id <> 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'the owner''s analytics never include another tenant');
select is((select count(*)::int from analytics.sales_daily
            where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000' and sales_date = '2026-10-12'),
  2, 'the owner sees every Nile branch that traded that day');

-- The same views under a Maadi cashier
reset role;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000006',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
set local role market_ai_reader;
select is((select count(*)::int from analytics.sales_daily
            where branch_id <> 'bbbbbbbb-0002-0000-0000-000000000002'), 0,
  'a Maadi cashier''s analytics show Maadi only');
select is((select count(*)::int from analytics.stock_on_hand
            where branch_id <> 'bbbbbbbb-0002-0000-0000-000000000002'), 0,
  'a Maadi cashier''s stock view shows Maadi only');
set local app.current_system_actor = 'report_job';
select throws_ok($$ select count(*) from analytics.sales_daily $$, '42501', null,
  'nor can it widen a cashier''s reach by posing as a background job');

-- The backend runs model SQL only through analytics.run_query
reset role;
set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select is((select (r ->> 'net_revenue')::numeric
             from analytics.run_query($q$ select net_revenue from analytics.sales_daily
                                          where branch_id = 'bbbbbbbb-0002-0000-0000-000000000002'
                                            and sales_date = '2026-10-12' $q$) r),
  70.00, 'analytics.run_query returns each result row as JSON');
select throws_ok($$ select * from analytics.run_query($q$ select set_config('role', 'market_backend', true) $q$) $$,
  '42501', null, 'model SQL cannot switch back to the backend role');
select throws_ok($$ select * from analytics.run_query($q$ select provider_token from app.customer_payment_methods $q$) $$,
  '42501', null, 'model SQL cannot read raw tables');
select throws_ok(
  $$ select * from analytics.run_query($q$
       with ctx as materialized (select set_config('app.current_tenant_id', 'aaaaaaaa-0000-0000-0000-000000000000', true) as t)
       select d.* from ctx, lateral (select * from analytics.sales_daily where ctx.t is not null) d $q$) $$,
  '42501', null, 'model SQL cannot rewrite its context inside run_query either');
create temp table model_lock as select * from analytics.run_query($q$ select pg_try_advisory_lock(42) as locked $q$);
select is((select count(*)::int from pg_catalog.pg_locks where locktype = 'advisory' and pid = pg_backend_pid()), 0,
  'advisory locks taken by model SQL are released when run_query returns');

-- Without context nothing comes back
reset role;
select app.set_context();
set local role market_ai_reader;
select is((select count(*)::int from analytics.sales_daily), 0, 'no context, no sales rows');
select is((select count(*)::int from analytics.stock_on_hand), 0, 'no context, no stock rows');
select is((select count(*)::int from analytics.product_sales_daily), 0, 'no context, no product rows');
reset role;

select * from finish();
rollback;
