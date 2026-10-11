-- Context is transaction-local. Run without an explicit transaction: every statement
-- autocommits, so a context set by one statement must be gone for the next one. This is
-- what keeps a pooled connection from carrying one tenant's context to the next client.
create extension if not exists pgtap with schema extensions;
select plan(3);

set role market_backend;
select app.set_context(p_tenant_id => 'bbbbbbbb-0000-0000-0000-000000000000',
                       p_staff_id  => 'bbbbbbbb-0003-0000-0000-000000000001');
select is(app.current_tenant_id(), null, 'tenant context ends with its transaction');
select is(app.current_staff_id(), null, 'staff context ends with its transaction');
select is((select count(*)::int from app.branches), 0, 'no rows are visible once the context transaction ended');
reset role;

select * from finish();
