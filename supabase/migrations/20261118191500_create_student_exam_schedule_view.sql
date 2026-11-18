-- Read-only exam schedule scoped to the authenticated student's own active/completed course enrollments.
-- Seat assignment rows are additionally protected by their own RLS policy until release.
CREATE OR REPLACE VIEW public.student_exam_schedule
WITH (security_invoker = true)
AS
SELECT
  e.tenant_id, e.student_id, e.id AS enrollment_id, x.id AS exam_session_id,
  o.id AS offering_id, c.id AS course_id, c.code AS course_code, c.title AS course_title,
  t.id AS term_id, t.code AS term_code, t.name AS term_name,
  ay.id AS academic_year_id, ay.code AS academic_year_code, ay.name AS academic_year_name,
  x.title AS exam_title, a.title AS assessment_title, a.kind::text AS assessment_kind,
  x.mode::text AS exam_mode, x.starts_at, x.ends_at, x.instructions, x.seats_released_at,
  CASE WHEN x.seats_released_at <= now() THEN seat.room_id END AS room_id,
  CASE WHEN x.seats_released_at <= now() THEN r.code END AS room_code,
  CASE WHEN x.seats_released_at <= now() THEN r.name END AS room_name,
  CASE WHEN x.seats_released_at <= now() THEN b.code END AS building_code,
  CASE WHEN x.seats_released_at <= now() THEN b.name END AS building_name,
  CASE WHEN x.seats_released_at <= now() THEN seat.seat_number END AS seat_number,
  e.status::text AS enrollment_status
FROM public.enrollments AS e
JOIN public.course_offerings AS o ON o.id=e.offering_id AND o.tenant_id=e.tenant_id
JOIN public.exam_sessions AS x ON x.offering_id=o.id AND x.tenant_id=o.tenant_id
JOIN public.courses AS c ON c.id=o.course_id AND c.tenant_id=o.tenant_id
JOIN public.terms AS t ON t.id=o.term_id AND t.tenant_id=o.tenant_id
LEFT JOIN public.academic_years AS ay ON ay.id=t.academic_year_id AND ay.tenant_id=t.tenant_id
LEFT JOIN public.assessments AS a ON a.id=x.assessment_id AND a.tenant_id=x.tenant_id
LEFT JOIN LATERAL (
  SELECT sa.room_id, sa.seat_number FROM public.seat_assignments AS sa
  WHERE sa.exam_session_id=x.id AND sa.student_id=e.student_id AND sa.tenant_id=e.tenant_id
  LIMIT 1
) AS seat ON true
LEFT JOIN public.rooms AS r ON r.id=seat.room_id AND r.tenant_id=e.tenant_id
LEFT JOIN public.buildings AS b ON b.id=r.building_id AND b.tenant_id=r.tenant_id
WHERE e.student_id=(SELECT auth.uid())
  AND e.status IN ('enrolled'::public.enrollment_status,'completed'::public.enrollment_status,
                   'failed'::public.enrollment_status,'incomplete'::public.enrollment_status);

REVOKE ALL ON public.student_exam_schedule FROM PUBLIC, anon;
GRANT SELECT ON public.student_exam_schedule TO authenticated;
