-- Loyalty (spec §5.6): one programme per tenant, tenant-scoped memberships of global
-- shoppers, and an append-only points ledger. Also opens the narrow cross paths between
-- shoppers and staff: each side sees the other only where they actually do business.

create table app.loyalty_programs (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null unique references app.tenants (id),
  name_en            text not null,
  name_ar            text,
  points_per_egp     numeric(8,4) not null default 1 check (points_per_egp >= 0),
  egp_per_point      numeric(8,4) not null default 0.05 check (egp_per_point >= 0),
  points_expiry_days int check (points_expiry_days > 0),
  tiers              jsonb not null default '[]' check (jsonb_typeof(tiers) = 'array'),
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (tenant_id, id)
);

create table app.loyalty_accounts (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  program_id  uuid not null,
  customer_id uuid not null references app.customers (id),
  card_number text,
  tier        text,
  joined_at   timestamptz not null default now(),
  unique (tenant_id, customer_id),
  unique (tenant_id, card_number),
  unique (tenant_id, id),
  unique (id, customer_id),
  foreign key (tenant_id, program_id) references app.loyalty_programs (tenant_id, id)
);

create table app.loyalty_ledger (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  account_id  uuid not null,
  customer_id uuid not null,
  branch_id   uuid,
  sale_id     uuid,
  entry_type  text not null check (entry_type in ('earn', 'redeem', 'expire', 'adjust')),
  points      int not null check (points <> 0),
  expires_at  timestamptz,
  occurred_at timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  check ((entry_type = 'earn' and points > 0)
      or (entry_type in ('redeem', 'expire') and points < 0)
      or entry_type = 'adjust'),
  foreign key (account_id, customer_id) references app.loyalty_accounts (id, customer_id),
  foreign key (tenant_id, account_id) references app.loyalty_accounts (tenant_id, id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, sale_id) references app.sales (tenant_id, id)
);
create index loyalty_ledger_account_idx on app.loyalty_ledger (account_id);

create trigger loyalty_ledger_append_only before update or delete on app.loyalty_ledger
  for each row execute function app.prevent_mutation();
create trigger loyalty_programs_updated_at before update on app.loyalty_programs
  for each row execute function app.set_updated_at();

create view app.loyalty_balances with (security_invoker = true) as
  select a.id as account_id, a.tenant_id, a.customer_id, coalesce(sum(l.points), 0)::int as points
    from app.loyalty_accounts a
    left join app.loyalty_ledger l on l.account_id = a.id
   group by a.id, a.tenant_id, a.customer_id;

alter table app.loyalty_programs enable row level security;
alter table app.loyalty_accounts enable row level security;
alter table app.loyalty_ledger enable row level security;

create policy loyalty_programs_read on app.loyalty_programs for select
  using (tenant_id = (select app.current_tenant_id()));
create policy loyalty_programs_write on app.loyalty_programs for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy loyalty_accounts_internal on app.loyalty_accounts for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy loyalty_accounts_self_read on app.loyalty_accounts for select
  using (customer_id = (select app.current_customer_id())
         and ((select app.current_tenant_id()) is null or tenant_id = (select app.current_tenant_id())));
create policy loyalty_accounts_self_join on app.loyalty_accounts for insert
  with check (customer_id = (select app.current_customer_id())
              and tenant_id = (select app.current_tenant_id()));

create policy loyalty_ledger_internal on app.loyalty_ledger for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy loyalty_ledger_internal_insert on app.loyalty_ledger for insert
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy loyalty_ledger_self_read on app.loyalty_ledger for select
  using (customer_id = (select app.current_customer_id())
         and ((select app.current_tenant_id()) is null or tenant_id = (select app.current_tenant_id())));

-- Cross paths. A shopper may read the markets and branches they belong to or bought
-- from; staff may read a shopper who is a member of, or bought from, their tenant.
-- Shopper paths span all markets only without a tenant context ("my account" in the
-- app); inside a storefront the tenant context bounds them like everything else.
create policy tenants_customer_read on app.tenants for select
  using ((select app.current_customer_id()) is not null
         and ((select app.current_tenant_id()) is null or tenants.id = (select app.current_tenant_id()))
         and (exists (select 1 from app.loyalty_accounts la
                       where la.tenant_id = tenants.id and la.customer_id = (select app.current_customer_id()))
              or exists (select 1 from app.sales s
                          where s.tenant_id = tenants.id and s.customer_id = (select app.current_customer_id()))));

create policy branches_customer_read on app.branches for select
  using ((select app.current_customer_id()) is not null
         and ((select app.current_tenant_id()) is null or branches.tenant_id = (select app.current_tenant_id()))
         and (exists (select 1 from app.loyalty_accounts la
                       where la.tenant_id = branches.tenant_id and la.customer_id = (select app.current_customer_id()))
              or exists (select 1 from app.sales s
                          where s.branch_id = branches.id and s.customer_id = (select app.current_customer_id()))));

create policy customers_staff_read on app.customers for select
  using ((select app.is_internal())
         and (exists (select 1 from app.loyalty_accounts la
                       where la.customer_id = customers.id and la.tenant_id = (select app.current_tenant_id()))
              or exists (select 1 from app.sales s
                          where s.customer_id = customers.id and s.tenant_id = (select app.current_tenant_id()))));

grant select, insert, update, delete on app.loyalty_programs to market_backend;
grant select, insert, update on app.loyalty_accounts to market_backend;
grant select, insert on app.loyalty_ledger to market_backend;
grant select on app.loyalty_balances to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
