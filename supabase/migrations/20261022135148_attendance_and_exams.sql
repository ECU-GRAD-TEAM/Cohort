-- Attendance and exams (paper 4.1, 4.3, 6.5): attendance sessions with a rotating QR code,
-- check-ins with a teacher-confirmed name-entry fallback, exam sessions and seat assignments.

create type public.attendance_status as enum ('present', 'late', 'absent', 'excused');
create type public.checkin_method as enum ('qr', 'name_entry', 'manual');
create type public.confirmation_status as enum ('confirmed', 'pending', 'rejected');
create type public.exam_mode as enum ('in_hall', 'online');

create table public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  section_id uuid not null,
  timetable_entry_id uuid,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  checkin_opens_at timestamptz not null,
  checkin_closes_at timestamptz not null,
  late_after_minutes integer not null default 10 check (late_after_minutes >= 0),
  -- Name entry is the fallback path; those check-ins wait for the teacher to confirm (paper 4.1).
  allow_name_entry boolean not null default true,
  qr_rotation_seconds integer not null default 30 check (qr_rotation_seconds between 10 and 300),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  check (ends_at > starts_at),
  check (checkin_closes_at > checkin_opens_at),
  foreign key (section_id, tenant_id) references public.sections (id, tenant_id) on delete cascade,
  foreign key (timetable_entry_id, tenant_id) references public.timetable_entries (id, tenant_id)
    on delete set null (timetable_entry_id)
);
create index on public.attendance_sessions (section_id, tenant_id, starts_at);
create index on public.attendance_sessions (timetable_entry_id, tenant_id);

-- QR secrets never leave the database: there are no grants on this table, and the private
-- schema is not exposed through the API.
create table private.attendance_secrets (
  session_id uuid primary key references public.attendance_sessions (id) on delete cascade,
  secret bytea not null default extensions.gen_random_bytes(32)
);
alter table private.attendance_secrets enable row level security;

create function private.create_attendance_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.attendance_secrets (session_id) values (new.id);
  return null;
end;
$$;

create trigger attendance_sessions_secret after insert on public.attendance_sessions
  for each row execute function private.create_attendance_secret();

create table public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  session_id uuid not null,
  student_id uuid not null,
  status public.attendance_status not null,
  method public.checkin_method not null,
  confirmation public.confirmation_status not null default 'confirmed',
  checked_in_at timestamptz,
  confirmed_by uuid,
  confirmed_at timestamptz,
  note text,
  unique (session_id, student_id),
  foreign key (session_id, tenant_id) references public.attendance_sessions (id, tenant_id) on delete cascade,
  foreign key (student_id, tenant_id) references public.users (id, tenant_id)
);
create index on public.attendance_records (student_id, tenant_id);
create index on public.attendance_records (session_id, tenant_id);

create trigger attendance_records_audit after update or delete on public.attendance_records
  for each row execute function private.audit_row_change();

create function private.attendance_token(p_session uuid, p_secret bytea, p_window bigint)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(encode(extensions.hmac(convert_to(p_session::text || ':' || p_window::text, 'UTF8'), p_secret, 'sha256'), 'hex'), 16)
$$;

-- The code the teacher's screen shows right now. Clients refresh it before valid_until.
create function public.attendance_qr_token(p_session uuid)
returns table (token text, valid_until timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session public.attendance_sessions;
  v_secret bytea;
  v_window bigint;
begin
  select * into v_session from public.attendance_sessions where id = p_session and tenant_id = private.tenant_id();
  if not found or not private.teaches_section(v_session.section_id) then
    raise exception 'Only the section''s teachers can display its code' using errcode = 'insufficient_privilege';
  end if;
  select s.secret into v_secret from private.attendance_secrets s where s.session_id = p_session;
  v_window := floor(extract(epoch from now()) / v_session.qr_rotation_seconds)::bigint;
  return query select
    private.attendance_token(p_session, v_secret, v_window),
    to_timestamp((v_window + 1) * v_session.qr_rotation_seconds);
end;
$$;

-- Students check in with the scanned code, or without one when name entry is allowed.
create function public.check_in(p_session uuid, p_token text default null)
returns public.attendance_records
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_session public.attendance_sessions;
  v_secret bytea;
  v_window bigint;
  v_method public.checkin_method;
  v_confirmation public.confirmation_status;
  v_status public.attendance_status;
  v_record public.attendance_records;
begin
  select * into v_session from public.attendance_sessions where id = p_session and tenant_id = private.tenant_id();
  if not found or not private.enrolled_in_section(v_session.section_id) then
    raise exception 'You are not enrolled in this section' using errcode = 'insufficient_privilege';
  end if;
  if now() not between v_session.checkin_opens_at and v_session.checkin_closes_at then
    raise exception 'Check-in is closed' using errcode = 'check_violation';
  end if;

  if p_token is not null then
    select s.secret into v_secret from private.attendance_secrets s where s.session_id = p_session;
    v_window := floor(extract(epoch from now()) / v_session.qr_rotation_seconds)::bigint;
    -- Accept the previous window too, so a code scanned just before it rotates still works.
    if lower(p_token) not in (
      private.attendance_token(p_session, v_secret, v_window),
      private.attendance_token(p_session, v_secret, v_window - 1)
    ) then
      raise exception 'This code has expired or is not valid' using errcode = 'check_violation';
    end if;
    v_method := 'qr';
    v_confirmation := 'confirmed';
  elsif v_session.allow_name_entry then
    v_method := 'name_entry';
    v_confirmation := 'pending';
  else
    raise exception 'Scan the code to check in' using errcode = 'check_violation';
  end if;

  v_status := case
    when now() > v_session.starts_at + make_interval(mins => v_session.late_after_minutes) then 'late'
    else 'present'
  end;

  insert into public.attendance_records (tenant_id, session_id, student_id, status, method, confirmation, checked_in_at)
  values (v_session.tenant_id, p_session, v_me, v_status, v_method, v_confirmation, now())
  on conflict (session_id, student_id) do update
    set status = excluded.status,
        method = excluded.method,
        confirmation = excluded.confirmation,
        checked_in_at = excluded.checked_in_at
    -- A record the teacher has already confirmed or set by hand stays as it is.
    where public.attendance_records.confirmation <> 'confirmed'
      and public.attendance_records.method <> 'manual'
  returning * into v_record;

  if v_record.id is null then
    select * into v_record from public.attendance_records where session_id = p_session and student_id = v_me;
  end if;
  return v_record;
end;
$$;

revoke execute on function public.attendance_qr_token(uuid), public.check_in(uuid, text) from public, anon;
grant execute on function public.attendance_qr_token(uuid), public.check_in(uuid, text) to authenticated;

create table public.exam_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  assessment_id uuid,
  title text not null,
  mode public.exam_mode not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  instructions text,
  -- Seat numbers become visible to students from this moment (paper 4.1).
  seats_released_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  check (ends_at > starts_at),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (assessment_id, tenant_id) references public.assessments (id, tenant_id) on delete set null (assessment_id)
);
create index on public.exam_sessions (offering_id, tenant_id);
create index on public.exam_sessions (assessment_id, tenant_id);
create index on public.exam_sessions (tenant_id, starts_at);

