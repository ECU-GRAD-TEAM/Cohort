-- Identity (paper 6.5, 6.6): tenants, users, roles and permissions, profiles, privacy, consent.
-- Each university is a tenant. A user is a Supabase Auth account that belongs to one tenant.
--
-- Conventions used by every migration:
--   * every table carries tenant_id;
--   * a reference to another tenant-scoped row is a composite foreign key on (row id, tenant_id),
--     so a row can never point at another tenant's data;
--   * row-level security is enabled on every table, and policies only grant access to the
--     authenticated role. The service role bypasses RLS and is reserved for backend workers.

create type public.tenant_status as enum ('active', 'suspended', 'offboarded');
create type public.user_type as enum ('student', 'teaching_staff', 'administrator', 'it_staff');
create type public.account_status as enum ('invited', 'active', 'suspended', 'graduated', 'archived');
create type public.audience as enum ('self', 'staff', 'tenant');
create type public.consent_purpose as enum (
  'ai_assistant',
  'chat_analytics',
  'risk_prediction_processing',
  'risk_prediction_display',
  'ai_grading',
  'parental_consent'
);

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  name text not null,
  country_code text check (country_code ~ '^[A-Z]{2}$'),
  -- Where this tenant's data must stay (paper 3.4, 8.1).
  data_region text not null,
  default_locale text not null default 'en',
  timezone text not null default 'UTC',
  -- Smallest group shown in analytics of student questions and feedback (paper 8.2).
  min_group_size integer not null default 10 check (min_group_size > 0),
  max_credits_per_term numeric(4, 1) not null default 21 check (max_credits_per_term > 0),
  settings jsonb not null default '{}'::jsonb,
  status public.tenant_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  tenant_id uuid not null references public.tenants (id),
  user_type public.user_type not null,
  status public.account_status not null default 'active',
  email text not null check (email = lower(email)),
  -- Student or staff number issued by the university.
  institutional_id text,
  is_minor boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, email),
  unique (tenant_id, institutional_id)
);

create table public.permissions (
  key text primary key check (key ~ '^[a-z_]+(\.[a-z_]+)+$'),
  description text not null
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  key text not null check (key ~ '^[a-z_]+$'),
  name text not null,
  description text,
  -- System roles are created with the tenant and cannot be deleted or have their permissions edited.
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, key)
);

create table public.role_permissions (
  role_id uuid not null,
  tenant_id uuid not null,
  permission_key text not null references public.permissions (key) on delete cascade,
  primary key (role_id, permission_key),
  foreign key (role_id, tenant_id) references public.roles (id, tenant_id) on delete cascade
);

create table public.user_roles (
  user_id uuid not null,
  role_id uuid not null,
  tenant_id uuid not null,
  granted_by uuid,
  granted_at timestamptz not null default now(),
  -- Set for just-in-time elevated access (paper 8.3).
  expires_at timestamptz,
  primary key (user_id, role_id),
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (role_id, tenant_id) references public.roles (id, tenant_id) on delete cascade
);
create index on public.user_roles (role_id, tenant_id);

create table public.person_profiles (
  user_id uuid primary key,
  tenant_id uuid not null,
  display_name text not null,
  first_name text,
  last_name text,
  title text,
  avatar_path text,
  bio text,
  phone text,
  personal_email text,
  date_of_birth date,
  office_location text,
  locale text,
  theme text not null default 'system' check (theme in ('system', 'light', 'dark')),
  updated_at timestamptz not null default now(),
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);

-- Who may see each profile field, and who may start a direct conversation (paper 4.1, 4.5).
create table public.privacy_settings (
  user_id uuid not null,
  tenant_id uuid not null,
  field text not null check (field in (
    'email', 'phone', 'personal_email', 'date_of_birth', 'avatar', 'bio', 'office_location',
    'direct_messages'
  )),
  audience public.audience not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, field),
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);

