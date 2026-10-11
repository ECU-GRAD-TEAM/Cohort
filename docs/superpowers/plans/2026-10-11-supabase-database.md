# Market SaaS Supabase Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the full Market SaaS database as Supabase CLI migrations, with pgTAP tests proving tenant isolation, ledgers, hash chains and the research requirements.

**Architecture:** Plain-SQL migrations in `supabase/migrations/`, one per module, each self-contained: tables, functions, RLS and grants. The backend connects as `market_backend` and calls `app.set_context(...)` per transaction, and RLS derives tenant and branch reach from that. pgTAP tests in `supabase/tests/database/` run against a fresh local Postgres with `supabase/seed.sql` canary data.

**Tech Stack:** PostgreSQL 16 locally and 17 on Supabase, pgvector ≥ 0.6, pgTAP 1.3, pg_prove, Supabase CLI 2.118.0 (layout and linking only).

**Spec:** `docs/superpowers/specs/2026-10-11-supabase-database-design.md`. Table columns, constraints and rules come from there. Each task names the spec section it implements.

## Global Constraints

- Everything must run on Supabase as the non-superuser `postgres`: no `alter system`, no superuser-only extensions in migrations, and extensions installed `with schema extensions`.
- No passwords, keys or connection strings in the repo. Roles are created `NOLOGIN`.
- Every table in `app` and `biometric` has RLS enabled. Policies wrap context calls in `(select …)`.
- Security-definer functions use `set search_path = ''` and schema-qualify everything (`pg_catalog` is implicit).
- Migration names: `supabase/migrations/20261011120NNN_<module>.sql`, applied in lexical order.
- Seed UUIDs follow `TTTTTTTT-EEEE-0000-0000-00000000000N`. `TTTTTTTT` is `aaaaaaaa` (Alpha), `bbbbbbbb` (Nile) or `cccccccc` (global customers). `EEEE` is 0000 tenant, 0001 region, 0002 branch, 0003 staff, 0004 device, 0005 product, 0006 batch, 0007 customer, 0008 supplier, 0009 category.
- Money is `numeric(14,2)`, quantities `numeric(14,3)`, VAT rate `numeric(5,2)` default 14.00, currency `EGP`.
- Test runner: `scripts/db-test.sh` (PG env vars; default DB `market_saas_test`). All tests must pass before each commit.

## Review Focus

1. **Context set outside a transaction:** with autocommit, a transaction-local `set_context` lasts one statement, so later statements must see zero rows and nothing may leak to the next pooled client. Pinned in Task 2 (`context_does_not_outlive_transaction`).
2. **Two offline tills selling the last unit:** the ledger must accept both sales, go negative, and show the item in `app.stock_discrepancies` rather than reject a real sale. Pinned in Task 4.
3. **Times near midnight Cairo vs UTC:** a sale at 23:30 UTC belongs to the next Cairo day in `analytics.sales_daily`, and the transit-expiry guard uses the destination branch's timezone. Pinned in Tasks 4 and 13.
4. **A customer with a sale but no loyalty account** must still see that store's name and receipt, and staff of *another* tenant must not see that customer. Pinned in Task 7.
5. **Arabic content:** Arabic chunks must be found by Arabic keyword queries, and mixed AR/EN tenants must still never cross tenants. Pinned in Task 11.

---

### Task 1: Tooling and foundation

**Files:**
- Create: `supabase/config.toml` (via `supabase init`), `supabase/.gitignore`, `.gitignore`
- Create: `scripts/db-test.sh`, `scripts/sql/supabase-compat.sql`
- Create: `supabase/migrations/20261011120000_foundation.sql`, `supabase/seed.sql` (header only)
- Test: `supabase/tests/database/010_security_baseline.test.sql`