create table public.seat_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  exam_session_id uuid not null,
  student_id uuid not null,
  room_id uuid,
  seat_number text,
  unique (exam_session_id, student_id),
  unique (exam_session_id, room_id, seat_number),
  check ((room_id is null) = (seat_number is null)),
  foreign key (exam_session_id, tenant_id) references public.exam_sessions (id, tenant_id) on delete cascade,
  foreign key (student_id, tenant_id) references public.users (id, tenant_id),
  foreign key (room_id, tenant_id) references public.rooms (id, tenant_id)
);
create index on public.seat_assignments (student_id, tenant_id);
create index on public.seat_assignments (room_id, tenant_id);

-- Seats go only to students of the offering, and never beyond the room's exam capacity.
create function private.check_seat_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_capacity integer;
  v_taken integer;
begin
  if not exists (
    select 1
    from public.exam_sessions x
    join public.enrollments e on e.offering_id = x.offering_id
    where x.id = new.exam_session_id and e.student_id = new.student_id and e.status = 'enrolled'
  ) then
    raise exception 'The student is not enrolled in this course' using errcode = 'check_violation';
  end if;

  if new.room_id is not null then
    select coalesce(r.exam_capacity, r.capacity) into v_capacity from public.rooms r where r.id = new.room_id;
    select count(*) into v_taken
    from public.seat_assignments sa
    where sa.exam_session_id = new.exam_session_id and sa.room_id = new.room_id and sa.id <> new.id;
    if v_capacity is not null and v_taken >= v_capacity then
      raise exception 'The room is full for this exam' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger seat_assignments_check before insert or update on public.seat_assignments
  for each row execute function private.check_seat_assignment();
create trigger seat_assignments_audit after insert or update or delete on public.seat_assignments
  for each row execute function private.audit_row_change();
create trigger exam_sessions_audit after insert or update or delete on public.exam_sessions
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
alter table public.exam_sessions enable row level security;
alter table public.seat_assignments enable row level security;

create policy "teachers and enrolled students read attendance sessions" on public.attendance_sessions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (private.teaches_section(section_id) or private.enrolled_in_section(section_id))
  );
create policy "teachers write attendance sessions" on public.attendance_sessions
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_section(section_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_section(section_id));

-- Students check in through check_in(); teachers mark, confirm and correct records directly.
create policy "students, their teachers and advisors read attendance" on public.attendance_records
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.can_view_student(student_id)
      or exists (
        select 1 from public.attendance_sessions s
        where s.id = attendance_records.session_id and private.teaches_section(s.section_id)
      )
    )
  );
create policy "teachers write attendance" on public.attendance_records
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.attendance_sessions s
      where s.id = attendance_records.session_id and private.teaches_section(s.section_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.attendance_sessions s
      where s.id = attendance_records.session_id and private.teaches_section(s.section_id)
    )
  );

create policy "exam managers, teachers and students read exam sessions" on public.exam_sessions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('exams.manage'))
      or private.teaches_offering(offering_id)
      or private.enrolled_in_offering(offering_id)
    )
  );
create policy "exam managers write exam sessions" on public.exam_sessions
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('exams.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('exams.manage')));

create policy "exam managers and teachers read seat plans" on public.seat_assignments
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('exams.manage'))
      or exists (
        select 1 from public.exam_sessions x
        where x.id = seat_assignments.exam_session_id and private.teaches_offering(x.offering_id)
      )
    )
  );
create policy "students read their seat once released" on public.seat_assignments
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and student_id = (select auth.uid())
    and exists (
      select 1 from public.exam_sessions x
      where x.id = seat_assignments.exam_session_id and x.seats_released_at <= now()
    )
  );
create policy "exam managers write seat plans" on public.seat_assignments
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('exams.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('exams.manage')));
