-- Communication (paper 4.1, 4.2, 4.5, 5.2, 6.5): course chat groups and direct messages,
-- moderation, announcements, events and registrations, surveys, office hours, appointments
-- and notifications.

create type public.channel_kind as enum ('course', 'direct', 'group');
create type public.channel_role as enum ('owner', 'moderator', 'member');
create type public.report_status as enum ('open', 'actioned', 'dismissed');
create type public.announcement_audience as enum ('tenant', 'department', 'offering', 'section', 'role');
create type public.announcement_priority as enum ('normal', 'important');
create type public.event_kind as enum ('activity', 'event', 'workshop', 'club', 'career');
create type public.registration_status as enum ('registered', 'waitlisted', 'cancelled', 'attended');
create type public.appointment_status as enum ('requested', 'confirmed', 'cancelled', 'completed', 'no_show');
create type public.meeting_mode as enum ('in_person', 'online');
create type public.severity as enum ('info', 'warning', 'critical', 'emergency');

-- One course channel per offering replaces the external chat group (paper 5.2).
create table public.channels (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.channel_kind not null,
  offering_id uuid,
  name text,
  -- For direct channels: the two member ids in sorted order, so each pair has one channel.
  direct_key text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, tenant_id),
  unique (tenant_id, direct_key),
  check ((kind = 'course') = (offering_id is not null)),
  check ((kind = 'direct') = (direct_key is not null)),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade
);
create unique index channels_one_per_offering on public.channels (offering_id) where kind = 'course';

