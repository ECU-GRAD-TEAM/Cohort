
create or replace function private.validate_student_academic_progression()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  account_type public.user_type;
begin
  select user_type into account_type
  from public.users
  where id = new.student_id and tenant_id = new.tenant_id;

  if account_type is distinct from 'student'::public.user_type then
    raise exception 'Academic progression can only be assigned to student accounts';
  end if;
  return new;
end;
$$;

create trigger validate_student_academic_progression
before insert or update of student_id, tenant_id
on public.student_academic_progressions
for each row execute function private.validate_student_academic_progression();

create or replace function private.sync_approved_student_programme()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'approved' and new.ends_on is null then
    insert into public.student_programs (
      student_id, program_id, tenant_id, status, admitted_on, level
    )
    values (
      new.student_id, new.program_id, new.tenant_id,
      'active'::public.program_membership_status,
      coalesce(new.starts_on, current_date), 8
    )
    on conflict (student_id, program_id) do update
      set status = 'active'::public.program_membership_status,
          admitted_on = coalesce(public.student_programs.admitted_on, excluded.admitted_on),
          level = 8;
  elsif tg_op = 'UPDATE'
    and old.status = 'approved'
    and (new.status <> 'approved' or new.ends_on is not null) then
    update public.student_programs
    set status = case
      when new.status = 'superseded' then 'transferred'::public.program_membership_status
      else 'withdrawn'::public.program_membership_status
    end
    where student_id = new.student_id
      and program_id = new.program_id
      and tenant_id = new.tenant_id
      and status = 'active'::public.program_membership_status;
  end if;
  return new;
end;
$$;
