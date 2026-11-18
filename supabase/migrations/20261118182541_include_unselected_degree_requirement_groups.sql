CREATE OR REPLACE VIEW public.student_degree_progress
WITH (security_invoker = true)
AS
WITH student AS (
  SELECT sp.tenant_id, sp.student_id, sp.program_id, sp.program_name,
         sp.specialization_id, sp.specialization_name
  FROM public.student_profile sp
  WHERE sp.student_id = (SELECT auth.uid())
),
core_requirements AS (
  SELECT s.tenant_id, s.student_id, s.program_id, pcc.course_id,
         c.credit_hours, pcc.minimum_grade_points
  FROM student s
  JOIN public.program_curriculum_courses pcc
    ON pcc.program_id = s.program_id AND pcc.tenant_id = s.tenant_id
   AND pcc.is_active AND pcc.requirement_type = 'required'
  JOIN public.courses c ON c.id = pcc.course_id AND c.tenant_id = pcc.tenant_id
),
student_attempts AS (
  SELECT e.tenant_id, e.student_id, COALESCE(e.course_id, o.course_id) AS course_id,
         e.status::text AS enrollment_status, e.final_grade_points,
         COALESCE(e.status_changed_at, e.enrolled_at) AS activity_at
  FROM public.enrollments e
  LEFT JOIN public.course_offerings o ON o.id = e.offering_id AND o.tenant_id = e.tenant_id
  JOIN student s ON s.student_id = e.student_id AND s.tenant_id = e.tenant_id
  WHERE COALESCE(e.course_id, o.course_id) IS NOT NULL
),
core_course_progress AS (
  SELECT cr.*,
    EXISTS (
      SELECT 1 FROM student_attempts a
      WHERE a.tenant_id = cr.tenant_id AND a.student_id = cr.student_id
        AND a.course_id = cr.course_id AND a.enrollment_status = 'completed'
        AND (cr.minimum_grade_points IS NULL OR a.final_grade_points >= cr.minimum_grade_points)
    ) AS is_completed,
    EXISTS (
      SELECT 1 FROM student_attempts a
      WHERE a.tenant_id = cr.tenant_id AND a.student_id = cr.student_id
        AND a.course_id = cr.course_id AND a.enrollment_status = 'enrolled'
    ) AS is_in_progress
  FROM core_requirements cr
),
core_summary AS (
  SELECT tenant_id, student_id, program_id,
    COUNT(*) AS required_course_count,
    COUNT(*) FILTER (WHERE is_completed) AS completed_course_count,
    COUNT(*) FILTER (WHERE NOT is_completed AND is_in_progress) AS in_progress_course_count,
    SUM(credit_hours) AS required_credits,
    SUM(credit_hours) FILTER (WHERE is_completed) AS completed_credits,
    SUM(credit_hours) FILTER (WHERE NOT is_completed AND is_in_progress) AS in_progress_credits,
    BOOL_OR(credit_hours IS NULL) AS has_missing_course_credits
  FROM core_course_progress
  GROUP BY tenant_id, student_id, program_id
),
required_groups AS (
  SELECT rg.id, rg.tenant_id, rg.program_id, rg.category,
         rg.required_course_count, rg.minimum_credit_hours
  FROM public.curriculum_requirement_groups rg
  JOIN student s ON s.program_id = rg.program_id AND s.tenant_id = rg.tenant_id
  WHERE rg.is_active AND rg.is_required
    AND rg.category <> 'graduation_project'
),
group_course_options AS (
  SELECT rg.id AS requirement_group_id, rg.tenant_id, rg.program_id,
         rg.required_course_count, rg.minimum_credit_hours,
         c.id AS course_id, c.credit_hours
  FROM required_groups rg
  JOIN public.curriculum_requirement_group_courses rgc
    ON rgc.requirement_group_id = rg.id AND rgc.tenant_id = rg.tenant_id AND rgc.is_active
  JOIN public.courses c ON c.id = rgc.course_id AND c.tenant_id = rgc.tenant_id
  WHERE rg.category <> 'technical_elective'
  UNION
  SELECT rg.id, rg.tenant_id, rg.program_id, rg.required_course_count,
         rg.minimum_credit_hours, c.id, c.credit_hours
  FROM required_groups rg
  JOIN student s ON s.program_id = rg.program_id AND s.tenant_id = rg.tenant_id
                AND s.specialization_id IS NOT NULL
  JOIN public.student_technical_elective_selections tes
    ON tes.requirement_group_id = rg.id AND tes.tenant_id = rg.tenant_id
   AND tes.program_id = rg.program_id AND tes.student_id = s.student_id
   AND tes.specialization_id = s.specialization_id AND tes.status = 'selected'
  JOIN public.curriculum_requirement_group_courses rgc
    ON rgc.requirement_group_id = rg.id AND rgc.tenant_id = rg.tenant_id
   AND rgc.course_id = tes.course_id AND rgc.is_active
  JOIN public.courses c ON c.id = tes.course_id AND c.tenant_id = tes.tenant_id
  WHERE rg.category = 'technical_elective'
),
group_option_progress AS (
  SELECT gco.*,
    EXISTS (
      SELECT 1 FROM student_attempts a
      WHERE a.tenant_id = gco.tenant_id AND a.course_id = gco.course_id
        AND a.enrollment_status = 'completed'
    ) AS is_completed,
    EXISTS (
      SELECT 1 FROM student_attempts a
      WHERE a.tenant_id = gco.tenant_id AND a.course_id = gco.course_id
        AND a.enrollment_status = 'enrolled'
    ) AS is_in_progress
  FROM group_course_options gco
),
group_summary AS (
  SELECT rg.id AS requirement_group_id, rg.tenant_id, rg.program_id,
    rg.required_course_count, rg.minimum_credit_hours AS required_credits,
    COUNT(DISTINCT gop.course_id) FILTER (WHERE gop.is_completed) AS completed_option_count,
    COUNT(DISTINCT gop.course_id) FILTER (WHERE NOT gop.is_completed AND gop.is_in_progress) AS in_progress_option_count,
    SUM(gop.credit_hours) FILTER (WHERE gop.is_completed) AS completed_option_credits,
    SUM(gop.credit_hours) FILTER (WHERE NOT gop.is_completed AND gop.is_in_progress) AS in_progress_option_credits
  FROM required_groups rg
  LEFT JOIN group_option_progress gop
    ON gop.requirement_group_id = rg.id AND gop.tenant_id = rg.tenant_id
  GROUP BY rg.id, rg.tenant_id, rg.program_id, rg.required_course_count, rg.minimum_credit_hours
),
group_progress AS (
  SELECT tenant_id, program_id,
    SUM(required_course_count) AS required_course_count,
    SUM(CASE
      WHEN completed_option_count >= required_course_count
       AND COALESCE(completed_option_credits, 0) >= COALESCE(required_credits, 0)
      THEN required_course_count ELSE 0 END) AS completed_course_count,
    SUM(CASE
      WHEN completed_option_count < required_course_count
      THEN LEAST(in_progress_option_count,
                 GREATEST(required_course_count - completed_option_count, 0))
      ELSE 0 END) AS in_progress_course_count,
    SUM(required_credits) AS required_credits,
    SUM(LEAST(COALESCE(completed_option_credits, 0),
              COALESCE(required_credits, completed_option_credits, 0))) AS completed_credits,
    SUM(LEAST(COALESCE(in_progress_option_credits, 0),
              GREATEST(COALESCE(required_credits, 0) -
                LEAST(COALESCE(completed_option_credits, 0),
                      COALESCE(required_credits, completed_option_credits, 0)), 0))) AS in_progress_credits
  FROM group_summary
  GROUP BY tenant_id, program_id
),
program_totals AS (
  SELECT s.tenant_id, s.student_id, s.program_id, s.program_name,
         s.specialization_id, s.specialization_name,
    COALESCE(cs.required_course_count, 0) + COALESCE(gp.required_course_count, 0) AS required_courses_count,
    COALESCE(cs.completed_course_count, 0) + COALESCE(gp.completed_course_count, 0) AS completed_required_courses,
    COALESCE(cs.in_progress_course_count, 0) + COALESCE(gp.in_progress_course_count, 0) AS in_progress_required_courses,
    CASE WHEN COALESCE(cs.has_missing_course_credits, FALSE) THEN NULL
         ELSE COALESCE(cs.required_credits, 0) + COALESCE(gp.required_credits, 0) END AS total_required_credits,
    COALESCE(cs.completed_credits, 0) + COALESCE(gp.completed_credits, 0) AS completed_credits,
    COALESCE(cs.in_progress_credits, 0) + COALESCE(gp.in_progress_credits, 0) AS in_progress_credits
  FROM student s
  LEFT JOIN core_summary cs ON cs.tenant_id = s.tenant_id
    AND cs.student_id = s.student_id AND cs.program_id = s.program_id
  LEFT JOIN group_progress gp ON gp.tenant_id = s.tenant_id AND gp.program_id = s.program_id
)
SELECT pt.tenant_id, pt.student_id, pt.program_id, pt.program_name,
       pt.specialization_id, pt.specialization_name,
       pt.total_required_credits, pt.completed_credits, pt.in_progress_credits,
  CASE WHEN pt.total_required_credits IS NULL THEN NULL
       ELSE GREATEST(pt.total_required_credits - pt.completed_credits - pt.in_progress_credits, 0)
  END AS remaining_credits,
  CASE WHEN pt.total_required_credits IS NULL OR pt.total_required_credits = 0 THEN NULL
       ELSE ROUND((pt.completed_credits / pt.total_required_credits) * 100, 2)
  END AS completion_percentage,
  pt.required_courses_count, pt.completed_required_courses,
  pt.in_progress_required_courses,
  GREATEST(pt.required_courses_count - pt.completed_required_courses - pt.in_progress_required_courses, 0)
    AS remaining_required_courses,
  (SELECT MAX(a.activity_at) FROM student_attempts a
   WHERE a.tenant_id = pt.tenant_id AND a.student_id = pt.student_id) AS last_updated_at
FROM program_totals pt;

REVOKE ALL ON public.student_degree_progress FROM PUBLIC, anon;
GRANT SELECT ON public.student_degree_progress TO authenticated;
