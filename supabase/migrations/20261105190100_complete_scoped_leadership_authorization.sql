-- Complete scoped leadership authorization and tenant role bootstrap.
-- Leadership appointments remain separate from academic rank and user_type.

INSERT INTO public.permissions (key, description)
VALUES ('appointments.manage', 'Create, update, end and revoke personnel appointments within the assigned scope')
ON CONFLICT (key) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO public.staff_positions (key, name, category, description, is_academic_rank)
VALUES
  ('dean', 'Dean', 'academic', 'Faculty-level academic leadership appointment.', false),
  ('vice_dean', 'Vice Dean', 'academic', 'Faculty-level deputy academic leadership appointment.', false),
  ('department_head', 'Department Head', 'academic', 'Department-level academic leadership appointment.', false)
ON CONFLICT (key) DO UPDATE SET
  name = EXCLUDED.name, category = EXCLUDED.category,
  description = EXCLUDED.description, is_academic_rank = EXCLUDED.is_academic_rank;

CREATE OR REPLACE FUNCTION private.seed_default_roles_for_tenant(p_tenant_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.roles (tenant_id, key, name, description, is_system)
  VALUES
    (p_tenant_id, 'dean', 'Dean', 'Faculty-scoped academic leadership role.', true),
    (p_tenant_id, 'vice_dean', 'Vice Dean', 'Faculty-scoped deputy academic leadership role.', true),
    (p_tenant_id, 'department_head', 'Department Head', 'Department-scoped academic leadership role.', true)
  ON CONFLICT (tenant_id, key) DO UPDATE
    SET name = EXCLUDED.name, description = EXCLUDED.description, is_system = true;

  INSERT INTO public.role_permissions (role_id, tenant_id, permission_key)
  SELECT r.id, r.tenant_id, p.permission_key
  FROM public.roles r
  CROSS JOIN (VALUES
    ('dean', 'academic.manage'), ('dean', 'analytics.view'),
    ('dean', 'grades.manage'), ('dean', 'enrollment.manage'),
    ('dean', 'exams.manage'), ('dean', 'announcements.publish'),
    ('dean', 'appointments.manage'),
    ('vice_dean', 'academic.manage'), ('vice_dean', 'analytics.view'),
    ('vice_dean', 'grades.manage'), ('vice_dean', 'exams.manage'),
    ('vice_dean', 'announcements.publish'), ('vice_dean', 'appointments.manage'),
    ('department_head', 'academic.manage'), ('department_head', 'analytics.view'),
    ('department_head', 'grades.manage'), ('department_head', 'enrollment.manage'),
    ('department_head', 'exams.manage'), ('department_head', 'announcements.publish'),
    ('department_head', 'appointments.manage')
  ) AS p(role_key, permission_key)
  WHERE r.tenant_id = p_tenant_id AND r.key = p.role_key
  ON CONFLICT (role_id, permission_key) DO NOTHING;
END;
$$;
REVOKE EXECUTE ON FUNCTION private.seed_default_roles_for_tenant(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.seed_default_roles_after_tenant_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  PERFORM private.seed_default_roles_for_tenant(NEW.id);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS tenants_seed_default_roles ON public.tenants;
CREATE TRIGGER tenants_seed_default_roles AFTER INSERT ON public.tenants
FOR EACH ROW EXECUTE FUNCTION private.seed_default_roles_after_tenant_insert();
SELECT private.seed_default_roles_for_tenant(t.id) FROM public.tenants t;

CREATE OR REPLACE FUNCTION private.has_permission_for_department(p_permission text, p_department_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT p_department_id IS NOT NULL
    AND private.has_permission(p_permission, 'department', p_department_id)
$$;

CREATE OR REPLACE FUNCTION private.has_permission_for_offering(p_permission text, p_offering_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.course_offerings co
    JOIN public.courses c ON c.id = co.course_id AND c.tenant_id = co.tenant_id
    WHERE co.id = p_offering_id AND co.tenant_id = private.tenant_id()
      AND (private.has_permission(p_permission, 'course', co.id)
        OR private.has_permission(p_permission, 'department', c.department_id))
  )
$$;

CREATE OR REPLACE FUNCTION private.has_permission_for_section(p_permission text, p_section_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.sections s
    WHERE s.id = p_section_id AND s.tenant_id = private.tenant_id()
      AND private.has_permission_for_offering(p_permission, s.offering_id)
  )
$$;

CREATE OR REPLACE FUNCTION private.has_permission_for_student(p_permission text, p_student_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.person_profiles pp
    WHERE pp.user_id = p_student_id AND pp.tenant_id = private.tenant_id()
      AND (private.has_permission(p_permission, 'department', pp.department_id)
        OR (pp.department_id IS NULL AND private.has_permission(p_permission, 'faculty', pp.faculty_id)))
  )
$$;

CREATE OR REPLACE FUNCTION private.has_permission_for_announcement(
  p_permission text, p_audience public.announcement_audience,
  p_department_id uuid, p_offering_id uuid, p_section_id uuid
)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_audience = 'department'::public.announcement_audience
      THEN private.has_permission(p_permission, 'department', p_department_id)
    WHEN p_audience = 'offering'::public.announcement_audience
      THEN private.has_permission_for_offering(p_permission, p_offering_id)
    WHEN p_audience = 'section'::public.announcement_audience
      THEN private.has_permission_for_section(p_permission, p_section_id)
    ELSE private.has_permission(p_permission)
  END
$$;

REVOKE EXECUTE ON FUNCTION private.has_permission_for_department(text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION private.has_permission_for_offering(text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION private.has_permission_for_section(text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION private.has_permission_for_student(text, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION private.has_permission_for_announcement(text, public.announcement_audience, uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_permission_for_department(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_permission_for_offering(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_permission_for_section(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_permission_for_student(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_permission_for_announcement(text, public.announcement_audience, uuid, uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.faculties;
CREATE POLICY "academic managers write the catalogue" ON public.faculties FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission('academic.manage', 'faculty', id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission('academic.manage', 'faculty', id));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.departments;
CREATE POLICY "academic managers write the catalogue" ON public.departments FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission('academic.manage', 'department', id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission('academic.manage', 'department', id));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.programs;
CREATE POLICY "academic managers write the catalogue" ON public.programs FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_department('academic.manage', department_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_department('academic.manage', department_id));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.courses;
CREATE POLICY "academic managers write the catalogue" ON public.courses FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_department('academic.manage', department_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_department('academic.manage', department_id));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.course_offerings;
CREATE POLICY "academic managers write the catalogue" ON public.course_offerings FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_offering('academic.manage', id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_offering('academic.manage', id));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.sections;
CREATE POLICY "academic managers write the catalogue" ON public.sections FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_section('academic.manage', id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_section('academic.manage', id));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.section_instructors;
CREATE POLICY "academic managers write the catalogue" ON public.section_instructors FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_section('academic.manage', section_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_section('academic.manage', section_id));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.timetable_entries;
CREATE POLICY "academic managers write the catalogue" ON public.timetable_entries FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_section('academic.manage', section_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_section('academic.manage', section_id));

DROP POLICY IF EXISTS "registrars write enrolments" ON public.enrollments;
CREATE POLICY "registrars write enrolments" ON public.enrollments FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_offering('enrollment.manage', offering_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_offering('enrollment.manage', offering_id));

DROP POLICY IF EXISTS "advisors, their students and registrars read assignments" ON public.advisor_assignments;
CREATE POLICY "advisors, their students and registrars read assignments" ON public.advisor_assignments FOR SELECT TO authenticated
USING (tenant_id = (SELECT private.tenant_id())
  AND (advisor_id = (SELECT auth.uid()) OR student_id = (SELECT auth.uid())
    OR private.has_permission_for_student('enrollment.manage', student_id)));

DROP POLICY IF EXISTS "registrars write advisor assignments" ON public.advisor_assignments;
CREATE POLICY "registrars write advisor assignments" ON public.advisor_assignments FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_student('enrollment.manage', student_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_student('enrollment.manage', student_id));

DROP POLICY IF EXISTS "exam managers write exam sessions" ON public.exam_sessions;
CREATE POLICY "exam managers write exam sessions" ON public.exam_sessions FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_offering('exams.manage', offering_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND private.has_permission_for_offering('exams.manage', offering_id));

DROP POLICY IF EXISTS "exam managers, teachers and students read exam sessions" ON public.exam_sessions;
CREATE POLICY "exam managers, teachers and students read exam sessions" ON public.exam_sessions FOR SELECT TO authenticated
USING (tenant_id = (SELECT private.tenant_id())
  AND (private.has_permission_for_offering('exams.manage', offering_id)
    OR private.teaches_offering(offering_id) OR private.enrolled_in_offering(offering_id)));

DROP POLICY IF EXISTS "exam managers write seat plans" ON public.seat_assignments;
CREATE POLICY "exam managers write seat plans" ON public.seat_assignments FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND EXISTS (
  SELECT 1 FROM public.exam_sessions es WHERE es.id = exam_session_id
    AND private.has_permission_for_offering('exams.manage', es.offering_id)))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND EXISTS (
  SELECT 1 FROM public.exam_sessions es WHERE es.id = exam_session_id
    AND private.has_permission_for_offering('exams.manage', es.offering_id)));

DROP POLICY IF EXISTS "grade managers record academic standing" ON public.academic_standings;
CREATE POLICY "grade managers record academic standing" ON public.academic_standings FOR INSERT TO authenticated
WITH CHECK (tenant_id = (SELECT private.tenant_id())
  AND private.has_permission_for_student('grades.manage', student_id)
  AND decided_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS "teachers announce to their courses, publishers to everyone" ON public.announcements;
CREATE POLICY "teachers announce to their courses, publishers to everyone" ON public.announcements FOR ALL TO authenticated
USING (tenant_id = (SELECT private.tenant_id())
  AND (private.has_permission_for_announcement('announcements.publish', audience, department_id, offering_id, section_id)
    OR (audience = 'offering'::public.announcement_audience AND private.teaches_offering(offering_id))
    OR (audience = 'section'::public.announcement_audience AND private.teaches_section(section_id))))
WITH CHECK (tenant_id = (SELECT private.tenant_id())
  AND (private.has_permission_for_announcement('announcements.publish', audience, department_id, offering_id, section_id)
    OR (audience = 'offering'::public.announcement_audience AND private.teaches_offering(offering_id))
    OR (audience = 'section'::public.announcement_audience AND private.teaches_section(section_id))));

DROP POLICY IF EXISTS "members read own appointments or account managers read all" ON public.personnel_appointments;
CREATE POLICY "members read own appointments or account managers read all" ON public.personnel_appointments FOR SELECT TO authenticated
USING (tenant_id = (SELECT private.tenant_id())
  AND (user_id = (SELECT auth.uid()) OR private.has_permission('appointments.manage', scope_type, scope_id)));

DROP POLICY IF EXISTS "account managers create appointments" ON public.personnel_appointments;
CREATE POLICY "account managers create appointments" ON public.personnel_appointments FOR INSERT TO authenticated
WITH CHECK (tenant_id = (SELECT private.tenant_id())
  AND private.has_permission('appointments.manage', scope_type, scope_id)
  AND appointed_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS "account managers update appointments" ON public.personnel_appointments;
CREATE POLICY "account managers update appointments" ON public.personnel_appointments FOR UPDATE TO authenticated
USING (tenant_id = (SELECT private.tenant_id())
  AND private.has_permission('appointments.manage', scope_type, scope_id))
WITH CHECK (tenant_id = (SELECT private.tenant_id())
  AND private.has_permission('appointments.manage', scope_type, scope_id));

CREATE OR REPLACE FUNCTION private.guard_personnel_appointment_actor()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.appointed_by IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'appointed_by must be the authenticated actor';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.appointed_by IS DISTINCT FROM OLD.appointed_by THEN
      RAISE EXCEPTION 'appointed_by is immutable';
    END IF;
    IF NEW.status IN ('ended', 'revoked') AND NEW.ended_by IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'ended_by must be the authenticated actor when ending or revoking an appointment';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS personnel_appointments_guard_actor ON public.personnel_appointments;
CREATE TRIGGER personnel_appointments_guard_actor BEFORE INSERT OR UPDATE ON public.personnel_appointments
FOR EACH ROW EXECUTE FUNCTION private.guard_personnel_appointment_actor();
