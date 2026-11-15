-- Academic structure (paper 4.3, 6.5): faculties, departments, programmes, buildings and rooms,
-- terms and the academic calendar, courses, offerings, sections and the timetable.
-- Every member of a tenant can read this catalogue; academic.manage writes it.

create type public.degree_level as enum ('certificate', 'diploma', 'bachelor', 'master', 'doctorate');
create type public.room_type as enum ('lecture_hall', 'classroom', 'lab', 'exam_hall', 'office', 'other');
create type public.term_status as enum ('planned', 'registration', 'in_progress', 'completed');
create type public.calendar_event_kind as enum ('teaching', 'registration', 'add_drop', 'exam_period', 'holiday', 'deadline', 'other');
create type public.offering_status as enum ('draft', 'published', 'archived');
create type public.section_kind as enum ('lecture', 'lab', 'tutorial');
create type public.teaching_role as enum ('instructor', 'teaching_assistant');
create type public.prerequisite_kind as enum ('prerequisite', 'corequisite');
create type public.timerange as range (subtype = time);

create table public.faculties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  code text not null,
  name text not null,
  dean_id uuid,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, code),
  foreign key (dean_id, tenant_id) references public.users (id, tenant_id) on delete set null (dean_id)
);
create index on public.faculties (dean_id, tenant_id);

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  faculty_id uuid not null,
  code text not null,
  name text not null,
  head_id uuid,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, code),
  foreign key (faculty_id, tenant_id) references public.faculties (id, tenant_id),
  foreign key (head_id, tenant_id) references public.users (id, tenant_id) on delete set null (head_id)
);
create index on public.departments (faculty_id, tenant_id);
create index on public.departments (head_id, tenant_id);

create table public.programs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  department_id uuid not null,
  code text not null,
  name text not null,
  degree_level public.degree_level not null,
  total_credits numeric(5, 1) check (total_credits > 0),
  is_active boolean not null default true,
  unique (id, tenant_id),
  unique (tenant_id, code),
  foreign key (department_id, tenant_id) references public.departments (id, tenant_id)
);
create index on public.programs (department_id, tenant_id);

-- Staff belong to a home department; students belong through their programme.
alter table public.person_profiles add column department_id uuid;
alter table public.person_profiles
  add foreign key (department_id, tenant_id) references public.departments (id, tenant_id)
  on delete set null (department_id);
create index on public.person_profiles (department_id, tenant_id);

-- Department membership grants access to department-scoped content, so only account
-- managers can change it.
create function private.guard_profile_department()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.department_id is distinct from old.department_id
     and auth.uid() is not null
     and not private.has_permission('users.manage') then
    raise exception 'Only account managers can change a home department' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger person_profiles_guard_department before update of department_id on public.person_profiles
  for each row execute function private.guard_profile_department();

create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  code text not null,
  name text not null,
  address text,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  unique (id, tenant_id),
  unique (tenant_id, code)
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  building_id uuid not null,
  code text not null,
  name text,
  room_type public.room_type not null,
  floor text,
  capacity integer check (capacity >= 0),
  exam_capacity integer check (exam_capacity >= 0),
  is_accessible boolean not null default true,
  unique (id, tenant_id),
  unique (building_id, code),
  foreign key (building_id, tenant_id) references public.buildings (id, tenant_id)
);
create index on public.rooms (building_id, tenant_id);

create table public.terms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  code text not null,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,
  add_drop_ends_at timestamptz,
  status public.term_status not null default 'planned',
  unique (id, tenant_id),
  unique (tenant_id, code),
  check (ends_on > starts_on),
  check (registration_closes_at is null or registration_opens_at is null or registration_closes_at > registration_opens_at)
);

create table public.academic_calendar_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  term_id uuid,
  kind public.calendar_event_kind not null,
  title text not null,
  starts_on date not null,
  ends_on date not null,
  check (ends_on >= starts_on),
  foreign key (term_id, tenant_id) references public.terms (id, tenant_id) on delete cascade
);
create index on public.academic_calendar_events (term_id, tenant_id);
create index on public.academic_calendar_events (tenant_id, starts_on);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  department_id uuid not null,
  code text not null,
  title text not null,
  description text,
  credit_hours numeric(4, 1) not null check (credit_hours >= 0),
  level smallint,
  is_active boolean not null default true,
  unique (id, tenant_id),
  unique (tenant_id, code),
  foreign key (department_id, tenant_id) references public.departments (id, tenant_id)
);
create index on public.courses (department_id, tenant_id);

