-- Support, workflows, IT operations and campus services (paper 4.1, 4.3, 4.4, 4.5, 6.5).
-- Tickets cover problems, complaints and requests in one workflow; Complaint and Request
-- from the paper's data model are ticket kinds rather than separate tables.

create type public.ticket_kind as enum ('problem', 'complaint', 'request', 'it_support', 'advising', 'admission', 'academic');
create type public.ticket_status as enum ('open', 'in_progress', 'waiting_on_requester', 'escalated', 'resolved', 'closed');
create type public.ticket_priority as enum ('low', 'normal', 'high', 'urgent');
create type public.workflow_run_status as enum (
  'pending', 'awaiting_approval', 'approved', 'rejected', 'running', 'completed', 'failed'
);
create type public.incident_severity as enum ('sev1', 'sev2', 'sev3', 'sev4');
create type public.incident_status as enum ('open', 'investigating', 'mitigated', 'resolved');
create type public.detection_source as enum ('rule', 'anomaly_model', 'user_report', 'manual');
create type public.lost_item_kind as enum ('lost', 'found');
create type public.lost_item_status as enum ('open', 'claimed', 'returned', 'closed');
create type public.map_feature_kind as enum ('building', 'room', 'service', 'entrance', 'parking', 'point_of_interest');

create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.ticket_kind not null,
  category text,
  subject text not null,
  description text not null,
  status public.ticket_status not null default 'open',
  priority public.ticket_priority not null default 'normal',
  requester_id uuid not null default auth.uid(),
  assignee_id uuid,
  department_id uuid,
  -- Response-time target; filled from the priority when not given.
  sla_due_at timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  escalation_level smallint not null default 0 check (escalation_level >= 0),
  -- Suggested routing from the workflow assistant; a person confirms it (paper 7.7).
  ai_triage jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (requester_id, tenant_id) references public.users (id, tenant_id),
  foreign key (assignee_id, tenant_id) references public.users (id, tenant_id) on delete set null (assignee_id),
  foreign key (department_id, tenant_id) references public.departments (id, tenant_id) on delete set null (department_id)
);
create index on public.tickets (tenant_id, status, sla_due_at);
create index on public.tickets (requester_id, tenant_id);
create index on public.tickets (assignee_id, tenant_id);
create index on public.tickets (department_id, tenant_id);

create table public.ticket_comments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  ticket_id uuid not null,
  author_id uuid not null default auth.uid(),
  body text not null,
  -- Internal notes are visible to handlers only.
  is_internal boolean not null default false,
  attachments jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (ticket_id, tenant_id) references public.tickets (id, tenant_id) on delete cascade,
  foreign key (author_id, tenant_id) references public.users (id, tenant_id)
);
create index on public.ticket_comments (ticket_id, tenant_id, created_at);
create index on public.ticket_comments (author_id, tenant_id);

create function private.set_ticket_sla()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.sla_due_at is null then
    new.sla_due_at := new.created_at + case new.priority
      when 'urgent' then interval '4 hours'
      when 'high' then interval '1 day'
      when 'normal' then interval '3 days'
      else interval '5 days'
    end;
  end if;
  if new.status in ('resolved', 'closed') and new.resolved_at is null then
    new.resolved_at := now();
  end if;
  return new;
end;
$$;

create trigger tickets_sla before insert or update on public.tickets
  for each row execute function private.set_ticket_sla();
create trigger tickets_touch before update on public.tickets
  for each row execute function private.touch_updated_at();

create function private.handles_ticket(p_ticket uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('support.manage')
    or exists (
      select 1 from public.tickets t
      where t.id = p_ticket
        and (
          t.assignee_id = (select auth.uid())
          or (t.kind = 'advising' and private.advises(t.requester_id))
        )
    )
$$;

create function private.requested_ticket(p_ticket uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.tickets t where t.id = p_ticket and t.requester_id = (select auth.uid()))
$$;

-- Routine approvals and notifications (paper 4.3, 7.7). Steps that change a record or send an
-- official decision need human approval before the run continues.
create table public.workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  key text not null,
  name text not null,
  description text,
  trigger_spec jsonb not null,
  steps jsonb not null,
  requires_human_approval boolean not null default true,
  is_active boolean not null default false,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, key)
);

