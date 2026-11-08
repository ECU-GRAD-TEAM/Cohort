
create table public.faculty_academic_pathways (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  faculty_id uuid not null,
  department_selection_semester smallint not null default 2,
  department_effective_semester smallint not null default 3,
  programme_selection_semester smallint not null default 8,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint faculty_academic_pathways_faculty_key unique (faculty_id, tenant_id),
  constraint faculty_academic_pathways_department_semesters_check
    check (department_selection_semester between 1 and 7
      and department_effective_semester > department_selection_semester
      and department_effective_semester <= 8),
  constraint faculty_academic_pathways_programme_semester_check
    check (programme_selection_semester between department_effective_semester and 8),
  constraint faculty_academic_pathways_faculty_fkey
    foreign key (faculty_id, tenant_id) references public.faculties(id, tenant_id) on delete cascade
);

insert into public.faculty_academic_pathways (
  tenant_id, faculty_id, department_selection_semester,
  department_effective_semester, programme_selection_semester
)
select t.id, f.id, 2, 3, 8
from public.tenants as t
join public.faculties as f
  on f.tenant_id = t.id
 and f.code = 'ENG'
where t.slug = 'ecu'
on conflict (faculty_id, tenant_id) do update
set department_selection_semester = excluded.department_selection_semester,
    department_effective_semester = excluded.department_effective_semester,
    programme_selection_semester = excluded.programme_selection_semester;

alter table public.student_department_assignments
  drop constraint student_department_assignments_semesters_check;
alter table public.student_programme_selections
  drop constraint student_programme_selections_semester_check;

create or replace function private.validate_student_department_assignment()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  progression_faculty uuid;
  progression_semester smallint;
  department_faculty uuid;
  required_selection_semester smallint;
  required_effective_semester smallint;
begin
  select p.faculty_id, p.current_semester,
         pathway.department_selection_semester, pathway.department_effective_semester
    into progression_faculty, progression_semester,
         required_selection_semester, required_effective_semester
  from public.student_academic_progressions p
  join public.faculty_academic_pathways pathway
    on pathway.tenant_id = p.tenant_id and pathway.faculty_id = p.faculty_id
  where p.tenant_id = new.tenant_id and p.student_id = new.student_id;

  if progression_faculty is null then
    raise exception 'Student academic progression and faculty pathway must be configured before department selection';
  end if;
  if progression_semester < required_effective_semester then
    raise exception 'Department selection is available only after completion of semester %', required_selection_semester;
  end if;
  if new.selection_semester <> required_selection_semester
     or new.effective_semester <> required_effective_semester then
    raise exception 'Department selection semesters must match the faculty academic pathway';
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

create or replace function private.validate_student_programme_selection()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  progression_semester smallint;
  assigned_department uuid;
  program_department uuid;
  required_programme_semester smallint;
begin
  select p.current_semester, pathway.programme_selection_semester
    into progression_semester, required_programme_semester
  from public.student_academic_progressions p
  join public.faculty_academic_pathways pathway
    on pathway.tenant_id = p.tenant_id and pathway.faculty_id = p.faculty_id
  where p.tenant_id = new.tenant_id and p.student_id = new.student_id;

  if progression_semester is distinct from required_programme_semester then
    raise exception 'Programme selection is available only in semester %', required_programme_semester;
  end if;
  if new.selection_semester <> required_programme_semester then
    raise exception 'Programme selection semester must match the faculty academic pathway';
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

drop policy "students submit their own department choices" on public.student_department_assignments;
create policy "students submit their own department choices"
on public.student_department_assignments for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and student_id = (select auth.uid())
  and status = 'pending'
  and exists (
    select 1
    from public.student_academic_progressions p
    join public.faculty_academic_pathways pathway
      on pathway.tenant_id = p.tenant_id and pathway.faculty_id = p.faculty_id
    where p.tenant_id = student_department_assignments.tenant_id
      and p.student_id = student_department_assignments.student_id
      and p.current_semester >= pathway.department_effective_semester
      and p.faculty_id = student_department_assignments.faculty_id
      and student_department_assignments.selection_semester = pathway.department_selection_semester
      and student_department_assignments.effective_semester = pathway.department_effective_semester
  ));

drop policy "students submit their own semester eight programme choice" on public.student_programme_selections;
create policy "students submit their own semester eight programme choice"
on public.student_programme_selections for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and student_id = (select auth.uid())
  and status = 'pending'
  and exists (
    select 1
    from public.student_academic_progressions p
    join public.faculty_academic_pathways pathway
      on pathway.tenant_id = p.tenant_id and pathway.faculty_id = p.faculty_id
    where p.tenant_id = student_programme_selections.tenant_id
      and p.student_id = student_programme_selections.student_id
      and p.current_semester = pathway.programme_selection_semester
      and student_programme_selections.selection_semester = pathway.programme_selection_semester
  ));

alter table public.faculty_academic_pathways enable row level security;
create policy "members read their faculty academic pathway"
on public.faculty_academic_pathways for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (private.has_permission('enrollment.manage')
    or exists (
      select 1 from public.student_academic_progressions p
      where p.tenant_id = faculty_academic_pathways.tenant_id
        and p.faculty_id = faculty_academic_pathways.faculty_id
        and p.student_id = (select auth.uid())
    )));
create policy "registrars manage faculty academic pathways"
on public.faculty_academic_pathways for all to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));

create index faculty_academic_pathways_tenant_faculty_idx
  on public.faculty_academic_pathways (tenant_id, faculty_id);
grant select, insert, update on public.faculty_academic_pathways to authenticated;
