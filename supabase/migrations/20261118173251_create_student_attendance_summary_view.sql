CREATE OR REPLACE VIEW public.student_attendance_summary
WITH (security_invoker = true)
AS
SELECT
  ar.tenant_id,
  ar.student_id,
  c.id AS course_id,
  c.code AS course_code,
  c.title AS course_title,
  t.id AS term_id,
  t.code AS term_code,
  t.name AS term_name,
  ay.id AS academic_year_id,
  ay.name AS academic_year_name,
  COUNT(*)::integer AS total_sessions,
  COUNT(*) FILTER (
    WHERE ar.status IN (
      'present'::public.attendance_status,
      'late'::public.attendance_status
    )
  )::integer AS attended_sessions,
  COUNT(*) FILTER (
    WHERE ar.status = 'absent'::public.attendance_status
  )::integer AS absent_sessions,
  COUNT(*) FILTER (
    WHERE ar.status = 'late'::public.attendance_status
  )::integer AS late_sessions,
  COUNT(*) FILTER (
    WHERE ar.status = 'excused'::public.attendance_status
  )::integer AS excused_sessions,
  ROUND(
    100.0 * COUNT(*) FILTER (
      WHERE ar.status IN (
        'present'::public.attendance_status,
        'late'::public.attendance_status
      )
    ) / NULLIF(
      COUNT(*) FILTER (
        WHERE ar.status IN (
          'present'::public.attendance_status,
          'late'::public.attendance_status,
          'absent'::public.attendance_status
        )
      ),
      0
    ),
    2
  ) AS attendance_percentage,
  ROUND(
    100.0 * COUNT(*) FILTER (
      WHERE ar.status = 'absent'::public.attendance_status
    ) / NULLIF(
      COUNT(*) FILTER (
        WHERE ar.status IN (
          'present'::public.attendance_status,
          'late'::public.attendance_status,
          'absent'::public.attendance_status
        )
      ),
      0
    ),
    2
  ) AS absence_percentage,
  MAX(s.starts_at)::date AS last_attendance_date
FROM public.attendance_records AS ar
JOIN public.attendance_sessions AS s
  ON s.id = ar.session_id
 AND s.tenant_id = ar.tenant_id
JOIN public.sections AS sec
  ON sec.id = s.section_id
 AND sec.tenant_id = s.tenant_id
JOIN public.course_offerings AS co
  ON co.id = sec.offering_id
 AND co.tenant_id = sec.tenant_id
JOIN public.courses AS c
  ON c.id = co.course_id
 AND c.tenant_id = co.tenant_id
JOIN public.terms AS t
  ON t.id = co.term_id
 AND t.tenant_id = co.tenant_id
LEFT JOIN public.academic_years AS ay
  ON ay.id = t.academic_year_id
 AND ay.tenant_id = t.tenant_id
WHERE ar.student_id = (SELECT auth.uid())
  AND ar.confirmation = 'confirmed'::public.confirmation_status
GROUP BY
  ar.tenant_id,
  ar.student_id,
  c.id,
  c.code,
  c.title,
  t.id,
  t.code,
  t.name,
  ay.id,
  ay.name;

GRANT SELECT ON public.student_attendance_summary TO authenticated;
REVOKE ALL ON public.student_attendance_summary FROM anon, PUBLIC;
