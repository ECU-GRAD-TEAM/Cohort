-- Tamper-evident audit ledger (T9, REQ-SECU-02): Hash_n = sha256(seq || Hash_{n-1} || payload).
-- Expected hashes below were computed independently (Python hashlib) from the same strings.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

set local role market_backend;

-- The tenant's cloud chain, written through append_audit
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select app.append_audit('PRICE_CHANGE', '{"product_id": "bbbbbbbb-0005-0000-0000-000000000002", "old_price": 89.50, "new_price": 92.00}',
                        'bbbbbbbb-0002-0000-0000-000000000002');
select app.append_audit('REFUND_APPROVED', '{"sale_id": null, "amount": 60.00}',
                        'bbbbbbbb-0002-0000-0000-000000000001', 'bbbbbbbb-0003-0000-0000-000000000004');
select app.append_audit('DRAWER_OPEN', '{"reason": "manual"}', 'bbbbbbbb-0002-0000-0000-000000000001');

select results_eq(
  $$ select seq from app.audit_log where chain_id = 'bbbbbbbb-0000-0000-0000-000000000000' order by seq $$,
  $$ values (0::bigint), (1), (2), (3) $$,
  'three appends follow an automatic genesis block');
select is((select hash from app.audit_log where chain_id = 'bbbbbbbb-0000-0000-0000-000000000000' and seq = 0),
  'bc4bda43015a9f269396874aea25ccfbae79a46f62e866c674ca2d5be043bf94',
  'the genesis hash is sha256(seq || prev_hash || payload)');
select is((select prev_hash from app.audit_log where chain_id = 'bbbbbbbb-0000-0000-0000-000000000000' and seq = 2),
  (select hash from app.audit_log where chain_id = 'bbbbbbbb-0000-0000-0000-000000000000' and seq = 1),
  'each block links to the hash of the block before it');
select is((select approved_by_staff_id from app.audit_log
            where chain_id = 'bbbbbbbb-0000-0000-0000-000000000000' and seq = 2),
  'bbbbbbbb-0003-0000-0000-000000000004'::uuid, 'the approving manager is recorded with the override');
select results_eq(
  $$ select * from app.verify_audit_chain('bbbbbbbb-0000-0000-0000-000000000000') $$,
  $$ values (true, 4::bigint, null::bigint, null::text) $$,
  'an untouched chain verifies');
select throws_ok(
  $$ select app.append_audit('DRAWER_OPEN', '{}', 'aaaaaaaa-0002-0000-0000-000000000001') $$,
  '42501', null, 'audit entries cannot be filed against another tenant''s branch');

-- A till's own chain, computed on the till and verified on arrival
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000005',
                       p_device_id => 'bbbbbbbb-0004-0000-0000-000000000001');
insert into app.audit_log (tenant_id, branch_id, chain_id, device_id, seq, event_type, payload, prev_hash, hash)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 0, 'GENESIS_BLOCK',
        '{"event": "GENESIS_BLOCK"}', repeat('0', 64),
        'bc4bda43015a9f269396874aea25ccfbae79a46f62e866c674ca2d5be043bf94');
select lives_ok(
  $$ insert into app.audit_log (tenant_id, branch_id, chain_id, device_id, seq, event_type, payload, prev_hash, hash)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 1, 'REFUND',
             '{"amount": 50.00, "event": "REFUND", "sale_id": null}',
             'bc4bda43015a9f269396874aea25ccfbae79a46f62e866c674ca2d5be043bf94',
             'c818b9f54cd59a7f0208513f8a6fff5b3e782d5806ab112d1bcdb9430c898a68') $$,
  'a till block with the right hash is accepted');
select throws_ok(
  $$ insert into app.audit_log (tenant_id, branch_id, chain_id, device_id, seq, event_type, payload, prev_hash, hash)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 2, 'SALE_VOID',
             '{"event": "SALE_VOID", "sale_id": null}', repeat('1', 64),
             'f69b8ccf8221f1ac08533f38fd84a887e4ca94d7ed06416e9406f7473806812d') $$,
  'P0001', null, 'a block that does not link to its predecessor is refused');
select throws_ok(
  $$ insert into app.audit_log (tenant_id, branch_id, chain_id, device_id, seq, event_type, payload, prev_hash, hash)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 2, 'SALE_VOID',
             '{"event": "SALE_VOID", "sale_id": null}',
             'c818b9f54cd59a7f0208513f8a6fff5b3e782d5806ab112d1bcdb9430c898a68', repeat('2', 64)) $$,
  'P0001', null, 'a block whose hash does not match its content is refused');
