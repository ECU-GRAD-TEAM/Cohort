-- Inventory: double-entry multi-echelon stock ledger (ADR-005, spec §5.3).
-- Stock is never edited in place: every movement is an append-only stock_moves row
-- between two location accounts, and stock_levels is derived from the ledger.

-- ---------------------------------------------------------------------------
-- Locations: physical (storage, shelf) and virtual accounts per branch
-- ---------------------------------------------------------------------------

create table app.stock_locations (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null,
  branch_id  uuid not null,
  kind       text not null check (kind in ('storage', 'shelf', 'transit', 'supplier', 'customer', 'scrap', 'adjustment')),
  name       text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);
create unique index stock_locations_virtual_key on app.stock_locations (branch_id, kind)
  where kind in ('transit', 'supplier', 'customer', 'scrap', 'adjustment');
create unique index stock_locations_default_key on app.stock_locations (branch_id, kind) where is_default;

create function app.create_branch_locations() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into app.stock_locations (tenant_id, branch_id, kind, name, is_default)
  select new.tenant_id, new.id, k.kind, k.name, true
    from (values ('storage', 'Main storage'), ('shelf', 'Sales floor'), ('transit', 'In transit'),
                 ('supplier', 'Suppliers'), ('customer', 'Customers'), ('scrap', 'Scrap'),
                 ('adjustment', 'Inventory adjustments')) as k (kind, name)
   where k.kind <> 'shelf' or new.kind = 'store';
  return new;
end
$$;

create trigger branches_create_locations after insert on app.branches
  for each row execute function app.create_branch_locations();

-- Branches that existed before this migration get their accounts too.
insert into app.stock_locations (tenant_id, branch_id, kind, name, is_default)
select b.tenant_id, b.id, k.kind, k.name, true
  from app.branches b
 cross join (values ('storage', 'Main storage'), ('shelf', 'Sales floor'), ('transit', 'In transit'),
                    ('supplier', 'Suppliers'), ('customer', 'Customers'), ('scrap', 'Scrap'),
                    ('adjustment', 'Inventory adjustments')) as k (kind, name)
 where (k.kind <> 'shelf' or b.kind = 'store')
   and not exists (select 1 from app.stock_locations l where l.branch_id = b.id and l.kind = k.kind);

-- The default location of a kind at a branch (virtual kinds have exactly one).
create function app.location_id(p_branch_id uuid, p_kind text) returns uuid
language sql
stable
as $$
  select l.id from app.stock_locations l
   where l.branch_id = p_branch_id and l.kind = p_kind and l.is_default
$$;

-- ---------------------------------------------------------------------------
-- Suppliers and batches
-- ---------------------------------------------------------------------------

create table app.suppliers (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references app.tenants (id),
  name                    text not null,
  tax_registration_number text,
  phone                   text,
  email                   text,
  lead_time_days          numeric(6,2) check (lead_time_days >= 0),
  lead_time_stddev_days   numeric(6,2) check (lead_time_stddev_days >= 0),
  is_active               boolean not null default true,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  deleted_at              timestamptz,
  unique (tenant_id, id)
);

create table app.supplier_products (
  tenant_id          uuid not null,
  supplier_id        uuid not null,
  product_id         uuid not null,
  supplier_sku       text,
  pack_size          numeric(14,3) not null default 1 check (pack_size > 0),
  min_order_quantity numeric(14,3) not null default 1 check (min_order_quantity > 0),
  unit_cost          numeric(14,4) check (unit_cost >= 0),
  updated_at         timestamptz not null default now(),
  primary key (supplier_id, product_id),
  foreign key (tenant_id, supplier_id) references app.suppliers (tenant_id, id),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id)
);

create table app.stock_batches (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  product_id      uuid not null,
  supplier_id     uuid,
  batch_code      text,
  production_date date,
  expiry_date     date,
  unit_cost       numeric(14,4) not null check (unit_cost >= 0),
  received_at     timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  unique (tenant_id, id),
  unique (id, product_id),
  check (expiry_date is null or production_date is null or expiry_date >= production_date),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id),
  foreign key (tenant_id, supplier_id) references app.suppliers (tenant_id, id)
);
comment on column app.stock_batches.unit_cost is 'Purchase cost of this batch: stock valuation uses it, never the retail price (REQ-INV-04).';
create index stock_batches_product_expiry_idx on app.stock_batches (product_id, expiry_date);

create function app.check_batch_expiry() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.expiry_date is null
     and exists (select 1 from app.products p where p.id = new.product_id and p.is_perishable) then
    raise exception 'perishable product % needs an expiry date on every batch', new.product_id;
  end if;
  return new;
end
$$;
create trigger stock_batches_expiry_check before insert or update on app.stock_batches
  for each row execute function app.check_batch_expiry();

