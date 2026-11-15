-- Remove transcript-origin marker columns while preserving historical records.
-- Historical enrollments are identified structurally by having no live offering/section.

begin;

set local lock_timeout = '5s';

drop policy if exists "registrars manage historical enrolments" on public.enrollments;
create policy "registrars manage historical enrolments"
on public.enrollments
for all
to authenticated
using (
  offering_id is null
  and section_id is null
  and course_id is not null
  and term_id is not null
  and tenant_id = (select private.tenant_id())
  and private.has_permission_for_student('enrollment.manage'::text, student_id)
)
with check (
  offering_id is null
  and section_id is null
  and course_id is not null
  and term_id is not null
  and tenant_id = (select private.tenant_id())
  and private.has_permission_for_student('enrollment.manage'::text, student_id)
);

drop index if exists public.enrollments_historical_student_course_term_uidx;
drop index if exists public.enrollments_historical_student_term_idx;

create unique index enrollments_historical_student_course_term_uidx
  on public.enrollments (tenant_id, student_id, course_id, term_id)
  where offering_id is null and section_id is null;

create index enrollments_historical_student_term_idx
  on public.enrollments (tenant_id, student_id, term_id)
  where offering_id is null and section_id is null;

alter table public.enrollments
  drop constraint if exists enrollments_record_origin_check,
  drop constraint if exists enrollments_record_shape_check;

alter table public.enrollments
  add constraint enrollments_record_shape_check
  check (
    (
      offering_id is null
      and section_id is null
      and course_id is not null
      and term_id is not null
      and credit_hours_attempted is not null
      and final_grade_letter is not null
      and final_grade_points is not null
      and quality_points is not null
    )
    or
    (
      offering_id is not null
      and section_id is not null
      and course_id is null
      and term_id is null
      and credit_hours_attempted is null
      and quality_points is null
    )
  );

create or replace function private.enforce_ecu_repeat_course_policy()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_course_id uuid;
  v_is_repeat boolean;
begin
  -- Historical academic records have no live offering/section.
  if new.offering_id is null and new.section_id is null then
    return new;
  end if;

  select o.course_id into v_course_id
  from public.course_offerings o
  where o.id = new.offering_id and o.tenant_id = new.tenant_id;

  if v_course_id is null then
    raise exception 'Course offering was not found for this enrollment'
      using errcode = 'foreign_key_violation';
  end if;

  select exists (
    select 1
    from public.enrollments prior
    join public.course_offerings prior_offering
      on prior_offering.id = prior.offering_id
     and prior_offering.tenant_id = prior.tenant_id
    where prior.student_id = new.student_id
      and prior.tenant_id = new.tenant_id
      and prior_offering.course_id = v_course_id
      and prior.id <> new.id
      and prior.status not in (
        'dropped'::public.enrollment_status,
        'withdrawn'::public.enrollment_status,
        'waitlisted'::public.enrollment_status
      )
  ) into v_is_repeat;

  if v_is_repeat and new.final_grade_points is not null and new.final_grade_points > 3.3 then
    new.final_grade_letter := 'B+';
    new.final_grade_points := 3.3;
  end if;

  return new;
end;
$function$;

alter table public.gpa_snapshots
  drop constraint if exists gpa_snapshots_source_check;

alter table public.enrollments
  drop column if exists record_origin;

alter table public.gpa_snapshots
  drop column if exists snapshot_source;

commit;