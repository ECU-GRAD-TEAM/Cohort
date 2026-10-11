-- POS shifts, the offline sync inbox and sales (spec §5.5, T2 paper, proposal §3.4).
-- Tills generate the UUIDs of events and sales, so re-uploads are idempotent:
-- insert … on conflict (id) do nothing.

create table app.cashier_shifts (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null,
  branch_id     uuid not null,
  device_id     uuid not null,
  staff_id      uuid not null,
  opened_at     timestamptz not null default now(),
  closed_at     timestamptz,
  opening_float numeric(14,2) not null default 0 check (opening_float >= 0),
  counted_cash  numeric(14,2) check (counted_cash >= 0),
  expected_cash numeric(14,2),
  status        text not null default 'open' check (status in ('open', 'closed')),
  unique (tenant_id, id),
  unique (id, branch_id),
  check ((status = 'closed') = (closed_at is not null)),
  check (closed_at is null or closed_at >= opened_at),
  foreign key (device_id, branch_id) references app.pos_devices (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, staff_id) references app.staff (tenant_id, id)
);

create table app.sync_events (
  id          uuid primary key,
  tenant_id   uuid not null,
  branch_id   uuid not null,
  device_id   uuid not null,
  event_type  text not null check (event_type ~ '^[A-Z][A-Z_]*$'),
  sequence_no bigint not null check (sequence_no >= 0),
  payload     jsonb not null check (jsonb_typeof(payload) = 'object'),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  status      text not null default 'received' check (status in ('received', 'applied', 'rejected', 'conflict')),
  error       text,
  applied_at  timestamptz,
  unique (device_id, sequence_no),
  foreign key (device_id, branch_id) references app.pos_devices (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);
comment on table app.sync_events is 'Offline inbox. id is the event UUID generated on the till, so a re-sent event is stored once.';
create index sync_events_pending_idx on app.sync_events (tenant_id, received_at) where status <> 'applied';

create table app.sales (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  branch_id        uuid not null,
  device_id        uuid,
  shift_id         uuid,
  staff_id         uuid,
  customer_id      uuid references app.customers (id),
  sale_type        text not null default 'sale' check (sale_type in ('sale', 'return')),
  original_sale_id uuid,
  status           text not null default 'completed' check (status in ('completed', 'voided')),
  receipt_number   text,
  subtotal         numeric(14,2) not null check (subtotal >= 0),
  discount_total   numeric(14,2) not null default 0 check (discount_total >= 0),
  tax_total        numeric(14,2) not null default 0 check (tax_total >= 0),
  grand_total      numeric(14,2) not null check (grand_total >= 0),
  currency         char(3) not null default 'EGP',
  is_offline       boolean not null default false,
  sync_event_id    uuid references app.sync_events (id),
  occurred_at      timestamptz not null,
  created_at       timestamptz not null default now(),
  voided_at        timestamptz,
  voided_by        uuid,
  void_approved_by uuid,
  void_reason      text,
  unique (tenant_id, id),
  unique (id, branch_id),
  check (grand_total = subtotal - discount_total + tax_total),
  check (sale_type = 'return' or original_sale_id is null),
  check ((status = 'voided') = (voided_at is not null)),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (device_id, branch_id) references app.pos_devices (id, branch_id),
  foreign key (shift_id, branch_id) references app.cashier_shifts (id, branch_id),
  foreign key (tenant_id, staff_id) references app.staff (tenant_id, id),
  foreign key (tenant_id, original_sale_id) references app.sales (tenant_id, id),
  foreign key (tenant_id, voided_by) references app.staff (tenant_id, id),
  foreign key (tenant_id, void_approved_by) references app.staff (tenant_id, id)
);
comment on table app.sales is 'Sales and returns. id is the till''s UUID; amounts are net of VAT like ETA receipts: grand_total = subtotal - discount_total + tax_total.';
create index sales_branch_time_idx on app.sales (tenant_id, branch_id, occurred_at);
create index sales_customer_idx on app.sales (customer_id) where customer_id is not null;
create index sales_shift_idx on app.sales (shift_id) where shift_id is not null;

create table app.sale_lines (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null,
  branch_id            uuid not null,
  sale_id              uuid not null,
  line_no              int not null check (line_no > 0),
  product_id           uuid not null,
  barcode              text,
  quantity             numeric(14,3) not null check (quantity > 0),
  unit_price           numeric(14,2) not null check (unit_price >= 0),
  discount_amount      numeric(14,2) not null default 0 check (discount_amount >= 0),
  vat_rate             numeric(5,2) not null check (vat_rate between 0 and 100),
  tax_amount           numeric(14,2) not null default 0 check (tax_amount >= 0),
  line_total           numeric(14,2) not null check (line_total >= 0),
  price_overridden     boolean not null default false,
  override_approved_by uuid,
  voided_at            timestamptz,
  voided_by            uuid,
  void_approved_by     uuid,
  unique (sale_id, line_no),
  unique (id, sale_id),
  foreign key (sale_id, branch_id) references app.sales (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id),
  foreign key (tenant_id, override_approved_by) references app.staff (tenant_id, id),
  foreign key (tenant_id, voided_by) references app.staff (tenant_id, id),
  foreign key (tenant_id, void_approved_by) references app.staff (tenant_id, id)
);
create index sale_lines_product_idx on app.sale_lines (tenant_id, product_id);

create table app.sale_payments (
  id                     uuid primary key default gen_random_uuid(),
  tenant_id              uuid not null,
  branch_id              uuid not null,
  sale_id                uuid not null,
  method                 text not null check (method in ('cash', 'card', 'wallet', 'instapay', 'face_pay',
                                                         'loyalty_points', 'voucher')),
  provider               text check (provider in ('geidea', 'paymob', 'fawry', 'cib', 'nbe', 'kashier',
                                                  'instapay', 'other')),
  amount                 numeric(14,2) not null check (amount > 0),
  tendered               numeric(14,2),
  change_given           numeric(14,2) not null default 0 check (change_given >= 0),
  status                 text not null default 'captured'
                         check (status in ('authorized', 'captured', 'failed', 'refunded', 'voided')),
  provider_reference     text,
  card_last4             char(4) check (card_last4 ~ '^[0-9]{4}$'),
  auth_code              text,
  face_pay_enrollment_id uuid,
  created_at             timestamptz not null default now(),
  check (method <> 'cash' or (tendered is not null and tendered >= amount and change_given = tendered - amount)),
  check (method = 'cash' or (tendered is null and change_given = 0)),
  check (method = 'face_pay' or face_pay_enrollment_id is null),
  foreign key (sale_id, branch_id) references app.sales (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);
create index sale_payments_sale_idx on app.sale_payments (sale_id);

create table app.sale_discounts (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null,
  branch_id    uuid not null,
  sale_id      uuid not null,
  sale_line_id uuid,
  promotion_id uuid,
  coupon_id    uuid,
  amount       numeric(14,2) not null check (amount > 0),
  description  text,
  check (promotion_id is not null or coupon_id is not null),
  foreign key (sale_id, branch_id) references app.sales (id, branch_id),
  foreign key (sale_line_id, sale_id) references app.sale_lines (id, sale_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, promotion_id) references app.promotions (tenant_id, id),
  foreign key (tenant_id, coupon_id) references app.coupons (tenant_id, id)
);
create index sale_discounts_sale_idx on app.sale_discounts (sale_id);
create index sale_discounts_coupon_idx on app.sale_discounts (coupon_id) where coupon_id is not null;

-- Financial records are permanent; lines and discounts never change after posting.
create trigger cashier_shifts_no_delete before delete on app.cashier_shifts
  for each row execute function app.prevent_delete();
create trigger sync_events_no_delete before delete on app.sync_events
  for each row execute function app.prevent_delete();
create trigger sales_no_delete before delete on app.sales
  for each row execute function app.prevent_delete();
create trigger sale_payments_no_delete before delete on app.sale_payments
  for each row execute function app.prevent_delete();
create trigger sale_lines_append_only before update or delete on app.sale_lines
  for each row execute function app.prevent_mutation();
create trigger sale_discounts_append_only before update or delete on app.sale_discounts
  for each row execute function app.prevent_mutation();

alter table app.cashier_shifts enable row level security;
alter table app.sync_events enable row level security;
alter table app.sales enable row level security;
alter table app.sale_lines enable row level security;
alter table app.sale_payments enable row level security;
alter table app.sale_discounts enable row level security;

create policy cashier_shifts_branch on app.cashier_shifts for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

create policy sync_events_branch on app.sync_events for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

create policy sales_branch on app.sales for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));
create policy sales_customer_read on app.sales for select
  using (customer_id = (select app.current_customer_id())
         and ((select app.current_tenant_id()) is null or tenant_id = (select app.current_tenant_id())));

