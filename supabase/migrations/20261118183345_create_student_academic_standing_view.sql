-- Expose the student's latest official academic standing and latest recorded GPA snapshot.
-- No warning counts or restrictions are inferred: Cohort has no dedicated records for those.
CREATE OR REPLACE VIEW public.student_academic_standing
WITH (security_invoker = true)
AS
SELECT
  sp.tenant_id,
  sp.student_id,
  sp.enrollment_status,
  standing_record.standing::text AS academic_standing,
  standing_record.reason AS standing_reason,
  standing_record.term_id AS standing_term_id,
  t.code AS standing_term_code,
  t.name AS standing_term_name,
  standing_record.decided_at AS standing_decided_at,
  gpa.cgpa AS cumulative_gpa,
  gpa.term_gpa,
  gpa.computed_at AS gpa_computed_at,
  GREATEST(standing_record.decided_at, gpa.computed_at) AS last_updated_at
FROM public.student_profile AS sp
LEFT JOIN LATERAL (
  SELECT ast.standing, ast.reason, ast.term_id, ast.decided_at
  FROM public.academic_standings AS ast
  WHERE ast.student_id = sp.student_id
    AND ast.tenant_id = sp.tenant_id
  ORDER BY ast.decided_at DESC, ast.id DESC
  LIMIT 1
) AS standing_record ON TRUE
LEFT JOIN public.terms AS t
  ON t.id = standing_record.term_id
 AND t.tenant_id = sp.tenant_id
LEFT JOIN LATERAL (
  SELECT gs.cgpa, gs.term_gpa, gs.computed_at
  FROM public.gpa_snapshots AS gs
  WHERE gs.student_id = sp.student_id
    AND gs.tenant_id = sp.tenant_id
  ORDER BY gs.computed_at DESC, gs.id DESC
  LIMIT 1
) AS gpa ON TRUE;

REVOKE ALL ON public.student_academic_standing FROM PUBLIC, anon;
GRANT SELECT ON public.student_academic_standing TO authenticated;