**Interfaces (Produces):**
- Schemas `app`, `analytics`, `biometric`; extension `vector` in `extensions`.
- Roles `market_backend`, `market_ai_reader` (granted to market_backend), `market_analytics_owner`, `market_biometric`, all NOLOGIN NOBYPASSRLS.
- `app.current_tenant_id() returns uuid`, `app.current_branch_id() returns uuid`, `app.current_staff_id() returns uuid`, `app.current_device_id() returns uuid`, `app.current_customer_id() returns uuid`, `app.current_system_actor() returns text`, `app.is_internal() returns boolean`.
- Trigger functions `app.set_updated_at()`, `app.prevent_mutation()` (raises `append-only table`), `app.prevent_delete()`.
- `app.is_valid_gtin14(p_code text) returns boolean` (immutable, GS1 mod-10).

- [ ] **Step 1:** Write `010_security_baseline.test.sql` with these assertions:
  - `has_schema('app')`, `has_schema('analytics')`, `has_schema('biometric')`, `has_extension('vector')`.
  - `has_role` for the four roles. `market_backend` has `rolbypassrls = false` and owns no table in `app`.
  - `anon` and `authenticated` lack USAGE on `app`, `analytics` and `biometric`, via `has_schema_privilege(..., 'USAGE') = false`.
  - Zero tables in `app` or `biometric` with `relrowsecurity = false`, from a `pg_class` query.
  - `app.is_valid_gtin14('00012345678905')` and `app.is_valid_gtin14('05901234123457')` are true. `'00012345678906'`, `'12345'` and `'0001234567890A'` are false.
  - Unset context: every `current_*()` returns NULL and `is_internal()` is false.
