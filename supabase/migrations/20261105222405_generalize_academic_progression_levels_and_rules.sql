-- Generalize faculty academic progression from fixed semesters to ordered academic levels.
-- Legacy semester fields are retained for backward compatibility during client migration.

create table public.academic_levels (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  faculty_id uuid not null,
  code text not null,
  name text not null,
  sequence_number integer not null,
  period_unit text not null default 'custom',
  stage_key text,
  is_terminal boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint academic_levels_period_unit_check
    check (period_unit in ('semester','trimester','quarter','year','block','module','custom')),
  constraint academic_levels_sequence_check check (sequence_number > 0),
  constraint academic_levels_faculty_code_key unique (tenant_id, faculty_id, code),
  constraint academic_levels_faculty_sequence_key unique (tenant_id, faculty_id, sequence_number),
  constraint academic_levels_id_tenant_key unique (id, tenant_id),
  constraint academic_levels_faculty_fkey
    foreign key (faculty_id, tenant_id) references public.faculties(id, tenant_id) on delete cascade
);
create index academic_levels_faculty_order_idx
  on public.academic_levels (tenant_id, faculty_id, sequence_number);

alter table public.faculty_academic_pathways
  add column department_selection_level_id uuid,
  add column department_effective_level_id uuid,
  add column programme_selection_level_id uuid;
alter table public.student_academic_progressions
  drop constraint if exists student_academic_progressions_semester_check,
  add column current_academic_level_id uuid,
  add column credits_earned numeric(8,2) not null default 0,
  add constraint student_academic_progressions_credits_check check (credits_earned >= 0);
alter table public.student_department_assignments
  add column selection_level_id uuid,
  add column effective_level_id uuid;
alter table public.student_programme_selections
  add column selection_level_id uuid;

-- Preserve the existing ECU eight-semester pathway and map all existing records.
insert into public.academic_levels
  (tenant_id, faculty_id, code, name, sequence_number, period_unit, stage_key, is_terminal)
select p.tenant_id, p.faculty_id, 'SEMESTER_' || n, 'Semester ' || n, n, 'semester',
       case when n <= 2 then 'preparatory' when n <= 7 then 'departmental' else 'programme' end,
       n = 8
from public.faculty_academic_pathways p
cross join generate_series(1, 8) as n
on conflict (tenant_id, faculty_id, code) do nothing;

update public.faculty_academic_pathways p
set department_selection_level_id = sel.id,
    department_effective_level_id = eff.id,
    programme_selection_level_id = prog.id
from public.academic_levels sel, public.academic_levels eff, public.academic_levels prog
where sel.tenant_id = p.tenant_id and sel.faculty_id = p.faculty_id
  and sel.sequence_number = p.department_selection_semester
  and eff.tenant_id = p.tenant_id and eff.faculty_id = p.faculty_id
  and eff.sequence_number = p.department_effective_semester
  and prog.tenant_id = p.tenant_id and prog.faculty_id = p.faculty_id
  and prog.sequence_number = p.programme_selection_semester;

update public.student_academic_progressions p
set current_academic_level_id = l.id
from public.academic_levels l
where l.tenant_id = p.tenant_id and l.faculty_id = p.faculty_id
  and l.sequence_number = p.current_semester;

update public.student_department_assignments a
set selection_level_id = sel.id, effective_level_id = eff.id
from public.academic_levels sel, public.academic_levels eff
where sel.tenant_id = a.tenant_id and sel.faculty_id = a.faculty_id
  and sel.sequence_number = a.selection_semester
  and eff.tenant_id = a.tenant_id and eff.faculty_id = a.faculty_id
  and eff.sequence_number = a.effective_semester;

update public.student_programme_selections s
set selection_level_id = l.id
from public.student_academic_progressions p
join public.academic_levels l on l.tenant_id = p.tenant_id
  and l.faculty_id = p.faculty_id and l.sequence_number = s.selection_semester
where p.tenant_id = s.tenant_id and p.student_id = s.student_id;

alter table public.faculty_academic_pathways
  add constraint faculty_pathways_department_selection_level_fkey
    foreign key (department_selection_level_id, tenant_id)
    references public.academic_levels(id, tenant_id) on delete restrict,
  add constraint faculty_pathways_department_effective_level_fkey
    foreign key (department_effective_level_id, tenant_id)
    references public.academic_levels(id, tenant_id) on delete restrict,
  add constraint faculty_pathways_programme_selection_level_fkey
    foreign key (programme_selection_level_id, tenant_id)
    references public.academic_levels(id, tenant_id) on delete restrict;
