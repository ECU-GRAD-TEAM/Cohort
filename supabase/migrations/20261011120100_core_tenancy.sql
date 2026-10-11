-- Core tenancy: tenant → region → branch hierarchy, staff and roles, global shoppers,
-- POS devices, request context and branch-scoped RBAC (spec §3.3–3.5, §5.1).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table app.tenants (
  id                      uuid primary key default gen_random_uuid(),
  name                    text not null check (length(btrim(name)) > 0),
  legal_name              text,
  tax_registration_number text check (tax_registration_number ~ '^[0-9]{9,14}$'),
  eta_activity_code       text,
  default_language        text not null default 'ar' check (default_language in ('ar', 'en')),
  currency                char(3) not null default 'EGP',
  status                  text not null default 'active' check (status in ('active', 'suspended', 'closed')),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create table app.regions (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references app.tenants (id),
  name       text not null,
  code       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, name)
);

create table app.branches (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references app.tenants (id),
  region_id       uuid,
  kind            text not null default 'store' check (kind in ('store', 'warehouse')),
  name            text not null,
  code            text not null check (code ~ '^[A-Z0-9_-]{2,16}$'),
  eta_branch_code text,
  governorate     text,
  city            text,
  address_line    text,
  phone           text,
  timezone        text not null default 'Africa/Cairo',
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, code),
  foreign key (tenant_id, region_id) references app.regions (tenant_id, id)
);

create table app.staff (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references app.tenants (id),
  auth_user_id uuid,
  full_name    text not null,
  email        text,
  phone        text,
  pin_hash     text,
  badge_code   text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, auth_user_id),
  unique (tenant_id, badge_code)
);
comment on column app.staff.auth_user_id is 'Supabase Auth user (web-app sign-in). Till-only cashiers have none and sign in with a PIN.';
comment on column app.staff.pin_hash is 'Slow hash (bcrypt/argon2) computed by the backend; never a raw PIN.';

create table app.permissions (
  code        text primary key check (code ~ '^[A-Z_]+$'),
  description text not null
);

create table app.roles (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid references app.tenants (id),
  code       text not null check (code ~ '^[a-z_]+$'),
  name       text not null,
  created_at timestamptz not null default now(),
  unique nulls not distinct (tenant_id, code)
);
comment on column app.roles.tenant_id is 'NULL for the system roles shared by every tenant.';

create table app.role_permissions (
  role_id         uuid not null references app.roles (id) on delete cascade,
  permission_code text not null references app.permissions (code),
  primary key (role_id, permission_code)
);

create table app.staff_assignments (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null,
  staff_id   uuid not null,
  role_id    uuid not null references app.roles (id),
  scope      text not null check (scope in ('tenant', 'region', 'branch')),
  region_id  uuid,
  branch_id  uuid,
  granted_by uuid,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  check ((scope = 'tenant' and region_id is null and branch_id is null)
      or (scope = 'region' and region_id is not null and branch_id is null)
      or (scope = 'branch' and branch_id is not null and region_id is null)),
  foreign key (tenant_id, staff_id) references app.staff (tenant_id, id),
  foreign key (tenant_id, region_id) references app.regions (tenant_id, id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, granted_by) references app.staff (tenant_id, id)
);
create index staff_assignments_active_idx on app.staff_assignments (staff_id) where revoked_at is null;