create table public.channel_members (
  channel_id uuid not null,
  user_id uuid not null,
  tenant_id uuid not null,
  role public.channel_role not null default 'member',
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  -- Set by the member: no notifications from this channel until then.
  notifications_muted_until timestamptz,
  -- Set by a moderator: the member cannot post until then.
  posting_blocked_until timestamptz,
  primary key (channel_id, user_id),
  foreign key (channel_id, tenant_id) references public.channels (id, tenant_id) on delete cascade,
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.channel_members (user_id, tenant_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  channel_id uuid not null,
  sender_id uuid not null,
  body text not null check (length(body) <= 10000),
  attachments jsonb not null default '[]'::jsonb,
  reply_to_id uuid,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  -- Hidden by a moderator.
  is_hidden boolean not null default false,
  unique (id, tenant_id),
  foreign key (channel_id, tenant_id) references public.channels (id, tenant_id) on delete cascade,
  foreign key (sender_id, tenant_id) references public.users (id, tenant_id),
  foreign key (reply_to_id, tenant_id) references public.messages (id, tenant_id) on delete set null (reply_to_id)
);
create index on public.messages (channel_id, created_at desc);
create index on public.messages (channel_id, tenant_id);
create index on public.messages (sender_id, tenant_id);
create index on public.messages (reply_to_id, tenant_id);

create table public.message_reports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  message_id uuid not null,
  reporter_id uuid not null,
  reason text not null,
  status public.report_status not null default 'open',
  handled_by uuid,
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  unique (message_id, reporter_id),
  foreign key (message_id, tenant_id) references public.messages (id, tenant_id) on delete cascade,
  foreign key (reporter_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.message_reports (message_id, tenant_id);
create index on public.message_reports (reporter_id, tenant_id);

create function private.is_staff_user(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.users u
    where u.id = p_user and u.tenant_id = private.tenant_id() and u.user_type <> 'student' and u.status = 'active'
  )
$$;

create function private.is_channel_member(p_channel uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.channel_members cm
    where cm.channel_id = p_channel and cm.user_id = (select auth.uid())
  )
$$;

create function private.moderates_channel(p_channel uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.channel_members cm
    where cm.channel_id = p_channel and cm.user_id = (select auth.uid()) and cm.role in ('owner', 'moderator')
  )
$$;

create function private.can_post(p_channel uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.channel_members cm
    join public.channels c on c.id = cm.channel_id
    where cm.channel_id = p_channel
      and cm.user_id = (select auth.uid())
      and c.archived_at is null
      and (cm.posting_blocked_until is null or cm.posting_blocked_until < now())
  )
$$;

-- Course channels are created with the offering. Members follow enrolment: students join
-- when enrolled and leave when they drop; teachers join as moderators.
create function private.create_course_channel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.channels (tenant_id, kind, offering_id, name)
  select new.tenant_id, 'course', new.id, c.code || ' ' || c.title
  from public.courses c where c.id = new.course_id;
  return null;
end;
$$;

create trigger course_offerings_channel after insert on public.course_offerings
  for each row execute function private.create_course_channel();

create function private.sync_course_channel_student()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.enrollments := coalesce(new, old);
  v_channel uuid;
begin
  select c.id into v_channel from public.channels c where c.kind = 'course' and c.offering_id = v_row.offering_id;
  if v_channel is null then
    return null;
  end if;

  if tg_op <> 'DELETE' and new.status = 'enrolled' then
    insert into public.channel_members (channel_id, user_id, tenant_id)
    values (v_channel, new.student_id, new.tenant_id)
    on conflict do nothing;
  elsif not exists (
    select 1 from public.enrollments e
    where e.offering_id = v_row.offering_id and e.student_id = v_row.student_id and e.status = 'enrolled'
  ) then
    delete from public.channel_members
    where channel_id = v_channel and user_id = v_row.student_id and role = 'member';
  end if;
  return null;
end;
$$;

create trigger enrollments_course_channel after insert or update of status or delete on public.enrollments
  for each row execute function private.sync_course_channel_student();

create function private.sync_course_channel_teacher()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.section_instructors := coalesce(new, old);
  v_channel uuid;
begin
  select c.id into v_channel
  from public.channels c join public.sections s on s.offering_id = c.offering_id
  where c.kind = 'course' and s.id = v_row.section_id;
  if v_channel is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    insert into public.channel_members (channel_id, user_id, tenant_id, role)
    values (v_channel, new.user_id, new.tenant_id, 'moderator')
    on conflict (channel_id, user_id) do update set role = 'moderator';
  elsif not exists (
    select 1 from public.section_instructors si
    join public.sections s on s.id = si.section_id
    join public.channels c on c.offering_id = s.offering_id
    where c.id = v_channel and si.user_id = old.user_id
  ) then
    delete from public.channel_members where channel_id = v_channel and user_id = old.user_id;
  end if;
  return null;
end;
$$;

create trigger section_instructors_course_channel after insert or delete on public.section_instructors
  for each row execute function private.sync_course_channel_teacher();

-- Starts (or returns) the direct channel between the caller and another user, if the other
-- user's privacy settings allow the caller to message them.
create function public.start_direct_channel(p_other uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_tenant uuid := private.tenant_id();
  v_other public.users;
  v_key text;
  v_channel uuid;
begin
  select * into v_other from public.users where id = p_other and tenant_id = v_tenant and status = 'active';
  if not found or p_other = v_me then
    raise exception 'User not found' using errcode = 'no_data_found';
  end if;
  if not private.field_visible_to_me(p_other, v_other.user_type, 'direct_messages') then
    raise exception 'This user does not accept direct messages from you' using errcode = 'insufficient_privilege';
  end if;

  v_key := least(v_me::text, p_other::text) || ':' || greatest(v_me::text, p_other::text);
  select id into v_channel from public.channels where tenant_id = v_tenant and direct_key = v_key;
  if v_channel is null then
    insert into public.channels (tenant_id, kind, direct_key)
    values (v_tenant, 'direct', v_key)
    on conflict (tenant_id, direct_key) do nothing
    returning id into v_channel;
    if v_channel is null then
      select id into v_channel from public.channels where tenant_id = v_tenant and direct_key = v_key;
    else
      insert into public.channel_members (channel_id, user_id, tenant_id)
      values (v_channel, v_me, v_tenant), (v_channel, p_other, v_tenant);
    end if;
  end if;
  return v_channel;
end;
$$;

revoke execute on function public.start_direct_channel(uuid) from public, anon;
grant execute on function public.start_direct_channel(uuid) to authenticated;

-- Senders edit and delete their own messages; only moderators hide them.
create function private.guard_message_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.channel_id, new.sender_id, new.created_at, new.reply_to_id)
     is distinct from (old.channel_id, old.sender_id, old.created_at, old.reply_to_id) then
    raise exception 'Only the body, deletion and visibility of a message can change' using errcode = 'insufficient_privilege';
  end if;
  if (new.body, new.attachments, new.deleted_at) is distinct from (old.body, old.attachments, old.deleted_at)
     and old.sender_id <> (select auth.uid()) then
    raise exception 'Only the sender can edit or delete a message' using errcode = 'insufficient_privilege';
  end if;
  if new.is_hidden is distinct from old.is_hidden and not private.moderates_channel(old.channel_id) then
    raise exception 'Only moderators can hide messages' using errcode = 'insufficient_privilege';
  end if;
  if new.deleted_at is not null and old.deleted_at is null then
    new.body := '';
    new.attachments := '[]'::jsonb;
  elsif new.body is distinct from old.body then
    new.edited_at := now();
  end if;
  return new;
end;
$$;

create trigger messages_guard before update on public.messages
  for each row when (auth.uid() is not null) execute function private.guard_message_update();

-- Members change their own read and notification state; only moderators change roles and blocks.
create function private.guard_channel_member_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.channel_id, new.user_id, new.tenant_id, new.joined_at)
     is distinct from (old.channel_id, old.user_id, old.tenant_id, old.joined_at) then
    raise exception 'Membership cannot be moved' using errcode = 'insufficient_privilege';
  end if;
  if (new.role, new.posting_blocked_until) is distinct from (old.role, old.posting_blocked_until)
     and not private.moderates_channel(old.channel_id) then
    raise exception 'Only moderators can change roles or block posting' using errcode = 'insufficient_privilege';
  end if;
  if (new.last_read_at, new.notifications_muted_until) is distinct from (old.last_read_at, old.notifications_muted_until)
     and old.user_id <> (select auth.uid()) then
    raise exception 'Members manage their own read and notification state' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger channel_members_guard before update on public.channel_members
  for each row when (auth.uid() is not null) execute function private.guard_channel_member_update();

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  audience public.announcement_audience not null,
  department_id uuid,
  offering_id uuid,
  section_id uuid,
  role_key text,
  title text not null,
  body text not null,
  priority public.announcement_priority not null default 'normal',
  attachments jsonb not null default '[]'::jsonb,
  publish_at timestamptz not null default now(),
  expires_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((audience = 'department') = (department_id is not null)),
  check ((audience = 'offering') = (offering_id is not null and section_id is null)),
  check ((audience = 'section') = (section_id is not null)),
  check ((audience = 'role') = (role_key is not null)),
  foreign key (department_id, tenant_id) references public.departments (id, tenant_id) on delete cascade,
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (section_id, tenant_id) references public.sections (id, tenant_id) on delete cascade
);
create index on public.announcements (tenant_id, publish_at desc);
create index on public.announcements (department_id, tenant_id);
create index on public.announcements (offering_id, tenant_id);
create index on public.announcements (section_id, tenant_id);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.event_kind not null default 'event',
  title text not null,
  description text,
  room_id uuid,
  location_text text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  capacity integer check (capacity > 0),
  waitlist_enabled boolean not null default true,
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,
  organizer_id uuid,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  check (ends_at > starts_at),
  foreign key (room_id, tenant_id) references public.rooms (id, tenant_id) on delete set null (room_id),
  foreign key (organizer_id, tenant_id) references public.users (id, tenant_id) on delete set null (organizer_id)
);
create index on public.events (tenant_id, starts_at);
create index on public.events (room_id, tenant_id);
create index on public.events (organizer_id, tenant_id);

