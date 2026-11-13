-- Expose one authoritative (latest) GPA snapshot per student and term.
-- Keep the source table append-only so corrected historical calculations remain auditable.
CREATE OR REPLACE VIEW public.student_latest_gpa_snapshots
WITH (security_invoker = true)
AS
SELECT
  id,
  tenant_id,
  student_id,
  term_id,
  scale_id,
  term_gpa,
  cgpa,
  credits_attempted,
  credits_earned,
  computed_at,
  term_quality_points,
  cumulative_quality_points
FROM (
  SELECT
    gs.*,
    row_number() OVER (
      PARTITION BY gs.tenant_id, gs.student_id, gs.term_id
      ORDER BY gs.computed_at DESC, gs.id DESC
    ) AS snapshot_rank
  FROM public.gpa_snapshots AS gs
) AS ranked
WHERE snapshot_rank = 1;

GRANT SELECT ON public.student_latest_gpa_snapshots TO authenticated, service_role;

COMMENT ON VIEW public.student_latest_gpa_snapshots IS
  'Latest append-only GPA snapshot per student and term. Older snapshots remain in gpa_snapshots for audit history; security_invoker preserves source-table RLS.';
