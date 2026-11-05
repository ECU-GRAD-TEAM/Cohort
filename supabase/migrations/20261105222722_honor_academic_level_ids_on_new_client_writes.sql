-- Academic-level UUIDs are authoritative for new clients; legacy sequence numbers
-- are translated only when an old client changes the numeric compatibility field.
create or replace function private.sync_student_academic_level_legacy()
returns trigger language plpgsql set search_path = '' as $$
declare level_sequence integer;
begin
  if new.current_academic_level_id is null
     or (tg_op = 'UPDATE' and new.current_semester is distinct from old.current_semester
         and new.current_academic_level_id is not distinct from old.current_academic_level_id) then
    select id into new.current_academic_level_id from public.academic_levels
    where tenant_id = new.tenant_id and faculty_id = new.faculty_id
      and sequence_number = new.current_semester and is_active;
    if new.current_academic_level_id is null then
      raise exception 'No active academic level matches the supplied progression sequence';
    end if;
  else
    select sequence_number into level_sequence from public.academic_levels
    where id = new.current_academic_level_id and tenant_id = new.tenant_id and faculty_id = new.faculty_id;
    if level_sequence is null then raise exception 'Academic level must belong to the student faculty and tenant'; end if;
    new.current_semester := level_sequence;
  end if;
  return new;
end;
$$;

create or replace function private.sync_student_selection_level_legacy()
returns trigger language plpgsql set search_path = '' as $$
declare seq integer; faculty uuid; target_level uuid; effective_level uuid;
begin
  select p.faculty_id into faculty from public.student_academic_progressions p
  where p.tenant_id = new.tenant_id and p.student_id = new.student_id;
  if tg_table_name = 'student_department_assignments' then
    select selection_level_id, academic_progression_rules.effective_level_id
    into target_level, effective_level from public.academic_progression_rules
    where tenant_id = new.tenant_id and faculty_id = faculty
      and action_key = 'department_selection' and is_enabled;
    if new.selection_level_id is null
       or (tg_op = 'UPDATE' and new.selection_semester is distinct from old.selection_semester
           and new.selection_level_id is not distinct from old.selection_level_id) then
      select id into new.selection_level_id from public.academic_levels
      where tenant_id = new.tenant_id and faculty_id = faculty
        and sequence_number = new.selection_semester and is_active;
    end if;
    if new.effective_level_id is null
       or (tg_op = 'UPDATE' and new.effective_semester is distinct from old.effective_semester
           and new.effective_level_id is not distinct from old.effective_level_id) then
      select id into new.effective_level_id from public.academic_levels
      where tenant_id = new.tenant_id and faculty_id = faculty
        and sequence_number = new.effective_semester and is_active;
    end if;
    if new.selection_level_id is null then new.selection_level_id := target_level; end if;
    if new.effective_level_id is null then new.effective_level_id := effective_level; end if;
    if new.selection_level_id is null or new.effective_level_id is null then
      raise exception 'Department assignment levels must match configured active academic levels';
    end if;
    select sequence_number into seq from public.academic_levels
    where id = new.selection_level_id and tenant_id = new.tenant_id and faculty_id = faculty;
    new.selection_semester := seq;
    select sequence_number into seq from public.academic_levels
    where id = new.effective_level_id and tenant_id = new.tenant_id and faculty_id = faculty;
    new.effective_semester := seq;
  else
    select selection_level_id into target_level from public.academic_progression_rules
    where tenant_id = new.tenant_id and faculty_id = faculty
      and action_key = 'programme_selection' and is_enabled;
    if new.selection_level_id is null
       or (tg_op = 'UPDATE' and new.selection_semester is distinct from old.selection_semester
           and new.selection_level_id is not distinct from old.selection_level_id) then
      select id into new.selection_level_id from public.academic_levels
      where tenant_id = new.tenant_id and faculty_id = faculty
        and sequence_number = new.selection_semester and is_active;
    end if;
    if new.selection_level_id is null then new.selection_level_id := target_level; end if;
    if new.selection_level_id is null then raise exception 'Programme selection level must match a configured active academic level'; end if;
    select sequence_number into seq from public.academic_levels
    where id = new.selection_level_id and tenant_id = new.tenant_id and faculty_id = faculty;
    new.selection_semester := seq;
  end if;
  return new;
end;
$$;
