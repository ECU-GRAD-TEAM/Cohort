-- Enrolment and records (paper 4.1, 4.3, 6.5): programme membership, enrolments and waiting lists,
-- advisor assignments, grade scales, grading criteria, append-only grade entries, GPA snapshots
-- and academic standing. Also defines the attribute checks (teaches, enrolled in, advises) that
-- the remaining migrations build their policies on.

create type public.program_membership_status as enum ('active', 'completed', 'withdrawn', 'transferred');
create type public.enrollment_status as enum (
  'enrolled', 'waitlisted', 'dropped', 'withdrawn', 'completed', 'failed', 'incomplete'
);
create type public.grade_category as enum (
  'assignment', 'quiz', 'midterm', 'final_exam', 'project', 'lab', 'attendance', 'participation', 'other'
);
create type public.grade_status as enum ('draft', 'published');
create type public.grade_source as enum ('manual', 'auto', 'ai_assisted', 'import');
create type public.standing as enum ('good', 'deans_list', 'warning', 'probation', 'suspension', 'dismissed');

create table public.student_programs (
  student_id uuid not null,
  program_id uuid not null,
  tenant_id uuid not null,
  status public.program_membership_status not null default 'active',
  admitted_on date,
  expected_graduation_on date,
  level smallint,
  primary key (student_id, program_id),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (program_id, tenant_id) references public.programs (id, tenant_id)
);
create index on public.student_programs (program_id, tenant_id);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  section_id uuid not null,
  offering_id uuid not null,
  status public.enrollment_status not null,
  waitlist_position integer check (waitlist_position > 0),
  enrolled_at timestamptz not null default now(),
  status_changed_at timestamptz not null default now(),
  -- Accommodations recorded by the disability or student-support office.
  accommodations text,
  -- Final result, written when the term's grades are finalised.
  final_percentage numeric(5, 2),
  final_grade_letter text,
  final_grade_points numeric(4, 2),
  unique (id, tenant_id),
  unique (student_id, section_id),
  check ((status = 'waitlisted') = (waitlist_position is not null)),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id),
  foreign key (section_id, tenant_id, offering_id) references public.sections (id, tenant_id, offering_id),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id)
);
create index on public.enrollments (student_id, tenant_id);
create index on public.enrollments (section_id, tenant_id, offering_id);
create index on public.enrollments (offering_id, tenant_id);

create table public.advisor_assignments (
  advisor_id uuid not null,
  student_id uuid not null,
  tenant_id uuid not null,
  starts_on date not null default current_date,
  ends_on date,
  primary key (advisor_id, student_id),
  check (ends_on is null or ends_on >= starts_on),
  foreign key (advisor_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (student_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.advisor_assignments (student_id, tenant_id);
create index on public.advisor_assignments (advisor_id, tenant_id);

-- Grading scales are configuration, not code (paper 3.4).
create table public.grade_scales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null,
  max_grade_points numeric(4, 2) not null default 4.0,
  is_default boolean not null default false,
  unique (id, tenant_id),
  unique (tenant_id, name)
);
create unique index grade_scales_one_default on public.grade_scales (tenant_id) where is_default;

create table public.grade_scale_bands (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  scale_id uuid not null,
  letter text not null,
  min_percentage numeric(5, 2) not null check (min_percentage between 0 and 100),
  grade_points numeric(4, 2) not null check (grade_points >= 0),
  is_passing boolean not null,
  unique (scale_id, letter),
  unique (scale_id, min_percentage),
  foreign key (scale_id, tenant_id) references public.grade_scales (id, tenant_id) on delete cascade
);
create index on public.grade_scale_bands (scale_id, tenant_id);

alter table public.course_offerings add column grade_scale_id uuid;
alter table public.course_offerings
  add foreign key (grade_scale_id, tenant_id) references public.grade_scales (id, tenant_id)
  on delete set null (grade_scale_id);
create index on public.course_offerings (grade_scale_id, tenant_id);

-- Grading rules per offering. Weights are the machine-readable source for the gradebook (paper 4.2).
create table public.grade_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  name text not null,
  category public.grade_category not null,
  weight numeric(5, 2) not null check (weight > 0 and weight <= 100),
  drop_lowest smallint not null default 0 check (drop_lowest >= 0),
  published_at timestamptz,
  unique (id, tenant_id),
  unique (offering_id, name),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade
);
create index on public.grade_components (offering_id, tenant_id);

create function private.check_component_weights()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select sum(gc.weight) from public.grade_components gc where gc.offering_id = new.offering_id) > 100 then
    raise exception 'Grade component weights for this offering add up to more than 100'
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;

