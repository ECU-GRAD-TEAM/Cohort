CREATE OR REPLACE VIEW public.student_assessments
WITH (security_invoker = true)
AS
SELECT g.id AS result_id,g.tenant_id,g.student_id,g.enrollment_id,g.offering_id,
       o.course_id,c.code AS course_code,c.title AS course_title,
       COALESCE(e.credit_hours_attempted,c.credit_hours)::numeric(8,2) AS credit_hours,
       o.term_id,t.code AS term_code,t.name AS term_name,
       ay.code AS academic_year_code,ay.name AS academic_year_name,
       'assessment'::text AS result_type,gc.category::text AS component_type,
       gc.name AS component_name,g.component_id,g.assessment_id,a.title AS assessment_title,
       g.score::numeric AS score,g.max_score::numeric AS max_score,
       NULL::text AS grade_letter,NULL::numeric AS grade_points,
       g.status::text AS result_status,NULL::text AS attendance_status,
       NULL::text AS gpa_exclusion_reason,g.published_at AS recorded_at,
       t.academic_year_id,sc.attempt_number,gc.weight::numeric AS component_weight,
       CASE WHEN g.max_score>0 THEN round((g.score/g.max_score)*100,2) ELSE NULL::numeric END AS score_percentage
FROM public.grade_entries g
JOIN public.enrollments e ON e.id=g.enrollment_id AND e.student_id=g.student_id AND e.tenant_id=g.tenant_id
JOIN public.student_courses sc ON sc.enrollment_id=e.id
JOIN public.course_offerings o ON o.id=g.offering_id AND o.tenant_id=g.tenant_id
JOIN public.courses c ON c.id=o.course_id AND c.tenant_id=o.tenant_id
JOIN public.terms t ON t.id=o.term_id AND t.tenant_id=o.tenant_id
LEFT JOIN public.academic_years ay ON ay.id=t.academic_year_id AND ay.tenant_id=t.tenant_id
JOIN public.grade_components gc ON gc.id=g.component_id AND gc.tenant_id=g.tenant_id
LEFT JOIN public.assessments a ON a.id=g.assessment_id AND a.tenant_id=g.tenant_id
WHERE g.status='published'::public.grade_status
AND NOT EXISTS (SELECT 1 FROM public.grade_entries newer WHERE newer.supersedes_id=g.id AND newer.status='published'::public.grade_status);