alter table public.student_academic_progressions
  add constraint student_progressions_current_level_fkey
    foreign key (current_academic_level_id, tenant_id)
    references public.academic_levels(id, tenant_id) on delete restrict;
alter table public.student_department_assignments
  add constraint student_department_selection_level_fkey
    foreign key (selection_level_id, tenant_id)
    references public.academic_levels(id, tenant_id) on delete restrict,
  add constraint student_department_effective_level_fkey
    foreign key (effective_level_id, tenant_id)
    references public.academic_levels(id, tenant_id) on delete restrict;
alter table public.student_programme_selections
  add constraint student_programme_selection_level_fkey
    foreign key (selection_level_id, tenant_id)
    references public.academic_levels(id, tenant_id) on delete restrict;

create table public.academic_progression_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  faculty_id uuid not null,
  action_key text not null,
  selection_level_id uuid not null,
  effective_level_id uuid,
  minimum_credits numeric(8,2) not null default 0,
  requires_department_assignment boolean not null default false,
  allows_direct_entry boolean not null default false,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint academic_progression_rules_action_check
    check (action_key in ('department_selection','programme_selection','major_selection','minor_selection','specialization_selection')),
  constraint academic_progression_rules_credits_check check (minimum_credits >= 0),
  constraint academic_progression_rules_faculty_action_key unique (tenant_id, faculty_id, action_key),
  constraint academic_progression_rules_faculty_fkey
    foreign key (faculty_id, tenant_id) references public.faculties(id, tenant_id) on delete cascade,
  constraint academic_progression_rules_selection_level_fkey
    foreign key (selection_level_id, tenant_id) references public.academic_levels(id, tenant_id) on delete restrict,
  constraint academic_progression_rules_effective_level_fkey
    foreign key (effective_level_id, tenant_id) references public.academic_levels(id, tenant_id) on delete restrict
);
create index academic_progression_rules_faculty_idx
  on public.academic_progression_rules (tenant_id, faculty_id, is_enabled);

insert into public.academic_progression_rules
  (tenant_id, faculty_id, action_key, selection_level_id, effective_level_id,
   minimum_credits, requires_department_assignment)
select tenant_id, faculty_id, 'department_selection',
       department_selection_level_id, department_effective_level_id, 0, false
from public.faculty_academic_pathways where department_selection_level_id is not null
on conflict (tenant_id, faculty_id, action_key) do update
set selection_level_id = excluded.selection_level_id, effective_level_id = excluded.effective_level_id;

insert into public.academic_progression_rules
  (tenant_id, faculty_id, action_key, selection_level_id, effective_level_id,
   minimum_credits, requires_department_assignment)
select tenant_id, faculty_id, 'programme_selection',
       programme_selection_level_id, programme_selection_level_id, 0, true
from public.faculty_academic_pathways where programme_selection_level_id is not null
on conflict (tenant_id, faculty_id, action_key) do update
set selection_level_id = excluded.selection_level_id, effective_level_id = excluded.effective_level_id;

alter table public.academic_levels enable row level security;
alter table public.academic_progression_rules enable row level security;
create policy "members read academic levels" on public.academic_levels for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (private.has_permission('enrollment.manage') or exists (
    select 1 from public.student_academic_progressions p
    where p.tenant_id = academic_levels.tenant_id and p.faculty_id = academic_levels.faculty_id
      and p.student_id = (select auth.uid())
  )));
create policy "registrars manage academic levels" on public.academic_levels for all to authenticated
using (tenant_id = (select private.tenant_id()) and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id()) and private.has_permission('enrollment.manage'));
create policy "members read academic progression rules" on public.academic_progression_rules for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (private.has_permission('enrollment.manage') or exists (
    select 1 from public.student_academic_progressions p
    where p.tenant_id = academic_progression_rules.tenant_id
      and p.faculty_id = academic_progression_rules.faculty_id
      and p.student_id = (select auth.uid())
  )));
create policy "registrars manage academic progression rules" on public.academic_progression_rules for all to authenticated
using (tenant_id = (select private.tenant_id()) and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id()) and private.has_permission('enrollment.manage'));
grant select, insert, update, delete on public.academic_levels to authenticated;
grant select, insert, update, delete on public.academic_progression_rules to authenticated;