create table public.event_registrations (
  event_id uuid not null,
  user_id uuid not null,
  tenant_id uuid not null,
  status public.registration_status not null,
  registered_at timestamptz not null default now(),
  primary key (event_id, user_id),
  foreign key (event_id, tenant_id) references public.events (id, tenant_id) on delete cascade,
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.event_registrations (user_id, tenant_id);

-- Registers the caller, or puts them on the waiting list when the event is full.
create function public.register_for_event(p_event uuid)
returns public.event_registrations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.events;
  v_taken integer;
  v_status public.registration_status;
  v_result public.event_registrations;
begin
  select * into v_event from public.events
  where id = p_event and tenant_id = private.tenant_id() and is_published
  for update;
  if not found then
    raise exception 'Event not found' using errcode = 'no_data_found';
  end if;
  if (v_event.registration_opens_at is not null and now() < v_event.registration_opens_at)
     or now() > coalesce(v_event.registration_closes_at, v_event.starts_at) then
    raise exception 'Registration is closed' using errcode = 'check_violation';
  end if;

  select count(*) into v_taken from public.event_registrations
  where event_id = p_event and status in ('registered', 'attended') and user_id <> auth.uid();
  if v_event.capacity is null or v_taken < v_event.capacity then
    v_status := 'registered';
  elsif v_event.waitlist_enabled then
    v_status := 'waitlisted';
  else
    raise exception 'This event is full' using errcode = 'check_violation';
  end if;

  insert into public.event_registrations (event_id, user_id, tenant_id, status)
  values (p_event, auth.uid(), v_event.tenant_id, v_status)
  on conflict (event_id, user_id) do update set status = excluded.status, registered_at = now()
  returning * into v_result;
  return v_result;
end;
$$;

revoke execute on function public.register_for_event(uuid) from public, anon;
grant execute on function public.register_for_event(uuid) to authenticated;

create table public.surveys (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  title text not null,
  description text,
  -- Null for a university-wide survey; otherwise a course evaluation.
  offering_id uuid,
  is_anonymous boolean not null default true,
  -- [{"key": "q1", "type": "rating|choice|text", "prompt": "...", "options": [...]}]
  questions jsonb not null,
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  check (closes_at > opens_at),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade
);
create index on public.surveys (offering_id, tenant_id);

-- Who has answered is stored apart from the answers, so anonymous answers carry no user id.
create table public.survey_participation (
  survey_id uuid not null,
  user_id uuid not null,
  tenant_id uuid not null,
  responded_at timestamptz not null default now(),
  primary key (survey_id, user_id),
  foreign key (survey_id, tenant_id) references public.surveys (id, tenant_id) on delete cascade,
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.survey_participation (user_id, tenant_id);

create table public.survey_responses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  survey_id uuid not null,
  respondent_id uuid,
  answers jsonb not null,
  submitted_at timestamptz not null default now(),
  foreign key (survey_id, tenant_id) references public.surveys (id, tenant_id) on delete cascade,
  foreign key (respondent_id, tenant_id) references public.users (id, tenant_id) on delete set null (respondent_id)
);
create index on public.survey_responses (survey_id, tenant_id);
create index on public.survey_responses (respondent_id, tenant_id);

create function public.submit_survey_response(p_survey uuid, p_answers jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_survey public.surveys;
begin
  select * into v_survey from public.surveys where id = p_survey and tenant_id = private.tenant_id();
  if not found or (v_survey.offering_id is not null and not private.enrolled_in_offering(v_survey.offering_id)) then
    raise exception 'Survey not found' using errcode = 'no_data_found';
  end if;
  if now() not between v_survey.opens_at and v_survey.closes_at then
    raise exception 'This survey is closed' using errcode = 'check_violation';
  end if;

  insert into public.survey_participation (survey_id, user_id, tenant_id)
  values (p_survey, auth.uid(), v_survey.tenant_id);

  insert into public.survey_responses (tenant_id, survey_id, respondent_id, answers, submitted_at)
  values (
    v_survey.tenant_id, p_survey,
    case when v_survey.is_anonymous then null else auth.uid() end,
    p_answers,
    -- Anonymous answers are dated to the day only, so timing cannot link them to a person.
    case when v_survey.is_anonymous then date_trunc('day', now()) else now() end
  );
exception
  when unique_violation then
    raise exception 'You have already answered this survey' using errcode = 'unique_violation';
end;
$$;

revoke execute on function public.submit_survey_response(uuid, jsonb) from public, anon;
grant execute on function public.submit_survey_response(uuid, jsonb) to authenticated;

create table public.office_hours (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  staff_id uuid not null,
  weekday smallint not null check (weekday between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  mode public.meeting_mode not null default 'in_person',
  location text,
  slot_minutes integer not null default 15 check (slot_minutes between 5 and 120),
  valid_from date not null default current_date,
  valid_until date,
  check (ends_at > starts_at),
  foreign key (staff_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.office_hours (staff_id, tenant_id);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  staff_id uuid not null,
  requester_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.appointment_status not null default 'requested',
  mode public.meeting_mode not null default 'in_person',
  topic text,
  location text,
  cancelled_by uuid,
  cancel_reason text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (staff_id <> requester_id),
  foreign key (staff_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (requester_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  constraint appointments_no_double_booking exclude using gist (
    staff_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status in ('requested', 'confirmed'))
);
create index on public.appointments (staff_id, tenant_id);
create index on public.appointments (requester_id, tenant_id);

-- The member of staff confirms and closes appointments; the requester can only cancel or
-- reschedule a request that has not been confirmed.
create function private.guard_appointment_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if (new.staff_id, new.requester_id, new.tenant_id) is distinct from (old.staff_id, old.requester_id, old.tenant_id) then
    raise exception 'The people on an appointment cannot change' using errcode = 'insufficient_privilege';
  end if;
  if v_me = old.requester_id and v_me <> old.staff_id then
    if new.status not in ('requested', 'cancelled')
       or (old.status <> 'requested' and (new.starts_at, new.ends_at) is distinct from (old.starts_at, old.ends_at)) then
      raise exception 'Requesters can cancel, or reschedule an unconfirmed request' using errcode = 'insufficient_privilege';
    end if;
  end if;
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    new.cancelled_by := v_me;
  end if;
  return new;
end;
$$;

create trigger appointments_guard before update on public.appointments
  for each row when (auth.uid() is not null) execute function private.guard_appointment_update();

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid not null,
  category text not null,
  severity public.severity not null default 'info',
  title text not null,
  body text,
  link text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.notifications (user_id, created_at desc);
create index on public.notifications (user_id, tenant_id);

create table public.notification_preferences (
  user_id uuid primary key,
  tenant_id uuid not null,
  -- {"<category>": ["in_app", "push", "email"]}. Emergency alerts ignore these choices.
  channels jsonb not null default '{}'::jsonb,
  quiet_hours_start time,
  quiet_hours_end time,
  timezone text,
  updated_at timestamptz not null default now(),
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);

create trigger announcements_touch before update on public.announcements
  for each row execute function private.touch_updated_at();
create trigger notification_preferences_touch before update on public.notification_preferences
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.channels enable row level security;
alter table public.channel_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reports enable row level security;
alter table public.announcements enable row level security;
alter table public.events enable row level security;
alter table public.event_registrations enable row level security;
alter table public.surveys enable row level security;
alter table public.survey_participation enable row level security;
alter table public.survey_responses enable row level security;
alter table public.office_hours enable row level security;
alter table public.appointments enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_preferences enable row level security;

create policy "members and creators read channels" on public.channels
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (private.is_channel_member(id) or created_by = (select auth.uid()))
  );
create policy "anyone can start a group channel" on public.channels
  for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and kind = 'group' and created_by = (select auth.uid()));
create policy "moderators rename and archive channels" on public.channels
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.moderates_channel(id))
  with check (tenant_id = (select private.tenant_id()));

create policy "members see who else is in the channel" on public.channel_members
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and private.is_channel_member(channel_id));
create policy "group owners add themselves and moderators add members" on public.channel_members
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.channels c
      where c.id = channel_members.channel_id
        and c.kind = 'group'
        and (
          private.moderates_channel(c.id)
          or (c.created_by = (select auth.uid()) and channel_members.user_id = (select auth.uid())
              and channel_members.role = 'owner')
        )
    )
  );
