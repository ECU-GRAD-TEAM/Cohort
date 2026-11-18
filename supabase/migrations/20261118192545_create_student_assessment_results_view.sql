-- Student-facing individual assessment results, including only released feedback.
CREATE OR REPLACE VIEW public.student_assessment_results WITH (security_invoker = true) AS
SELECT g.id AS result_id, g.tenant_id, g.student_id, g.enrollment_id,
 sc.attempt_number, sc.enrollment_status, sc.course_id, sc.course_code, sc.course_title,
 sc.term_id, sc.term_code, sc.term_name, sc.academic_year_id, sc.academic_year_code, sc.academic_year_name,
 g.offering_id, COALESCE(g.component_id, a.component_id) AS component_id,
 gc.name AS component_name, gc.category::text AS component_type, gc.weight::numeric AS component_weight,
 g.assessment_id, a.title AS assessment_title, a.kind::text AS assessment_kind, a.delivery::text AS assessment_delivery,
 a.opens_at, a.due_at, a.closes_at, a.grades_released_at,
 g.score::numeric AS score, g.max_score::numeric AS max_score,
 CASE WHEN g.max_score > 0::numeric THEN round(g.score / g.max_score * 100::numeric, 2) ELSE NULL::numeric END AS score_percentage,
 g.feedback, g.status::text AS result_status, g.published_at AS recorded_at, g.published_by, g.source::text AS result_source
FROM public.grade_entries AS g
JOIN public.student_courses AS sc ON sc.enrollment_id = g.enrollment_id AND sc.student_id = g.student_id AND sc.tenant_id = g.tenant_id
LEFT JOIN public.assessments AS a ON a.id = g.assessment_id AND a.tenant_id = g.tenant_id
JOIN public.grade_components AS gc ON gc.id = COALESCE(g.component_id, a.component_id) AND gc.tenant_id = g.tenant_id
WHERE g.student_id = (SELECT auth.uid()) AND g.status = 'published'::public.grade_status
 AND (a.id IS NULL OR a.grades_released_at IS NULL OR a.grades_released_at <= now())
 AND NOT EXISTS (SELECT 1 FROM public.grade_entries AS newer WHERE newer.supersedes_id = g.id AND newer.status = 'published'::public.grade_status);
REVOKE ALL ON public.student_assessment_results FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.student_assessment_results FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_assessment_results TO authenticated;