create table app.customers (
  id                 uuid primary key default gen_random_uuid(),
  auth_user_id       uuid unique,
  full_name          text not null,
  phone              text not null unique check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  email              text,
  preferred_language text not null default 'ar' check (preferred_language in ('ar', 'en')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
comment on table app.customers is 'Global shopper accounts: one account works in every market on the platform.';

create table app.customer_payment_methods (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references app.customers (id),
  provider       text not null check (provider in ('paymob', 'geidea', 'fawry', 'kashier', 'cib', 'nbe', 'other')),
  provider_token text not null,
  brand          text,
  last4          char(4) check (last4 ~ '^[0-9]{4}$'),
  exp_month      smallint check (exp_month between 1 and 12),
  exp_year       smallint check (exp_year between 2000 and 2100),
  is_default     boolean not null default false,
  created_at     timestamptz not null default now(),
  revoked_at     timestamptz,
  unique (customer_id, id)
);
comment on column app.customer_payment_methods.provider_token is 'Payment-provider token only; card numbers never enter this database.';

create table app.pos_devices (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  branch_id           uuid not null,
  code                text not null check (code ~ '^[A-Z0-9_-]{2,16}$'),
  device_type         text not null default 'register' check (device_type in ('register', 'kiosk', 'handheld')),
  hardware_serial     text,
  eta_pos_serial      text,
  eta_os_version      text,
  eta_model_framework text,
  last_seen_at        timestamptz,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (tenant_id, id),
  unique (id, branch_id),
  unique (branch_id, code),
  unique (tenant_id, eta_pos_serial),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);

create table app.pos_device_secrets (
  device_id                     uuid primary key,
  tenant_id                     uuid not null,
  branch_id                     uuid not null,
  api_key_hash                  text not null check (api_key_hash ~ '^[0-9a-f]{64}$'),
  eta_pre_shared_key_ciphertext bytea,
  eta_access_token_ciphertext   bytea,
  eta_token_expires_at          timestamptz,
  rotated_at                    timestamptz not null default now(),
  foreign key (device_id, branch_id) references app.pos_devices (id, branch_id) on delete cascade,
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);
comment on table app.pos_device_secrets is 'Device credentials. api_key_hash = sha256 hex of the device API key; ETA secrets are encrypted by the backend before they arrive.';

create trigger tenants_updated_at before update on app.tenants for each row execute function app.set_updated_at();
create trigger regions_updated_at before update on app.regions for each row execute function app.set_updated_at();
create trigger branches_updated_at before update on app.branches for each row execute function app.set_updated_at();
create trigger staff_updated_at before update on app.staff for each row execute function app.set_updated_at();
create trigger customers_updated_at before update on app.customers for each row execute function app.set_updated_at();
create trigger pos_devices_updated_at before update on app.pos_devices for each row execute function app.set_updated_at();

-- A role must be a system role or belong to the assignment's tenant.
create function app.check_assignment_role() returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from app.roles r
                  where r.id = new.role_id and (r.tenant_id is null or r.tenant_id = new.tenant_id)) then
    raise exception 'role % is not available to tenant %', new.role_id, new.tenant_id using errcode = '23503';
  end if;
  return new;
end
$$;
create trigger staff_assignments_role_check before insert or update on app.staff_assignments
  for each row execute function app.check_assignment_role();

-- ---------------------------------------------------------------------------
-- Reference data: permissions and the system roles (spec §3.4)
-- ---------------------------------------------------------------------------

insert into app.permissions (code, description) values
  ('SALE_CREATE',        'Ring up sales at a till'),
  ('LINE_VOID',          'Void a line from an open sale'),
  ('SALE_VOID',          'Void a completed sale'),
  ('REFUND_LINKED',      'Refund against an original receipt'),
  ('REFUND_UNLINKED',    'Refund without a receipt'),
  ('PRICE_OVERRIDE',     'Override a price at the till'),
  ('DISCOUNT_MANUAL',    'Give a manual discount'),
  ('DRAWER_OPEN_MANUAL', 'Open the cash drawer without a sale'),
  ('SHIFT_MANAGE',       'Open, close and reconcile cashier shifts'),
  ('STOCK_VIEW',         'See stock levels'),
  ('STOCK_RECEIVE',      'Receive supplier deliveries'),
  ('STOCK_TRANSFER',     'Dispatch and receive transfers'),
  ('STOCK_ADJUST',       'Count, scrap and adjust stock'),
  ('CATALOG_MANAGE',     'Edit products, categories and barcodes'),
  ('PRICE_MANAGE',       'Set branch prices'),
  ('PROMOTION_MANAGE',   'Create and publish promotions'),
  ('LOYALTY_MANAGE',     'Manage loyalty members and points'),
  ('STAFF_MANAGE',       'Invite staff and assign roles'),
  ('BRANCH_MANAGE',      'Configure the market, its regions and branches'),
  ('DEVICE_MANAGE',      'Register and retire tills'),
  ('REPORT_VIEW',        'See sales and stock reports'),
  ('AUDIT_VIEW',         'Read the audit trail'),
  ('FRAUD_REVIEW',       'Review loss-prevention flags'),
  ('AI_ANALYTICS',       'Ask the analytics assistant about business data')
on conflict (code) do nothing;

insert into app.roles (tenant_id, code, name) values
  (null, 'owner',            'Business owner'),
  (null, 'regional_manager', 'Regional manager'),
  (null, 'branch_manager',   'Branch manager'),
  (null, 'cashier',          'Cashier'),
  (null, 'stock_clerk',      'Stock clerk')
on conflict (tenant_id, code) do nothing;

insert into app.role_permissions (role_id, permission_code)
select r.id, p.code
  from app.roles r
  join app.permissions p on
       (r.code = 'owner')
    or (r.code = 'regional_manager'
        and p.code not in ('BRANCH_MANAGE', 'CATALOG_MANAGE', 'SALE_CREATE', 'DISCOUNT_MANUAL'))
    or (r.code = 'branch_manager'
        and p.code in ('SALE_CREATE', 'LINE_VOID', 'SALE_VOID', 'REFUND_LINKED', 'REFUND_UNLINKED',
                       'PRICE_OVERRIDE', 'DISCOUNT_MANUAL', 'DRAWER_OPEN_MANUAL', 'SHIFT_MANAGE',
                       'STOCK_VIEW', 'STOCK_RECEIVE', 'STOCK_TRANSFER', 'STOCK_ADJUST', 'REPORT_VIEW',
                       'FRAUD_REVIEW', 'AI_ANALYTICS', 'LOYALTY_MANAGE'))
    or (r.code = 'cashier' and p.code in ('SALE_CREATE', 'REFUND_LINKED', 'STOCK_VIEW'))
    or (r.code = 'stock_clerk' and p.code in ('STOCK_VIEW', 'STOCK_RECEIVE', 'STOCK_TRANSFER', 'STOCK_ADJUST'))
 where r.tenant_id is null
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Request context and reach
-- ---------------------------------------------------------------------------

-- Validates, binds and seals the request context for the current transaction (ADR-004).
create function app.set_context(
  p_tenant_id    uuid default null,
  p_staff_id     uuid default null,
  p_branch_id    uuid default null,
  p_device_id    uuid default null,
  p_customer_id  uuid default null,
  p_system_actor text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_id     uuid := p_branch_id;
  v_device_branch uuid;
begin
  if p_tenant_id is null
     and (p_staff_id is not null or p_device_id is not null or p_branch_id is not null or p_system_actor is not null) then
    raise exception 'staff, device, branch and system contexts need a tenant' using errcode = '42501';
  end if;

  if p_tenant_id is not null
     and not exists (select 1 from app.tenants t where t.id = p_tenant_id and t.status = 'active') then
    raise exception 'tenant % is not active', p_tenant_id using errcode = '42501';
  end if;

  if p_staff_id is not null
     and not exists (select 1 from app.staff s
                      where s.id = p_staff_id and s.tenant_id = p_tenant_id and s.is_active) then
    raise exception 'staff % is not an active member of tenant %', p_staff_id, p_tenant_id using errcode = '42501';
  end if;

  if p_device_id is not null then
    select d.branch_id into v_device_branch
      from app.pos_devices d
     where d.id = p_device_id and d.tenant_id = p_tenant_id and d.is_active;
    if not found then
      raise exception 'device % is not an active device of tenant %', p_device_id, p_tenant_id using errcode = '42501';
    end if;
    if v_branch_id is null then
      v_branch_id := v_device_branch;
    elsif v_branch_id <> v_device_branch then
      raise exception 'device % belongs to branch %, not %', p_device_id, v_device_branch, v_branch_id
        using errcode = '42501';
    end if;
  end if;

  if v_branch_id is not null
     and not exists (select 1 from app.branches b where b.id = v_branch_id and b.tenant_id = p_tenant_id) then
    raise exception 'branch % is not part of tenant %', v_branch_id, p_tenant_id using errcode = '42501';
  end if;

  if p_customer_id is not null
     and not exists (select 1 from app.customers c where c.id = p_customer_id and c.deleted_at is null) then
    raise exception 'customer % does not exist', p_customer_id using errcode = '42501';
  end if;

  if p_system_actor is not null and p_system_actor !~ '^[a-z][a-z0-9_]{1,62}$' then
    raise exception 'invalid system actor name %', p_system_actor using errcode = '22023';
  end if;

  perform pg_catalog.set_config('app.current_tenant_id', coalesce(p_tenant_id::text, ''), true);
  perform pg_catalog.set_config('app.current_branch_id', coalesce(v_branch_id::text, ''), true);
  perform pg_catalog.set_config('app.current_staff_id', coalesce(p_staff_id::text, ''), true);
  perform pg_catalog.set_config('app.current_device_id', coalesce(p_device_id::text, ''), true);
  perform pg_catalog.set_config('app.current_customer_id', coalesce(p_customer_id::text, ''), true);
  perform pg_catalog.set_config('app.current_system_actor', coalesce(p_system_actor, ''), true);
  perform pg_catalog.set_config('app.context_seal', app_private.context_seal(array[
    coalesce(p_tenant_id::text, ''), coalesce(v_branch_id::text, ''), coalesce(p_staff_id::text, ''),
    coalesce(p_device_id::text, ''), coalesce(p_customer_id::text, ''), coalesce(p_system_actor, '')]), true);
end
$$;

-- Branches the current context may touch (spec §3.4). Derived from assignments in the
-- database, so a wrong branch sent by the backend can never widen access.
create function app.accessible_branch_ids() returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    -- one seal check, then the raw values (each reader would check again)
    select nullif(pg_catalog.current_setting('app.current_tenant_id', true), '')::uuid    as tenant_id,
           nullif(pg_catalog.current_setting('app.current_staff_id', true), '')::uuid     as staff_id,
           nullif(pg_catalog.current_setting('app.current_device_id', true), '')::uuid    as device_id,
           nullif(pg_catalog.current_setting('app.current_branch_id', true), '')::uuid    as branch_id,
           nullif(pg_catalog.current_setting('app.current_system_actor', true), '')       as system_actor
     where app.context_is_sealed()
  ),
  device_branch as (
    select d.branch_id
      from ctx
      join app.pos_devices d on d.id = ctx.device_id and d.tenant_id = ctx.tenant_id and d.is_active
  ),
  reach as (
    select b.id
      from ctx
      join app.branches b on b.tenant_id = ctx.tenant_id
     where ctx.system_actor is not null
    union
    select b.id
      from ctx
      join app.staff s on s.id = ctx.staff_id and s.tenant_id = ctx.tenant_id and s.is_active
      join app.staff_assignments sa on sa.staff_id = s.id and sa.tenant_id = s.tenant_id and sa.revoked_at is null
      join app.branches b on b.tenant_id = sa.tenant_id
                         and (sa.scope = 'tenant'
                              or (sa.scope = 'region' and b.region_id = sa.region_id)
                              or (sa.scope = 'branch' and b.id = sa.branch_id))
    union
    select db.branch_id
      from ctx, device_branch db
     where ctx.staff_id is null and ctx.system_actor is null
  )
  select coalesce(array_agg(r.id order by r.id), '{}')
    from reach r, ctx
   where (ctx.device_id is null or r.id in (select db.branch_id from device_branch db))
     and (ctx.branch_id is null or r.id = ctx.branch_id)
$$;

-- Role check bounded by space (hybrid branch-scoped RBAC). A NULL branch asks for
-- tenant-level authority; at a till, authority stops at the till's branch.
create function app.has_permission(p_permission text, p_branch_id uuid default null) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (app.current_device_id() is null
          or p_branch_id is null
          or exists (select 1 from app.pos_devices d
                      where d.id = app.current_device_id() and d.branch_id = p_branch_id))
     and exists (
       select 1
         from app.staff s
         join app.staff_assignments sa on sa.staff_id = s.id and sa.tenant_id = s.tenant_id and sa.revoked_at is null
         join app.role_permissions rp on rp.role_id = sa.role_id and rp.permission_code = p_permission
        where s.id = app.current_staff_id()
          and s.tenant_id = app.current_tenant_id()
          and s.is_active
          and case sa.scope
                when 'tenant' then
                  p_branch_id is null
                  or exists (select 1 from app.branches b where b.id = p_branch_id and b.tenant_id = sa.tenant_id)
                when 'region' then
                  exists (select 1 from app.branches b
                           where b.id = p_branch_id and b.tenant_id = sa.tenant_id and b.region_id = sa.region_id)
                else
                  sa.branch_id = p_branch_id
              end)
$$;

-- Granting is bounded by the grantor's own power (spec §3.4): STAFF_MANAGE over the
-- assignment's scope, and every permission of the granted role held there too. Region and
-- tenant assignments need tenant-wide authority.
create function app.can_grant(p_role_id uuid, p_scope text, p_branch_id uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_scope = 'branch' then
           app.has_permission('STAFF_MANAGE', p_branch_id)
           and not exists (select 1 from app.role_permissions rp
                            where rp.role_id = p_role_id
                              and not app.has_permission(rp.permission_code, p_branch_id))
         else
           app.has_permission('STAFF_MANAGE')
           and not exists (select 1 from app.role_permissions rp
                            where rp.role_id = p_role_id
                              and not app.has_permission(rp.permission_code))
         end
$$;

-- Managing a staff account (login, PIN, badge, active flag) needs STAFF_MANAGE over every
-- branch the person works in: tenant-wide authority for anyone, regional or branch authority
-- only for staff whose assignments all sit inside it (new staff have none yet).
create function app.can_manage_staff(p_staff_id uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app.has_permission('STAFF_MANAGE')
      or (exists (select 1 from app.branches b
                   where b.tenant_id = app.current_tenant_id()
                     and app.has_permission('STAFF_MANAGE', b.id))
          and not exists (select 1 from app.staff_assignments sa
                           where sa.staff_id = p_staff_id and sa.revoked_at is null
                             and (sa.scope <> 'branch' or not app.has_permission('STAFF_MANAGE', sa.branch_id))))
$$;

-- ---------------------------------------------------------------------------
-- Lookups the backend needs before a context exists
-- ---------------------------------------------------------------------------

create function app.staff_memberships(p_auth_user_id uuid)
returns table (staff_id uuid, tenant_id uuid, tenant_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, t.id, t.name
    from app.staff s
    join app.tenants t on t.id = s.tenant_id
   where s.auth_user_id = p_auth_user_id and s.is_active and t.status = 'active'
   order by t.name
$$;

create function app.customer_id_for_auth_user(p_auth_user_id uuid) returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id from app.customers c where c.auth_user_id = p_auth_user_id and c.deleted_at is null
$$;

create function app.authenticate_device(p_device_id uuid, p_api_key text)
returns table (tenant_id uuid, branch_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select d.tenant_id, d.branch_id
    from app.pos_devices d
    join app.pos_device_secrets ds on ds.device_id = d.id
    join app.tenants t on t.id = d.tenant_id
   where d.id = p_device_id
     and d.is_active
     and t.status = 'active'
     and ds.api_key_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_api_key, 'UTF8')), 'hex')
$$;

-- Finds a shopper by app account or phone, or creates one. The backend must have
-- verified the phone (OTP) before linking an app account to an existing phone.
create function app.register_customer(
  p_full_name    text,
  p_phone        text,
  p_email        text default null,
  p_auth_user_id uuid default null,
  p_language     text default 'ar'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      uuid;
  v_auth_id uuid;
begin
  if p_auth_user_id is not null then
    select c.id into v_id from app.customers c where c.auth_user_id = p_auth_user_id;
    if found then
      return v_id;
    end if;
  end if;

  select c.id, c.auth_user_id into v_id, v_auth_id from app.customers c where c.phone = p_phone for update;
  if found then
    if p_auth_user_id is not null then
      if v_auth_id is not null then
        raise exception 'phone % already belongs to another account', p_phone using errcode = '23505';
      end if;
      update app.customers c
         set auth_user_id = p_auth_user_id,
             email = coalesce(c.email, p_email)
       where c.id = v_id;
    end if;
    return v_id;
  end if;

  insert into app.customers (full_name, phone, email, auth_user_id, preferred_language)
  values (p_full_name, p_phone, p_email, p_auth_user_id, p_language)
  on conflict (phone) do nothing
  returning id into v_id;

  if v_id is null then
    select c.id into v_id from app.customers c where c.phone = p_phone;
  end if;
  return v_id;
end
$$;

-- Self-service onboarding (UC-01): one tenant, its owner, tenant-wide ownership.
create function app.provision_tenant(
  p_name               text,
  p_owner_full_name    text,
  p_owner_auth_user_id uuid,
  p_owner_email        text default null,
  p_default_language   text default 'ar'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_staff_id  uuid;
begin
  insert into app.tenants (name, default_language)
  values (p_name, p_default_language)
  returning id into v_tenant_id;

  insert into app.staff (tenant_id, auth_user_id, full_name, email)
  values (v_tenant_id, p_owner_auth_user_id, p_owner_full_name, p_owner_email)
  returning id into v_staff_id;

  insert into app.staff_assignments (tenant_id, staff_id, role_id, scope)
  select v_tenant_id, v_staff_id, r.id, 'tenant'
    from app.roles r
   where r.tenant_id is null and r.code = 'owner';

  return v_tenant_id;
end
$$;

-- ---------------------------------------------------------------------------
-- Row level security (spec §3.5)
-- ---------------------------------------------------------------------------

alter table app.tenants enable row level security;
alter table app.regions enable row level security;
alter table app.branches enable row level security;
alter table app.staff enable row level security;
alter table app.permissions enable row level security;
alter table app.roles enable row level security;
alter table app.role_permissions enable row level security;
alter table app.staff_assignments enable row level security;
alter table app.customers enable row level security;
alter table app.customer_payment_methods enable row level security;
alter table app.pos_devices enable row level security;
alter table app.pos_device_secrets enable row level security;

create policy tenants_read on app.tenants for select
  using (id = (select app.current_tenant_id()));
-- Role checks are the backend's job (spec §3.4), except authority over the business itself:
-- tenant and branch configuration, staff accounts and role grants are enforced here, so a
-- backend bug cannot let staff escalate their own power or take over someone else's account.
create policy tenants_update on app.tenants for update
  using (id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')))
  with check (id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')));

create policy regions_read on app.regions for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy regions_insert on app.regions for insert
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')));
create policy regions_update on app.regions for update
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')));
create policy regions_delete on app.regions for delete
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')));

create policy branches_read on app.branches for select
  using (tenant_id = (select app.current_tenant_id()));
create policy branches_insert on app.branches for insert
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')));
create policy branches_update on app.branches for update
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')));
create policy branches_delete on app.branches for delete
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('BRANCH_MANAGE')));

create policy staff_read on app.staff for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy staff_insert on app.staff for insert
  with check (tenant_id = (select app.current_tenant_id()) and app.can_manage_staff(id));
create policy staff_update on app.staff for update
  using (tenant_id = (select app.current_tenant_id()) and app.can_manage_staff(id))
  with check (tenant_id = (select app.current_tenant_id()) and app.can_manage_staff(id));
create policy staff_delete on app.staff for delete
  using (tenant_id = (select app.current_tenant_id()) and app.can_manage_staff(id));

create policy permissions_read on app.permissions for select using (true);

create policy roles_read on app.roles for select
  using ((select app.is_internal()) and (tenant_id is null or tenant_id = (select app.current_tenant_id())));
create policy roles_insert on app.roles for insert
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('STAFF_MANAGE')));
create policy roles_update on app.roles for update
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('STAFF_MANAGE')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('STAFF_MANAGE')));
create policy roles_delete on app.roles for delete
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('STAFF_MANAGE')));