- [ ] **Step 2:** Run `scripts/db-test.sh`. Expected: FAIL (schemas and functions missing).
- [ ] **Step 3:** Run `supabase init` and write the compat SQL. The compat SQL creates the `anon`, `authenticated` and `service_role` roles if missing, creates the `extensions` schema with `vector` and `pgtap`, and sets the database search_path to `"$user", public, extensions`. Then write the runner and the foundation migration. The runner recreates the DB, applies compat, migrations and seed in order, then runs `pg_prove`.
- [ ] **Step 4:** Run `scripts/db-test.sh`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): foundation schemas, roles, context readers and test runner`.

### Task 2: Core tenancy, devices and context (spec §3.3–3.5, §5.1)

**Files:**
- Create: `supabase/migrations/20261011120100_core_tenancy.sql`
- Modify: `supabase/seed.sql`, adding tenants, regions, branches, staff, assignments, devices with secrets, and customers
- Test: `supabase/tests/database/020_tenant_isolation.test.sql`, `supabase/tests/database/030_hierarchy_rbac.test.sql`

**Interfaces (Produces):**
- Tables `app.tenants`, `regions`, `branches`, `staff`, `permissions`, `roles`, `role_permissions`, `staff_assignments`, `customers`, `customer_payment_methods`, `pos_devices`, `pos_device_secrets`.
- `app.set_context(p_tenant_id uuid default null, p_staff_id uuid default null, p_branch_id uuid default null, p_device_id uuid default null, p_customer_id uuid default null, p_system_actor text default null) returns void`
- `app.accessible_branch_ids() returns uuid[]`, `app.has_permission(p_permission text, p_branch_id uuid default null) returns boolean`
- `app.staff_memberships(p_auth_user_id uuid) returns table(staff_id uuid, tenant_id uuid, tenant_name text)`, `app.customer_id_for_auth_user(p_auth_user_id uuid) returns uuid`, `app.authenticate_device(p_device_id uuid, p_api_key text) returns table(tenant_id uuid, branch_id uuid)`, `app.register_customer(p_full_name text, p_phone text, p_email text default null, p_auth_user_id uuid default null, p_language text default 'ar') returns uuid`
- Seed: Alpha has store `aaaaaaaa-0002-…-01`, owner `aaaaaaaa-0003-…-01`, cashier `-02` and device `aaaaaaaa-0004-…-01`. Nile has region Cairo `bbbbbbbb-0001-…-01` and Alexandria `-02`. Its branches are Nasr City store `bbbbbbbb-0002-…-01` (Cairo), Maadi store `-02` (Cairo), Smouha store `-03` (Alex) and Cairo warehouse `-04` (Cairo). Its staff are owner `bbbbbbbb-0003-…-01`, Cairo regional manager `-02`, Alex regional manager `-03`, Nasr City branch manager `-04`, Nasr City cashier `-05`, Maadi cashier `-06` and warehouse stock clerk `-07`. Its devices are Nasr City REG-01 `bbbbbbbb-0004-…-01` and Maadi REG-01 `-02`. Device API keys are `dev-key-<device code>-<branch code>`. Customers are Mona `cccccccc-0007-…-01` and Karim `-02`.

- [ ] **Step 1:** Write the failing tests.
  - `020_tenant_isolation`:
    - With no context, `app.branches`, `app.staff` and `app.pos_devices` return 0 rows for `market_backend`.
    - Nile owner context sees 4 branches and 0 Alpha rows. Alpha owner context sees 1 branch.
    - Inserting a branch with Alpha's tenant_id under Nile context throws `42501` (RLS WITH CHECK).
    - A staff_assignment pointing at another tenant's branch throws `23503` (composite FK).
    - `set_context` with Alpha's tenant and Nile's staff throws `42501`, as does a device from another branch.
    - `context_does_not_outlive_transaction` lives in its own file, `021_context_autocommit.test.sql`. That file has no `begin`, so every statement autocommits. It runs `set role market_backend`, then `app.set_context(Nile owner)` as one statement, then asserts that `app.current_tenant_id()` is null and that `app.branches` returns 0 rows. It ends with `reset role`.
    - A malformed GUC (`set_config('app.current_tenant_id','x',true)`) makes `select … from app.branches` throw `22P02`.
  - `030_hierarchy_rbac`:
    - `accessible_branch_ids()` cardinality: Nile owner 4, Cairo regional manager 3 (Nasr City, Maadi, warehouse), Alex regional manager 1, Nasr City branch manager 1, cashier at the Nasr City device 1.
    - The owner with `p_branch_id` set to Maadi gets 1.
    - A Nasr City cashier at the Maadi device throws on `set_context`. A staff member at a device in a branch outside their reach gets 0.
    - `has_permission`:
      - The Nasr City branch manager has REFUND_UNLINKED at Nasr City but not at Maadi.
      - The cashier has REFUND_LINKED but not REFUND_UNLINKED.
      - The Cairo regional manager has PRICE_MANAGE at Maadi but not at Smouha.
      - The owner has STAFF_MANAGE with NULL branch; the branch manager doesn't.
    - `authenticate_device` returns Nasr City for the right key and 0 rows for a wrong key.
    - `staff_memberships` lists Nile for the owner's auth id.
    - `register_customer` called twice with the same phone returns the same id.
- [ ] **Step 2:** Run `scripts/db-test.sh`. Expected: FAIL (relations missing).
- [ ] **Step 3:** Write the core migration (tables, reference roles and permissions per spec §3.4, functions, RLS per spec §3.5, grants) and the seed rows.
- [ ] **Step 4:** Run `scripts/db-test.sh`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): core tenancy hierarchy, devices, context and branch-scoped RBAC`.

### Task 3: Catalog (spec §5.2)

**Files:** Create `supabase/migrations/20261011120200_catalog.sql`. Modify `supabase/seed.sql`, adding categories and products. Nile products: Milk 1L (perishable) `bbbbbbbb-0005-…-01`, Rice 5kg `-02`, Tomatoes (weighed, kg) `-03`, Bread `-04`. Alpha: Milk 1L `aaaaaaaa-0005-…-01` and Water 1.5L `-02`. Add barcodes and a Maadi price override for Rice. Test: `supabase/tests/database/040_catalog.test.sql`.

