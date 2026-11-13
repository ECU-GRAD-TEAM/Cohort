-- 20261110212400 renamed public.person_profiles to public.user_profiles but updated only
-- private.guard_identity_fields. Five functions still named the old table, so creating a user
-- (private.on_user_created), linking an Auth account (private.provision_auth_user_account), and the
-- checks that read a person's department failed with "relation does not exist".
--
-- GradProj's live copies of some of these differ from the migrations (they were edited directly),
-- so each function is rewritten from its own current definition, changing only the table name. A
-- function that no longer names the old table is left as it is.

DO $$
DECLARE
  f regprocedure;
  def text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'private.on_user_created()'::regprocedure,
    'private.provision_auth_user_account(uuid, text, timestamp with time zone, jsonb, jsonb)'::regprocedure,
    'private.has_permission_for_student(text, uuid)'::regprocedure,
    'private.in_department(uuid)'::regprocedure,
    'public.directory_search(text, integer)'::regprocedure
  ] LOOP
    def := pg_get_functiondef(f);
    IF def ~ 'public\.person_profiles\M' THEN
      EXECUTE regexp_replace(def, 'public\.person_profiles\M', 'public.user_profiles', 'g');
    END IF;
  END LOOP;
END
$$;

-- 20261112185500 moved an enrolment's sections to its assigned meetings (public.student_meetings)
-- and dropped enrollments.section_id, but these two still joined on it, so the policies that call
-- them (announcements, assessments, attendance sessions) failed. They now reach the section
-- through the assigned meetings, the same way the new enrolment read policy does.

CREATE OR REPLACE FUNCTION private.enrolled_in_section(p_section uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.enrollments e
    join public.student_meetings sm on sm.enrollment_id = e.id and sm.tenant_id = e.tenant_id
    join public.section_meetings m on m.id = sm.meeting_id and m.tenant_id = sm.tenant_id
    where m.section_id = p_section
      and e.student_id = (select auth.uid())
      and e.status in ('enrolled', 'completed', 'failed', 'incomplete')
  )
$function$
;

CREATE OR REPLACE FUNCTION private.teaches_student(p_student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.enrollments e
    join public.student_meetings sm on sm.enrollment_id = e.id and sm.tenant_id = e.tenant_id
    join public.section_meetings m on m.id = sm.meeting_id and m.tenant_id = sm.tenant_id
    join public.section_instructors si on si.section_id = m.section_id
    where e.student_id = p_student
      and si.user_id = (select auth.uid())
      and e.status in ('enrolled', 'waitlisted', 'completed', 'failed', 'incomplete')
  )
  or exists (
    select 1
    from public.enrollments e
    join public.course_offerings o on o.id = e.offering_id
    where e.student_id = p_student
      and o.coordinator_id = (select auth.uid())
      and e.status in ('enrolled', 'waitlisted', 'completed', 'failed', 'incomplete')
  )
$function$
;

-- The same change left this trigger reading new.section_id, so inserting any enrolment failed.
-- A historical record is the one without an offering.

CREATE OR REPLACE FUNCTION private.enforce_ecu_repeat_course_policy()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_course_id uuid;
  v_is_repeat boolean;
begin
  -- Historical academic records have no live offering/section.
  if new.offering_id is null then
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
$function$
;

-- 20261112185500 also made the enrolment read policy look into public.student_meetings, whose own
-- read policy looks back into public.enrollments. Postgres refuses that loop ("infinite recursion
-- detected in policy for relation enrollments"), so every enrolment read by a student or teacher
-- failed. The teacher check now runs in a SECURITY DEFINER helper, like private.teaches_section, so
-- the policy no longer reads student_meetings under row-level security. Who may read what is
-- unchanged.

CREATE OR REPLACE FUNCTION private.teaches_enrollment(p_enrollment uuid, p_tenant uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.student_meetings sm
    join public.section_meetings m on m.id = sm.meeting_id and m.tenant_id = sm.tenant_id
    where sm.enrollment_id = p_enrollment
      and sm.tenant_id = p_tenant
      and private.teaches_section(m.section_id)
  )
$function$;

REVOKE ALL ON FUNCTION private.teaches_enrollment(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.teaches_enrollment(uuid, uuid) TO authenticated, service_role;

DROP POLICY "students, teachers, advisors and registrars read enrolments" ON public.enrollments;
CREATE POLICY "students, teachers, advisors and registrars read enrolments"
ON public.enrollments FOR SELECT TO authenticated
USING (
  tenant_id = (select private.tenant_id())
  and (
    student_id = (select auth.uid())
    or private.advises(student_id)
    or private.has_record_grant(student_id)
    or private.has_permission_for_offering('enrollment.manage'::text, offering_id)
    or private.teaches_enrollment(id, tenant_id)
  )
);
