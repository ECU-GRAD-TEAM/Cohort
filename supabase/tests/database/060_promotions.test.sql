-- Promotions (ADR-003): rule definitions, versioned till bundles, coupons, shopper visibility.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');

select throws_ok(
  $$ insert into app.promotions (tenant_id, name_en, mechanic, rule, starts_at)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'Bad rule', 'percentage', '[10]', now()) $$,
  '23514', null, 'a promotion rule must be a JSON object');
select throws_ok(
  $$ insert into app.promotions (tenant_id, name_en, mechanic, rule, starts_at, ends_at)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'Backwards', 'percentage', '{"percent": 10}',
             '2026-11-01', '2026-10-01') $$,
  '23514', null, 'a promotion cannot end before it starts');
select throws_ok(
  $$ insert into app.promotions (tenant_id, name_en, mechanic, rule, starts_at)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'Mystery', 'mystery_box', '{}', now()) $$,
  '23514', null, 'only the ten supported mechanics are accepted');

insert into app.promotions (id, tenant_id, name_en, mechanic, rule, starts_at) values
  ('bbbbbbbb-000a-0000-0000-0000000000f1', 'bbbbbbbb-0000-0000-0000-000000000000', 'Ramadan preview', 'percentage',
   '{"percent": 20}', now() + interval '30 days');

-- Versioned bundles the tills download (FR-07 hot-swap)
insert into app.promotion_rule_sets (tenant_id, version, compiled)
values ('bbbbbbbb-0000-0000-0000-000000000000', 1, '{"rules": [], "v": 1}');
select is((select checksum from app.promotion_rule_sets
            where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000' and version = 1),
  '2aec0b155f8dc685b821c1b0622f3ea74cb4688bd97b9744f93b4e6a7e5b27c5',
  'the checksum is the sha256 of the canonical bundle text tills download');
select throws_ok(
  $$ insert into app.promotion_rule_sets (tenant_id, version, compiled)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 1, '{"v": 9}') $$,
  '23505', null, 'each bundle version is published once');
select ok(not has_table_privilege('market_backend', 'app.promotion_rule_sets', 'UPDATE'),
  'the backend cannot rewrite a published bundle');

-- Coupon codes are case-insensitive within a tenant
insert into app.coupons (tenant_id, promotion_id, code)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-000a-0000-0000-000000000002', 'WELCOME10');
select throws_ok(
  $$ insert into app.coupons (tenant_id, promotion_id, code)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-000a-0000-0000-000000000002', 'welcome10') $$,
  '23505', null, 'coupon codes are unique regardless of case');
select is((select count(*)::int from app.promotions), 3, 'staff see every promotion, including unannounced ones');

-- A till downloads the bundle
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
select is((select count(*)::int from app.promotion_rule_sets where version = 1), 1, 'a till can download the compiled bundle');

-- Shopper view of the Nile storefront
select app.set_context(p_tenant_id   => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.promotions where id = 'bbbbbbbb-000a-0000-0000-000000000001'), 1,
  'a shopper sees the running multibuy offer');
select is((select count(*)::int from app.promotions where id = 'bbbbbbbb-000a-0000-0000-0000000000f1'), 0,
  'a shopper cannot see a promotion that has not started');
select is((select count(*)::int from app.coupons where code = 'SAVE5'), 0, 'a shopper cannot browse generic coupon codes');
select is((select count(*)::int from app.coupons where customer_id = 'cccccccc-0007-0000-0000-000000000001'), 1,
  'a shopper sees their personal reward coupon');
select is((select count(*)::int from app.promotion_rule_sets), 0, 'compiled bundles are for tills, not shoppers');
select throws_ok(
  $$ insert into app.promotions (tenant_id, name_en, mechanic, rule, starts_at)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'Free for me', 'percentage', '{"percent": 100}', now()) $$,
  '42501', null, 'a shopper cannot create promotions');

select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000002');
select is((select count(*)::int from app.coupons), 0, 'another shopper cannot see Mona''s personal coupon');

select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select is((select count(*)::int from app.promotions where tenant_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 0,
  'another tenant never sees Nile promotions');

reset role;
select throws_like($$ update app.promotion_rule_sets set compiled = '{"v": 2}' $$, '%append-only%',
  'a published bundle never changes, even for the table owner');
select throws_like($$ delete from app.promotion_rule_sets $$, '%append-only%',
  'a published bundle is never deleted, even by the table owner');

select * from finish();
rollback;