-- Append-only: the latest row per user and purpose is the current decision.
create table public.consent_records (
  id bigint generated always as identity primary key,
  tenant_id uuid not null,
  user_id uuid not null,
  purpose public.consent_purpose not null,
  granted boolean not null,
  -- Version of the consent text the user saw.
  policy_version text not null,
  -- Someone other than the user, for parental consent or a paper form entered by staff.
  recorded_by uuid,
  recorded_at timestamptz not null default now(),
  source text not null default 'app' check (source in ('app', 'paper', 'import')),
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.consent_records (user_id, tenant_id);
create index on public.consent_records (user_id, purpose, recorded_at desc);

create trigger tenants_touch before update on public.tenants
  for each row execute function private.touch_updated_at();
create trigger users_touch before update on public.users
  for each row execute function private.touch_updated_at();
create trigger person_profiles_touch before update on public.person_profiles
  for each row execute function private.touch_updated_at();
create trigger privacy_settings_touch before update on public.privacy_settings
  for each row execute function private.touch_updated_at();
create trigger consent_records_append_only before update or delete on public.consent_records
  for each row execute function private.reject_change();

-- ---------------------------------------------------------------------------
-- Request context helpers. SECURITY DEFINER lets them read identity tables without
-- recursing through those tables' own policies. Policies call them as
-- (select private.fn()) so Postgres evaluates them once per statement.
-- ---------------------------------------------------------------------------

create function private.tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.tenant_id
  from public.users u
  join public.tenants t on t.id = u.tenant_id
  where u.id = (select auth.uid())
    and u.status in ('invited', 'active', 'graduated')
    and t.status = 'active'
$$;

create function private.user_type()
returns public.user_type
language sql
stable
security definer
set search_path = ''
as $$
  select u.user_type from public.users u where u.id = (select auth.uid())
$$;

create function private.has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    where ur.user_id = (select auth.uid())
      and ur.tenant_id = private.tenant_id()
      and rp.permission_key = p_permission
      and (ur.expires_at is null or ur.expires_at > now())
  )
$$;

create function private.has_role(p_role_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = (select auth.uid())
      and ur.tenant_id = private.tenant_id()
      and r.key = p_role_key
      and (ur.expires_at is null or ur.expires_at > now())
  )
$$;

create function private.has_consent(p_user uuid, p_purpose public.consent_purpose)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select c.granted
    from public.consent_records c
    where c.user_id = p_user and c.purpose = p_purpose
    order by c.recorded_at desc, c.id desc
    limit 1
  ), false)
$$;

