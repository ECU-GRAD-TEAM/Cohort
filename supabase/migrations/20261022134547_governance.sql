-- Governance (paper 6.5, 6.6, 8.2, 8.3): audit log, data access log, break-glass access,
-- retention schedules and legal holds.

create type public.data_class as enum (
  'chat_messages',
  'ai_interactions',
  'submissions',
  'attendance_records',
  'notifications',
  'support_tickets',
  'survey_responses',
  'lost_items',
  'audit_log',
  'data_access_log'
);

-- Immutable record of grade changes, role changes, AI settings, admin actions and so on.
create table public.audit_log (
  id bigint generated always as identity primary key,
  tenant_id uuid references public.tenants (id),
  occurred_at timestamptz not null default now(),
  actor_id uuid,
  db_role text not null default current_user,
  action text not null,
  table_name text,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  reason text
);
create index on public.audit_log (tenant_id, occurred_at desc);
create index on public.audit_log (table_name, record_id);

-- An administrator sees aggregates by default and an individual record only through an
-- audited, reason-recorded action (paper 6.6). Each grant is short-lived.
create table public.record_access_grants (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  grantee_id uuid not null,
  subject_user_id uuid not null,
  reason text not null check (length(btrim(reason)) >= 10),
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  check (expires_at > granted_at),
  foreign key (grantee_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (subject_user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.record_access_grants (grantee_id, tenant_id);
create index on public.record_access_grants (subject_user_id, tenant_id);

create table public.data_access_log (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants (id),
  accessed_at timestamptz not null default now(),
  actor_id uuid not null,
  subject_user_id uuid not null,
  grant_id uuid references public.record_access_grants (id) on delete set null,
  action text not null,
  reason text not null
);
create index on public.data_access_log (tenant_id, accessed_at desc);
create index on public.data_access_log (subject_user_id);
create index on public.data_access_log (grant_id);

create table public.retention_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  data_class public.data_class not null,
  retain_days integer not null check (retain_days > 0),
  action text not null default 'delete' check (action in ('delete', 'anonymise')),
  legal_basis text,
  updated_at timestamptz not null default now(),
  unique (tenant_id, data_class)
);

create table public.legal_holds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  -- A hold covers one person, one data class, or both. At least one must be set.
  subject_user_id uuid,
  data_class public.data_class,
  reason text not null,
  placed_by uuid not null,
  placed_at timestamptz not null default now(),
  released_at timestamptz,
  check (subject_user_id is not null or data_class is not null),
  foreign key (subject_user_id, tenant_id) references public.users (id, tenant_id),
  foreign key (placed_by, tenant_id) references public.users (id, tenant_id)
);
create index on public.legal_holds (tenant_id);
create index on public.legal_holds (subject_user_id, tenant_id);
create index on public.legal_holds (placed_by, tenant_id);

create trigger audit_log_append_only before update or delete on public.audit_log
  for each row execute function private.reject_change();
create trigger data_access_log_append_only before update or delete on public.data_access_log
  for each row execute function private.reject_change();
create trigger retention_policies_touch before update on public.retention_policies
  for each row execute function private.touch_updated_at();

-- A grant can be revoked early but never extended or repointed.
create function private.guard_grant_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.tenant_id, new.grantee_id, new.subject_user_id, new.reason, new.granted_at, new.expires_at)
     is distinct from
     (old.tenant_id, old.grantee_id, old.subject_user_id, old.reason, old.granted_at, old.expires_at) then
    raise exception 'Only revoked_at can change on an access grant' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger record_access_grants_guard before update on public.record_access_grants
  for each row execute function private.guard_grant_update();

-- Generic row-change auditing. Attached by each migration to the tables it owns that
-- hold decisions about people: grades, roles, enrolments, AI settings and so on.
create function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
begin
  insert into public.audit_log (tenant_id, actor_id, action, table_name, record_id, old_data, new_data)
  values (
    case when tg_table_name = 'tenants' then (v_row ->> 'id')::uuid else (v_row ->> 'tenant_id')::uuid end,
    (select auth.uid()),
    lower(tg_op),
    tg_table_name,
    v_row ->> 'id',
    v_old,
    v_new
  );
  return null;