-- ---------------------------------------------------------------------------
-- Transfers and purchase orders
-- ---------------------------------------------------------------------------

create table app.stock_transfers (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  from_branch_id      uuid not null,
  to_branch_id        uuid not null,
  status              text not null default 'draft' check (status in ('draft', 'dispatched', 'received', 'cancelled')),
  expected_arrival_at timestamptz not null,
  dispatched_at       timestamptz,
  received_at         timestamptz,
  created_by          uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (from_branch_id <> to_branch_id),
  unique (tenant_id, id),
  foreign key (tenant_id, from_branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, to_branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, created_by) references app.staff (tenant_id, id)
);

create table app.stock_transfer_lines (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null,
  transfer_id        uuid not null,
  product_id         uuid not null,
  requested_quantity numeric(14,3) not null check (requested_quantity > 0),
  unique (transfer_id, product_id),
  foreign key (tenant_id, transfer_id) references app.stock_transfers (tenant_id, id) on delete cascade,
  foreign key (tenant_id, product_id) references app.products (tenant_id, id)
);

create table app.purchase_orders (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  branch_id   uuid not null,
  supplier_id uuid not null,
  status      text not null default 'draft'
              check (status in ('draft', 'sent', 'partially_received', 'received', 'cancelled')),
  source      text not null default 'manual' check (source in ('manual', 'forecast')),
  expected_at timestamptz,
  notes       text,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, id),
  unique (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, supplier_id) references app.suppliers (tenant_id, id),
  foreign key (tenant_id, created_by) references app.staff (tenant_id, id)
);

create table app.purchase_order_lines (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null,
  branch_id         uuid not null,
  purchase_order_id uuid not null,
  product_id        uuid not null,
  quantity          numeric(14,3) not null check (quantity > 0),
  unit_cost         numeric(14,4) check (unit_cost >= 0),
  received_quantity numeric(14,3) not null default 0 check (received_quantity >= 0),
  unique (purchase_order_id, product_id),
  foreign key (purchase_order_id, branch_id) references app.purchase_orders (id, branch_id) on delete cascade,
  foreign key (tenant_id, product_id) references app.products (tenant_id, id)
);

-- ---------------------------------------------------------------------------
-- The ledger and its derived balances
-- ---------------------------------------------------------------------------

create table app.stock_moves (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  product_id       uuid not null,
  batch_id         uuid not null,
  from_location_id uuid not null,
  from_branch_id   uuid not null,
  to_location_id   uuid not null,
  to_branch_id     uuid not null,
  quantity         numeric(14,3) not null check (quantity > 0),
  move_type        text not null check (move_type in ('receipt', 'transfer_dispatch', 'transfer_receive', 'sale',
                                                      'return', 'scrap', 'adjustment_in', 'adjustment_out', 'replenish')),
  reference_type   text check (reference_type in ('sale', 'transfer', 'purchase_order', 'count', 'manual')),
  reference_id     uuid,
  device_id        uuid,
  actor_staff_id   uuid,
  occurred_at      timestamptz not null default now(),
  recorded_at      timestamptz not null default now(),
  check (from_location_id <> to_location_id),
  check ((reference_type is null) = (reference_id is null)),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id),
  foreign key (tenant_id, batch_id) references app.stock_batches (tenant_id, id),
  foreign key (batch_id, product_id) references app.stock_batches (id, product_id),
  foreign key (from_location_id, from_branch_id) references app.stock_locations (id, branch_id),
  foreign key (to_location_id, to_branch_id) references app.stock_locations (id, branch_id),
  foreign key (tenant_id, from_branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, to_branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, device_id) references app.pos_devices (tenant_id, id),
  foreign key (tenant_id, actor_staff_id) references app.staff (tenant_id, id)
);
comment on table app.stock_moves is 'Append-only double-entry ledger: each row moves a batch quantity from one location account to another. Corrections are compensating moves.';
create index stock_moves_from_idx on app.stock_moves (tenant_id, from_branch_id, occurred_at);
create index stock_moves_to_idx on app.stock_moves (tenant_id, to_branch_id, occurred_at);
create index stock_moves_reference_idx on app.stock_moves (reference_type, reference_id);