create table public.course_prerequisites (
  course_id uuid not null,
  prerequisite_course_id uuid not null,
  tenant_id uuid not null,
  kind public.prerequisite_kind not null default 'prerequisite',
  primary key (course_id, prerequisite_course_id),
  check (course_id <> prerequisite_course_id),
  foreign key (course_id, tenant_id) references public.courses (id, tenant_id) on delete cascade,
  foreign key (prerequisite_course_id, tenant_id) references public.courses (id, tenant_id) on delete cascade
);
create index on public.course_prerequisites (prerequisite_course_id, tenant_id);

-- A course taught in a given term. Grade scale and channel links are added by later migrations.
create table public.course_offerings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  course_id uuid not null,
  term_id uuid not null,
  coordinator_id uuid,
  status public.offering_status not null default 'draft',
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (course_id, term_id),
  foreign key (course_id, tenant_id) references public.courses (id, tenant_id),
  foreign key (term_id, tenant_id) references public.terms (id, tenant_id),
  foreign key (coordinator_id, tenant_id) references public.users (id, tenant_id) on delete set null (coordinator_id)
);
create index on public.course_offerings (course_id, tenant_id);
create index on public.course_offerings (term_id, tenant_id);
create index on public.course_offerings (coordinator_id, tenant_id);

create table public.sections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  code text not null,
  kind public.section_kind not null default 'lecture',
  capacity integer check (capacity >= 0),
  waitlist_capacity integer not null default 0 check (waitlist_capacity >= 0),
  unique (id, tenant_id),
  -- Lets enrolments carry offering_id and still be checked against their section.
  unique (id, tenant_id, offering_id),
  unique (offering_id, code),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade
);
create index on public.sections (offering_id, tenant_id);

create table public.section_instructors (
  section_id uuid not null,
  user_id uuid not null,
  tenant_id uuid not null,
  role public.teaching_role not null default 'instructor',
  primary key (section_id, user_id),
  foreign key (section_id, tenant_id) references public.sections (id, tenant_id) on delete cascade,
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.section_instructors (user_id, tenant_id);

-- Weekly recurring slots. The exclusion constraint is the room clash check (paper 4.3).
create table public.timetable_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  section_id uuid not null,
  room_id uuid,
  weekday smallint not null check (weekday between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  valid_from date not null,
  valid_until date not null,
  note text,
  unique (id, tenant_id),
  check (ends_at > starts_at),
  check (valid_until >= valid_from),
  foreign key (section_id, tenant_id) references public.sections (id, tenant_id) on delete cascade,
  foreign key (room_id, tenant_id) references public.rooms (id, tenant_id) on delete set null (room_id),
  constraint timetable_entries_no_room_clash exclude using gist (
    room_id with =,
    weekday with =,
    public.timerange(starts_at, ends_at) with &&,
    daterange(valid_from, valid_until, '[]') with &&
  )
);
create index on public.timetable_entries (section_id, tenant_id);
create index on public.timetable_entries (room_id, tenant_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'faculties', 'departments', 'programs', 'buildings', 'rooms', 'terms', 'academic_calendar_events',
    'courses', 'course_prerequisites', 'course_offerings', 'sections', 'section_instructors', 'timetable_entries'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "members read the catalogue" on public.%I for select to authenticated
         using (tenant_id = (select private.tenant_id()))', t);
    execute format(
      'create policy "academic managers write the catalogue" on public.%I for all to authenticated
         using (tenant_id = (select private.tenant_id()) and (select private.has_permission(''academic.manage'')))
         with check (tenant_id = (select private.tenant_id()) and (select private.has_permission(''academic.manage'')))', t);
  end loop;
end;
$$;

create trigger section_instructors_audit after insert or update or delete on public.section_instructors
  for each row execute function private.audit_row_change();