-- Default audience for a profile field when the user has not chosen one.
create function private.field_visible_to_me(p_owner uuid, p_owner_type public.user_type, p_field text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with chosen as (
    select coalesce(
      (select ps.audience from public.privacy_settings ps where ps.user_id = p_owner and ps.field = p_field),
      case
        when p_field in ('phone', 'personal_email', 'date_of_birth') then 'self'::public.audience
        when p_field = 'email' and p_owner_type = 'student' then 'staff'::public.audience
        else 'tenant'::public.audience
      end
    ) as audience
  )
  select p_owner = (select auth.uid())
    or audience = 'tenant'
    or (audience = 'staff' and private.user_type() <> 'student')
  from chosen
$$;

-- ---------------------------------------------------------------------------
-- Permission catalogue and tenant bootstrap.
-- Teaching, enrolment and advising access is attribute-based (who teaches or advises whom)
-- and is not expressed as permissions.
-- ---------------------------------------------------------------------------

insert into public.permissions (key, description) values
  ('tenant.settings.manage', 'Edit university-wide settings'),
  ('users.manage', 'Create, suspend and archive accounts; assign roles'),
  ('academic.manage', 'Manage faculties, departments, programmes, courses, terms, sections, rooms and timetables'),
  ('enrollment.manage', 'Manage registrations, waiting lists, withdrawals and advisor assignments'),
  ('grades.manage', 'Manage grade scales and academic standing'),
  ('exams.manage', 'Schedule exam sessions, assign halls and seats'),
  ('announcements.publish', 'Publish university-wide, department and role announcements'),
  ('events.manage', 'Create and manage activities and events'),
  ('surveys.manage', 'Create university-wide surveys and read raw responses'),
  ('support.manage', 'Triage and resolve tickets in every queue'),
  ('workflows.manage', 'Define workflow automations and approve their runs'),
  ('campus.manage', 'Manage the campus map and moderate lost and found'),
  ('emergency.publish', 'Send emergency notifications'),
  ('ai.settings.manage', 'Enable AI features, choose models, set budgets and prompt templates'),
  ('ai.knowledge.manage', 'Manage the institutional documents the assistants answer from'),
  ('analytics.view', 'View aggregate analytics and dashboards'),
  ('records.break_glass', 'Open an audited, time-limited view of an individual student record'),
  ('audit.read', 'Read audit and data access logs'),
  ('retention.manage', 'Manage retention schedules and legal holds'),
  ('ops.manage', 'Manage incidents and monitoring');

create function private.seed_tenant_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.roles (tenant_id, key, name, is_system) values
    (new.id, 'student', 'Student', true),
    (new.id, 'instructor', 'Instructor', true),
    (new.id, 'teaching_assistant', 'Teaching assistant', true),
    (new.id, 'advisor', 'Academic advisor', true),
    (new.id, 'administrator', 'Administrator', true),
    (new.id, 'it_staff', 'IT staff', true),
    (new.id, 'data_protection_officer', 'Data protection officer', true);

  insert into public.role_permissions (role_id, tenant_id, permission_key)
  select r.id, new.id, d.permission_key
  from (values
    ('administrator', 'tenant.settings.manage'),
    ('administrator', 'users.manage'),
    ('administrator', 'academic.manage'),
    ('administrator', 'enrollment.manage'),
    ('administrator', 'grades.manage'),
    ('administrator', 'exams.manage'),
    ('administrator', 'announcements.publish'),
    ('administrator', 'events.manage'),
    ('administrator', 'surveys.manage'),
    ('administrator', 'support.manage'),
    ('administrator', 'workflows.manage'),
    ('administrator', 'campus.manage'),
    ('administrator', 'emergency.publish'),
    ('administrator', 'ai.settings.manage'),
    ('administrator', 'ai.knowledge.manage'),
    ('administrator', 'analytics.view'),
    ('administrator', 'records.break_glass'),
    ('it_staff', 'users.manage'),
    ('it_staff', 'support.manage'),
    ('it_staff', 'ops.manage'),
    ('data_protection_officer', 'audit.read'),
    ('data_protection_officer', 'retention.manage')
  ) as d (role_key, permission_key)
  join public.roles r on r.tenant_id = new.id and r.key = d.role_key;

  return new;
end;
$$;

create trigger tenants_seed_roles after insert on public.tenants
  for each row execute function private.seed_tenant_roles();

-- Every new user gets a profile and the system role that matches their user type.
create function private.on_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.person_profiles (user_id, tenant_id, display_name)
  values (new.id, new.tenant_id, split_part(new.email, '@', 1))
  on conflict (user_id) do nothing;

  insert into public.user_roles (user_id, role_id, tenant_id)
  select new.id, r.id, new.tenant_id
  from public.roles r
  where r.tenant_id = new.tenant_id
    and r.key = case new.user_type
      when 'student' then 'student'
      when 'teaching_staff' then 'instructor'
      when 'administrator' then 'administrator'
      when 'it_staff' then 'it_staff'
    end
  on conflict do nothing;

  return new;
end;
$$;

create trigger users_on_created after insert on public.users
  for each row execute function private.on_user_created();

-- Accounts are provisioned by the backend (bulk import or invite) through Supabase Auth with
-- app_metadata = {"tenant_id": ..., "user_type": ..., "institutional_id": ...}.
-- app_metadata is only writable with the service role; user_metadata is user-editable and is
-- used for the display name only.
create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := nullif(new.raw_app_meta_data ->> 'tenant_id', '')::uuid;
  v_type public.user_type := nullif(new.raw_app_meta_data ->> 'user_type', '')::public.user_type;
begin
  if v_tenant is null or v_type is null then
    return new;
  end if;

  insert into public.users (id, tenant_id, user_type, email, institutional_id)
  values (new.id, v_tenant, v_type, lower(new.email), nullif(new.raw_app_meta_data ->> 'institutional_id', ''));

  update public.person_profiles
  set display_name = coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), display_name)
  where user_id = new.id;

  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_auth_user();

