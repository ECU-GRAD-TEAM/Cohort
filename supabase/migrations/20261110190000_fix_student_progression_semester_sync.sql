-- Repair progression synchronization after academic_levels was replaced by academic_semesters.
create or replace function private.sync_student_academic_level_legacy()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  semester_sequence integer;
begin
  if new.current_academic_level_id is null
     or (tg_op = 'UPDATE'
         and new.current_semester is distinct from old.current_semester
         and new.current_academic_level_id is not distinct from old.current_academic_level_id) then
    select s.id
      into new.current_academic_level_id
    from public.academic_semesters s
    where s.tenant_id = new.tenant_id
      and s.faculty_id = new.faculty_id
      and s.sequence_number = new.current_semester
      and s.is_active;

    if new.current_academic_level_id is null then
      raise exception 'No active academic semester matches the supplied progression sequence';
    end if;
  else
    select s.sequence_number
      into semester_sequence
    from public.academic_semesters s
    where s.id = new.current_academic_level_id
      and s.tenant_id = new.tenant_id
      and s.faculty_id = new.faculty_id;

    if semester_sequence is null then
      raise exception 'Academic semester must belong to the student faculty and tenant';
    end if;

    new.current_semester := semester_sequence;
  end if;

  return new;
end;
$function$;
