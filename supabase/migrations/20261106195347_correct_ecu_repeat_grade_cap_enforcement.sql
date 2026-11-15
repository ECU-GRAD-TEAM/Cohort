-- Reapply the corrected repeat-grade cap function.
-- Kept as a separate migration because the initial version was already applied remotely.

create or replace function private.enforce_ecu_repeat_course_policy()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_course_id uuid;
  v_is_repeat boolean;
begin
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

  if v_is_repeat
     and new.final_grade_points is not null
     and new.final_grade_points > 3.3 then
    new.final_grade_letter := 'B+';
    new.final_grade_points := 3.3;
  end if;

  return new;
end;
$$;

comment on function private.enforce_ecu_repeat_course_policy() is
'Caps every subsequent non-dropped repeat attempt at B+ (3.3), regardless of the previous result. Dropped, withdrawn, and waitlisted registrations do not trigger the repeat cap. The original percentage is retained.';
