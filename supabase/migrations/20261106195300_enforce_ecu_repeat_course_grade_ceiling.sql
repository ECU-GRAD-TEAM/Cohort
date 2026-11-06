-- Enforce ECU's repeat-course grade ceiling.
-- A previous non-dropped/non-withdrawn registration makes a later registration a repeat.
-- Repeat attempts are capped at B+ (3.3); original percentage is retained.
-- A passing previous result at or above B+ cannot be repeated solely for grade improvement.

create or replace function private.enforce_ecu_repeat_course_policy()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_course_id uuid;
  v_is_repeat boolean;
  v_best_previous_points numeric;
begin
  select o.course_id
    into v_course_id
  from public.course_offerings o
  where o.id = new.offering_id
    and o.tenant_id = new.tenant_id;

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
      and prior.status not in ('dropped'::public.enrollment_status, 'withdrawn'::public.enrollment_status, 'waitlisted'::public.enrollment_status)
  ), max(prior.final_grade_points) filter (
    where prior.status in ('completed'::public.enrollment_status, 'failed'::public.enrollment_status)
  )
  into v_is_repeat, v_best_previous_points
  from public.enrollments prior
  join public.course_offerings prior_offering
    on prior_offering.id = prior.offering_id
   and prior_offering.tenant_id = prior.tenant_id
  where prior.student_id = new.student_id
    and prior.tenant_id = new.tenant_id
    and prior_offering.course_id = v_course_id
    and prior.id <> new.id
    and prior.status not in ('dropped'::public.enrollment_status, 'withdrawn'::public.enrollment_status, 'waitlisted'::public.enrollment_status);

  if tg_op = 'INSERT' and v_is_repeat and coalesce(v_best_previous_points, 0) >= 3.3 then
    raise exception 'This course cannot be repeated for grade improvement because the previous grade is already B+ or higher'
      using errcode = 'check_violation';
  end if;

  if tg_op = 'UPDATE'
     and new.final_grade_points is not null
     and v_is_repeat
     and new.final_grade_points > 3.3 then
    new.final_grade_letter := 'B+';
    new.final_grade_points := 3.3;
  end if;

  return new;
end;
$$;

drop trigger if exists enrollments_ecu_repeat_policy on public.enrollments;
create trigger enrollments_ecu_repeat_policy
before insert or update of final_percentage, final_grade_letter, final_grade_points, status
on public.enrollments
for each row
execute function private.enforce_ecu_repeat_course_policy();

comment on function private.enforce_ecu_repeat_course_policy() is
'Enforces ECU repeat-course policy: non-dropped prior registration triggers a B+ (3.3) maximum on subsequent attempts; grade-improvement repeats are blocked when the previous recorded grade is already B+ or higher.';