create policy "members update their own read and mute state" on public.channel_members
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));
create policy "moderators manage group members" on public.channel_members
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.moderates_channel(channel_id))
  with check (tenant_id = (select private.tenant_id()));
create policy "members leave groups and moderators remove members" on public.channel_members
  for delete to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.channels c where c.id = channel_members.channel_id and c.kind = 'group')
    and (user_id = (select auth.uid()) or private.moderates_channel(channel_id))
  );

create policy "members read visible messages" on public.messages
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and private.is_channel_member(channel_id)
    and (not is_hidden or sender_id = (select auth.uid()) or private.moderates_channel(channel_id))
  );
create policy "members post to open channels" on public.messages
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and sender_id = (select auth.uid())
    and not is_hidden
    and private.can_post(channel_id)
  );
create policy "senders and moderators update messages" on public.messages
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (sender_id = (select auth.uid()) or private.moderates_channel(channel_id))
  )
  with check (tenant_id = (select private.tenant_id()));

create policy "reporters and moderators read reports" on public.message_reports
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      reporter_id = (select auth.uid())
      or exists (
        select 1 from public.messages m
        where m.id = message_reports.message_id and private.moderates_channel(m.channel_id)
      )
    )
  );
create policy "members report messages they can see" on public.message_reports
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and reporter_id = (select auth.uid())
    and status = 'open'
    and exists (select 1 from public.messages m where m.id = message_reports.message_id)
  );
