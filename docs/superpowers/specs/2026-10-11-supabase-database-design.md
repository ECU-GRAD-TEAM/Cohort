# Market SaaS Database Design (Supabase / PostgreSQL)

Date: 2026-10-11
Status: Approved for implementation ("Implement", 2026-10-11)
Sources: the team's Google Drive "GradProj Stuff" folder: the Retail SaaS Platform proposal
(2026–2027) and research topics T1–T11 (multi-tenancy ADR-004, offline POS, inventory ADR-005,
pricing ADR-003, forecasting, ETA payments/tax, access control and audit, RAG assistant and
isolation addendum, Face Pay, UX research).

## 1. Intent

One cloud database for the whole platform. It serves a single-shop market and a 100-branch
hypermarket chain on the same tables. Row-level security keeps each market's data isolated
inside the database engine (ADR-004). Tills keep selling offline on local SQLite and sync to
this database later. The database is the shared source of truth: stock, sales, receipts, audit
trail, analytics and assistant data.

Two apps sit in front of it, both through the team's own backend:

- **Web app**: the business side. Owners, regional managers, branch managers, cashiers and
  stock clerks. It includes the browser POS till (PWA).
- **Mobile app**: the shopper. Account, receipts, loyalty, linked card, optional Face Pay.

## 2. Decisions

Decided by the team lead in conversation:

1. Hierarchy is **tenant (business owner) → region (regional manager) → branch**.
2. A **separate backend** (not Supabase's auto-generated API) sits between both apps and the
   database. The apps never query Supabase directly.
3. The AI assistant side needs **a JSON column** for the assistant's output.
4. Scope: all five proposal stages, as played back on 2026-10-11.

Defaults taken by the builder (open to change):

- Users sign in with **Supabase Auth**; the backend verifies the token. Staff and customer
  rows keep `auth_user_id` with no hard FK to `auth.users`, so the schema also runs on plain
  Postgres.
- Products belong to the **tenant**. Price and stock are per branch. This replaces the
  papers' `products.branch_id`.
- Warehouses are branches with `kind = 'warehouse'`. A single-shop tenant can skip regions.
  A person may manage several regions.
- One **shopper account works across all markets** (global `customers`). Each market's
  loyalty membership is tenant-scoped.
- Staff profiles are tenant-scoped. A person working for two markets has two staff rows. Till
  cashiers may have no Supabase Auth account; they sign in with a PIN on an authenticated
  device.
- Business rules that need many rows (sale projection from sync events, the promotion
  solver, forecasting, ETA submission) live in the backend or on the edge. The database
  enforces isolation, integrity, ledgers and chains, and offers small query helpers (FEFO
  pick, hybrid search, chain verification, exception detection).
- Embedding size **1024** for text, matching common multilingual models such as bge-m3,
  Voyage and Cohere, or OpenAI v3 with `dimensions=1024`. Face embeddings are **128-D**
  (FaceNet).

## 3. Architecture

### 3.1 Schemas

| Schema | Holds | Who can touch it |
|---|---|---|
| `app` | All business tables, helpers, RLS policies | `market_backend` |
| `analytics` | Read-only "semantic layer" views for NL-to-SQL | `market_ai_reader` (select), views owned by `market_analytics_owner` |
| `biometric` | Face templates (embeddings) only | `market_biometric` only |
| `extensions` | `vector` (pgvector), plus `pgtap` in tests | Supabase convention |

None of these schemas is exposed through Supabase's Data API, and Supabase's built-in
`anon` and `authenticated` roles have no privileges on them.

### 3.2 Database roles

Every role is created `NOLOGIN` by migrations. Passwords are set by hand and never committed.

- `market_backend`: the backend's login. Not the table owner and no `BYPASSRLS`, so every
  query is subject to RLS. It is a member of `market_ai_reader`.
- `market_ai_reader`: the backend switches to it (`SET LOCAL ROLE`) to run LLM-generated
  SQL. It can only `SELECT` from `analytics` views.
- `market_analytics_owner`: owns the `analytics` views and has `SELECT` on the base tables
  they read. It is not the table owner, so RLS still applies through the views.
- `market_biometric`: login for the separate Face Pay matching service. It is the only role
  with access to `biometric`, and it is **not** granted to `market_backend`, which keeps
  biometric templates apart from identity (PDPL Law 151/2020).

The `postgres` login and `service_role` bypass RLS and must never be used by the apps.

### 3.3 Request context (ADR-004 on Supabase)

The backend opens a transaction per request and calls `app.set_context(...)` first. This is
the parameterised form of ADR-004's `SET LOCAL app.current_tenant_id`. All values are
transaction-local, so they work with Supavisor transaction pooling and disappear at
`COMMIT`/`ROLLBACK`.

```
select app.set_context(
  p_tenant_id    => $1,  -- uuid
  p_staff_id     => $2,  -- uuid, staff member (web app or till PIN login)
  p_branch_id    => $3,  -- uuid, optional narrowing ("active branch")
  p_device_id    => $4,  -- uuid, authenticated POS device
  p_customer_id  => $5,  -- uuid, shopper (mobile app)
  p_system_actor => $6   -- text, background job name, e.g. 'eta_worker'
);
```

GUCs set: `app.current_tenant_id`, `app.current_branch_id`, `app.current_staff_id`,
`app.current_device_id`, `app.current_customer_id`, `app.current_system_actor`. Every call
sets all six (unused ones become empty), so stale values cannot linger.

`set_context` validates before setting. It raises SQLSTATE `42501` when the staff member is
not an active member of the tenant, the device is not an active device of the tenant, the
branch is not in the tenant, the branch differs from the device's branch, or the customer
does not exist. With a device and no branch, the branch is set to the device's branch.

Reader functions (`stable`): `app.current_tenant_id()`, `app.current_branch_id()`,
`app.current_staff_id()`, `app.current_device_id()`, `app.current_customer_id()`,
`app.current_system_actor()`, `app.is_internal()`. The last is true when a tenant is set and
there is a staff member, a device or a system actor.

Unset context returns NULL, so policies match **zero rows** (fail closed). A malformed value
raises a cast error.

Lookup functions callable before any context exists (`security definer`, backend only):

- `app.staff_memberships(p_auth_user_id uuid) returns table(staff_id uuid, tenant_id uuid, tenant_name text)`
- `app.customer_id_for_auth_user(p_auth_user_id uuid) returns uuid`
- `app.authenticate_device(p_device_id uuid, p_api_key text) returns table(tenant_id uuid, branch_id uuid)`.
  It compares `sha256(api_key)` with the stored hash and only matches active devices.
- `app.register_customer(p_full_name text, p_phone text, p_email text default null, p_auth_user_id uuid default null, p_language text default 'ar') returns uuid`.
  Finds the customer by `auth_user_id` or phone, or creates one. It is idempotent.

### 3.4 Branch reach (spatial RBAC)

`app.accessible_branch_ids() returns uuid[]` (`security definer`, `stable`):

- System actor: every branch of the tenant.
- Staff member: the union of their active assignments. A `tenant` scope gives every branch, a
  `region` scope gives the branches whose `region_id` matches, and a `branch` scope gives that
  branch.
- Device only: the device's branch.
- Staff member at a device: the staff set ∩ {device's branch}, meaning only the till's own
  branch.
- With `app.current_branch_id` set, the result is ∩ {that branch}.
- Anything else, including customers: the empty array.

Because the database derives reach from assignments, a backend bug that sends the wrong
branch cannot widen access.

`app.has_permission(p_permission text, p_branch_id uuid default null) returns boolean`. It is
true when the current staff member holds an active assignment whose role grants the
permission and whose scope covers `p_branch_id`. A NULL branch requires `tenant` scope. At a
device, `p_branch_id` must also be the device's branch. The backend uses it for role checks;
RLS only enforces tenant and branch boundaries.

System roles, seeded by migration and shared by all tenants:

| Role | Permissions |
|---|---|
| owner | all |
| regional_manager | all except BRANCH_MANAGE, CATALOG_MANAGE, SALE_CREATE, DISCOUNT_MANUAL |
| branch_manager | SALE_CREATE, LINE_VOID, SALE_VOID, REFUND_LINKED, REFUND_UNLINKED, PRICE_OVERRIDE, DISCOUNT_MANUAL, DRAWER_OPEN_MANUAL, SHIFT_MANAGE, STOCK_VIEW, STOCK_RECEIVE, STOCK_TRANSFER, STOCK_ADJUST, REPORT_VIEW, FRAUD_REVIEW, AI_ANALYTICS, LOYALTY_MANAGE |
| cashier | SALE_CREATE, REFUND_LINKED, STOCK_VIEW |
| stock_clerk | STOCK_VIEW, STOCK_RECEIVE, STOCK_TRANSFER, STOCK_ADJUST |

Full permission list: SALE_CREATE, LINE_VOID, SALE_VOID, REFUND_LINKED, REFUND_UNLINKED,
PRICE_OVERRIDE, DISCOUNT_MANUAL, DRAWER_OPEN_MANUAL, SHIFT_MANAGE, STOCK_VIEW, STOCK_RECEIVE,
STOCK_TRANSFER, STOCK_ADJUST, CATALOG_MANAGE, PRICE_MANAGE, PROMOTION_MANAGE, LOYALTY_MANAGE,
STAFF_MANAGE, BRANCH_MANAGE, DEVICE_MANAGE, REPORT_VIEW, AUDIT_VIEW, FRAUD_REVIEW,
AI_ANALYTICS. Tenants may add their own roles.

### 3.5 RLS patterns

Policies wrap context calls in `(select …)` so Postgres evaluates them once per statement.

| Pattern | USING / WITH CHECK |
|---|---|
| **TP** tenant, any context (storefront-readable) | `tenant_id = (select app.current_tenant_id())` |
| **TI** tenant, internal only | TP `and (select app.is_internal())` |
| **BI** branch-scoped internal | TP `and branch_id = any ((select app.accessible_branch_ids())::uuid[])` |
| **CO** customer-owned | `customer_id = (select app.current_customer_id())` |

Reference tables that shoppers may read (products, prices, promotions) use TP for `SELECT`
and TI for writes. Children of customer-visible parents (sale lines, payments, receipts) add
a CO path through `exists (…parent…)`.

Every table in `app` and `biometric` has RLS enabled. A test enforces this.

## 4. Integrity conventions

- Primary keys: `uuid default gen_random_uuid()`. Tills supply their own UUIDs for offline
  rows (sales, sync events, shifts, stock moves). That makes ingestion idempotent:
  `insert … on conflict (id) do nothing`.
- **Composite tenant FKs.** A child references `(tenant_id, parent_id) → parent(tenant_id,
  id)`, so a row can never point at another tenant's data. Branch-bound children use
  `(x_id, branch_id)` pairs in the same way.
- Money is `numeric(14,2)` EGP. Quantities are `numeric(14,3)` (scale weights such as
  `01.235` kg). `vat_rate` is `numeric(5,2)`, default `14.00`.
- Bilingual names: `name_en` (required) and `name_ar`.
- Barcodes are `text`, so leading zeros are kept. A `gtin` barcode must be a 14-digit GTIN
  with a valid GS1 mod-10 check digit: `app.is_valid_gtin14(text)`.
- Enumerations are `text` with CHECK constraints.
- Mutable reference tables have `updated_at` (set by trigger) and `deleted_at` (soft-delete
  tombstones for till delta sync).
- Append-only tables (`stock_moves`, `audit_log`, `loyalty_ledger`) have a trigger that
  rejects UPDATE and DELETE, and no UPDATE/DELETE grants. Financial tables (`sales`,
  `eta_receipts`, `sync_events`) reject DELETE and only allow column-level updates of
  status fields.

## 5. Modules and tables

### 5.1 Core tenancy and devices

- `tenants`: name, legal_name, tax_registration_number (digits), eta_activity_code,
  default_language (`ar`|`en`), currency `EGP`, status (`active`|`suspended`|`closed`).
- `regions`: tenant_id, name, code; `unique(tenant_id, name)`.
- `branches`: tenant_id, region_id (optional, same tenant), kind (`store`|`warehouse`), name,
  code, eta_branch_code, governorate, city, address_line, phone, timezone (`Africa/Cairo`),
  is_active.
- `staff`: tenant_id, auth_user_id (optional, unique within tenant), full_name, email, phone,
  pin_hash (computed by the backend), badge_code (unique within tenant), is_active.
- `permissions` (code PK), `roles` (tenant_id NULL for system roles; `unique nulls not
  distinct (tenant_id, code)`), `role_permissions`.
- `staff_assignments`: staff_id, role_id, scope (`tenant`|`region`|`branch`), region_id,
  branch_id, granted_by, granted_at, revoked_at. A CHECK ties scope to the id columns, and the
  role must be a system role or belong to the same tenant.
- `customers` (global): auth_user_id (unique), full_name, phone (E.164, unique), email,
  preferred_language.
- `customer_payment_methods`: customer_id, provider, provider_token (provider-tokenised card,
  never a PAN), brand, last4, expiry, is_default, revoked_at. CO only.
- `pos_devices`: tenant_id, branch_id, code (unique per branch), device_type
  (`register`|`kiosk`|`handheld`), hardware_serial, eta_pos_serial (unique per tenant),
  eta_os_version, eta_model_framework, last_seen_at, is_active.
- `pos_device_secrets`: device_id PK, api_key_hash, eta_pre_shared_key_ciphertext,
  eta_access_token_ciphertext, eta_token_expires_at. The backend encrypts these values; the
  database never sees the key.

### 5.2 Catalog

- `product_categories`: tenant, parent_id (same tenant), name_en, name_ar.
- `products`: tenant, category, sku (unique per tenant), name_en, name_ar, description,
  unit_of_measure (`unit`|`kg`|`g`|`l`|`ml`|`m`), is_weighed, is_perishable, vat_rate,
  base_price, eta_item_code, eta_item_type (`EGS`|`GS1`), eta_unit_type (default `EA`),
  is_active.
- `product_barcodes`: product, barcode (unique per tenant), kind
  (`gtin`|`plu`|`variable_measure`|`internal`), pack_quantity.
- `branch_prices`: PK (branch_id, product_id), price, updated_by. The effective price is
  `coalesce(branch price, base_price)`.

### 5.3 Inventory: double-entry ledger (ADR-005)

- `stock_locations`: tenant, branch, kind (`storage`|`shelf`|`transit`|`supplier`|`customer`|`scrap`|`adjustment`),
  name, is_default. Each branch gets exactly one of each virtual kind, created by a trigger on
  branch insert. It also gets a default `storage` location, and stores get a default `shelf`.
  Readable tenant-wide by internal contexts, so a receiving branch can address the sender's
  transit location.
- `app.location_id(p_branch_id uuid, p_kind text) returns uuid` returns that branch's default
  location of that kind.
- `suppliers` (lead_time_days, lead_time_stddev_days) and `supplier_products` (pack_size,
  min_order_quantity, unit_cost).
- `stock_batches`: product, supplier, batch_code, production_date, expiry_date, unit_cost
  `numeric(14,4)`, received_at. **Perishable products require expiry_date** (REQ-INV-01).
- `stock_moves` (append-only): product, batch (must belong to the product),
  from_location/from_branch, to_location/to_branch, quantity > 0, move_type, reference_type,
  reference_id, device_id, actor_staff_id, occurred_at, recorded_at.

  | move_type | from kind | to kind | branches |
  |---|---|---|---|
  | receipt | supplier | storage/shelf | same |
  | transfer_dispatch | storage/shelf | transit | same |
  | transfer_receive | transit | storage/shelf | different |
  | sale | storage/shelf | customer | same |
  | return | customer | storage/shelf/scrap | same |
  | scrap | storage/shelf | scrap | same |
  | adjustment_in | adjustment | storage/shelf | same |
  | adjustment_out | storage/shelf | adjustment | same |
  | replenish | storage/shelf | storage/shelf | same |

- `stock_levels` (derived): PK (location_id, batch_id), quantity. A security-definer trigger
  on `stock_moves` maintains it; the backend can only read it. Quantities may go negative:
  an oversell from two offline tills is surfaced in `app.stock_discrepancies` (physical
  locations below zero), never hidden (T2 paper).
- In-transit stock is the balance of the source branch's `transit` location, so
  `sum(in transit) = sum(dispatched) − sum(received)` holds by construction (REQ-INVN-01).
- `stock_transfers` (from_branch, to_branch, status, expected_arrival_at) and
  `stock_transfer_lines` (requested quantities). A `transfer_dispatch` move is rejected when
  the batch's `expiry_date <= ((expected_arrival_at + 48h) at time zone destination
  timezone)::date` (REQ-INV-03, proposal §3.2).
- `purchase_orders` (branch, supplier, status, source `manual`|`forecast`) and
  `purchase_order_lines`.
- **FEFO**: `app.fefo_pick(p_location_id uuid, p_product_id uuid, p_quantity numeric,
  p_as_of date default current_date) returns table(batch_id uuid, take_quantity numeric,
  expiry_date date)`. It takes batches with positive stock and expiry ≥ `p_as_of` (or no
  expiry), ordered by expiry ascending (nulls last), then received_at, then id. It takes
  greedily and returns less than requested when stock is short (REQ-INV-02, REQ-INVN-02).
- Valuation uses the batch's purchase cost (REQ-INV-04) through the
  `analytics.stock_on_hand` value.

### 5.4 Promotions (T5)

- `promotions`: mechanic (`percentage`|`fixed_amount`|`multibuy`|`bogo`|`tiered_spend`|`category_spend`|`loyalty_tier`|`meal_deal`|`coupon`|`cheapest_free`),
  `rule jsonb` (an object: AST/JDM definition), priority, exclusive_group, starts_at, ends_at,
  is_active.
- `promotion_branches`: if no rows exist, the promotion applies at all branches.
- `promotion_rule_sets`: versioned compiled bundles for tills, `unique(tenant_id, version)`,
  and a `checksum` generated as the sha256 hex of `compiled::text`. Append-only.
- `coupons`: code (unique per tenant, case-insensitive), optional customer_id for personal
  reward coupons, max_redemptions, per_customer_limit, validity.

### 5.5 POS, sync and sales

- `cashier_shifts`: device, staff, opened/closed, opening_float, counted_cash, expected_cash,
  status.
- `sync_events` (offline inbox, idempotent): `id` is the client event UUID, device_id plus
  branch_id (must match the device), event_type (`^[A-Z_]+$`), sequence_no
  (`unique(device_id, sequence_no)`), payload jsonb, occurred_at, received_at, status
  (`received`|`applied`|`rejected`|`conflict`), error, applied_at.
- `sales`: `id` is the till's UUID; branch, device, shift, staff, customer, sale_type
  (`sale`|`return`), original_sale_id (for returns only), status (`completed`|`voided`),
  receipt_number, subtotal, discount_total, tax_total, grand_total, currency, is_offline,
  sync_event_id, occurred_at, void fields. A CHECK enforces `grand_total = subtotal −
  discount_total + tax_total` (amounts net of VAT, as ETA receipts do).
- `sale_lines`: line_no, product, barcode, quantity, unit_price, discount_amount, vat_rate,
  tax_amount, line_total, price override and void fields.
- `sale_payments`: method (`cash`|`card`|`wallet`|`instapay`|`face_pay`|`loyalty_points`|`voucher`),
  provider (geidea, paymob, fawry, cib, nbe, kashier, …), amount, tendered, change_given,
  status, provider_reference, card_last4, auth_code, face_pay_enrollment_id. For cash,
  `tendered ≥ amount` and `change_given = tendered − amount`.
- `sale_discounts`: sale or line, promotion and/or coupon, amount > 0.
- Customers read their own sales, lines, payments, discounts and receipts across every
  market through the CO path.

### 5.6 Loyalty

- `loyalty_programs`: one per tenant; points_per_egp, egp_per_point, points_expiry_days,
  `tiers jsonb`.
- `loyalty_accounts`: tenant, customer (unique per tenant), card_number (unique per tenant),
  tier. A customer may join from the app in a storefront context.
- `loyalty_ledger` (append-only): account, customer (denormalised and FK-consistent), branch,
  sale, entry_type (`earn` > 0, `redeem`/`expire` < 0, `adjust` ≠ 0), points, expires_at.
- `app.loyalty_balances` view (security invoker).
- This migration also adds the cross paths: staff may read a customer who has an account or a
  sale in their tenant, and a customer may read tenants and branches where they have an
  account or a sale.

### 5.7 ETA e-receipts (T7)

- `eta_receipts`: sale (unique), device, receipt_type (`sale`|`return`), receipt_number
  (unique per device), `uuid` (64 hex characters, unique), previous_uuid, reference_uuid,
  buyer_type (`B`|`P`|`F`), buyer_id, buyer_name, total_amount, tax_total, issued_at,
  `document jsonb` (the ETA receipt JSON), status (`new` = ETA status 0, `submitted`,
  `valid`, `invalid`, `cancelled`), submission_id, validation_errors, submitted_at,
  validated_at.
  - `buyer_type = 'B'` requires buyer_id. `buyer_type = 'P'` with total ≥ 150,000 requires
    buyer_id.
  - The chain per device is linear. previous_uuid must exist on the same device, there is
    one successor per receipt (`unique(device_id, previous_uuid)`) and one genesis per
    device. Rows cannot be deleted, and the chain columns are immutable.
  - Returns must have reference_uuid. The original must belong to the same tenant and be no
    more than 540 days older.
- `eta_submissions`: 1–500 receipts, payload ≤ 1,572,864 bytes (1.5 MB), status, response.
- `app.eta_overdue_receipts` view: status `new` and issued more than 24 hours ago.

### 5.8 Audit chain and loss prevention (T9)

- `audit_log` (append-only): chain_id (a device id for till chains, the tenant id for the
  cloud chain), seq (`unique(chain_id, seq)`), event_type, actor_staff_id,
  approved_by_staff_id, device_id, shift_id, branch_id (optional), `payload text` (the exact
  canonical JSON string that was hashed), `payload_json jsonb` (generated from payload),
  prev_hash, hash, occurred_at.
  - **Hash** = `encode(sha256(convert_to(seq::text || prev_hash || payload, 'UTF8')), 'hex')`,
    the index + prev_hash + payload of the T9 proof of concept.
  - Genesis: seq 0 and `prev_hash` = 64 zeros.
  - A security-definer BEFORE INSERT trigger rejects any row whose seq, prev_hash or hash does
    not continue the chain.
  - `app.append_audit(p_event_type text, p_payload jsonb, p_branch_id uuid default null,
    p_approved_by uuid default null, p_shift_id uuid default null) returns app.audit_log`
    appends to the tenant's cloud chain under an advisory lock. Tills append their own chains
    by inserting device-computed rows, which the trigger verifies.
  - `app.verify_audit_chain(p_chain_id uuid) returns table(is_valid boolean, checked_count
    bigint, first_invalid_seq bigint, reason text)` recomputes the whole chain. It detects
    altered payloads (`hash mismatch`), deleted rows (`sequence gap`) and relinked rows
    (`prev_hash mismatch`) (REQ-SECU-02, UC-02).
- `audit_checkpoints`: chain_id, seq, hash, anchored_at, anchor_reference. These are the
  every-1000-blocks anchors from ADR-005 (T9).
- `loss_prevention_settings` (per tenant, defaults from the research):
  unlinked_refund_amount 50.00, unlinked_refunds_per_hour 3, void_amount_per_shift 200.00,
  manual_drawer_opens_per_shift 3.
- `fraud_flags`: rule, severity, subject_id, shift, staff, details, status
  (`open`|`reviewed`|`dismissed`|`confirmed`), `unique(rule, subject_id)`.
- `app.detect_shift_exceptions(p_shift_id uuid) returns setof app.fraud_flags` inserts new
  flags and returns them:
  - `UNLINKED_REFUND_AMOUNT`: a return without original_sale_id and grand_total > 50.
    Subject: the sale.
  - `UNLINKED_REFUND_FREQUENCY`: more than 3 unlinked returns within any 60-minute window of
    the shift. Subject: the shift.
  - `VOID_AMOUNT`: voided sales plus voided lines in the shift > 200. Subject: the shift.
  - `POST_CLOSE_VOID`: a voided sale that had a cash payment, meaning the drawer had already
    fired. Subject: the sale.
  - `MANUAL_DRAWER_OPENS`: more than 3 `DRAWER_OPEN` audit entries in the shift with payload
    `reason = 'manual'`. Subject: the shift.

### 5.9 Forecasting (optional stage 4)

- `demand_forecasts`: branch, product, model_version, generated_at, forecast_date,
  point_forecast, q10 ≤ q50 ≤ q90, std_dev.
- `reorder_points`: PK (branch, product), service_level_z (1.645), lead_time_days,
  safety_stock, reorder_point, model_version, computed_at.

### 5.10 AI assistant (Dual-RAG)

- `ai_conversations`: audience `admin` (staff required) or `shopper` (customer required), an
  optional branch scope, and a title. Only the owner sees them.
- `ai_messages`: role (`user`|`assistant`|`tool`|`system`), content, **`response jsonb`**,
  pipeline (`analytics`|`public`|`both`|`none`), task_type
  (`lookup`|`analysis`|`report`|`chitchat`), model, temperature, top_p, prompt_tokens,
  completion_tokens, latency_ms, retrieval_confidence, abstained, escalated.
  - `response` holds the assistant's full structured output. It must be a JSON object, and is
    required for assistant messages, with `answer` as a string. When `citations` is present
    it must be an array. Recommended shape:
    `{"answer", "citations":[{"chunk_id","document_id","quote"}], "sql",
    "result":{"columns","rows"}, "chart":{…}, "document":{…}, "abstained"}`.
- `kb_documents`: audience (`admin`|`public`), doc_type
  (`faq`|`policy`|`catalog`|`glossary`|`report`|`other`), title, source_uri, language
  (`ar`|`en`), status (`draft`|`published`|`superseded`), effective_from/to, version,
  `metadata jsonb`.
- `kb_chunks`: document, audience (must match the document), chunk_index, content, language,
  `fts tsvector` generated with the `arabic` or `english` configuration,
  `embedding vector(1024)`, metadata, token_count. GIN index on fts, HNSW (cosine) on
  embedding.
- RLS: tenant match, and either `audience = 'public'` or an internal context. Shoppers can
  never retrieve admin documents (addendum §3.2, §3.5).
- `app.kb_hybrid_search(p_query_text text, p_query_embedding extensions.vector(1024),
  p_match_count int default 10, p_audience text default null, p_full_text_weight float8
  default 1, p_semantic_weight float8 default 1, p_rrf_k int default 50) returns table(chunk_id
  uuid, document_id uuid, content text, score float8)`.
  - It filters on the current tenant **inside the retrieval query** and only searches
    published documents within their effective dates.
  - It runs keyword and vector search and fuses them with RRF (Supabase's hybrid-search
    pattern). It runs as security invoker, so RLS also applies.
- `analytics` semantic layer for NL-to-SQL:
  - `analytics.sales_daily`: tenant, branch, branch name, local date, transactions, gross,
    discounts, tax, returns, net revenue, average basket.
  - `analytics.product_sales_daily`.
  - `analytics.stock_on_hand`: quantity and batch-cost value.
  - The backend runs LLM SQL as `market_ai_reader` in a read-only transaction with a short
    statement timeout. RLS still filters to the caller's tenant and branches (addendum §3.3).

### 5.11 Face Pay (optional stage 5)

- `app.face_pay_enrollments` (identity side, CO): customer, `subject_token` (64 hex
  characters; an HMAC the backend computes, non-reversible), payment_method_id (must be the
  same customer's), status (`active`|`paused`|`revoked`), consent_version, consented_at,
  per_transaction_limit, daily_limit, revoked_at.
- `app.resolve_face_pay(p_subject_token text, p_amount numeric) returns table(enrollment_id
  uuid, customer_id uuid, payment_method_id uuid, provider text, provider_token text)`.
  - Security definer, internal context only.
  - Returns a row only for an active enrollment within its limits, where the daily limit
    counts today's face-pay payments.
- `biometric.face_templates`: subject_token, `embedding vector(128)`, model_version,
  quality_score, with an HNSW (L2) index. There is no customer id in this schema.
- `biometric.match_face(p_embedding extensions.vector(128), p_max_squared_distance float8
  default 1.10, p_limit int default 3) returns table(subject_token text, squared_distance
  float8)`, using the proposal's squared-L2 threshold of 1.10.
- `biometric.delete_subject(p_subject_token text) returns integer` handles PDPL erasure.

## 6. Testing

pgTAP files live in `supabase/tests/database/`. They run locally against PostgreSQL with
pgvector and pgTAP through `scripts/db-test.sh`, and through `supabase test db` once linked.
Fixtures come from `supabase/seed.sql`, which holds two canary tenants with fixed UUIDs:
"Alpha Mini Market" (one store, no regions) and "Nile Hypermarket" (Cairo and Alexandria
regions, three stores and a warehouse).

| Requirement (proposal) | Proven by |
|---|---|
| REQ-SECU-01 zero cross-tenant leaks | tenant isolation, hierarchy and AI tests; RLS coverage test |
| REQ-PERF-02 spatial RBAC | `has_permission` matrix, cross-branch denial |
| REQ-INVN-01 no dangling transit stock | transfer dispatch/receive balances |
| REQ-INVN-02 / REQ-INV-02 FEFO | `fefo_pick` ordering, split 3 + 2, expired skipped |
| REQ-INV-01 perishable batches need expiry | batch insert rejected |
| REQ-INV-03 transit expiry guard | 48h dispatch rejection |
| REQ-SECU-02 tamper detection | verify after altered and deleted rows |
| REQ-ETA-01 chain and buyer rules | fork, buyer, 540-day, batch-size tests |
| Idempotent ingestion | duplicate event and sale inserts |
| Loss prevention thresholds | one test per rule |
| AI isolation | shopper can't reach admin docs; other tenant's chunks never returned |
| PDPL separation | backend cannot read templates; biometric role can match |

## 7. Applying to the Supabase project

The migrations live in `supabase/migrations/` (Supabase CLI layout). Two ways to apply them:

1. Reconnect the Supabase connector with the account that owns project
   `vtvvyykyyorsbkfitlur`. Claude then applies each migration with the Supabase tools.
2. Run `supabase link --project-ref vtvvyykyyorsbkfitlur` and then `supabase db push` from a
   machine that can reach the database.

After applying, set the logins by hand:
`alter role market_backend with login password '…'` (and `market_biometric` for the Face Pay
service). Connect the backend through the Supavisor **transaction** pooler as
`market_backend.<project_ref>`. Never commit passwords; the database password shared in chat
should be rotated.

## 8. Out of scope

- The backend service itself (next project), the local SQLite till schema, the promotion
  solver, the LightGBM pipeline, ETA API calls, and payment-provider integrations.
- Variable-measure barcode layouts (store config to add later), Merkle-tree checkpoint
  computation, vector index sharding by region.
- Column-level encryption of embeddings. Supabase encrypts storage at rest; encrypting the
  vectors would make similarity search impossible.