**Interfaces (Produces):** tables `app.product_categories`, `app.products`, `app.product_barcodes`, `app.branch_prices`.

- [ ] **Step 1:** Write `040_catalog`:
  - A gtin barcode `'12345678901234'` (bad check digit) throws `23514`, and `'00012345678905'` inserts.
  - Barcode uniqueness per tenant: the same code in two tenants is OK; a duplicate within one tenant throws `23505`.
  - A shopper (customer-only context with Nile tenant) can read products and branch_prices but cannot insert into products (`42501`).
  - Nile staff never see Alpha products.
  - The effective Rice price at Maadi is the override and at Nasr City is the base price.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the migration, with the TP read policy and TI/BI write policies, and the seed rows.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): tenant catalog with GTIN-14 validation and branch prices`.

### Task 4: Inventory ledger (spec §5.3)

**Files:** Create `supabase/migrations/20261011120300_inventory.sql`. Modify `supabase/seed.sql`, adding a supplier, milk batches received into the Cairo warehouse, and Nasr City storage stock. Test: `supabase/tests/database/050_inventory_ledger.test.sql`.

**Interfaces (Produces):**
- Tables: `app.stock_locations`, `suppliers`, `supplier_products`, `stock_batches`, `stock_moves`, `stock_levels`, `stock_transfers`, `stock_transfer_lines`, `purchase_orders`, `purchase_order_lines`.
- View `app.stock_discrepancies`.
- `app.location_id(p_branch_id uuid, p_kind text) returns uuid`.
- `app.fefo_pick(p_location_id uuid, p_product_id uuid, p_quantity numeric, p_as_of date default current_date) returns table(batch_id uuid, take_quantity numeric, expiry_date date)`.

- [ ] **Step 1:** Write `050_inventory_ledger`:
  - Every seeded branch has the 5 virtual locations plus default storage, and stores also have a shelf.
  - A perishable batch without expiry throws `P0001`.
  - Receipt supplier → storage raises the storage level by the move quantity and lowers the supplier location.
  - `update`/`delete` on `stock_moves` throws `append-only table`, and `market_backend` lacks UPDATE privilege.
  - A move_type/kind mismatch throws (sale into storage). `market_backend` cannot write `stock_levels`.
  - `fefo_pick`, with batches A (exp D+5, qty 3), B (exp D+20, qty 10) and C (expired), for 5 units returns A=3 then B=2. With 20 units it returns a total of 13 (shortfall). C is never returned.
  - Transfer: dispatching to transit then receiving at Maadi leaves the transit balance 0, and after dispatch only, the transit balance equals the dispatched quantity.
  - The 48h guard: arrival 2026-10-18 10:00 Africa/Cairo with expiry 2026-10-20 throws `P0001`, and expiry 2026-10-21 is allowed.
  - Oversell: two sales of the last unit leave a level of −1, and `stock_discrepancies` lists it.
  - Maadi staff can read the transfer from Nasr City but not Nasr City's `stock_levels`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - The branch-insert trigger that creates locations, with a backfill for existing branches.
  - The security-definer validation and level triggers.
  - The perishable trigger and `fefo_pick` (window-sum greedy).
  - RLS: locations TI read, BI write. Moves BI on (from_branch OR to_branch). Transfers BI on from OR to. Levels BI read-only.
  - The seed rows.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): double-entry stock ledger with FEFO and transit guard`.

### Task 5: Promotions (spec §5.4)

**Files:** Create `supabase/migrations/20261011120400_promotions.sql`. Modify the seed, adding one Nile "3 for 9" multibuy promotion. Test: `supabase/tests/database/060_promotions.test.sql`.

**Interfaces (Produces):** tables `app.promotions`, `app.promotion_branches`, `app.promotion_rule_sets`, `app.coupons`.

