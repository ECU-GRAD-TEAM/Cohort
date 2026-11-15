-- Reduce the account classification to staff / not_staff.
-- Fine-grained authorization remains in user_roles and scoped appointments.

DROP POLICY IF EXISTS "staff manage their own office hours" ON public.office_hours;

DROP FUNCTION IF EXISTS public.directory_search(text, integer);
DROP FUNCTION IF EXISTS private.field_visible_to_me(uuid, public.user_type, text);
DROP FUNCTION IF EXISTS private.user_type();

ALTER TYPE public.user_type RENAME TO user_type_legacy;
CREATE TYPE public.user_type AS ENUM ('staff', 'not_staff');

ALTER TABLE public.users
  ALTER COLUMN user_type TYPE public.user_type
  USING (
    CASE user_type::text
      WHEN 'student' THEN 'not_staff'
      ELSE 'staff'
    END
  )::public.user_type;

DROP TYPE public.user_type_legacy;

CREATE OR REPLACE FUNCTION private.user_type()
RETURNS public.user_type
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT u.user_type FROM public.users u WHERE u.id = (SELECT auth.uid())
$function$;

CREATE OR REPLACE FUNCTION private.field_visible_to_me(p_owner uuid, p_owner_type public.user_type, p_field text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  WITH chosen AS (
    SELECT coalesce(
      (SELECT ps.audience FROM public.privacy_settings ps WHERE ps.user_id = p_owner AND ps.field = p_field),
      CASE
        WHEN p_field IN ('phone', 'personal_email', 'date_of_birth') THEN 'self'::public.audience
        WHEN p_field = 'email' AND p_owner_type = 'not_staff'::public.user_type THEN 'staff'::public.audience
        ELSE 'tenant'::public.audience
      END
    ) AS audience
  )
  SELECT p_owner = (SELECT auth.uid())
    OR audience = 'tenant'
    OR (audience = 'staff' AND private.user_type() = 'staff'::public.user_type)
  FROM chosen
$function$;

CREATE OR REPLACE FUNCTION public.directory_search(p_query text DEFAULT NULL, p_limit integer DEFAULT 50)
RETURNS TABLE(user_id uuid, user_type public.user_type, display_name text, title text, email text, phone text, avatar_path text, bio text, office_location text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT u.id, u.user_type, p.display_name, p.title,
    CASE WHEN private.field_visible_to_me(u.id, u.user_type, 'email') THEN u.email END,
    CASE WHEN private.field_visible_to_me(u.id, u.user_type, 'phone') THEN p.phone END,
    CASE WHEN private.field_visible_to_me(u.id, u.user_type, 'avatar') THEN p.avatar_path END,
    CASE WHEN private.field_visible_to_me(u.id, u.user_type, 'bio') THEN p.bio END,
    CASE WHEN private.field_visible_to_me(u.id, u.user_type, 'office_location') THEN p.office_location END
  FROM public.users u
  JOIN public.person_profiles p ON p.user_id = u.id
  WHERE u.tenant_id = private.tenant_id()
    AND u.status = 'active'
    AND (p_query IS NULL OR p.display_name ILIKE '%' || p_query || '%')
  ORDER BY p.display_name
  LIMIT least(greatest(p_limit, 1), 200)
$function$;

CREATE OR REPLACE FUNCTION private.is_staff_user(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = p_user AND u.tenant_id = private.tenant_id()
      AND u.user_type = 'staff'::public.user_type AND u.status = 'active'
  )
$function$;

CREATE OR REPLACE FUNCTION private.validate_student_academic_progression()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
DECLARE
  account_type public.user_type;
  has_student_role boolean;
BEGIN
  SELECT u.user_type INTO account_type FROM public.users u
  WHERE u.id = NEW.student_id AND u.tenant_id = NEW.tenant_id;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = NEW.student_id AND ur.tenant_id = NEW.tenant_id
      AND r.key = 'student' AND ur.assignment_status = 'active'
      AND ur.starts_at <= now() AND (ur.expires_at IS NULL OR ur.expires_at > now())
      AND ur.revoked_at IS NULL
  ) INTO has_student_role;

  IF account_type IS DISTINCT FROM 'not_staff'::public.user_type OR NOT has_student_role THEN
    RAISE EXCEPTION 'Academic progression requires a non-staff account with an active student role';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.on_user_created()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.person_profiles (user_id, tenant_id, display_name)
  VALUES (NEW.id, NEW.tenant_id, split_part(NEW.email, '@', 1))
  ON CONFLICT (user_id) DO NOTHING;
  -- Do not assign roles from broad staff/not_staff classification.
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.handle_new_auth_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_tenant uuid := nullif(NEW.raw_app_meta_data ->> 'tenant_id', '')::uuid;
  v_type public.user_type;
BEGIN
  v_type := CASE NEW.raw_app_meta_data ->> 'user_type'
    WHEN 'staff' THEN 'staff'::public.user_type
    WHEN 'not_staff' THEN 'not_staff'::public.user_type
    ELSE NULL
  END;
  IF v_tenant IS NULL OR v_type IS NULL THEN RETURN NEW; END IF;

  INSERT INTO public.users (id, tenant_id, user_type, email, institutional_id)
  VALUES (NEW.id, v_tenant, v_type, lower(NEW.email),
    nullif(NEW.raw_app_meta_data ->> 'institutional_id', ''));

  UPDATE public.person_profiles
  SET display_name = coalesce(nullif(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''), display_name)
  WHERE user_id = NEW.id;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.enroll_in_section(p_section uuid)
RETURNS public.enrollments LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_tenant uuid := private.tenant_id();
  v_section public.sections;
  v_offering public.course_offerings;
  v_course public.courses;
  v_term public.terms;
  v_enrolled integer;
  v_waiting integer;
  v_credits numeric;
  v_status public.enrollment_status;
  v_position integer;
  v_result public.enrollments;
BEGIN
  IF v_tenant IS NULL
     OR private.user_type() <> 'not_staff'::public.user_type
     OR NOT EXISTS (
       SELECT 1 FROM public.user_roles ur JOIN public.roles r ON r.id = ur.role_id
       WHERE ur.user_id = v_me AND ur.tenant_id = v_tenant AND r.key = 'student'
         AND ur.assignment_status = 'active' AND ur.starts_at <= now()
         AND (ur.expires_at IS NULL OR ur.expires_at > now()) AND ur.revoked_at IS NULL
     ) THEN
    RAISE EXCEPTION 'Only users with an active student role can register themselves'
      USING errcode = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_section FROM public.sections
  WHERE id = p_section AND tenant_id = v_tenant FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Section not found' USING errcode = 'no_data_found'; END IF;

  SELECT * INTO v_offering FROM public.course_offerings WHERE id = v_section.offering_id;
  SELECT * INTO v_course FROM public.courses WHERE id = v_offering.course_id;
  SELECT * INTO v_term FROM public.terms WHERE id = v_offering.term_id;

  IF v_offering.status <> 'published' THEN
    RAISE EXCEPTION 'This course is not open for registration' USING errcode = 'check_violation';
  END IF;
  IF v_term.registration_opens_at IS NULL OR now() < v_term.registration_opens_at
     OR now() > coalesce(v_term.add_drop_ends_at, v_term.registration_closes_at, 'infinity') THEN
    RAISE EXCEPTION 'Registration is closed for this term' USING errcode = 'check_violation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.enrollments e JOIN public.sections s ON s.id = e.section_id
    WHERE e.student_id = v_me AND e.offering_id = v_offering.id AND s.kind = v_section.kind
      AND e.status IN ('enrolled', 'waitlisted')
  ) THEN
    RAISE EXCEPTION 'Already registered in a % section of this course', v_section.kind
      USING errcode = 'unique_violation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.course_prerequisites p
    WHERE p.course_id = v_course.id AND NOT EXISTS (
      SELECT 1 FROM public.enrollments e JOIN public.course_offerings o ON o.id = e.offering_id
      WHERE e.student_id = v_me AND o.course_id = p.prerequisite_course_id
        AND (e.status = 'completed' OR
          (p.kind = 'corequisite' AND e.status = 'enrolled' AND o.term_id = v_term.id))
    )
  ) THEN
    RAISE EXCEPTION 'Prerequisites for % are not met', v_course.code USING errcode = 'check_violation';
  END IF;

  SELECT coalesce(sum(c.credit_hours), 0) INTO v_credits
  FROM public.courses c
  WHERE c.id IN (
    SELECT o.course_id FROM public.enrollments e
    JOIN public.course_offerings o ON o.id = e.offering_id
    WHERE e.student_id = v_me AND o.term_id = v_term.id AND e.status = 'enrolled'
  ) AND c.id <> v_course.id;

  IF v_credits + v_course.credit_hours >
    (SELECT t.max_credits_per_term FROM public.tenants t WHERE t.id = v_tenant) THEN
    RAISE EXCEPTION 'Registering would exceed the credit limit for the term' USING errcode = 'check_violation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.timetable_entries mine
    JOIN public.enrollments e ON e.section_id = mine.section_id
    JOIN public.course_offerings o ON o.id = e.offering_id
    JOIN public.timetable_entries new_slot ON new_slot.section_id = p_section
    WHERE e.student_id = v_me AND e.status = 'enrolled' AND o.term_id = v_term.id
      AND mine.weekday = new_slot.weekday AND mine.starts_at < new_slot.ends_at
      AND new_slot.starts_at < mine.ends_at
      AND daterange(mine.valid_from, mine.valid_until, '[]')
        && daterange(new_slot.valid_from, new_slot.valid_until, '[]')
  ) THEN
    RAISE EXCEPTION 'This section clashes with your timetable' USING errcode = 'check_violation';
  END IF;

  SELECT count(*) FILTER (WHERE e.status = 'enrolled'),
         count(*) FILTER (WHERE e.status = 'waitlisted')
  INTO v_enrolled, v_waiting FROM public.enrollments e WHERE e.section_id = p_section;

  IF v_section.capacity IS NULL OR v_enrolled < v_section.capacity THEN
    v_status := 'enrolled';
  ELSIF v_waiting < v_section.waitlist_capacity THEN
    v_status := 'waitlisted';
    v_position := v_waiting + 1;
  ELSE
    RAISE EXCEPTION 'This section is full' USING errcode = 'check_violation';
  END IF;

  INSERT INTO public.enrollments
    (tenant_id, student_id, section_id, offering_id, status, waitlist_position)
  VALUES (v_tenant, v_me, p_section, v_offering.id, v_status, v_position)
  ON CONFLICT (student_id, section_id) DO UPDATE
    SET status = EXCLUDED.status, waitlist_position = EXCLUDED.waitlist_position,
        status_changed_at = now()
  RETURNING * INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE POLICY "staff manage their own office hours"
ON public.office_hours FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND staff_id = (SELECT auth.uid()))
WITH CHECK (
  tenant_id = (SELECT private.tenant_id())
  AND staff_id = (SELECT auth.uid())
  AND (SELECT private.user_type()) = 'staff'::public.user_type
);
