-- Analytics semantic layer (spec §5.10, Dual-RAG §2.8): pre-approved metrics for the
-- NL-to-SQL pipeline. The backend runs LLM-generated SQL as market_ai_reader, which can
-- read these views and nothing else. The views belong to market_analytics_owner, which is
-- not the owner of the base tables, so row level security still filters every row by the
-- caller's tenant and branch reach.

grant select on app.sales, app.sale_lines, app.branches, app.products,
                app.stock_levels, app.stock_locations, app.stock_batches
  to market_analytics_owner;
-- Policies on app.branches look into loyalty_accounts (shopper path); Postgres checks that
-- access as the view owner even when the shopper path does not apply.
grant select on app.loyalty_accounts to market_analytics_owner;
grant usage on schema analytics to market_analytics_owner;
grant create on schema analytics to market_analytics_owner;

create view analytics.sales_daily as
  select s.tenant_id,
         s.branch_id,
         b.name                                                                     as branch_name,
         (s.occurred_at at time zone b.timezone)::date                              as sales_date,
         count(*) filter (where s.sale_type = 'sale')                               as transactions,
         coalesce(sum(s.subtotal) filter (where s.sale_type = 'sale'), 0)           as gross_sales,
         coalesce(sum(s.discount_total) filter (where s.sale_type = 'sale'), 0)     as discounts,
         coalesce(sum(s.subtotal - s.discount_total) filter (where s.sale_type = 'return'), 0) as returns,
         coalesce(sum(s.subtotal - s.discount_total) filter (where s.sale_type = 'sale'), 0)
           - coalesce(sum(s.subtotal - s.discount_total) filter (where s.sale_type = 'return'), 0) as net_revenue,
         coalesce(sum(s.tax_total) filter (where s.sale_type = 'sale'), 0)
           - coalesce(sum(s.tax_total) filter (where s.sale_type = 'return'), 0)    as tax_collected,
         round(avg(s.grand_total) filter (where s.sale_type = 'sale'), 2)           as average_basket
    from app.sales s
    join app.branches b on b.id = s.branch_id
   where s.status = 'completed'
   group by s.tenant_id, s.branch_id, b.name, (s.occurred_at at time zone b.timezone)::date;
comment on view analytics.sales_daily is
  'Per branch and local (branch time zone) day. Amounts exclude VAT: net_revenue = gross_sales - discounts - returns. Voided sales are excluded.';

create view analytics.product_sales_daily as
  select l.tenant_id,
         l.branch_id,
         (s.occurred_at at time zone b.timezone)::date as sales_date,
         l.product_id,
         p.sku,
         p.name_en                                     as product_name,
         sum(case when s.sale_type = 'sale' then l.quantity else -l.quantity end) as quantity,
         sum(case when s.sale_type = 'sale' then l.line_total - l.tax_amount
                  else -(l.line_total - l.tax_amount) end)                         as net_revenue
    from app.sale_lines l
    join app.sales s on s.id = l.sale_id
    join app.branches b on b.id = l.branch_id
    join app.products p on p.id = l.product_id
   where s.status = 'completed' and l.voided_at is null
   group by l.tenant_id, l.branch_id, (s.occurred_at at time zone b.timezone)::date, l.product_id, p.sku, p.name_en;
comment on view analytics.product_sales_daily is 'Units and revenue (net of discounts and VAT) per product, branch and local day; returns count negative.';

create view analytics.stock_on_hand as
  select l.tenant_id,
         l.branch_id,
         b.name                         as branch_name,
         l.product_id,
         p.sku,
         p.name_en                      as product_name,
         sum(l.quantity)                as quantity,
         sum(l.quantity * bt.unit_cost) as stock_value
    from app.stock_levels l
    join app.stock_locations loc on loc.id = l.location_id and loc.kind in ('storage', 'shelf')
    join app.stock_batches bt on bt.id = l.batch_id
    join app.branches b on b.id = l.branch_id
    join app.products p on p.id = l.product_id
   group by l.tenant_id, l.branch_id, b.name, l.product_id, p.sku, p.name_en;
comment on view analytics.stock_on_hand is 'Physical stock per branch and product, valued at each batch''s purchase cost.';

alter view analytics.sales_daily owner to market_analytics_owner;
alter view analytics.product_sales_daily owner to market_analytics_owner;
alter view analytics.stock_on_hand owner to market_analytics_owner;

revoke create on schema analytics from market_analytics_owner;
grant select on analytics.sales_daily, analytics.product_sales_daily, analytics.stock_on_hand
  to market_ai_reader, market_backend;
grant usage on schema analytics to market_backend;

-- RLS policies on the base tables call these read-only context functions, and Postgres
-- checks EXECUTE (and, for inlined SQL functions, schema USAGE) as the querying role.
-- market_ai_reader still has no privilege on any app table, and set_context is
-- deliberately not granted, so LLM-generated SQL can never switch tenant or widen its reach.
grant usage on schema app to market_ai_reader;
grant execute on function
  app.current_tenant_id(), app.current_branch_id(), app.current_staff_id(), app.current_device_id(),
  app.current_customer_id(), app.current_system_actor(), app.is_internal(), app.accessible_branch_ids()
  to market_ai_reader;