- [ ] **Step 1:** Write the tests:
  - A `rule` that isn't an object throws `23514`, and `ends_at <= starts_at` throws `23514`.
  - `promotion_rule_sets.checksum = encode(sha256(convert_to(compiled::text,'UTF8')),'hex')`, a duplicate version throws `23505`, and update throws `append-only table`.
  - Coupon `SAVE5` vs `save5` in one tenant throws `23505`.
  - A shopper sees the promotion but not a non-personal coupon. Mona sees her personal coupon.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the migration and the seed.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): promotions, versioned rule sets and coupons`.

### Task 6: POS shifts, sync inbox and sales (spec §5.5)

**Files:** Create `supabase/migrations/20261011120500_sales.sql`. Test: `supabase/tests/database/070_sales_sync.test.sql`.

**Interfaces (Produces):** tables `app.cashier_shifts`, `app.sync_events`, `app.sales`, `app.sale_lines`, `app.sale_payments`, `app.sale_discounts`.

- [ ] **Step 1:** Write `070_sales_sync`:
  - The same sync event inserted twice with `on conflict (id) do nothing` gives count 1. The same `(device_id, sequence_no)` with a new id throws `23505`. A branch_id that doesn't match the device throws `23503`.
  - `market_backend` can update `sync_events.status` but not `payload` (`42501`). Delete throws.
  - A sale with `grand_total <> subtotal − discount + tax` throws `23514`. A cash payment with `change_given` wrong throws `23514`.
  - A sale inserted twice by id gives count 1.
  - Delete on `sales` throws, and `market_backend` cannot update `sales.grand_total`.
  - Mona (customer context, no tenant) sees her Nile sale, its lines and its payments, but not Karim's sale.
  - The Maadi cashier context doesn't see Nasr City sales.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the migration.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): idempotent sync inbox, sales, payments and discounts`.

### Task 7: Loyalty and cross paths (spec §5.6)

**Files:** Create `supabase/migrations/20261011120600_loyalty.sql`. Modify the seed, adding a Nile program, Mona's and Karim's Nile accounts, and Mona's Alpha account. Test: `supabase/tests/database/080_loyalty.test.sql`.

**Interfaces (Produces):** tables `app.loyalty_programs`, `app.loyalty_accounts`, `app.loyalty_ledger`, and view `app.loyalty_balances`. Policies `tenants_customer_read`, `branches_customer_read` and `customers_staff_read`.

- [ ] **Step 1:** Write `080_loyalty`:
  - Earn with a negative number of points throws `23514`. The ledger rejects update and delete.
  - The balance after earn 100 and redeem −30 is 70.
  - Mona sees both her accounts (Nile and Alpha) and Karim's is hidden.
  - Nile staff see Mona and Karim. Alpha staff see Mona and not Karim.
  - A customer with a sale and no account (Karim at Alpha, inserted in the test) can read Alpha's tenant and branch name, and Alpha staff can then see Karim through the sales path.
  - Mona can create her own account with a storefront tenant context, and cannot create one for Karim (`42501`).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the migration and the seed.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): loyalty accounts and append-only points ledger`.

### Task 8: ETA e-receipts (spec §5.7)

**Files:** Create `supabase/migrations/20261011120700_eta_receipts.sql`. Test: `supabase/tests/database/090_eta_receipts.test.sql`.

**Interfaces (Produces):** tables `app.eta_receipts` and `app.eta_submissions`; view `app.eta_overdue_receipts`.

- [ ] **Step 1:** Write `090_eta_receipts`:
  - A buyer B without an id throws `23514`. A buyer P with 150000.00 and no id throws, and with 149999.99 inserts.
  - A second genesis on the same device throws `23505`. Two receipts with the same previous_uuid throw `23505`. A previous_uuid from another device throws `P0001`.
  - A return without reference throws `23514`, and a return 541 days after the original throws `P0001`.
  - Updating `uuid` throws, updating `status` succeeds, and delete throws.
  - A submission with 501 receipts or 1572865 bytes throws `23514`.
  - An overdue view row appears for a `new` receipt issued 25h ago.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the migration.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): ETA e-receipt chain and submission batches`.