create policy role_permissions_read on app.role_permissions for select
  using (exists (select 1 from app.roles r where r.id = role_id));
-- A tenant role can only be given permissions its editor holds tenant-wide.
create policy role_permissions_insert on app.role_permissions for insert
  with check (exists (select 1 from app.roles r
                       where r.id = role_id and r.tenant_id = (select app.current_tenant_id()))
              and (select app.has_permission('STAFF_MANAGE'))
              and app.has_permission(permission_code));
create policy role_permissions_update on app.role_permissions for update
  using (exists (select 1 from app.roles r
                  where r.id = role_id and r.tenant_id = (select app.current_tenant_id()))
         and (select app.has_permission('STAFF_MANAGE')))
  with check (exists (select 1 from app.roles r
                       where r.id = role_id and r.tenant_id = (select app.current_tenant_id()))
              and (select app.has_permission('STAFF_MANAGE'))
              and app.has_permission(permission_code));
create policy role_permissions_delete on app.role_permissions for delete
  using (exists (select 1 from app.roles r
                  where r.id = role_id and r.tenant_id = (select app.current_tenant_id()))
         and (select app.has_permission('STAFF_MANAGE')));

create policy staff_assignments_read on app.staff_assignments for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy staff_assignments_insert on app.staff_assignments for insert
  with check (tenant_id = (select app.current_tenant_id()) and app.can_grant(role_id, scope, branch_id));