create table app.stock_levels (
  tenant_id   uuid not null,
  branch_id   uuid not null,
  location_id uuid not null,
  batch_id    uuid not null,
  product_id  uuid not null,
  quantity    numeric(14,3) not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (location_id, batch_id),
  foreign key (location_id, branch_id) references app.stock_locations (id, branch_id),
  foreign key (batch_id, product_id) references app.stock_batches (id, product_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);
comment on table app.stock_levels is 'Derived from stock_moves by trigger. May go negative: an oversell from offline tills stays visible (app.stock_discrepancies).';
create index stock_levels_branch_product_idx on app.stock_levels (tenant_id, branch_id, product_id);
create index stock_levels_fefo_idx on app.stock_levels (location_id, product_id) where quantity > 0;

-- Which location kinds each move type may connect, and the transit-expiry guard.
create function app.validate_stock_move() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from_kind   text;
  v_to_kind     text;
  v_same_branch boolean := new.from_branch_id = new.to_branch_id;
  v_transfer    record;
  v_expiry      date;
  v_cutoff      date;
  v_in_transit  numeric;
begin
  select l.kind into v_from_kind from app.stock_locations l where l.id = new.from_location_id;
  select l.kind into v_to_kind from app.stock_locations l where l.id = new.to_location_id;

  if not coalesce(case new.move_type
      when 'receipt'           then v_from_kind = 'supplier' and v_to_kind in ('storage', 'shelf') and v_same_branch
      when 'transfer_dispatch' then v_from_kind in ('storage', 'shelf') and v_to_kind = 'transit' and v_same_branch
      when 'transfer_receive'  then v_from_kind = 'transit' and v_to_kind in ('storage', 'shelf') and not v_same_branch
      when 'sale'              then v_from_kind in ('storage', 'shelf') and v_to_kind = 'customer' and v_same_branch
      when 'return'            then v_from_kind = 'customer' and v_to_kind in ('storage', 'shelf', 'scrap') and v_same_branch
      when 'scrap'             then v_from_kind in ('storage', 'shelf') and v_to_kind = 'scrap' and v_same_branch
      when 'adjustment_in'     then v_from_kind = 'adjustment' and v_to_kind in ('storage', 'shelf') and v_same_branch
      when 'adjustment_out'    then v_from_kind in ('storage', 'shelf') and v_to_kind = 'adjustment' and v_same_branch
      when 'replenish'         then v_from_kind in ('storage', 'shelf') and v_to_kind in ('storage', 'shelf') and v_same_branch
    end, false) then
    raise exception 'a % move cannot go from % to %', new.move_type, v_from_kind, v_to_kind;
  end if;

  if new.move_type in ('transfer_dispatch', 'transfer_receive') then
    -- Locking the transfer serialises its legs, so concurrent receipts cannot both pass the
    -- in-transit check below.
    select t.* into v_transfer
      from app.stock_transfers t
     where t.id = new.reference_id and new.reference_type = 'transfer' and t.tenant_id = new.tenant_id
       for update;
    if not found then
      raise exception '% moves must reference their transfer', new.move_type;
    end if;
    if v_transfer.from_branch_id <> new.from_branch_id
       or (new.move_type = 'transfer_receive' and v_transfer.to_branch_id <> new.to_branch_id) then
      raise exception 'move does not match the branches of transfer %', v_transfer.id;
    end if;

    -- A receipt can only bring in what this transfer dispatched and has not yet delivered,
    -- batch by batch, so in transit = dispatched - received never goes negative (REQ-INVN-01).
    if new.move_type = 'transfer_receive' then
      select coalesce(sum(case m.move_type when 'transfer_dispatch' then m.quantity else -m.quantity end), 0)
        into v_in_transit
        from app.stock_moves m
       where m.reference_type = 'transfer' and m.reference_id = v_transfer.id
         and m.batch_id = new.batch_id
         and m.move_type in ('transfer_dispatch', 'transfer_receive');
      if new.quantity > v_in_transit then
        raise exception 'transfer % has only % of batch % in transit, not %',
          v_transfer.id, v_in_transit, new.batch_id, new.quantity;
      end if;
    end if;

    if new.move_type = 'transfer_dispatch' then
      select b.expiry_date into v_expiry from app.stock_batches b where b.id = new.batch_id;
      select ((v_transfer.expected_arrival_at + interval '48 hours') at time zone br.timezone)::date
        into v_cutoff
        from app.branches br
       where br.id = v_transfer.to_branch_id;
      if v_expiry is not null and v_expiry <= v_cutoff then
        raise exception 'batch % expires on %, within 48 hours of arrival', new.batch_id, v_expiry;
      end if;
    end if;
  end if;

  return new;
end
$$;

create function app.apply_stock_move() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into app.stock_levels (tenant_id, branch_id, location_id, batch_id, product_id, quantity)
  values (new.tenant_id, new.from_branch_id, new.from_location_id, new.batch_id, new.product_id, -new.quantity),
         (new.tenant_id, new.to_branch_id, new.to_location_id, new.batch_id, new.product_id, new.quantity)
  on conflict (location_id, batch_id) do update
     set quantity = app.stock_levels.quantity + excluded.quantity,
         updated_at = now();
  return null;
end
$$;

create trigger stock_moves_validate before insert on app.stock_moves
  for each row execute function app.validate_stock_move();
create trigger stock_moves_apply after insert on app.stock_moves
  for each row execute function app.apply_stock_move();
create trigger stock_moves_append_only before update or delete on app.stock_moves
  for each row execute function app.prevent_mutation();

-- FEFO: earliest expiry first, never expired stock; returns less than asked when short.
create function app.fefo_pick(
  p_location_id uuid,
  p_product_id  uuid,
  p_quantity    numeric,
  p_as_of       date default current_date
) returns table (batch_id uuid, take_quantity numeric, expiry_date date)
language sql
stable
as $$
  with available as (
    select l.batch_id, l.quantity, b.expiry_date, b.received_at,
           sum(l.quantity) over (order by b.expiry_date asc nulls last, b.received_at, l.batch_id) as running_total
      from app.stock_levels l
      join app.stock_batches b on b.id = l.batch_id
     where l.location_id = p_location_id
       and l.product_id = p_product_id
       and l.quantity > 0
       and (b.expiry_date is null or b.expiry_date >= p_as_of)
  )
  select a.batch_id, least(a.quantity, p_quantity - (a.running_total - a.quantity)), a.expiry_date
    from available a
   where a.running_total - a.quantity < p_quantity
   order by a.expiry_date asc nulls last, a.received_at, a.batch_id
$$;

create view app.stock_discrepancies with (security_invoker = true) as
  select l.tenant_id, l.branch_id, l.location_id, loc.kind as location_kind,
         l.product_id, l.batch_id, l.quantity, l.updated_at
    from app.stock_levels l
    join app.stock_locations loc on loc.id = l.location_id
   where loc.kind in ('storage', 'shelf') and l.quantity < 0;

create trigger suppliers_updated_at before update on app.suppliers
  for each row execute function app.set_updated_at();
create trigger supplier_products_updated_at before update on app.supplier_products
  for each row execute function app.set_updated_at();
create trigger stock_transfers_updated_at before update on app.stock_transfers
  for each row execute function app.set_updated_at();
create trigger purchase_orders_updated_at before update on app.purchase_orders
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table app.stock_locations enable row level security;
alter table app.suppliers enable row level security;
alter table app.supplier_products enable row level security;
alter table app.stock_batches enable row level security;
alter table app.stock_transfers enable row level security;
alter table app.stock_transfer_lines enable row level security;
alter table app.purchase_orders enable row level security;
alter table app.purchase_order_lines enable row level security;
alter table app.stock_moves enable row level security;
alter table app.stock_levels enable row level security;

-- Any internal context of the tenant can address another branch's accounts (transfers).
create policy stock_locations_read on app.stock_locations for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy stock_locations_write on app.stock_locations for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

create policy suppliers_internal on app.suppliers for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy supplier_products_internal on app.supplier_products for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy stock_batches_internal on app.stock_batches for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy stock_transfers_either_branch on app.stock_transfers for all
  using (tenant_id = (select app.current_tenant_id())
         and (from_branch_id = any ((select app.accessible_branch_ids())::uuid[])
              or to_branch_id = any ((select app.accessible_branch_ids())::uuid[])))
  with check (tenant_id = (select app.current_tenant_id())
              and (from_branch_id = any ((select app.accessible_branch_ids())::uuid[])
                   or to_branch_id = any ((select app.accessible_branch_ids())::uuid[])));
create policy stock_transfer_lines_via_transfer on app.stock_transfer_lines for all
  using (tenant_id = (select app.current_tenant_id())
         and exists (select 1 from app.stock_transfers t where t.id = transfer_id))
  with check (tenant_id = (select app.current_tenant_id())
              and exists (select 1 from app.stock_transfers t where t.id = transfer_id));

create policy purchase_orders_branch on app.purchase_orders for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));
create policy purchase_order_lines_branch on app.purchase_order_lines for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

create policy stock_moves_either_branch on app.stock_moves for select
  using (tenant_id = (select app.current_tenant_id())
         and (from_branch_id = any ((select app.accessible_branch_ids())::uuid[])
              or to_branch_id = any ((select app.accessible_branch_ids())::uuid[])));
create policy stock_moves_insert on app.stock_moves for insert
  with check (tenant_id = (select app.current_tenant_id())
              and (from_branch_id = any ((select app.accessible_branch_ids())::uuid[])
                   or to_branch_id = any ((select app.accessible_branch_ids())::uuid[])));

create policy stock_levels_branch on app.stock_levels for select
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select, insert, update, delete on
  app.stock_locations, app.suppliers, app.supplier_products, app.stock_batches,
  app.stock_transfers, app.stock_transfer_lines, app.purchase_orders, app.purchase_order_lines
  to market_backend;
grant select, insert on app.stock_moves to market_backend;
grant select on app.stock_levels, app.stock_discrepancies to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
