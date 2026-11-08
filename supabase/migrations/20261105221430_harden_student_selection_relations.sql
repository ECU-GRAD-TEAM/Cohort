
alter table public.student_department_assignments
  drop constraint student_department_assignments_reviewer_fkey;
alter table public.student_department_assignments
  add constraint student_department_assignments_reviewer_fkey
  foreign key (reviewed_by, tenant_id) references public.users(id, tenant_id) on delete restrict;

alter table public.student_programme_selections
  drop constraint student_programme_selections_reviewer_fkey;
alter table public.student_programme_selections
  add constraint student_programme_selections_reviewer_fkey
  foreign key (reviewed_by, tenant_id) references public.users(id, tenant_id) on delete restrict;

create index student_academic_progressions_faculty_fk_idx
  on public.student_academic_progressions (faculty_id, tenant_id);
create index student_department_assignments_faculty_fk_idx
  on public.student_department_assignments (faculty_id, tenant_id);
create index student_department_assignments_department_fk_idx
  on public.student_department_assignments (department_id, tenant_id);
create index student_department_assignments_reviewer_fk_idx
  on public.student_department_assignments (reviewed_by, tenant_id);
create index student_programme_selections_department_fk_idx
  on public.student_programme_selections (department_id, tenant_id);
create index student_programme_selections_program_fk_idx
  on public.student_programme_selections (program_id, tenant_id);
create index student_programme_selections_reviewer_fk_idx
  on public.student_programme_selections (reviewed_by, tenant_id);

create or replace function private.set_student_progression_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger set_student_progression_updated_at
before update on public.student_academic_progressions
for each row execute function private.set_student_progression_updated_at();

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
  end if;
  return new;
end;
$$;

create trigger sync_approved_student_programme
after insert or update of status, starts_on, ends_on, program_id
on public.student_programme_selections
for each row execute function private.sync_approved_student_programme();