### Task 9: Audit hash chain (spec §5.8)

**Files:** Create `supabase/migrations/20261011120800_audit_loss_prevention.sql` (audit part first). Test: `supabase/tests/database/100_audit_chain.test.sql`.

**Interfaces (Produces):** tables `app.audit_log` and `app.audit_checkpoints`; `app.append_audit(p_event_type text, p_payload jsonb, p_branch_id uuid default null, p_approved_by uuid default null, p_shift_id uuid default null) returns app.audit_log`; `app.verify_audit_chain(p_chain_id uuid) returns table(is_valid boolean, checked_count bigint, first_invalid_seq bigint, reason text)`.

- [ ] **Step 1:** Write `100_audit_chain`:
  - Three `append_audit` calls under the Nile owner give seq 0 (genesis) through 3 on chain_id = tenant id, and verify returns `(true, 4, null, null)`.
  - A row's hash equals the documented formula.
  - A device-chain insert with the right hash succeeds; with a wrong prev_hash or wrong hash it throws `P0001`.
  - As superuser with `session_replication_role = replica`, updating seq 2's payload makes verify return `(false, …, 2, 'hash mismatch')`.
  - Deleting seq 2 makes it return first_invalid_seq 3 with reason `sequence gap`.
  - `market_backend` update or delete throws.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the audit part.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): SHA-256 hash-chained audit log with verification`.

### Task 10: Loss prevention (spec §5.8)

**Files:** Modify `supabase/migrations/20261011120800_audit_loss_prevention.sql` (loss-prevention part; same migration, not yet applied anywhere). Test: `supabase/tests/database/110_loss_prevention.test.sql`.

**Interfaces (Produces):** tables `app.loss_prevention_settings` and `app.fraud_flags`; `app.detect_shift_exceptions(p_shift_id uuid) returns setof app.fraud_flags`.

- [ ] **Step 1:** Write `110_loss_prevention`, building one Nasr City shift per scenario:
  - One unlinked return of 60 gives `UNLINKED_REFUND_AMOUNT`; 50.00 gives none.
  - 4 unlinked returns within 59 minutes give `UNLINKED_REFUND_FREQUENCY`; 4 spread over 3h give none.
  - Voided sales and lines totalling 200.01 give `VOID_AMOUNT`; 200.00 gives none.
  - A voided sale with a cash payment gives `POST_CLOSE_VOID`.
  - 4 manual `DRAWER_OPEN` audit entries give `MANUAL_DRAWER_OPENS`; 3 give none.
  - Running detection twice adds no duplicates.
  - A tenant threshold override (unlinked_refund_amount 100) suppresses the 60 refund.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): exception-based loss prevention flags`.

### Task 11: Forecasting and AI assistant (spec §5.9, §5.10 except analytics)

**Files:** Create `supabase/migrations/20261011120900_forecasting.sql` and `supabase/migrations/20261011121000_ai_assistant.sql`. Test: `supabase/tests/database/120_ai_assistant.test.sql`.

**Interfaces (Produces):**
- Tables `app.demand_forecasts`, `app.reorder_points`, `app.ai_conversations`, `app.ai_messages`, `app.kb_documents`, `app.kb_chunks`.
- `app.kb_hybrid_search(p_query_text text, p_query_embedding extensions.vector(1024), p_match_count int default 10, p_audience text default null, p_full_text_weight float8 default 1, p_semantic_weight float8 default 1, p_rrf_k int default 50) returns table(chunk_id uuid, document_id uuid, content text, score float8)`.

