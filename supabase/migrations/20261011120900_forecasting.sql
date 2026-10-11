-- Demand forecasting outputs (optional stage 4, spec §5.9): nightly LightGBM Tweedie
-- forecasts per branch and product, and the dynamic reorder points derived from them.

create table app.demand_forecasts (
  id             bigint generated always as identity primary key,
  tenant_id      uuid not null,
  branch_id      uuid not null,
  product_id     uuid not null,
  model_version  text not null,
  generated_at   timestamptz not null,
  forecast_date  date not null,
  point_forecast numeric(14,3) not null check (point_forecast >= 0),
  q10            numeric(14,3) check (q10 >= 0),
  q50            numeric(14,3) check (q50 >= 0),
  q90            numeric(14,3) check (q90 >= 0),
  std_dev        numeric(14,3) check (std_dev >= 0),
  unique (branch_id, product_id, model_version, generated_at, forecast_date),
  check (q10 is null or q50 is null or q10 <= q50),
  check (q50 is null or q90 is null or q50 <= q90),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id)
);
create index demand_forecasts_lookup_idx on app.demand_forecasts (tenant_id, branch_id, product_id, forecast_date);

create table app.reorder_points (
  tenant_id       uuid not null,
  branch_id       uuid not null,
  product_id      uuid not null,
  service_level_z numeric(5,3) not null default 1.645 check (service_level_z > 0),
  lead_time_days  numeric(6,2) not null check (lead_time_days >= 0),
  safety_stock    numeric(14,3) not null check (safety_stock >= 0),
  reorder_point   numeric(14,3) not null check (reorder_point >= 0),
  model_version   text,
  computed_at     timestamptz not null default now(),
  primary key (branch_id, product_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, product_id) references app.products (tenant_id, id)
);
comment on table app.reorder_points is 'SS = Z·sqrt(L·σD² + μD²·σL²), ROP = μD·L + SS, recomputed nightly per branch and product.';

alter table app.demand_forecasts enable row level security;
alter table app.reorder_points enable row level security;

create policy demand_forecasts_branch on app.demand_forecasts for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));
create policy reorder_points_branch on app.reorder_points for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

grant select, insert, delete on app.demand_forecasts to market_backend;
grant select, insert, update, delete on app.reorder_points to market_backend;
grant usage on all sequences in schema app to market_backend;