create policy staff_assignments_update on app.staff_assignments for update
  using (tenant_id = (select app.current_tenant_id()) and app.can_grant(role_id, scope, branch_id))
  with check (tenant_id = (select app.current_tenant_id()) and app.can_grant(role_id, scope, branch_id));
create policy staff_assignments_delete on app.staff_assignments for delete
  using (tenant_id = (select app.current_tenant_id()) and app.can_grant(role_id, scope, branch_id));

create policy customers_self on app.customers for select
  using (id = (select app.current_customer_id()));
create policy customers_self_update on app.customers for update
  using (id = (select app.current_customer_id()))
  with check (id = (select app.current_customer_id()));

create policy payment_methods_self on app.customer_payment_methods for all
  using (customer_id = (select app.current_customer_id()))
  with check (customer_id = (select app.current_customer_id()));

create policy pos_devices_branch on app.pos_devices for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

create policy pos_device_secrets_branch on app.pos_device_secrets for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select, update on app.tenants to market_backend;
grant select, insert, update, delete on
  app.regions, app.branches, app.staff, app.roles, app.role_permissions, app.staff_assignments,
  app.customer_payment_methods, app.pos_devices, app.pos_device_secrets
  to market_backend;
grant select on app.permissions to market_backend;
grant select, update on app.customers to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
grant execute on function app.accessible_branch_ids() to market_analytics_owner;