- [ ] **Step 1:** Write `120_ai_assistant`. Embeddings are built with `array_fill`/one-hot vectors so they are deterministic.
  - An assistant message without `response` throws `23514`. `response = '[]'` throws. `response` without a string `answer` throws. A valid object inserts and round-trips `response->'chart'`.
  - The Nile shopper context (Mona) cannot read admin chunks or start an admin conversation.
  - Hybrid search under the Nile shopper context returns only Nile public chunks, even when an Alpha chunk has the identical embedding and text.
  - Under Nile staff, admin glossary chunks are returned.
  - Superseded documents are excluded.
  - The Arabic query `'الاسترجاع'` finds the Arabic policy chunk.
  - The best keyword+semantic match ranks first.
  - Staff A cannot read staff B's conversation.
  - A forecast with q10 > q50 throws `23514`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement both migrations.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): forecasting tables and AI assistant with JSON responses and hybrid search`.

### Task 12: Face Pay (spec §5.11)

**Files:** Create `supabase/migrations/20261011121100_face_pay.sql`. Test: `supabase/tests/database/130_face_pay.test.sql`.

**Interfaces (Produces):**
- Table `app.face_pay_enrollments` and table `biometric.face_templates`.
- `app.resolve_face_pay(p_subject_token text, p_amount numeric) returns table(enrollment_id uuid, customer_id uuid, payment_method_id uuid, provider text, provider_token text)`.
- `biometric.match_face(p_embedding extensions.vector(128), p_max_squared_distance float8 default 1.10, p_limit int default 3) returns table(subject_token text, squared_distance float8)`.
- `biometric.delete_subject(p_subject_token text) returns integer`.
- FK `sale_payments.face_pay_enrollment_id`.

- [ ] **Step 1:** Write `130_face_pay`:
  - `market_backend` has no privileges on `biometric.face_templates`.
  - `market_biometric` matches an identical embedding with distance 0, and an embedding at squared distance 1.21 is not matched.
  - Enrolling with another customer's payment method throws `23503`.
  - `resolve_face_pay` returns a row for an active enrollment under the limit, none when paused, none over per_transaction_limit, and none when today's face-pay total plus the amount exceeds daily_limit.
  - Mona sees her enrollment and Karim's is hidden.
  - `delete_subject` returns 1 and leaves no templates.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): optional Face Pay enrollment and separated biometric templates`.

### Task 13: Analytics semantic layer (spec §5.10)

**Files:** Create `supabase/migrations/20261011121200_analytics.sql`. Test: `supabase/tests/database/140_analytics.test.sql`.

**Interfaces (Produces):** views `analytics.sales_daily`, `analytics.product_sales_daily` and `analytics.stock_on_hand`, owned by `market_analytics_owner`. `market_ai_reader` has SELECT on them only.

- [ ] **Step 1:** Write `140_analytics`:
  - As `market_ai_reader` with the Nile owner context, `select … from app.sales` throws `42501` and the views return rows.
  - Rows are Nile only, and under the Maadi cashier context only Maadi rows.
  - A sale at 2026-10-11 23:30 UTC is counted on 2026-10-12 (Cairo).
  - Net revenue = sales − returns.
  - Stock value = quantity × batch unit_cost.
  - With no context, there are 0 rows.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(db): analytics semantic layer for NL-to-SQL`.

### Task 14: Documentation, final verification, push

**Files:** Create `supabase/README.md`, which covers:
- the backend connection contract, with a `set_context` snippet in Node (pg) and Python (psycopg);
- the role setup SQL to run by hand;
- `db push` and test instructions;
- a module map and a Mermaid ER overview.

Also modify `README.md` (project overview and links).

- [ ] **Step 1:** Write the docs.
- [ ] **Step 2:** Run the full `scripts/db-test.sh` from a clean DB. Expected: all files `ok`.
- [ ] **Step 3:** Run a `supabase db lint`-style sanity pass: `psql -f` every migration twice against a fresh DB. Every migration must fail cleanly or be idempotent. Expected: the 2nd run errors only on objects that legitimately exist.
- [ ] **Step 4:** Commit `docs(db): database README and backend connection contract` and push to `claude/eager-feynman-lmukrw`.
