-- Catalog: tenant-owned products, GTIN-14 barcodes, branch prices, shopper read access.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

set local role market_backend;

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select throws_ok(
  $$ insert into app.product_barcodes (tenant_id, product_id, barcode, kind)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002', '12345678901234', 'gtin') $$,
  '23514', null, 'a GTIN with a wrong check digit is rejected');
select lives_ok(
  $$ insert into app.product_barcodes (tenant_id, product_id, barcode, kind)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000002', '00012345678905', 'gtin') $$,
  'a valid GTIN-14 is accepted');
select throws_ok(
  $$ insert into app.product_barcodes (tenant_id, product_id, barcode, kind)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000004', '00012345678905', 'gtin') $$,
  '23505', null, 'a barcode belongs to one product within a tenant');
select is((select barcode from app.product_barcodes
            where product_id = 'bbbbbbbb-0005-0000-0000-000000000001' and kind = 'gtin'),
  '06221000000010', 'barcodes keep their leading zeros');
update app.product_barcodes set deleted_at = now()
 where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000' and barcode = '00012345678905';
select lives_ok(
  $$ insert into app.product_barcodes (tenant_id, product_id, barcode, kind)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0005-0000-0000-000000000004', '00012345678905', 'gtin') $$,
  'a retired barcode can be given to another product');
select throws_ok(
  $$ insert into app.products (tenant_id, sku, name_en, base_price, is_weighed, unit_of_measure)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'W-1', 'Loose olives', 120, true, 'unit') $$,
  '23514', null, 'weighed products need a measurable unit');

select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select lives_ok(
  $$ insert into app.product_barcodes (tenant_id, product_id, barcode, kind)
     values ('aaaaaaaa-0000-0000-0000-000000000000', 'aaaaaaaa-0005-0000-0000-000000000002', '00012345678905', 'gtin') $$,
  'another tenant may use the same barcode');
select is((select count(*)::int from app.products), 2, 'Alpha sees its two products');
select is((select count(*)::int from app.products where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'Alpha staff never see Nile products');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000005',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
select is((select count(*)::int from app.products), 4, 'Nile staff see the four Nile products');
select is((select count(*)::int from app.products where tenant_id <> 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'Nile staff never see Alpha products');
select is(app.effective_price('bbbbbbbb-0002-0000-0000-000000000002', 'bbbbbbbb-0005-0000-0000-000000000002'), 95.00,
  'Maadi sells rice at its own price');
select is(app.effective_price('bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0005-0000-0000-000000000002'), 89.50,
  'Nasr City falls back to the base price');

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000006',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000002');
select throws_ok(
  $$ insert into app.branch_prices (tenant_id, branch_id, product_id, price)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0005-0000-0000-000000000004', 1) $$,
  '42501', null, 'staff cannot set prices for a branch outside their reach');

select app.set_context(p_tenant_id   => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.products), 4, 'a shopper can browse the catalog');
select is((select count(*)::int from app.branch_prices), 1, 'a shopper can read branch prices');
select throws_ok(
  $$ insert into app.products (tenant_id, sku, name_en, base_price)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'HACK', 'Free stuff', 0) $$,
  '42501', null, 'a shopper cannot change the catalog');
select throws_ok(
  $$ insert into app.branch_prices (tenant_id, branch_id, product_id, price)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0005-0000-0000-000000000002', 1) $$,
  '42501', null, 'a shopper cannot set prices');

select * from finish();
rollback;