create or replace function private.sync_student_academic_level_legacy()
returns trigger language plpgsql set search_path = '' as $$
declare level_sequence integer;
begin
  if new.current_academic_level_id is not null then
    select sequence_number into level_sequence from public.academic_levels
    where id = new.current_academic_level_id and tenant_id = new.tenant_id;
    new.current_semester := level_sequence;
  end if;
  return new;
end;
$$;
create trigger sync_student_academic_level_legacy
before insert or update of current_academic_level_id
on public.student_academic_progressions
for each row execute function private.sync_student_academic_level_legacy();

create or replace function private.validate_student_department_assignment()
returns trigger language plpgsql set search_path = '' as $$
declare
  progression_faculty uuid; progression_level integer; earned_credits numeric;
  department_faculty uuid; rule_selection_level integer; rule_effective_level integer;
  rule_minimum_credits numeric;
begin
  select p.faculty_id, l.sequence_number, p.credits_earned, rsel.sequence_number,
         reff.sequence_number, r.minimum_credits
  into progression_faculty, progression_level, earned_credits, rule_selection_level,
       rule_effective_level, rule_minimum_credits
  from public.student_academic_progressions p
  join public.academic_levels l on l.id = p.current_academic_level_id and l.tenant_id = p.tenant_id
  join public.academic_progression_rules r on r.tenant_id = p.tenant_id
    and r.faculty_id = p.faculty_id and r.action_key = 'department_selection' and r.is_enabled
  join public.academic_levels rsel on rsel.id = r.selection_level_id and rsel.tenant_id = r.tenant_id
  left join public.academic_levels reff on reff.id = r.effective_level_id and reff.tenant_id = r.tenant_id
  where p.tenant_id = new.tenant_id and p.student_id = new.student_id;
  if progression_faculty is null then
    raise exception 'Student progression and an enabled department-selection rule are required';
  end if;
  if progression_level < coalesce(rule_effective_level, rule_selection_level)
     or earned_credits < rule_minimum_credits then
    raise exception 'Student has not met the academic-level or credit requirement for department selection';
  end if;
  if new.selection_level_id is distinct from (select selection_level_id from public.academic_progression_rules
      where tenant_id = new.tenant_id and faculty_id = progression_faculty
        and action_key = 'department_selection' and is_enabled)
     or new.effective_level_id is distinct from (select effective_level_id from public.academic_progression_rules
      where tenant_id = new.tenant_id and faculty_id = progression_faculty
        and action_key = 'department_selection' and is_enabled) then
    raise exception 'Department assignment levels must match the configured progression rule';
  end if;
  select faculty_id into department_faculty from public.departments
  where id = new.department_id and tenant_id = new.tenant_id;
  if department_faculty is distinct from progression_faculty or new.faculty_id is distinct from progression_faculty then
    raise exception 'Selected department must belong to the student faculty';
  end if;
  return new;
end;
$$;

create or replace function private.validate_student_programme_selection()
returns trigger language plpgsql set search_path = '' as $$
declare
  progression_faculty uuid; progression_level integer; earned_credits numeric;
  rule_selection_level integer; rule_minimum_credits numeric; requires_department boolean;
  assigned_department uuid; program_department uuid;
begin
  select p.faculty_id, l.sequence_number, p.credits_earned, target.sequence_number,
         r.minimum_credits, r.requires_department_assignment
  into progression_faculty, progression_level, earned_credits, rule_selection_level,
       rule_minimum_credits, requires_department
  from public.student_academic_progressions p
  join public.academic_levels l on l.id = p.current_academic_level_id and l.tenant_id = p.tenant_id
  join public.academic_progression_rules r on r.tenant_id = p.tenant_id
    and r.faculty_id = p.faculty_id and r.action_key = 'programme_selection' and r.is_enabled
  join public.academic_levels target on target.id = r.selection_level_id and target.tenant_id = r.tenant_id
  where p.tenant_id = new.tenant_id and p.student_id = new.student_id;
  if progression_faculty is null then
    raise exception 'Student progression and an enabled programme-selection rule are required';
  end if;
  if progression_level < rule_selection_level or earned_credits < rule_minimum_credits then
    raise exception 'Student has not met the academic-level or credit requirement for programme selection';
  end if;
  if new.selection_level_id is distinct from (select selection_level_id from public.academic_progression_rules
      where tenant_id = new.tenant_id and faculty_id = progression_faculty
        and action_key = 'programme_selection' and is_enabled) then
    raise exception 'Programme selection level must match the configured progression rule';
  end if;
  if requires_department then
    select department_id into assigned_department from public.student_department_assignments
    where tenant_id = new.tenant_id and student_id = new.student_id
      and status = 'approved' and ends_on is null order by reviewed_at desc nulls last limit 1;
    if assigned_department is distinct from new.department_id then
      raise exception 'Student must have an approved current department assignment before programme selection';
    end if;
  end if;
  select department_id into program_department from public.programs
  where id = new.program_id and tenant_id = new.tenant_id and is_active;
  if program_department is distinct from new.department_id then
    raise exception 'Selected programme must be active and belong to the selected department';
  end if;
  return new;
