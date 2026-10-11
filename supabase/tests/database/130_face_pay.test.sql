-- Face Pay (optional stage 5): consented enrollments on the identity side, templates kept in a
-- separate schema only the matching service can touch (PDPL Law 151/2020), limits at checkout.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- Fixtures (as the table owner)
create temp table probe as
  select (select array_agg(case when g = 1 then 1.0 else 0 end order by g) from generate_series(1, 128) g)::real[]::extensions.vector(128) as mona,
         (select array_agg(case when g = 2 then 1.0 else 0 end order by g) from generate_series(1, 128) g)::real[]::extensions.vector(128) as karim,
         (select array_agg(case when g = 1 then 2.1 else 0 end order by g) from generate_series(1, 128) g)::real[]::extensions.vector(128) as far;
grant select on probe to market_biometric;

insert into biometric.face_templates (subject_token, embedding)
select lpad('a1', 64, '0'), mona from probe
union all
select lpad('a2', 64, '0'), karim from probe;

insert into app.customer_payment_methods (id, customer_id, provider, provider_token, brand, last4)
values ('cccccccc-00f0-0000-0000-000000000002', 'cccccccc-0007-0000-0000-000000000002', 'paymob', 'tok_test_karim', 'meeza', '5078');

insert into app.face_pay_enrollments (id, customer_id, subject_token, payment_method_id, consent_version,
                                      per_transaction_limit, daily_limit)
select 'cccccccc-00f1-0000-0000-000000000001', 'cccccccc-0007-0000-0000-000000000001', lpad('a1', 64, '0'),
       pm.id, 'face-pay-consent-v1', 500.00, 1000.00
  from app.customer_payment_methods pm where pm.customer_id = 'cccccccc-0007-0000-0000-000000000001';
insert into app.face_pay_enrollments (id, customer_id, subject_token, payment_method_id, consent_version)
values ('cccccccc-00f1-0000-0000-000000000002', 'cccccccc-0007-0000-0000-000000000002', lpad('a2', 64, '0'),
        'cccccccc-00f0-0000-0000-000000000002', 'face-pay-consent-v1');

-- The backend never sees templates
select ok(not has_schema_privilege('market_backend', 'biometric', 'USAGE'), 'the backend cannot enter the biometric schema');
select ok(not has_table_privilege('market_backend', 'biometric.face_templates', 'SELECT'),
  'the backend cannot read face templates');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'biometric' and table_name = 'face_templates' and column_name like '%customer%'),
  0, 'templates carry no customer identity, only a non-reversible token');

-- The matching service
set local role market_biometric;
select results_eq(
  $$ select subject_token, squared_distance from biometric.match_face((select mona from probe)) $$,
  $$ values (lpad('a1', 64, '0'), 0::float8) $$,
  'an identical face matches its own template at distance 0');
select is_empty(
  $$ select * from biometric.match_face((select far from probe)) $$,
  'a face at squared distance 1.21 is above the 1.10 threshold and matches nobody');
reset role;

-- Checkout at the Nasr City till
set local role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000005',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
select results_eq(
  $$ select customer_id, provider_token from app.resolve_face_pay(lpad('a1', 64, '0'), 100.00) $$,
  $$ values ('cccccccc-0007-0000-0000-000000000001'::uuid, 'tok_test_mona_visa'::text) $$,
  'an active enrollment within its limits resolves to the shopper''s tokenised card');
select is_empty($$ select * from app.resolve_face_pay(lpad('a1', 64, '0'), 600.00) $$,
  'a payment above the per-transaction limit does not resolve');

insert into app.sales (id, tenant_id, branch_id, device_id, customer_id, subtotal, grand_total, occurred_at)
values ('bbbbbbbb-00f0-0000-0000-000000000701', 'bbbbbbbb-0000-0000-0000-000000000000',
        'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
        'cccccccc-0007-0000-0000-000000000001', 450.00, 450.00, now());
insert into app.sale_payments (tenant_id, branch_id, sale_id, method, provider, amount, face_pay_enrollment_id)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000701', 'face_pay', 'paymob', 450.00, 'cccccccc-00f1-0000-0000-000000000001');
insert into app.sales (id, tenant_id, branch_id, device_id, customer_id, subtotal, grand_total, occurred_at)
values ('bbbbbbbb-00f0-0000-0000-000000000702', 'bbbbbbbb-0000-0000-0000-000000000000',
        'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001',
        'cccccccc-0007-0000-0000-000000000001', 450.00, 450.00, now());
insert into app.sale_payments (tenant_id, branch_id, sale_id, method, provider, amount, face_pay_enrollment_id)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-00f0-0000-0000-000000000702', 'face_pay', 'paymob', 450.00, 'cccccccc-00f1-0000-0000-000000000001');
select is_empty($$ select * from app.resolve_face_pay(lpad('a1', 64, '0'), 100.01) $$,
  'a payment that would take today''s face-pay total above the daily limit does not resolve');
select is((select count(*)::int from app.resolve_face_pay(lpad('a1', 64, '0'), 100.00)), 1,
  'a payment that reaches the daily limit exactly still resolves');

-- The shopper controls their own enrollment
select app.set_context(p_customer_id => 'cccccccc-0007-0000-0000-000000000001');
select is((select count(*)::int from app.face_pay_enrollments), 1, 'Mona sees only her own enrollment');
select throws_ok($$ select * from app.resolve_face_pay(lpad('a1', 64, '0'), 10.00) $$, '42501', null,
  'a shopper cannot resolve a face token');
select throws_ok(
  $$ insert into app.face_pay_enrollments (customer_id, subject_token, payment_method_id, consent_version)
     values ('cccccccc-0007-0000-0000-000000000001', lpad('b1', 64, '0'), 'cccccccc-00f0-0000-0000-000000000002',
             'face-pay-consent-v1') $$,
  '23503', null, 'an enrollment cannot charge another shopper''s card');
update app.face_pay_enrollments set status = 'paused' where id = 'cccccccc-00f1-0000-0000-000000000001';

select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
select is_empty($$ select * from app.resolve_face_pay(lpad('a1', 64, '0'), 10.00) $$,
  'a paused enrollment does not resolve');
reset role;

-- Erasure (PDPL): the matching service deletes a subject's templates
set local role market_biometric;
select is(biometric.delete_subject(lpad('a1', 64, '0')), 1, 'erasing a subject removes their template');
select is_empty($$ select * from biometric.match_face((select mona from probe)) $$,
  'an erased face no longer matches');
reset role;

select * from finish();
rollback;
