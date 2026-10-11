-- Promotions (ADR-003, spec §5.4): rules authored centrally as JSON ASTs, compiled into
-- versioned bundles that tills evaluate offline, plus coupons and personal reward codes.

create table app.promotions (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references app.tenants (id),
  name_en         text not null,
  name_ar         text,
  mechanic        text not null check (mechanic in ('percentage', 'fixed_amount', 'multibuy', 'bogo', 'tiered_spend',
                                                    'category_spend', 'loyalty_tier', 'meal_deal', 'coupon',
                                                    'cheapest_free')),
  rule            jsonb not null check (jsonb_typeof(rule) = 'object'),
  priority        int not null default 0,
  exclusive_group text,
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  is_active       boolean not null default true,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (tenant_id, id),
  check (ends_at is null or ends_at > starts_at),
  foreign key (tenant_id, created_by) references app.staff (tenant_id, id)
);
comment on column app.promotions.rule is 'Promotion definition (AST / JSON Decision Model) evaluated by the offline pricing engine.';

create table app.promotion_branches (
  tenant_id    uuid not null,
  promotion_id uuid not null,
  branch_id    uuid not null,
  primary key (promotion_id, branch_id),
  foreign key (tenant_id, promotion_id) references app.promotions (tenant_id, id) on delete cascade,
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);
comment on table app.promotion_branches is 'Branch scope of a promotion. No rows means every branch of the tenant.';

create table app.promotion_rule_sets (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references app.tenants (id),
  version      int not null check (version > 0),
  compiled     jsonb not null check (jsonb_typeof(compiled) = 'object'),
  checksum     text not null,
  published_at timestamptz not null default now(),
  published_by uuid,
  unique (tenant_id, version),
  foreign key (tenant_id, published_by) references app.staff (tenant_id, id)
);
comment on column app.promotion_rule_sets.checksum is 'sha256 hex of compiled::text (the canonical bundle tills download), set on insert.';

create function app.set_rule_set_checksum() returns trigger
language plpgsql
as $$
begin
  new.checksum := encode(sha256(convert_to(new.compiled::text, 'UTF8')), 'hex');
  return new;
end
$$;
create trigger promotion_rule_sets_checksum before insert on app.promotion_rule_sets
  for each row execute function app.set_rule_set_checksum();
create trigger promotion_rule_sets_append_only before update or delete on app.promotion_rule_sets
  for each row execute function app.prevent_mutation();

create table app.coupons (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  promotion_id       uuid not null,
  code               text not null check (code ~ '^[A-Za-z0-9_-]{3,32}$'),
  customer_id        uuid references app.customers (id),
  max_redemptions    int check (max_redemptions > 0),
  per_customer_limit int check (per_customer_limit > 0),
  starts_at          timestamptz,
  ends_at            timestamptz,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  unique (tenant_id, id),
  check (ends_at is null or starts_at is null or ends_at > starts_at),
  foreign key (tenant_id, promotion_id) references app.promotions (tenant_id, id)
);
comment on column app.coupons.customer_id is 'Set for personal reward coupons; NULL for codes anyone may type in.';
create unique index coupons_code_key on app.coupons (tenant_id, lower(code));

create trigger promotions_updated_at before update on app.promotions
  for each row execute function app.set_updated_at();

alter table app.promotions enable row level security;
alter table app.promotion_branches enable row level security;
alter table app.promotion_rule_sets enable row level security;
alter table app.coupons enable row level security;

-- Shoppers see running offers only; unannounced promotions stay internal.
create policy promotions_read on app.promotions for select
  using (tenant_id = (select app.current_tenant_id())
         and ((select app.is_internal())
              or (is_active and deleted_at is null and starts_at <= now()
                  and (ends_at is null or ends_at > now()))));
create policy promotions_write on app.promotions for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy promotion_branches_read on app.promotion_branches for select
  using (tenant_id = (select app.current_tenant_id()));
create policy promotion_branches_write on app.promotion_branches for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy promotion_rule_sets_read on app.promotion_rule_sets for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy promotion_rule_sets_insert on app.promotion_rule_sets for insert
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy coupons_internal on app.coupons for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy coupons_personal on app.coupons for select
  using (customer_id = (select app.current_customer_id()));

grant select, insert, update, delete on app.promotions, app.promotion_branches, app.coupons to market_backend;
grant select, insert on app.promotion_rule_sets to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