create trigger grade_components_weights after insert or update of weight, offering_id on public.grade_components
  for each row execute function private.check_component_weights();

-- Grades are append-only entries with a published state (paper 6.5). A draft can be edited,
-- deleted or published. A published entry never changes: a correction is a new entry that
-- supersedes it, with a reason, so every change leaves a reviewable history.
create table public.grade_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  enrollment_id uuid not null,
  student_id uuid not null,
  offering_id uuid not null,
  component_id uuid,
  -- Set by the assessment migration when the grade comes from an assessment.
  assessment_id uuid,
  score numeric(7, 2) not null check (score >= 0),
  max_score numeric(7, 2) not null check (max_score > 0),
  status public.grade_status not null default 'draft',
  source public.grade_source not null default 'manual',
  supersedes_id uuid unique references public.grade_entries (id),
  change_reason text,
  feedback text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  published_by uuid,
  unique (id, tenant_id),
  check (supersedes_id is null or change_reason is not null),
  check ((status = 'published') = (published_at is not null)),
  foreign key (enrollment_id, tenant_id) references public.enrollments (id, tenant_id),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id),
  foreign key (component_id, tenant_id) references public.grade_components (id, tenant_id)
);
create index on public.grade_entries (enrollment_id, tenant_id);
create index on public.grade_entries (student_id, tenant_id);
create index on public.grade_entries (offering_id, tenant_id);
create index on public.grade_entries (component_id, tenant_id);

create function private.guard_grade_entry()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_previous public.grade_entries;
begin
  if tg_op = 'DELETE' then
    if old.status = 'published' then
      raise exception 'Published grades cannot be deleted; add a superseding entry instead'
        using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.status = 'published' then
    raise exception 'Published grades cannot be changed; add a superseding entry instead'
      using errcode = 'insufficient_privilege';
  end if;

  if new.supersedes_id is not null then
    select * into v_previous from public.grade_entries where id = new.supersedes_id;
    if v_previous.status <> 'published'
       or v_previous.enrollment_id <> new.enrollment_id
       or v_previous.component_id is distinct from new.component_id
       or v_previous.assessment_id is distinct from new.assessment_id then
      raise exception 'A correction must supersede a published grade for the same enrolment and item'
        using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
  end if;
  if new.status = 'published' and (tg_op = 'INSERT' or old.status = 'draft') then
    new.published_at := now();
    new.published_by := coalesce(auth.uid(), new.published_by);
  end if;

  return new;
end;
$$;

create trigger grade_entries_guard before insert or update or delete on public.grade_entries
  for each row execute function private.guard_grade_entry();

create table public.gpa_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  -- Null for a cumulative-only snapshot.
  term_id uuid,
  scale_id uuid,
  term_gpa numeric(4, 2),
  cgpa numeric(4, 2),
  credits_attempted numeric(6, 1),
  credits_earned numeric(6, 1),
  computed_at timestamptz not null default now(),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id),
  foreign key (term_id, tenant_id) references public.terms (id, tenant_id),
  foreign key (scale_id, tenant_id) references public.grade_scales (id, tenant_id)
);
create index on public.gpa_snapshots (student_id, tenant_id, computed_at desc);
create index on public.gpa_snapshots (term_id, tenant_id);
create index on public.gpa_snapshots (scale_id, tenant_id);

create table public.academic_standings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  term_id uuid not null,
  standing public.standing not null,
  reason text,
  decided_by uuid,
  decided_at timestamptz not null default now(),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id),
  foreign key (term_id, tenant_id) references public.terms (id, tenant_id)
);
create index on public.academic_standings (student_id, tenant_id, decided_at desc);
create index on public.academic_standings (term_id, tenant_id);

create trigger gpa_snapshots_append_only before update or delete on public.gpa_snapshots
  for each row execute function private.reject_change();
create trigger academic_standings_append_only before update or delete on public.academic_standings
  for each row execute function private.reject_change();

create trigger enrollments_audit after insert or update or delete on public.enrollments
  for each row execute function private.audit_row_change();
create trigger advisor_assignments_audit after insert or update or delete on public.advisor_assignments
  for each row execute function private.audit_row_change();
create trigger grade_components_audit after insert or update or delete on public.grade_components
  for each row execute function private.audit_row_change();
create trigger grade_entries_audit after insert or update or delete on public.grade_entries
  for each row execute function private.audit_row_change();
create trigger academic_standings_audit after insert on public.academic_standings
  for each row execute function private.audit_row_change();

