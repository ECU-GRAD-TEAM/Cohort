-- 20261110212400 renamed public.person_profiles to public.user_profiles but updated only
-- private.guard_identity_fields. These five functions still named the old table, so creating a
-- user (private.on_user_created), linking an Auth account (private.provision_auth_user_account),
-- and the checks that read a person's department failed with "relation does not exist".
-- Each is redefined unchanged except for the table name.

CREATE OR REPLACE FUNCTION private.on_user_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.user_profiles (user_id, tenant_id, display_name)
  VALUES (NEW.id, NEW.tenant_id, split_part(NEW.email, '@', 1))
  ON CONFLICT (user_id) DO NOTHING;
  -- Do not assign roles from broad staff/not_staff classification.
  RETURN NEW;
END;
$function$

;

CREATE OR REPLACE FUNCTION private.provision_auth_user_account(p_user_id uuid, p_email text, p_email_confirmed_at timestamp with time zone, p_raw_app_meta_data jsonb, p_raw_user_meta_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_tenant_text text;
  v_tenant uuid;
  v_type public.user_type;
  v_existing_tenant uuid;
  v_existing_type public.user_type;
  v_status public.account_status;
BEGIN
  IF p_user_id IS NULL OR p_email IS NULL THEN
    RAISE EXCEPTION 'Auth account requires an id and email'
      USING ERRCODE = 'check_violation';
  END IF;

  v_tenant_text := nullif(btrim(coalesce(p_raw_app_meta_data ->> 'tenant_id', '')), '');
  IF v_tenant_text IS NULL
     AND nullif(btrim(coalesce(p_raw_app_meta_data ->> 'user_type', '')), '') IS NULL THEN
    RETURN;
  END IF;

  IF v_tenant_text IS NULL THEN
    RAISE EXCEPTION 'Trusted app_metadata requires tenant_id'
      USING ERRCODE = 'check_violation';
  END IF;

  BEGIN
    v_tenant := v_tenant_text::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Auth account requires a valid app_metadata tenant_id'
      USING ERRCODE = 'check_violation';
  END;

  v_type := CASE p_raw_app_meta_data ->> 'user_type'
    WHEN 'staff' THEN 'staff'::public.user_type
    WHEN 'non_staff' THEN 'non_staff'::public.user_type
    ELSE NULL
  END;

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'Auth account requires app_metadata user_type staff or non_staff'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = v_tenant AND t.status = 'active'
  ) THEN
    RAISE EXCEPTION 'The requested tenant does not exist or is not active'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_status := CASE
    WHEN p_email_confirmed_at IS NULL
      THEN 'invited'::public.account_status
    ELSE 'active'::public.account_status
  END;

  INSERT INTO public.users (id, tenant_id, user_type, status, email, institutional_id)
  VALUES (
    p_user_id,
    v_tenant,
    v_type,
    v_status,
    lower(p_email),
    nullif(p_raw_app_meta_data ->> 'institutional_id', '')
  )
  ON CONFLICT (id) DO NOTHING;

  SELECT u.tenant_id, u.user_type
  INTO v_existing_tenant, v_existing_type
  FROM public.users u
  WHERE u.id = p_user_id;

  IF NOT FOUND
     OR v_existing_tenant IS DISTINCT FROM v_tenant
     OR v_existing_type IS DISTINCT FROM v_type THEN
    RAISE EXCEPTION 'Existing university account does not match trusted Auth tenant and user_type metadata'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.user_profiles
  SET display_name = coalesce(
    nullif(btrim(p_raw_user_meta_data ->> 'full_name'), ''),
    display_name
  )
  WHERE user_id = p_user_id;
END;
$function$

;

CREATE OR REPLACE FUNCTION private.has_permission_for_student(p_permission text, p_student_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles pp
    WHERE pp.user_id = p_student_id AND pp.tenant_id = private.tenant_id()
      AND (private.has_permission(p_permission, 'department', pp.department_id)
        OR (pp.department_id IS NULL AND private.has_permission(p_permission, 'faculty', pp.faculty_id)))
  )
$function$

;

CREATE OR REPLACE FUNCTION private.in_department(p_department uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.user_profiles p
    where p.user_id = (select auth.uid()) and p.department_id = p_department
  )
  or exists (
    select 1
    from public.student_programs sp
    join public.programs pr on pr.id = sp.program_id
    where sp.student_id = (select auth.uid()) and sp.status = 'active' and pr.department_id = p_department
  )
$function$

;

CREATE OR REPLACE FUNCTION public.directory_search(p_query text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS TABLE(user_id uuid, user_type user_type, display_name text, title text, email text, phone text, avatar_path text, bio text, office_location text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    u.id,
    u.user_type,
    p.display_name,
    p.title,
    case when private.field_visible_to_me(u.id, u.user_type, 'email') then u.email end,
    case when private.field_visible_to_me(u.id, u.user_type, 'phone') then primary_phone.phone_number end,
    case when private.field_visible_to_me(u.id, u.user_type, 'avatar') then p.avatar_path end,
    case when private.field_visible_to_me(u.id, u.user_type, 'bio') then p.bio end,
    case when private.field_visible_to_me(u.id, u.user_type, 'office_location') then p.office_location end
  from public.users u
  join public.user_profiles p on p.user_id = u.id
  left join lateral (
    select ppn.phone_number
    from public.person_profile_phones ppn
    where ppn.user_id = u.id
      and ppn.tenant_id = u.tenant_id
      and ppn.is_primary
    order by ppn.created_at desc
    limit 1
  ) primary_phone on true
  where u.tenant_id = private.tenant_id()
    and u.status = 'active'
    and (p_query is null or p.display_name ilike '%' || p_query || '%')
  order by p.display_name
  limit least(greatest(p_limit, 1), 200)
$function$

;

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