create policy "moderators handle reports" on public.message_reports
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.messages m
      where m.id = message_reports.message_id and private.moderates_channel(m.channel_id)
    )
  )
  with check (tenant_id = (select private.tenant_id()));

create policy "audiences read published announcements" on public.announcements
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      created_by = (select auth.uid())
      or (
        publish_at <= now()
        and (expires_at is null or expires_at > now())
        and (
          audience = 'tenant'
          or (audience = 'department' and private.in_department(department_id))
          or (audience = 'offering' and (private.enrolled_in_offering(offering_id) or private.teaches_offering(offering_id)))
          or (audience = 'section' and (private.enrolled_in_section(section_id) or private.teaches_section(section_id)))
          or (audience = 'role' and private.has_role(role_key))
        )
      )
    )
  );
create policy "teachers announce to their courses, publishers to everyone" on public.announcements
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('announcements.publish'))
      or (audience = 'offering' and private.teaches_offering(offering_id))
      or (audience = 'section' and private.teaches_section(section_id))
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('announcements.publish'))
      or (audience = 'offering' and private.teaches_offering(offering_id))
      or (audience = 'section' and private.teaches_section(section_id))
    )
  );

create policy "members read published events" on public.events
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (is_published or organizer_id = (select auth.uid()) or (select private.has_permission('events.manage')))
  );