create table public.workflow_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  definition_id uuid not null,
  ticket_id uuid,
  status public.workflow_run_status not null default 'pending',
  context jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  approved_by uuid,
  approved_at timestamptz,
  error text,
  foreign key (definition_id, tenant_id) references public.workflow_definitions (id, tenant_id),
  foreign key (ticket_id, tenant_id) references public.tickets (id, tenant_id) on delete set null (ticket_id)
);
create index on public.workflow_runs (definition_id, tenant_id);
create index on public.workflow_runs (ticket_id, tenant_id);
create index on public.workflow_runs (tenant_id, status);

create trigger workflow_definitions_audit after insert or update or delete on public.workflow_definitions
  for each row execute function private.audit_row_change();
create trigger workflow_runs_audit after update of status on public.workflow_runs
  for each row execute function private.audit_row_change();

-- IT incidents (paper 4.4, 7.8). Metrics, logs and traces live in the observability stack;
-- this is the record of what happened and who owns it.
create table public.incidents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  title text not null,
  severity public.incident_severity not null,
  status public.incident_status not null default 'open',
  detected_by public.detection_source not null,
  affected_service text,
  started_at timestamptz not null default now(),
  resolved_at timestamptz,
  summary text,
  -- Drafted by the log summariser; alert decisions stay rule- or model-based.
  ai_summary text,
  owner_id uuid,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (owner_id, tenant_id) references public.users (id, tenant_id) on delete set null (owner_id)
);
create index on public.incidents (tenant_id, status, started_at desc);
create index on public.incidents (owner_id, tenant_id);

create table public.incident_tickets (
  incident_id uuid not null,
  ticket_id uuid not null,
  tenant_id uuid not null,
  primary key (incident_id, ticket_id),
  foreign key (incident_id, tenant_id) references public.incidents (id, tenant_id) on delete cascade,
  foreign key (ticket_id, tenant_id) references public.tickets (id, tenant_id) on delete cascade
);
create index on public.incident_tickets (ticket_id, tenant_id);

create table public.lost_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.lost_item_kind not null,
  title text not null,
  description text,
  category text,
  photo_path text,
  building_id uuid,
  location_text text,
  occurred_at timestamptz,
  status public.lost_item_status not null default 'open',
  -- Contact happens through the platform's direct messages, not shared phone numbers.
  reporter_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  foreign key (building_id, tenant_id) references public.buildings (id, tenant_id) on delete set null (building_id),
  foreign key (reporter_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.lost_items (tenant_id, status, created_at desc);
create index on public.lost_items (building_id, tenant_id);
create index on public.lost_items (reporter_id, tenant_id);

create table public.map_features (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.map_feature_kind not null,
  name text not null,
  description text,
  building_id uuid,
  room_id uuid,
  floor text,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  -- GeoJSON geometry for outlines and paths.
  geometry jsonb,
  is_accessible boolean not null default true,
  foreign key (building_id, tenant_id) references public.buildings (id, tenant_id) on delete cascade,
  foreign key (room_id, tenant_id) references public.rooms (id, tenant_id) on delete cascade
);
create index on public.map_features (tenant_id, kind);
create index on public.map_features (building_id, tenant_id);
create index on public.map_features (room_id, tenant_id);

create table public.emergency_alerts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  title text not null,
  body text not null,
  severity public.severity not null default 'emergency',
  -- Null for the whole campus.
  building_id uuid,
  issued_by uuid not null default auth.uid(),
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  cancelled_at timestamptz,
  unique (id, tenant_id),
  foreign key (building_id, tenant_id) references public.buildings (id, tenant_id) on delete set null (building_id),
  foreign key (issued_by, tenant_id) references public.users (id, tenant_id)
);
create index on public.emergency_alerts (tenant_id, issued_at desc);
create index on public.emergency_alerts (building_id, tenant_id);
create index on public.emergency_alerts (issued_by, tenant_id);

