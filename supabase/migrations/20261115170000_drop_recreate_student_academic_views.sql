-- Drop and recreate the student academic-record views from the agreed design.
-- student_gpa and student_timetable are intentionally preserved.
-- student_gpa_counted_attempts is removed.

DROP VIEW IF EXISTS public.student_assessments;
DROP VIEW IF EXISTS public.student_courses;
DROP VIEW IF EXISTS public.student_gpa_counted_attempts;

CREATE VIEW public.student_courses
WITH (security_invoker = true)
AS
WITH attempts AS (
  SELECT
    e.id AS enrollment_id,
    e.tenant_id,
    e.student_id,
    e.offering_id,
    e.status AS source_enrollment_status,
    e.enrolled_at,
    e.status_changed_at,
    COALESCE(e.course_id, o.course_id) AS course_id,
    COALESCE(e.term_id, o.term_id) AS term_id,
    COALESCE(e.credit_hours_attempted, c.credit_hours) AS credit_hours,
    e.final_percentage,
    e.final_grade_letter,
    e.final_grade_points,
    e.gpa_exclusion_reason,
    row_number() OVER (
      PARTITION BY e.tenant_id, e.student_id, COALESCE(e.course_id, o.course_id)
      ORDER BY e.enrolled_at, e.id
    )::integer AS attempt_number
  FROM public.enrollments e
  LEFT JOIN public.course_offerings o
    ON o.id = e.offering_id AND o.tenant_id = e.tenant_id
  LEFT JOIN public.courses c
    ON c.id = COALESCE(e.course_id, o.course_id) AND c.tenant_id = e.tenant_id
  WHERE e.status <> 'waitlisted'::public.enrollment_status
)
SELECT
  e.enrollment_id,e.tenant_id,e.student_id,e.course_id,
  c.code AS course_code,c.title AS course_title,e.offering_id,
  e.source_enrollment_status,
  CASE
    WHEN e.source_enrollment_status IN ('dropped'::public.enrollment_status,'withdrawn'::public.enrollment_status) THEN 'withdrawn'
    WHEN e.source_enrollment_status = 'failed'::public.enrollment_status THEN 'failed'
    WHEN e.source_enrollment_status = 'enrolled'::public.enrollment_status THEN 'enrolled'
    ELSE 'completed'
  END::text AS enrollment_status,
  e.credit_hours::numeric(8,2) AS credit_hours,
  e.term_id,t.code AS term_code,t.name AS term_name,t.academic_year_id,
  ay.code AS academic_year_code,ay.name AS academic_year_name,
  e.final_percentage::numeric AS final_percentage,
  e.final_grade_letter,e.final_grade_points::numeric AS final_grade_points,
  e.attempt_number,e.gpa_exclusion_reason,
  COALESCE(e.status_changed_at,e.enrolled_at) AS recorded_at
FROM attempts e
JOIN public.courses c ON c.id=e.course_id AND c.tenant_id=e.tenant_id
JOIN public.terms t ON t.id=e.term_id AND t.tenant_id=e.tenant_id
LEFT JOIN public.academic_years ay ON ay.id=t.academic_year_id AND ay.tenant_id=t.tenant_id;

CREATE VIEW public.student_assessments
WITH (security_invoker = true)
AS
SELECT
  g.id AS result_id,g.tenant_id,g.student_id,g.enrollment_id,
  sc.attempt_number,sc.enrollment_status,
  sc.course_id,sc.course_code,sc.course_title,sc.credit_hours,
  sc.term_id,sc.term_code,sc.term_name,sc.academic_year_id,
  sc.academic_year_code,sc.academic_year_name,g.offering_id,
  COALESCE(g.component_id,a.component_id) AS component_id,
  gc.name AS component_name,gc.category::text AS component_type,
  g.assessment_id,a.title AS assessment_title,
  g.score::numeric AS score,g.max_score::numeric AS max_score,
  CASE WHEN g.max_score>0 THEN round((g.score/g.max_score)*100,2) ELSE NULL::numeric END AS score_percentage,
  gc.weight::numeric AS component_weight,
  g.status::text AS result_status,g.published_at AS recorded_at
FROM public.grade_entries g
JOIN public.student_courses sc
  ON sc.enrollment_id=g.enrollment_id AND sc.student_id=g.student_id AND sc.tenant_id=g.tenant_id
LEFT JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id
JOIN public.grade_components gc
  ON gc.id=COALESCE(g.component_id,a.component_id) AND gc.tenant_id=g.tenant_id
WHERE g.status='published'::public.grade_status
  AND NOT EXISTS (
    SELECT 1 FROM public.grade_entries newer
    WHERE newer.supersedes_id=g.id AND newer.status='published'::public.grade_status
  );

GRANT SELECT ON public.student_courses TO authenticated;
GRANT SELECT ON public.student_assessments TO authenticated;
REVOKE ALL ON public.student_courses FROM anon,PUBLIC;
REVOKE ALL ON public.student_assessments FROM anon,PUBLIC;
