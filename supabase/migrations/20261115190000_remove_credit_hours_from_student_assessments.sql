-- Credit hours belong to the course/enrollment summary, not individual assessment results.
-- Keep credit_hours in public.student_courses; omit it from public.student_assessments.

DROP VIEW public.student_assessments;

CREATE VIEW public.student_assessments
WITH (security_invoker = true)
AS
SELECT
  g.id AS result_id,
  g.tenant_id,
  g.student_id,
  g.enrollment_id,
  sc.attempt_number,
  sc.enrollment_status,
  sc.course_id,
  sc.course_code,
  sc.course_title,
  sc.term_id,
  sc.term_code,
  sc.term_name,
  sc.academic_year_id,
  sc.academic_year_code,
  sc.academic_year_name,
  g.offering_id,
  COALESCE(g.component_id, a.component_id) AS component_id,
  gc.name AS component_name,
  gc.category::text AS component_type,
  g.assessment_id,
  a.title AS assessment_title,
  g.score::numeric AS score,
  g.max_score::numeric AS max_score,
  CASE WHEN g.max_score > 0 THEN round((g.score / g.max_score) * 100, 2) ELSE NULL::numeric END AS score_percentage,
  gc.weight::numeric AS component_weight,
  g.status::text AS result_status,
  g.published_at AS recorded_at
FROM public.grade_entries g
JOIN public.student_courses sc
  ON sc.enrollment_id = g.enrollment_id
 AND sc.student_id = g.student_id
 AND sc.tenant_id = g.tenant_id
LEFT JOIN public.assessments a
  ON a.id = g.assessment_id AND a.tenant_id = g.tenant_id
JOIN public.grade_components gc
  ON gc.id = COALESCE(g.component_id, a.component_id)
 AND gc.tenant_id = g.tenant_id
WHERE g.status = 'published'::public.grade_status
  AND NOT EXISTS (
    SELECT 1
    FROM public.grade_entries newer
    WHERE newer.supersedes_id = g.id
      AND newer.status = 'published'::public.grade_status
  );

GRANT SELECT ON public.student_assessments TO authenticated;
REVOKE ALL ON public.student_assessments FROM anon, PUBLIC;
