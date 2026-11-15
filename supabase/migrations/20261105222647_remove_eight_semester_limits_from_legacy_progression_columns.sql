-- Remove hard-coded eight-semester limits while retaining legacy sequence aliases.
drop policy "students submit their own department choices" on public.student_department_assignments;
drop policy "students submit their own semester eight programme choice" on public.student_programme_selections;
drop trigger sync_student_academic_level_legacy on public.student_academic_progressions;
drop trigger sync_student_department_selection_level_legacy on public.student_department_assignments;
drop trigger sync_student_programme_selection_level_legacy on public.student_programme_selections;

alter table public.faculty_academic_pathways
  drop constraint if exists faculty_academic_pathways_department_semesters_check,
  drop constraint if exists faculty_academic_pathways_programme_semester_check,
  alter column department_selection_semester type integer,
  alter column department_effective_semester type integer,
  alter column programme_selection_semester type integer;
alter table public.student_academic_progressions alter column current_semester type integer;
alter table public.student_department_assignments
  alter column selection_semester type integer,
  alter column effective_semester type integer;
alter table public.student_programme_selections alter column selection_semester type integer;

create trigger sync_student_academic_level_legacy
before insert or update of current_semester, current_academic_level_id, faculty_id
on public.student_academic_progressions
for each row execute function private.sync_student_academic_level_legacy();
create trigger sync_student_department_selection_level_legacy
before insert or update of selection_level_id, effective_level_id, selection_semester, effective_semester
on public.student_department_assignments
for each row execute function private.sync_student_selection_level_legacy();
create trigger sync_student_programme_selection_level_legacy
before insert or update of selection_level_id, selection_semester
on public.student_programme_selections
for each row execute function private.sync_student_selection_level_legacy();

create policy "students submit their own department choices"
on public.student_department_assignments for insert to authenticated
with check (
  tenant_id = (select private.tenant_id())
  and student_id = (select auth.uid())
  and status = 'pending'
  and exists (
    select 1 from public.student_academic_progressions p
    join public.academic_levels current_level
      on current_level.id = p.current_academic_level_id and current_level.tenant_id = p.tenant_id
    join public.academic_progression_rules rule
      on rule.tenant_id = p.tenant_id and rule.faculty_id = p.faculty_id
      and rule.action_key = 'department_selection' and rule.is_enabled
    join public.academic_levels selection_level
      on selection_level.id = rule.selection_level_id and selection_level.tenant_id = rule.tenant_id
    left join public.academic_levels effective_level
      on effective_level.id = rule.effective_level_id and effective_level.tenant_id = rule.tenant_id
    where p.tenant_id = student_department_assignments.tenant_id
      and p.student_id = student_department_assignments.student_id
      and p.faculty_id = student_department_assignments.faculty_id
      and current_level.sequence_number >= coalesce(effective_level.sequence_number, selection_level.sequence_number)
      and p.credits_earned >= rule.minimum_credits
      and student_department_assignments.selection_level_id = rule.selection_level_id
      and student_department_assignments.effective_level_id is not distinct from rule.effective_level_id
  )
);

create policy "students submit their own semester eight programme choice"
on public.student_programme_selections for insert to authenticated
with check (
  tenant_id = (select private.tenant_id())
  and student_id = (select auth.uid())
  and status = 'pending'
  and exists (
    select 1 from public.student_academic_progressions p
    join public.academic_levels current_level
      on current_level.id = p.current_academic_level_id and current_level.tenant_id = p.tenant_id
    join public.academic_progression_rules rule
      on rule.tenant_id = p.tenant_id and rule.faculty_id = p.faculty_id
      and rule.action_key = 'programme_selection' and rule.is_enabled
    join public.academic_levels selection_level
      on selection_level.id = rule.selection_level_id and selection_level.tenant_id = rule.tenant_id
    where p.tenant_id = student_programme_selections.tenant_id
      and p.student_id = student_programme_selections.student_id
      and current_level.sequence_number >= selection_level.sequence_number
      and p.credits_earned >= rule.minimum_credits
      and student_programme_selections.selection_level_id = rule.selection_level_id
      and (not rule.requires_department_assignment or exists (
        select 1 from public.student_department_assignments assignment
        where assignment.tenant_id = p.tenant_id and assignment.student_id = p.student_id
          and assignment.status = 'approved' and assignment.ends_on is null
          and assignment.department_id = student_programme_selections.department_id
      ))
  )
);
