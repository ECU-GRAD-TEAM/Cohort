-- Extend scoped academic leadership visibility to programme membership and grades.

CREATE OR REPLACE FUNCTION private.has_permission_for_program(p_permission text,p_program_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.programs p
    WHERE p.id=p_program_id AND p.tenant_id=private.tenant_id()
      AND private.has_permission(p_permission,'department',p.department_id)
  )
$$;
REVOKE EXECUTE ON FUNCTION private.has_permission_for_program(text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.has_permission_for_program(text,uuid) TO authenticated;

DROP POLICY IF EXISTS "registrars write programme membership" ON public.student_programs;
CREATE POLICY "registrars write programme membership" ON public.student_programs
FOR ALL TO authenticated
USING (tenant_id=(SELECT private.tenant_id()) AND private.has_permission_for_program('enrollment.manage',program_id))
WITH CHECK (tenant_id=(SELECT private.tenant_id()) AND private.has_permission_for_program('enrollment.manage',program_id));

DROP POLICY IF EXISTS "students, their staff and registrars read programme membership" ON public.student_programs;
CREATE POLICY "students, their staff and registrars read programme membership" ON public.student_programs
FOR SELECT TO authenticated
USING (tenant_id=(SELECT private.tenant_id())
  AND (private.can_view_student(student_id) OR private.has_permission_for_program('enrollment.manage',program_id)));

DROP POLICY IF EXISTS "students, teachers, advisors and registrars read enrolments" ON public.enrollments;
CREATE POLICY "students, teachers, advisors and registrars read enrolments" ON public.enrollments
FOR SELECT TO authenticated
USING (tenant_id=(SELECT private.tenant_id())
  AND (student_id=(SELECT auth.uid()) OR private.teaches_section(section_id)
    OR private.advises(student_id) OR private.has_record_grant(student_id)
    OR private.has_permission_for_offering('enrollment.manage',offering_id)));

DROP POLICY IF EXISTS "teachers read grades for their offerings" ON public.grade_entries;
CREATE POLICY "teachers read grades for their offerings" ON public.grade_entries
FOR SELECT TO authenticated
USING (tenant_id=(SELECT private.tenant_id())
  AND (private.teaches_offering(offering_id) OR private.has_permission_for_offering('grades.manage',offering_id)));

DROP POLICY IF EXISTS "advisors and record holders read published grades" ON public.grade_entries;
CREATE POLICY "advisors and record holders read published grades" ON public.grade_entries
FOR SELECT TO authenticated
USING (tenant_id=(SELECT private.tenant_id()) AND status='published'::public.grade_status
  AND (private.advises(student_id) OR private.has_record_grant(student_id)
    OR private.has_permission_for_offering('grades.manage',offering_id)));

DROP POLICY IF EXISTS "students and their teachers read grade reviews" ON public.grade_reviews;
CREATE POLICY "students and their teachers read grade reviews" ON public.grade_reviews
FOR SELECT TO authenticated
USING (tenant_id=(SELECT private.tenant_id())
  AND (student_id=(SELECT auth.uid()) OR private.teaches_offering(offering_id)
    OR private.has_permission_for_offering('grades.manage',offering_id)));

DROP POLICY IF EXISTS "students and their staff read academic standing" ON public.academic_standings;
CREATE POLICY "students and their staff read academic standing" ON public.academic_standings
FOR SELECT TO authenticated
USING (tenant_id=(SELECT private.tenant_id())
  AND (private.can_view_student(student_id) OR private.has_permission_for_student('grades.manage',student_id)));
