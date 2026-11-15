CREATE OR REPLACE VIEW public.student_assessments
WITH (security_invoker = true)
AS
SELECT
 g.id AS result_id, g.tenant_id, g.student_id, g.enrollment_id, g.offering_id,
 o.course_id, c.code AS course_code, c.title AS course_title,
 c.credit_hours::numeric(8,2) AS credit_hours, o.term_id, t.code AS term_code, t.name AS term_name,
 ay.code AS academic_year_code, ay.name AS academic_year_name,
 'assessment'::text AS result_type, 'assessment'::text AS component_type,
 COALESCE(gc.name,a.title,'Assessment'::text) AS component_name,
 g.component_id, g.assessment_id, a.title AS assessment_title,
 g.score::numeric AS score, g.max_score::numeric AS max_score,
 NULL::text AS grade_letter, NULL::numeric AS grade_points,
 g.status::text AS result_status, NULL::text AS attendance_status,
 NULL::text AS gpa_exclusion_reason, g.published_at AS recorded_at
FROM public.grade_entries g
JOIN public.course_offerings o ON o.id=g.offering_id AND o.tenant_id=g.tenant_id
JOIN public.courses c ON c.id=o.course_id AND c.tenant_id=o.tenant_id
JOIN public.terms t ON t.id=o.term_id AND t.tenant_id=o.tenant_id
LEFT JOIN public.academic_years ay ON ay.id=t.academic_year_id AND ay.tenant_id=t.tenant_id
LEFT JOIN public.grade_components gc ON gc.id=g.component_id AND gc.tenant_id=g.tenant_id
LEFT JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id
WHERE g.status='published'::public.grade_status
AND NOT EXISTS (SELECT 1 FROM public.grade_entries newer WHERE newer.supersedes_id=g.id AND newer.status='published'::public.grade_status)
UNION ALL
SELECT
 ar.id AS result_id, ar.tenant_id, ar.student_id, e.id AS enrollment_id, o.id AS offering_id,
 o.course_id, c.code AS course_code, c.title AS course_title,
 c.credit_hours::numeric(8,2) AS credit_hours, o.term_id, t.code AS term_code, t.name AS term_name,
 ay.code AS academic_year_code, ay.name AS academic_year_name,
 'attendance'::text AS result_type, 'attendance'::text AS component_type,
 'Attendance'::text AS component_name, NULL::uuid AS component_id,
 NULL::uuid AS assessment_id, NULL::text AS assessment_title,
 NULL::numeric AS score, NULL::numeric AS max_score, NULL::text AS grade_letter,
 NULL::numeric AS grade_points, ar.status::text AS result_status,
 ar.status::text AS attendance_status, NULL::text AS gpa_exclusion_reason,
 COALESCE(ar.confirmed_at,ar.checked_in_at,ats.starts_at) AS recorded_at
FROM public.attendance_records ar
JOIN public.attendance_sessions ats ON ats.id=ar.session_id AND ats.tenant_id=ar.tenant_id
JOIN public.sections s ON s.id=ats.section_id AND s.tenant_id=ats.tenant_id
JOIN public.course_offerings o ON o.id=s.offering_id AND o.tenant_id=s.tenant_id
JOIN public.enrollments e ON e.student_id=ar.student_id AND e.offering_id=o.id AND e.tenant_id=ar.tenant_id
JOIN public.courses c ON c.id=o.course_id AND c.tenant_id=o.tenant_id
JOIN public.terms t ON t.id=o.term_id AND t.tenant_id=o.tenant_id
LEFT JOIN public.academic_years ay ON ay.id=t.academic_year_id AND ay.tenant_id=t.tenant_id;