create policy sale_lines_branch on app.sale_lines for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));
create policy sale_lines_customer_read on app.sale_lines for select
  using ((select app.current_customer_id()) is not null
         and exists (select 1 from app.sales s
                      where s.id = sale_id and s.customer_id = (select app.current_customer_id())));

create policy sale_payments_branch on app.sale_payments for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));
create policy sale_payments_customer_read on app.sale_payments for select
  using ((select app.current_customer_id()) is not null
         and exists (select 1 from app.sales s
                      where s.id = sale_id and s.customer_id = (select app.current_customer_id())));

create policy sale_discounts_branch on app.sale_discounts for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));
create policy sale_discounts_customer_read on app.sale_discounts for select
  using ((select app.current_customer_id()) is not null
         and exists (select 1 from app.sales s
                      where s.id = sale_id and s.customer_id = (select app.current_customer_id())));

grant select, insert on app.cashier_shifts, app.sync_events, app.sales, app.sale_lines,
                        app.sale_payments, app.sale_discounts to market_backend;
grant update (closed_at, counted_cash, expected_cash, status) on app.cashier_shifts to market_backend;
grant update (status, error, applied_at) on app.sync_events to market_backend;
grant update (status, voided_at, voided_by, void_approved_by, void_reason, sync_event_id) on app.sales to market_backend;
grant update (status, provider_reference, auth_code) on app.sale_payments to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