create policy "event managers create events" on public.events
  for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('events.manage')));
create policy "event managers and organisers edit events" on public.events
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and ((select private.has_permission('events.manage')) or organizer_id = (select auth.uid()))
  )
  with check (tenant_id = (select private.tenant_id()));
create policy "event managers delete events" on public.events
  for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('events.manage')));

create policy "registrants and organisers read registrations" on public.event_registrations
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      user_id = (select auth.uid())
      or (select private.has_permission('events.manage'))
      or exists (
        select 1 from public.events e
        where e.id = event_registrations.event_id and e.organizer_id = (select auth.uid())
      )
    )
  );
create policy "registrants cancel their own registration" on public.event_registrations
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()) and status = 'cancelled');
create policy "organisers mark attendance" on public.event_registrations
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('events.manage'))
      or exists (
        select 1 from public.events e
        where e.id = event_registrations.event_id and e.organizer_id = (select auth.uid())
      )
    )
  )
  with check (tenant_id = (select private.tenant_id()));

create policy "audiences and authors read surveys" on public.surveys
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      created_by = (select auth.uid())
      or (select private.has_permission('surveys.manage'))
      or (offering_id is null and opens_at <= now())
      or (offering_id is not null and (private.enrolled_in_offering(offering_id) or private.teaches_offering(offering_id)))
    )
  );
create policy "survey managers and teachers write surveys" on public.surveys
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('surveys.manage'))
      or (offering_id is not null and private.teaches_offering(offering_id))
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('surveys.manage'))
      or (offering_id is not null and private.teaches_offering(offering_id))
    )
  );

create policy "respondents see what they have answered" on public.survey_participation
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));

-- Raw responses are for survey managers; feedback intelligence works on de-identified
-- summaries (paper 7.7).
create policy "survey managers and respondents read responses" on public.survey_responses
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and ((select private.has_permission('surveys.manage')) or respondent_id = (select auth.uid()))
  );

create policy "members read office hours" on public.office_hours
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "staff manage their own office hours" on public.office_hours
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and staff_id = (select auth.uid()))
  with check (
    tenant_id = (select private.tenant_id())
    and staff_id = (select auth.uid())
    and (select private.user_type()) <> 'student'
  );

create policy "both parties read an appointment" on public.appointments
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (requester_id = (select auth.uid()) or staff_id = (select auth.uid()))
  );
create policy "members request appointments with staff" on public.appointments
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and requester_id = (select auth.uid())
    and status = 'requested'
    and private.is_staff_user(staff_id)
  );
create policy "both parties update an appointment" on public.appointments
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (requester_id = (select auth.uid()) or staff_id = (select auth.uid()))
  )
  with check (tenant_id = (select private.tenant_id()));

create policy "users read their notifications" on public.notifications
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));
create policy "users mark their notifications read" on public.notifications
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));
create policy "users clear their notifications" on public.notifications
  for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));

create policy "users manage their notification preferences" on public.notification_preferences
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));

-- Moderators rename and archive channels; kind, course and pair stay fixed.
revoke update on public.channels from authenticated;
grant update (name, archived_at) on public.channels to authenticated;

-- Notifications are written by the backend; readers may only change read_at.
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