-- What students and teachers normally read: the newest published grade for each item.
create view public.published_grades with (security_invoker = true) as
  select g.*
  from public.grade_entries g
  where g.status = 'published'
    and not exists (
      select 1 from public.grade_entries newer
      where newer.supersedes_id = g.id and newer.status = 'published'
    );

-- ---------------------------------------------------------------------------
-- Attribute checks used by policies from here on (paper 6.6).
-- ---------------------------------------------------------------------------

create function private.teaches_section(p_section uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.section_instructors si
    where si.section_id = p_section and si.user_id = (select auth.uid())
  )
$$;

create function private.teaches_offering(p_offering uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.section_instructors si
    join public.sections s on s.id = si.section_id
    where s.offering_id = p_offering and si.user_id = (select auth.uid())
  )
  or exists (
    select 1 from public.course_offerings o
    where o.id = p_offering and o.coordinator_id = (select auth.uid())
  )
$$;

-- Teaches any offering of the course, past or present. Used for question banks and topics.
create function private.teaches_course(p_course uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.course_offerings o
    where o.course_id = p_course and private.teaches_offering(o.id)
  )
$$;

-- Current and former students of a section keep read access to its course space.
create function private.enrolled_in_section(p_section uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.enrollments e
    where e.section_id = p_section
      and e.student_id = (select auth.uid())
      and e.status in ('enrolled', 'completed', 'failed', 'incomplete')
  )
$$;

create function private.enrolled_in_offering(p_offering uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.enrollments e
    where e.offering_id = p_offering
      and e.student_id = (select auth.uid())
      and e.status in ('enrolled', 'completed', 'failed', 'incomplete')
  )
$$;

create function private.advises(p_student uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.advisor_assignments a
    where a.advisor_id = (select auth.uid())
      and a.student_id = p_student
      and a.starts_on <= current_date
      and (a.ends_on is null or a.ends_on >= current_date)
  )
$$;

create function private.teaches_student(p_student uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.enrollments e
    join public.section_instructors si on si.section_id = e.section_id
    where e.student_id = p_student
      and si.user_id = (select auth.uid())
      and e.status in ('enrolled', 'waitlisted', 'completed', 'failed', 'incomplete')
  )
  or exists (
    select 1
    from public.enrollments e
    join public.course_offerings o on o.id = e.offering_id
    where e.student_id = p_student
      and o.coordinator_id = (select auth.uid())
      and e.status in ('enrolled', 'waitlisted', 'completed', 'failed', 'incomplete')
  )
$$;