end;
$$;

create or replace function private.sync_approved_student_programme()
returns trigger language plpgsql set search_path = '' as $$
declare level_value integer;
begin
  select sequence_number into level_value from public.academic_levels
  where id = new.selection_level_id and tenant_id = new.tenant_id;
  if new.status = 'approved' and new.ends_on is null then
    insert into public.student_programs (student_id, program_id, tenant_id, status, admitted_on, level)
    values (new.student_id, new.program_id, new.tenant_id, 'active'::public.program_membership_status,
      coalesce(new.starts_on, current_date), level_value)
    on conflict (student_id, program_id) do update
      set status = 'active'::public.program_membership_status,
          admitted_on = coalesce(public.student_programs.admitted_on, excluded.admitted_on),
          level = excluded.level;
  elsif tg_op = 'UPDATE' and old.status = 'approved'
    and (new.status <> 'approved' or new.ends_on is not null) then
    update public.student_programs
    set status = case when new.status = 'superseded' then 'transferred'::public.program_membership_status
      else 'withdrawn'::public.program_membership_status end
    where student_id = new.student_id and program_id = new.program_id and tenant_id = new.tenant_id
      and status = 'active'::public.program_membership_status;
  end if;
  return new;
end;
$$;

create or replace function private.sync_student_selection_level_legacy()
returns trigger language plpgsql set search_path = '' as $$
declare seq integer; faculty uuid; target_level uuid; effective_level uuid;
begin
  if tg_table_name = 'student_department_assignments' then
    select p.faculty_id into faculty from public.student_academic_progressions p
    where p.tenant_id = new.tenant_id and p.student_id = new.student_id;
    if new.selection_level_id is null then
      select selection_level_id, academic_progression_rules.effective_level_id
      into target_level, effective_level from public.academic_progression_rules
      where tenant_id = new.tenant_id and faculty_id = faculty
        and action_key = 'department_selection' and is_enabled;
      new.selection_level_id := target_level;
      new.effective_level_id := coalesce(new.effective_level_id, effective_level);
    end if;
    if new.selection_level_id is not null then
      select sequence_number into seq from public.academic_levels
      where id = new.selection_level_id and tenant_id = new.tenant_id;
      new.selection_semester := seq;
    end if;
    if new.effective_level_id is not null then
      select sequence_number into seq from public.academic_levels
      where id = new.effective_level_id and tenant_id = new.tenant_id;
      new.effective_semester := seq;
    end if;
  else
    if new.selection_level_id is null then
      select p.faculty_id into faculty from public.student_academic_progressions p
      where p.tenant_id = new.tenant_id and p.student_id = new.student_id;
      select selection_level_id into target_level from public.academic_progression_rules
      where tenant_id = new.tenant_id and faculty_id = faculty
        and action_key = 'programme_selection' and is_enabled;
      new.selection_level_id := target_level;
    end if;
    if new.selection_level_id is not null then
      select sequence_number into seq from public.academic_levels
      where id = new.selection_level_id and tenant_id = new.tenant_id;
      new.selection_semester := seq;
    end if;
  end if;
  return new;
end;
$$;
create trigger sync_student_department_selection_level_legacy
before insert or update of selection_level_id, effective_level_id
on public.student_department_assignments
for each row execute function private.sync_student_selection_level_legacy();
create trigger sync_student_programme_selection_level_legacy
before insert or update of selection_level_id
on public.student_programme_selections
for each row execute function private.sync_student_selection_level_legacy();

create or replace function private.touch_academic_progression_rule_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end;
$$;
create trigger academic_progression_rules_updated_at
before update on public.academic_progression_rules
for each row execute function private.touch_academic_progression_rule_updated_at();

create index student_academic_progressions_level_idx
  on public.student_academic_progressions (tenant_id, current_academic_level_id);
create index student_department_assignments_level_idx
  on public.student_department_assignments (tenant_id, selection_level_id, effective_level_id);
create index student_programme_selections_level_idx
  on public.student_programme_selections (tenant_id, selection_level_id);