end;
$$;

create function private.has_record_grant(p_subject uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.record_access_grants g
    where g.grantee_id = (select auth.uid())
      and g.subject_user_id = p_subject
      and g.tenant_id = private.tenant_id()
      and g.revoked_at is null
      and now() between g.granted_at and g.expires_at
  )
$$;

-- Break-glass: open an individual student's records for a limited time, with a reason.
create function public.open_record_access(p_subject uuid, p_reason text, p_minutes integer default 60)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := private.tenant_id();
  v_grant uuid;
begin
  if v_tenant is null or not private.has_permission('records.break_glass') then
    raise exception 'Not allowed to open individual records' using errcode = 'insufficient_privilege';
  end if;
  if p_minutes not between 5 and 480 then
    raise exception 'Access must last between 5 and 480 minutes' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.users u where u.id = p_subject and u.tenant_id = v_tenant) then
    raise exception 'User not found' using errcode = 'no_data_found';
  end if;

  insert into public.record_access_grants (tenant_id, grantee_id, subject_user_id, reason, expires_at)
  values (v_tenant, auth.uid(), p_subject, p_reason, now() + make_interval(mins => p_minutes))
  returning id into v_grant;

  insert into public.data_access_log (tenant_id, actor_id, subject_user_id, grant_id, action, reason)
  values (v_tenant, auth.uid(), p_subject, v_grant, 'break_glass_opened', p_reason);

  return v_grant;
end;
$$;

revoke execute on function public.open_record_access(uuid, text, integer) from public, anon;
grant execute on function public.open_record_access(uuid, text, integer) to authenticated;

create trigger tenants_audit after update on public.tenants
  for each row when (old is distinct from new) execute function private.audit_row_change();
create trigger users_audit after insert or update or delete on public.users
  for each row execute function private.audit_row_change();
create trigger roles_audit after insert or update or delete on public.roles
  for each row execute function private.audit_row_change();
create trigger role_permissions_audit after insert or delete on public.role_permissions
  for each row execute function private.audit_row_change();
create trigger user_roles_audit after insert or update or delete on public.user_roles
  for each row execute function private.audit_row_change();
create trigger record_access_grants_audit after insert or update on public.record_access_grants
  for each row execute function private.audit_row_change();
create trigger retention_policies_audit after insert or update or delete on public.retention_policies
  for each row execute function private.audit_row_change();
create trigger legal_holds_audit after insert or update or delete on public.legal_holds
  for each row execute function private.audit_row_change();

alter table public.audit_log enable row level security;
alter table public.record_access_grants enable row level security;
alter table public.data_access_log enable row level security;
alter table public.retention_policies enable row level security;
alter table public.legal_holds enable row level security;

-- Rows are written only by triggers and security-definer functions, so there are no insert policies.
create policy "auditors read the audit log" on public.audit_log
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('audit.read')));

-- Students can see what is recorded about them, including who opened their record (paper 8.5).
create policy "auditors, actors and subjects read access entries" on public.data_access_log
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('audit.read'))
      or actor_id = (select auth.uid())
      or subject_user_id = (select auth.uid())
    )
  );

create policy "grantees and auditors read grants" on public.record_access_grants
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (grantee_id = (select auth.uid()) or (select private.has_permission('audit.read')))
  );
create policy "grantees and auditors revoke grants" on public.record_access_grants
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (grantee_id = (select auth.uid()) or (select private.has_permission('audit.read')))
  )
  with check (tenant_id = (select private.tenant_id()));

create policy "members read retention schedules" on public.retention_policies
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "retention managers write retention schedules" on public.retention_policies
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('retention.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('retention.manage')));

create policy "retention managers and auditors read legal holds" on public.legal_holds
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and ((select private.has_permission('retention.manage')) or (select private.has_permission('audit.read')))
  );
create policy "retention managers write legal holds" on public.legal_holds
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('retention.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('retention.manage')));