-- Directory search for "connect to any other user" (paper 4.5). Returns the whole tenant with
-- each field masked according to the owner's privacy settings.
create function public.directory_search(p_query text default null, p_limit integer default 50)
returns table (
  user_id uuid,
  user_type public.user_type,
  display_name text,
  title text,
  email text,
  phone text,
  avatar_path text,
  bio text,
  office_location text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    u.id,
    u.user_type,
    p.display_name,
    p.title,
    case when private.field_visible_to_me(u.id, u.user_type, 'email') then u.email end,
    case when private.field_visible_to_me(u.id, u.user_type, 'phone') then p.phone end,
    case when private.field_visible_to_me(u.id, u.user_type, 'avatar') then p.avatar_path end,
    case when private.field_visible_to_me(u.id, u.user_type, 'bio') then p.bio end,
    case when private.field_visible_to_me(u.id, u.user_type, 'office_location') then p.office_location end
  from public.users u
  join public.person_profiles p on p.user_id = u.id
  where u.tenant_id = private.tenant_id()
    and u.status = 'active'
    and (p_query is null or p.display_name ilike '%' || p_query || '%')
  order by p.display_name
  limit least(greatest(p_limit, 1), 200)
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.tenants enable row level security;
alter table public.users enable row level security;
alter table public.permissions enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.person_profiles enable row level security;
alter table public.privacy_settings enable row level security;
alter table public.consent_records enable row level security;

create policy "members read their tenant" on public.tenants
  for select to authenticated
  using (id = (select private.tenant_id()));
create policy "admins update their tenant" on public.tenants
  for update to authenticated
  using (id = (select private.tenant_id()) and (select private.has_permission('tenant.settings.manage')))
  with check (id = (select private.tenant_id()));

create policy "read own account or manage accounts" on public.users
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (id = (select auth.uid()) or (select private.has_permission('users.manage')))
  );
create policy "account managers insert" on public.users
  for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')));
create policy "account managers update" on public.users
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')))
  with check (tenant_id = (select private.tenant_id()));
create policy "account managers delete" on public.users
  for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')));

create policy "signed-in users read the catalogue" on public.permissions
  for select to authenticated
  using (true);

create policy "members read roles" on public.roles
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "account managers create roles" on public.roles
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('users.manage'))
    and not is_system
  );
create policy "account managers edit custom roles" on public.roles
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')) and not is_system)
  with check (tenant_id = (select private.tenant_id()) and not is_system);
create policy "account managers delete custom roles" on public.roles
  for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')) and not is_system);

create policy "members read role permissions" on public.role_permissions
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "account managers grant permissions to custom roles" on public.role_permissions
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('users.manage'))
    and exists (select 1 from public.roles r where r.id = role_permissions.role_id and not r.is_system)
  );
create policy "account managers revoke permissions from custom roles" on public.role_permissions
  for delete to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('users.manage'))
    and exists (select 1 from public.roles r where r.id = role_permissions.role_id and not r.is_system)
  );

create policy "read own roles or manage accounts" on public.user_roles
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (user_id = (select auth.uid()) or (select private.has_permission('users.manage')))
  );
create policy "account managers assign roles" on public.user_roles
  for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')));
create policy "account managers change role assignments" on public.user_roles
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')))
  with check (tenant_id = (select private.tenant_id()));
create policy "account managers remove roles" on public.user_roles
  for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')));

create policy "read own profile or manage accounts" on public.person_profiles
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (user_id = (select auth.uid()) or (select private.has_permission('users.manage')))
  );
create policy "account managers create profiles" on public.person_profiles
  for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')));
create policy "edit own profile or manage accounts" on public.person_profiles
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (user_id = (select auth.uid()) or (select private.has_permission('users.manage')))
  )
  with check (tenant_id = (select private.tenant_id()));

create policy "manage own privacy settings" on public.privacy_settings
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));
create policy "account managers read privacy settings" on public.privacy_settings
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('users.manage')));

create policy "read own consent or manage accounts" on public.consent_records
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      user_id = (select auth.uid())
      or (select private.has_permission('users.manage'))
      or (select private.has_permission('audit.read'))
    )
  );
create policy "record own consent" on public.consent_records
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and user_id = (select auth.uid())
    and recorded_by is null
  );
create policy "account managers record consent on behalf of a user" on public.consent_records
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('users.manage'))
    and recorded_by = (select auth.uid())
  );

revoke execute on function public.directory_search(text, integer) from public, anon;
grant execute on function public.directory_search(text, integer) to authenticated;
