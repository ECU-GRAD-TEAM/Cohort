create table public.student_academic_progressions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  faculty_id uuid not null,
  current_semester smallint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_academic_progressions_semester_check check (current_semester between 1 and 8),
  constraint student_academic_progressions_student_tenant_key unique (student_id, tenant_id),
  constraint student_academic_progressions_student_fkey
    foreign key (student_id, tenant_id) references public.users(id, tenant_id) on delete cascade,
  constraint student_academic_progressions_faculty_fkey
    foreign key (faculty_id, tenant_id) references public.faculties(id, tenant_id) on delete restrict
);

create table public.student_department_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  faculty_id uuid not null,
  department_id uuid not null,
  selection_semester smallint not null default 2,
  effective_semester smallint not null default 3,
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  decision_note text,
  starts_on date,
  ends_on date,
  constraint student_department_assignments_status_check
    check (status in ('pending','approved','rejected','cancelled','superseded')),
  constraint student_department_assignments_semesters_check
    check (selection_semester = 2 and effective_semester = 3),
  constraint student_department_assignments_student_fkey
    foreign key (student_id, tenant_id) references public.users(id, tenant_id) on delete cascade,
  constraint student_department_assignments_faculty_fkey
    foreign key (faculty_id, tenant_id) references public.faculties(id, tenant_id) on delete restrict,
  constraint student_department_assignments_department_fkey
    foreign key (department_id, tenant_id) references public.departments(id, tenant_id) on delete restrict,
  constraint student_department_assignments_reviewer_fkey
    foreign key (reviewed_by, tenant_id) references public.users(id, tenant_id) on delete set null
);

create index student_department_assignments_student_history_idx
  on public.student_department_assignments (tenant_id, student_id, requested_at desc);
create unique index student_department_assignments_one_pending_idx
  on public.student_department_assignments (tenant_id, student_id) where status = 'pending';
create unique index student_department_assignments_one_current_idx
  on public.student_department_assignments (tenant_id, student_id)
  where status = 'approved' and ends_on is null;

create table public.student_programme_selections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  department_id uuid not null,
  program_id uuid not null,
  selection_semester smallint not null default 8,
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  decision_note text,
  starts_on date,
  ends_on date,
  constraint student_programme_selections_status_check
    check (status in ('pending','approved','rejected','cancelled','superseded')),
  constraint student_programme_selections_semester_check check (selection_semester = 8),
  constraint student_programme_selections_student_fkey
    foreign key (student_id, tenant_id) references public.users(id, tenant_id) on delete cascade,
  constraint student_programme_selections_department_fkey
    foreign key (department_id, tenant_id) references public.departments(id, tenant_id) on delete restrict,
  constraint student_programme_selections_program_fkey
    foreign key (program_id, tenant_id) references public.programs(id, tenant_id) on delete restrict,
  constraint student_programme_selections_reviewer_fkey
    foreign key (reviewed_by, tenant_id) references public.users(id, tenant_id) on delete set null
);

create index student_programme_selections_student_history_idx
  on public.student_programme_selections (tenant_id, student_id, requested_at desc);
create unique index student_programme_selections_one_pending_idx
  on public.student_programme_selections (tenant_id, student_id) where status = 'pending';
create unique index student_programme_selections_one_current_idx
  on public.student_programme_selections (tenant_id, student_id)
  where status = 'approved' and ends_on is null;

create or replace function private.validate_student_department_assignment()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  progression_faculty uuid;
  progression_semester smallint;
  department_faculty uuid;
begin
  select faculty_id, current_semester
    into progression_faculty, progression_semester
  from public.student_academic_progressions
  where tenant_id = new.tenant_id and student_id = new.student_id;

  if progression_faculty is null then
    raise exception 'Student academic progression must be created before department selection';
  end if;
  if progression_semester < 2 then
    raise exception 'Department selection is available only after semester 2';
  end if;

  select faculty_id into department_faculty
  from public.departments
  where id = new.department_id and tenant_id = new.tenant_id;

  if department_faculty is distinct from progression_faculty
     or new.faculty_id is distinct from progression_faculty then
    raise exception 'Selected department must belong to the student faculty';
  end if;
  return new;
end;
$$;

create trigger validate_student_department_assignment
before insert or update of student_id, tenant_id, faculty_id, department_id, status
on public.student_department_assignments
for each row execute function private.validate_student_department_assignment();

create or replace function private.validate_student_programme_selection()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  progression_semester smallint;
  assigned_department uuid;
  program_department uuid;
begin
  select current_semester into progression_semester
  from public.student_academic_progressions
  where tenant_id = new.tenant_id and student_id = new.student_id;

  if progression_semester is distinct from 8 then
    raise exception 'Programme selection is available only in semester 8';
  end if;

  select department_id into assigned_department
  from public.student_department_assignments
  where tenant_id = new.tenant_id
    and student_id = new.student_id
    and status = 'approved'
    and ends_on is null
  order by reviewed_at desc nulls last
  limit 1;

  if assigned_department is distinct from new.department_id then
    raise exception 'Student must have an approved current department assignment before programme selection';
  end if;

  select department_id into program_department
  from public.programs
  where id = new.program_id and tenant_id = new.tenant_id and is_active;

  if program_department is distinct from new.department_id then
    raise exception 'Selected programme must be active and belong to the assigned department';
  end if;
  return new;
end;
$$;

create trigger validate_student_programme_selection
before insert or update of student_id, tenant_id, department_id, program_id, status
on public.student_programme_selections
for each row execute function private.validate_student_programme_selection();

alter table public.student_academic_progressions enable row level security;
alter table public.student_department_assignments enable row level security;
alter table public.student_programme_selections enable row level security;

create policy "students and authorized staff read academic progression"
on public.student_academic_progressions for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (student_id = (select auth.uid()) or private.can_view_student(student_id)
       or private.has_permission('enrollment.manage')));

create policy "registrars manage academic progression"
on public.student_academic_progressions for all to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));

create policy "students and authorized staff read department assignment history"
on public.student_department_assignments for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (student_id = (select auth.uid()) or private.can_view_student(student_id)
       or private.has_permission('enrollment.manage')));

create policy "students submit their own department choices"
on public.student_department_assignments for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and student_id = (select auth.uid())
  and status = 'pending'
  and exists (
    select 1 from public.student_academic_progressions p
    where p.tenant_id = student_department_assignments.tenant_id
      and p.student_id = student_department_assignments.student_id
      and p.current_semester >= 2
      and p.faculty_id = student_department_assignments.faculty_id
  ));

create policy "registrars manage department assignment decisions"
on public.student_department_assignments for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));

create policy "students and authorized staff read programme selection history"
on public.student_programme_selections for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (student_id = (select auth.uid()) or private.can_view_student(student_id)
       or private.has_permission('enrollment.manage')));

create policy "students submit their own semester eight programme choice"
on public.student_programme_selections for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and student_id = (select auth.uid())
  and status = 'pending'
  and selection_semester = 8
  and exists (
    select 1 from public.student_academic_progressions p
    where p.tenant_id = student_programme_selections.tenant_id
      and p.student_id = student_programme_selections.student_id
      and p.current_semester = 8
  ));

create policy "registrars manage programme selection decisions"
on public.student_programme_selections for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));

grant select, insert, update on public.student_academic_progressions to authenticated;
grant select, insert, update on public.student_department_assignments to authenticated;
grant select, insert, update on public.student_programme_selections to authenticated;
