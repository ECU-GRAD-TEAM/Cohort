-- Backward-compatible writes for applications still sending numeric semester values,
-- plus indexes covering all new academic progression foreign keys.

create or replace function private.sync_student_academic_level_legacy()
returns trigger language plpgsql set search_path = '' as $$
declare level_sequence integer;
begin
  if new.current_academic_level_id is null then
    select id into new.current_academic_level_id from public.academic_levels
    where tenant_id = new.tenant_id and faculty_id = new.faculty_id
      and sequence_number = new.current_semester and is_active;
  else
    select sequence_number into level_sequence from public.academic_levels
    where id = new.current_academic_level_id and tenant_id = new.tenant_id;
    new.current_semester := level_sequence;
  end if;
  return new;
end;
$$;
drop trigger if exists sync_student_academic_level_legacy on public.student_academic_progressions;
create trigger sync_student_academic_level_legacy
before insert or update of current_semester, current_academic_level_id, faculty_id
on public.student_academic_progressions
for each row execute function private.sync_student_academic_level_legacy();

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
drop trigger if exists sync_student_department_selection_level_legacy on public.student_department_assignments;
drop trigger if exists sync_student_programme_selection_level_legacy on public.student_programme_selections;
create trigger sync_student_department_selection_level_legacy
before insert or update of selection_level_id, effective_level_id, selection_semester, effective_semester
on public.student_department_assignments
for each row execute function private.sync_student_selection_level_legacy();
create trigger sync_student_programme_selection_level_legacy
before insert or update of selection_level_id, selection_semester
on public.student_programme_selections
for each row execute function private.sync_student_selection_level_legacy();

create index if not exists academic_levels_faculty_fk_idx on public.academic_levels (faculty_id, tenant_id);
create index if not exists academic_progression_rules_faculty_fk_idx on public.academic_progression_rules (faculty_id, tenant_id);
create index if not exists academic_progression_rules_selection_level_fk_idx on public.academic_progression_rules (selection_level_id, tenant_id);
create index if not exists academic_progression_rules_effective_level_fk_idx on public.academic_progression_rules (effective_level_id, tenant_id);
create index if not exists faculty_pathways_department_selection_level_fk_idx on public.faculty_academic_pathways (department_selection_level_id, tenant_id);
create index if not exists faculty_pathways_department_effective_level_fk_idx on public.faculty_academic_pathways (department_effective_level_id, tenant_id);
create index if not exists faculty_pathways_programme_selection_level_fk_idx on public.faculty_academic_pathways (programme_selection_level_id, tenant_id);
create index if not exists student_progressions_current_level_fk_idx on public.student_academic_progressions (current_academic_level_id, tenant_id);
create index if not exists student_department_selection_level_fk_idx on public.student_department_assignments (selection_level_id, tenant_id);
create index if not exists student_department_effective_level_fk_idx on public.student_department_assignments (effective_level_id, tenant_id);
create index if not exists student_programme_selection_level_fk_idx on public.student_programme_selections (selection_level_id, tenant_id);