select throws_ok(
  $$ insert into app.audit_log (tenant_id, branch_id, chain_id, device_id, seq, event_type, payload, prev_hash, hash)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 5, 'SALE_VOID',
             '{"event": "SALE_VOID", "sale_id": null}',
             'c818b9f54cd59a7f0208513f8a6fff5b3e782d5806ab112d1bcdb9430c898a68',
             'f69b8ccf8221f1ac08533f38fd84a887e4ca94d7ed06416e9406f7473806812d') $$,
  'P0001', null, 'blocks must arrive in order');
select throws_ok(
  $$ insert into app.audit_log (tenant_id, branch_id, chain_id, device_id, seq, event_type, payload, prev_hash, hash)
     values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
             'aaaaaaaa-0004-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 0, 'GENESIS_BLOCK',
             '{"event": "GENESIS_BLOCK"}', repeat('0', 64),
             'bc4bda43015a9f269396874aea25ccfbae79a46f62e866c674ca2d5be043bf94') $$,
  'P0001', null, 'a tenant cannot write into another tenant''s chain');
insert into app.audit_log (tenant_id, branch_id, chain_id, device_id, seq, event_type, payload, prev_hash, hash)
values ('bbbbbbbb-0000-0000-0000-000000000000', 'bbbbbbbb-0002-0000-0000-000000000001',
        'bbbbbbbb-0004-0000-0000-000000000001', 'bbbbbbbb-0004-0000-0000-000000000001', 2, 'SALE_VOID',
        '{"event": "SALE_VOID", "sale_id": null}',
        'c818b9f54cd59a7f0208513f8a6fff5b3e782d5806ab112d1bcdb9430c898a68',
        'f69b8ccf8221f1ac08533f38fd84a887e4ca94d7ed06416e9406f7473806812d');
select is((select payload_json ->> 'event' from app.audit_log
            where chain_id = 'bbbbbbbb-0004-0000-0000-000000000001' and seq = 2),
  'SALE_VOID', 'the hashed payload text stays queryable as JSON');

select ok(not has_table_privilege('market_backend', 'app.audit_log', 'UPDATE'), 'the backend cannot edit audit blocks');
select ok(not has_table_privilege('market_backend', 'app.audit_log', 'DELETE'), 'the backend cannot delete audit blocks');

-- Even the table owner is stopped by the guard; going around it is detected
reset role;
select throws_like($$ update app.audit_log set payload = '{}' $$, '%append-only%',
  'the guard stops edits by the table owner');

alter table app.audit_log disable trigger audit_log_append_only;

update app.audit_log set payload = '{"reason": "manual", "amount": 0}'
 where chain_id = 'bbbbbbbb-0000-0000-0000-000000000000' and seq = 2;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select results_eq(
  $$ select is_valid, first_invalid_seq, reason from app.verify_audit_chain('bbbbbbbb-0000-0000-0000-000000000000') $$,
  $$ values (false, 2::bigint, 'hash mismatch'::text) $$,
  'an edited payload is caught at its own block');

delete from app.audit_log where chain_id = 'bbbbbbbb-0000-0000-0000-000000000000' and seq = 2;
select results_eq(
  $$ select is_valid, first_invalid_seq, reason from app.verify_audit_chain('bbbbbbbb-0000-0000-0000-000000000000') $$,
  $$ values (false, 3::bigint, 'sequence gap'::text) $$,
  'a deleted block is caught at the next block');

-- An attacker who edits a block and recomputes its hash breaks the link to the next block
update app.audit_log
   set payload = '{"amount": 5.00, "event": "REFUND", "sale_id": null}',
       hash = '6309916487bb81ad2a16c2438115a4754000e0e91769cb52b0244301e497f62c'
 where chain_id = 'bbbbbbbb-0004-0000-0000-000000000001' and seq = 1;
select results_eq(
  $$ select is_valid, first_invalid_seq, reason from app.verify_audit_chain('bbbbbbbb-0004-0000-0000-000000000001') $$,
  $$ values (false, 2::bigint, 'prev_hash mismatch'::text) $$,
  'a re-hashed edit is caught where the chain no longer links');

alter table app.audit_log enable trigger audit_log_append_only;

select app.set_context(p_tenant_id => 'aaaaaaaa-0000-0000-0000-000000000000',
                       p_staff_id  => 'aaaaaaaa-0003-0000-0000-000000000001');
select throws_ok(
  $$ select * from app.verify_audit_chain('bbbbbbbb-0000-0000-0000-000000000000') $$,
  '42501', null, 'one tenant cannot inspect another tenant''s chain');

select * from finish();
rollback;
