-- Catalog: tenant-owned products with bilingual names, GTIN-14 barcodes and per-branch
-- price overrides (spec §5.2). Shoppers browsing a storefront may read; staff write.

create table app.product_categories (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references app.tenants (id),
  parent_id  uuid,
  name_en    text not null,
  name_ar    text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant_id, id),
  foreign key (tenant_id, parent_id) references app.product_categories (tenant_id, id)
);

create table app.products (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references app.tenants (id),
  category_id     uuid,
  sku             text not null,
  name_en         text not null,
  name_ar         text,
  description     text,
  unit_of_measure text not null default 'unit' check (unit_of_measure in ('unit', 'kg', 'g', 'l', 'ml', 'm')),
  is_weighed      boolean not null default false,
  is_perishable   boolean not null default false,
  vat_rate        numeric(5,2) not null default 14.00 check (vat_rate between 0 and 100),
  base_price      numeric(14,2) not null check (base_price >= 0),
  eta_item_code   text,
  eta_item_type   text check (eta_item_type in ('EGS', 'GS1')),
  eta_unit_type   text not null default 'EA',
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (tenant_id, id),
  unique (tenant_id, sku),
  foreign key (tenant_id, category_id) references app.product_categories (tenant_id, id),
  check (not is_weighed or unit_of_measure <> 'unit')
);
comment on column app.products.base_price is 'Tenant-wide price, net of VAT; a branch override in app.branch_prices wins.';

create table app.product_barcodes (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null,
  product_id    uuid not null,
  barcode       text not null,
  kind          text not null default 'gtin' check (kind in ('gtin', 'plu', 'variable_measure', 'internal')),
  pack_quantity numeric(14,3) not null default 1 check (pack_quantity > 0),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  check (kind <> 'gtin' or app.is_valid_gtin14(barcode)),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id) on delete cascade
);
comment on column app.product_barcodes.barcode is 'Text, never a number: GTINs are normalised to 14 digits and keep their leading zeros.';
create unique index product_barcodes_live_key on app.product_barcodes (tenant_id, barcode) where deleted_at is null;
create index product_barcodes_product_idx on app.product_barcodes (product_id);

create table app.branch_prices (
  tenant_id  uuid not null,
  branch_id  uuid not null,
  product_id uuid not null,
  price      numeric(14,2) not null check (price >= 0),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (branch_id, product_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id) on delete cascade,
  foreign key (tenant_id, updated_by) references app.staff (tenant_id, id)
);

create trigger product_categories_updated_at before update on app.product_categories
  for each row execute function app.set_updated_at();
create trigger products_updated_at before update on app.products
  for each row execute function app.set_updated_at();
create trigger product_barcodes_updated_at before update on app.product_barcodes
  for each row execute function app.set_updated_at();
create trigger branch_prices_updated_at before update on app.branch_prices
  for each row execute function app.set_updated_at();

-- One definition of "the price at this branch", shared by tills, backend and reports.
create function app.effective_price(p_branch_id uuid, p_product_id uuid) returns numeric
language sql
stable
as $$
  select coalesce(bp.price, p.base_price)
    from app.products p
    left join app.branch_prices bp
           on bp.product_id = p.id and bp.branch_id = p_branch_id and bp.deleted_at is null
   where p.id = p_product_id
$$;

alter table app.product_categories enable row level security;
alter table app.products enable row level security;
alter table app.product_barcodes enable row level security;
alter table app.branch_prices enable row level security;

create policy product_categories_read on app.product_categories for select
  using (tenant_id = (select app.current_tenant_id()));
create policy product_categories_write on app.product_categories for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy products_read on app.products for select
  using (tenant_id = (select app.current_tenant_id()));
create policy products_write on app.products for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy product_barcodes_read on app.product_barcodes for select
  using (tenant_id = (select app.current_tenant_id()));
create policy product_barcodes_write on app.product_barcodes for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy branch_prices_read on app.branch_prices for select
  using (tenant_id = (select app.current_tenant_id()));
create policy branch_prices_write on app.branch_prices for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

grant select, insert, update, delete on
  app.product_categories, app.products, app.product_barcodes, app.branch_prices
  to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