-- A student's own record is visible to the student, their advisor, their teachers and anyone
-- holding a live break-glass grant for them.
create function private.can_view_student(p_student uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_student = (select auth.uid())
    or private.advises(p_student)
    or private.teaches_student(p_student)
    or private.has_record_grant(p_student)
$$;

create function private.in_department(p_department uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.person_profiles p
    where p.user_id = (select auth.uid()) and p.department_id = p_department
  )
  or exists (
    select 1
    from public.student_programs sp
    join public.programs pr on pr.id = sp.program_id
    where sp.student_id = (select auth.uid()) and sp.status = 'active' and pr.department_id = p_department
  )
$$;

-- ---------------------------------------------------------------------------
-- Self-service registration (paper 4.3: rule engine for prerequisites and limits).
-- Students cannot write enrolments directly; these functions apply the rules.
-- ---------------------------------------------------------------------------

create function public.enroll_in_section(p_section uuid)
returns public.enrollments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_tenant uuid := private.tenant_id();
  v_section public.sections;
  v_offering public.course_offerings;
  v_course public.courses;
  v_term public.terms;
  v_enrolled integer;
  v_waiting integer;
  v_credits numeric;
  v_status public.enrollment_status;
  v_position integer;
  v_result public.enrollments;
begin
  if v_tenant is null or private.user_type() <> 'student' then
    raise exception 'Only students can register themselves' using errcode = 'insufficient_privilege';
  end if;

  -- Locking the section serialises concurrent registrations for its seats.
  select * into v_section from public.sections where id = p_section and tenant_id = v_tenant for update;
  if not found then
    raise exception 'Section not found' using errcode = 'no_data_found';
  end if;
  select * into v_offering from public.course_offerings where id = v_section.offering_id;
  select * into v_course from public.courses where id = v_offering.course_id;
  select * into v_term from public.terms where id = v_offering.term_id;

  if v_offering.status <> 'published' then
    raise exception 'This course is not open for registration' using errcode = 'check_violation';
  end if;
  if v_term.registration_opens_at is null
     or now() < v_term.registration_opens_at
     or now() > coalesce(v_term.add_drop_ends_at, v_term.registration_closes_at, 'infinity') then
    raise exception 'Registration is closed for this term' using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from public.enrollments e
    join public.sections s on s.id = e.section_id
    where e.student_id = v_me and e.offering_id = v_offering.id and s.kind = v_section.kind
      and e.status in ('enrolled', 'waitlisted')
  ) then
    raise exception 'Already registered in a % section of this course', v_section.kind
      using errcode = 'unique_violation';
  end if;

  if exists (
    select 1 from public.course_prerequisites p
    where p.course_id = v_course.id
      and not exists (
        select 1 from public.enrollments e
        join public.course_offerings o on o.id = e.offering_id
        where e.student_id = v_me
          and o.course_id = p.prerequisite_course_id
          and (e.status = 'completed'
               or (p.kind = 'corequisite' and e.status = 'enrolled' and o.term_id = v_term.id))
      )
  ) then
    raise exception 'Prerequisites for % are not met', v_course.code using errcode = 'check_violation';
  end if;

  select coalesce(sum(c.credit_hours), 0) into v_credits
  from public.courses c
  where c.id in (
    select o.course_id from public.enrollments e
    join public.course_offerings o on o.id = e.offering_id
    where e.student_id = v_me and o.term_id = v_term.id and e.status = 'enrolled'
  ) and c.id <> v_course.id;
  if v_credits + v_course.credit_hours > (select t.max_credits_per_term from public.tenants t where t.id = v_tenant) then
    raise exception 'Registering would exceed the credit limit for the term' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.timetable_entries mine
    join public.enrollments e on e.section_id = mine.section_id
    join public.course_offerings o on o.id = e.offering_id
    join public.timetable_entries new_slot on new_slot.section_id = p_section
    where e.student_id = v_me and e.status = 'enrolled' and o.term_id = v_term.id
      and mine.weekday = new_slot.weekday
      and public.timerange(mine.starts_at, mine.ends_at) && public.timerange(new_slot.starts_at, new_slot.ends_at)
      and daterange(mine.valid_from, mine.valid_until, '[]') && daterange(new_slot.valid_from, new_slot.valid_until, '[]')
  ) then
    raise exception 'This section clashes with your timetable' using errcode = 'check_violation';
  end if;

  select count(*) filter (where e.status = 'enrolled'), count(*) filter (where e.status = 'waitlisted')
  into v_enrolled, v_waiting
  from public.enrollments e where e.section_id = p_section;

  if v_section.capacity is null or v_enrolled < v_section.capacity then
    v_status := 'enrolled';
  elsif v_waiting < v_section.waitlist_capacity then
    v_status := 'waitlisted';
    v_position := v_waiting + 1;
  else
    raise exception 'This section is full' using errcode = 'check_violation';
  end if;

  insert into public.enrollments (tenant_id, student_id, section_id, offering_id, status, waitlist_position)
  values (v_tenant, v_me, p_section, v_offering.id, v_status, v_position)
  on conflict (student_id, section_id) do update
    set status = excluded.status,
        waitlist_position = excluded.waitlist_position,
        status_changed_at = now()
  returning * into v_result;

  return v_result;
end;
$$;

create function public.drop_section(p_section uuid)
returns public.enrollments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_enrollment public.enrollments;
  v_term public.terms;
  v_old_position integer;
  v_next uuid;
begin
  perform 1 from public.sections where id = p_section for update;

  select * into v_enrollment
  from public.enrollments
  where section_id = p_section and student_id = v_me and status in ('enrolled', 'waitlisted');
  if not found then
    raise exception 'You are not registered in this section' using errcode = 'no_data_found';
  end if;

  select t.* into v_term
  from public.terms t join public.course_offerings o on o.term_id = t.id
  where o.id = v_enrollment.offering_id;
  if now() > coalesce(v_term.add_drop_ends_at, v_term.registration_closes_at, 'infinity') then
    raise exception 'The add/drop period has ended; ask the registrar to withdraw you'
      using errcode = 'check_violation';
  end if;

  v_old_position := v_enrollment.waitlist_position;

  update public.enrollments
  set status = 'dropped', waitlist_position = null, status_changed_at = now()
  where id = v_enrollment.id
  returning * into v_enrollment;

  -- Close the gap in the waiting list, then promote the head of the list into a freed seat.
  if v_old_position is not null then
    update public.enrollments
    set waitlist_position = waitlist_position - 1
    where section_id = p_section and status = 'waitlisted' and waitlist_position > v_old_position;
  end if;

  if exists (
    select 1 from public.sections s
    where s.id = p_section
      and (s.capacity is null
           or (select count(*) from public.enrollments e where e.section_id = s.id and e.status = 'enrolled') < s.capacity)
  ) then
    select e.id into v_next from public.enrollments e
    where e.section_id = p_section and e.status = 'waitlisted'
    order by e.waitlist_position
    limit 1;
    if v_next is not null then
      update public.enrollments
      set status = 'enrolled', waitlist_position = null, status_changed_at = now()
      where id = v_next;
      update public.enrollments
      set waitlist_position = waitlist_position - 1
      where section_id = p_section and status = 'waitlisted';
    end if;
  end if;

  return v_enrollment;
