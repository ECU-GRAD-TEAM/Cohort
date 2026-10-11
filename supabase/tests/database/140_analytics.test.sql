-- Analytics semantic layer for NL-to-SQL (Dual-RAG §2.8, addendum §3.3): LLM-generated SQL
-- runs as market_ai_reader, sees only governed views, and RLS still bounds every row.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

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