-- Delivery tracking per person and channel (paper 4.5).
create table public.emergency_alert_deliveries (
  alert_id uuid not null,
  user_id uuid not null,
  channel text not null check (channel in ('push', 'sms', 'email', 'in_app')),
  tenant_id uuid not null,
  delivered_at timestamptz,
  failed_reason text,
  acknowledged_at timestamptz,
  primary key (alert_id, user_id, channel),
  foreign key (alert_id, tenant_id) references public.emergency_alerts (id, tenant_id) on delete cascade,
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.emergency_alert_deliveries (user_id, tenant_id);

create trigger emergency_alerts_audit after insert or update on public.emergency_alerts
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.tickets enable row level security;
alter table public.ticket_comments enable row level security;
alter table public.workflow_definitions enable row level security;
alter table public.workflow_runs enable row level security;
alter table public.incidents enable row level security;
alter table public.incident_tickets enable row level security;
alter table public.lost_items enable row level security;
alter table public.map_features enable row level security;
alter table public.emergency_alerts enable row level security;
alter table public.emergency_alert_deliveries enable row level security;

create policy "requesters and handlers read tickets" on public.tickets
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (requester_id = (select auth.uid()) or private.handles_ticket(id))
  );
create policy "members open tickets for themselves" on public.tickets
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and requester_id = (select auth.uid())
    and status = 'open'
    and assignee_id is null
    and escalation_level = 0
  );
create policy "handlers work tickets" on public.tickets
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.handles_ticket(id))
  with check (tenant_id = (select private.tenant_id()));

create policy "requesters read public comments, handlers read all" on public.ticket_comments
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.handles_ticket(ticket_id)
      or (not is_internal and private.requested_ticket(ticket_id))
    )
  );
create policy "requesters and handlers comment" on public.ticket_comments
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and author_id = (select auth.uid())
    and (
      private.handles_ticket(ticket_id)
      or (not is_internal and private.requested_ticket(ticket_id))
    )
  );

create policy "workflow managers manage definitions" on public.workflow_definitions
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('workflows.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('workflows.manage')));

-- Runs are created by the workflow worker; managers read them and approve or reject them.
create policy "workflow managers read runs" on public.workflow_runs
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('workflows.manage')));
create policy "workflow managers approve or reject runs" on public.workflow_runs
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('workflows.manage'))
    and status = 'awaiting_approval'
  )
  with check (
    tenant_id = (select private.tenant_id())
    and status in ('approved', 'rejected')
    and approved_by = (select auth.uid())
  );

create policy "ops staff manage incidents" on public.incidents
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('ops.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('ops.manage')));
create policy "ops staff link incidents and tickets" on public.incident_tickets
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('ops.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('ops.manage')));

create policy "members read lost and found" on public.lost_items
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "members post lost and found items" on public.lost_items
  for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and reporter_id = (select auth.uid()));
create policy "reporters and moderators update items" on public.lost_items
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (reporter_id = (select auth.uid()) or (select private.has_permission('campus.manage')))
  )
  with check (tenant_id = (select private.tenant_id()));
create policy "reporters and moderators remove items" on public.lost_items
  for delete to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (reporter_id = (select auth.uid()) or (select private.has_permission('campus.manage')))
  );

create policy "members read the campus map" on public.map_features
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "campus managers edit the map" on public.map_features
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('campus.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('campus.manage')));

create policy "members read emergency alerts" on public.emergency_alerts
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "authorised staff issue emergency alerts" on public.emergency_alerts
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('emergency.publish'))
    and issued_by = (select auth.uid())
  );
create policy "authorised staff update emergency alerts" on public.emergency_alerts
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('emergency.publish')))
  with check (tenant_id = (select private.tenant_id()));

create policy "recipients and issuers read deliveries" on public.emergency_alert_deliveries
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (user_id = (select auth.uid()) or (select private.has_permission('emergency.publish')))
  );
create policy "recipients acknowledge alerts" on public.emergency_alert_deliveries
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));

-- Handlers work a ticket; who raised it and when stay fixed.
revoke update on public.tickets from authenticated;
grant update (
  kind, category, subject, status, priority, assignee_id, department_id, sla_due_at,
  first_response_at, resolved_at, escalation_level, ai_triage
) on public.tickets to authenticated;

revoke update on public.emergency_alert_deliveries from authenticated;
grant update (acknowledged_at) on public.emergency_alert_deliveries to authenticated;