end;
$$;

revoke execute on function public.enroll_in_section(uuid), public.drop_section(uuid) from public, anon;
grant execute on function public.enroll_in_section(uuid), public.drop_section(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.student_programs enable row level security;
alter table public.enrollments enable row level security;
alter table public.advisor_assignments enable row level security;
alter table public.grade_scales enable row level security;
alter table public.grade_scale_bands enable row level security;
alter table public.grade_components enable row level security;
alter table public.grade_entries enable row level security;
alter table public.gpa_snapshots enable row level security;
alter table public.academic_standings enable row level security;

-- Teachers and advisors can see the accounts and profiles of their own students.
create policy "teachers and advisors read their students' accounts" on public.users
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and private.can_view_student(id));
create policy "teachers and advisors read their students' profiles" on public.person_profiles
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and private.can_view_student(user_id));

create policy "students, their staff and registrars read programme membership" on public.student_programs
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (private.can_view_student(student_id) or (select private.has_permission('enrollment.manage')))
  );
create policy "registrars write programme membership" on public.student_programs
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('enrollment.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('enrollment.manage')));

create policy "students, teachers, advisors and registrars read enrolments" on public.enrollments
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      student_id = (select auth.uid())
      or private.teaches_section(section_id)
      or private.advises(student_id)
      or private.has_record_grant(student_id)
      or (select private.has_permission('enrollment.manage'))
    )
  );
create policy "registrars write enrolments" on public.enrollments
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('enrollment.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('enrollment.manage')));

create policy "advisors, their students and registrars read assignments" on public.advisor_assignments
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      advisor_id = (select auth.uid())
      or student_id = (select auth.uid())
      or (select private.has_permission('enrollment.manage'))
    )
  );
create policy "registrars write advisor assignments" on public.advisor_assignments
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('enrollment.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('enrollment.manage')));

create policy "members read grade scales" on public.grade_scales
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "grade managers write grade scales" on public.grade_scales
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('grades.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('grades.manage')));

create policy "members read grade scale bands" on public.grade_scale_bands
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "grade managers write grade scale bands" on public.grade_scale_bands
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('grades.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('grades.manage')));

create policy "teachers and enrolled students read grading rules" on public.grade_components
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.teaches_offering(offering_id)
      or (published_at is not null and private.enrolled_in_offering(offering_id))
    )
  );
create policy "teachers write grading rules" on public.grade_components
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

-- Students see only published grades. Teachers manage grades for offerings they teach; the
-- trigger stops them editing or deleting anything already published.
create policy "students read their published grades" on public.grade_entries
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and student_id = (select auth.uid()) and status = 'published');
create policy "advisors and record holders read published grades" on public.grade_entries
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and status = 'published'
    and (private.advises(student_id) or private.has_record_grant(student_id))
  );
create policy "teachers read grades for their offerings" on public.grade_entries
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));
create policy "teachers add grades for their offerings" on public.grade_entries
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and private.teaches_offering(offering_id)
    and exists (
      select 1 from public.enrollments e
      where e.id = grade_entries.enrollment_id
        and e.student_id = grade_entries.student_id
        and e.offering_id = grade_entries.offering_id
    )
  );
create policy "teachers edit draft grades for their offerings" on public.grade_entries
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));
create policy "teachers delete draft grades for their offerings" on public.grade_entries
  for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

create policy "students and their staff read GPA snapshots" on public.gpa_snapshots
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and private.can_view_student(student_id));

create policy "students and their staff read academic standing" on public.academic_standings
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and private.can_view_student(student_id));
create policy "grade managers record academic standing" on public.academic_standings
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('grades.manage'))
    and decided_by = (select auth.uid())
  );
