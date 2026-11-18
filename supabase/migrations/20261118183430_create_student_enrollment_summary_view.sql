-- Term-level enrollment summary for the authenticated student.
-- The enrollment_status enum has no pending state; expose only statuses actually stored.
CREATE OR REPLACE VIEW public.student_enrollment_summary
WITH (security_invoker = true)
AS
SELECT
  e.tenant_id,
  e.student_id,
  term.id AS term_id,
  term.code AS term_code,
  term.name AS term_name,
  COUNT(*)::integer AS total_enrollments,
  COUNT(*) FILTER (WHERE e.status = 'enrolled'::public.enrollment_status)::integer AS enrolled_courses_count,
  COUNT(*) FILTER (WHERE e.status = 'waitlisted'::public.enrollment_status)::integer AS waitlisted_courses_count,
  COUNT(*) FILTER (WHERE e.status = 'dropped'::public.enrollment_status)::integer AS dropped_courses_count,
  COUNT(*) FILTER (WHERE e.status = 'withdrawn'::public.enrollment_status)::integer AS withdrawn_courses_count,
  COUNT(*) FILTER (WHERE e.status = 'completed'::public.enrollment_status)::integer AS completed_courses_count,
  COUNT(*) FILTER (WHERE e.status = 'failed'::public.enrollment_status)::integer AS failed_courses_count,
  COUNT(*) FILTER (WHERE e.status = 'incomplete'::public.enrollment_status)::integer AS incomplete_courses_count,
  COALESCE(SUM(course.credit_hours) FILTER (WHERE e.status = 'enrolled'::public.enrollment_status), 0) AS registered_credit_hours,
  MAX(e.status_changed_at) AS last_updated_at
FROM public.enrollments AS e
LEFT JOIN public.course_offerings AS offering
  ON offering.id = e.offering_id
 AND offering.tenant_id = e.tenant_id
JOIN public.terms AS term
  ON term.id = COALESCE(e.term_id, offering.term_id)
 AND term.tenant_id = e.tenant_id
JOIN public.courses AS course
  ON course.id = COALESCE(e.course_id, offering.course_id)
 AND course.tenant_id = e.tenant_id
WHERE e.student_id = (SELECT auth.uid())
GROUP BY e.tenant_id, e.student_id, term.id, term.code, term.name;

REVOKE ALL ON public.student_enrollment_summary FROM PUBLIC, anon;
GRANT SELECT ON public.student_enrollment_summary TO authenticated;
