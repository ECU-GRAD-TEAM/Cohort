-- Append corrected term-quality-point snapshots without mutating append-only GPA history.
INSERT INTO public.gpa_snapshots(
 tenant_id,student_id,term_id,term_gpa,cgpa,credits_attempted,credits_earned,
 term_quality_points,cumulative_quality_points,snapshot_source,computed_at
)
SELECT s.tenant_id,s.student_id,s.term_id,s.term_gpa,s.cgpa,s.credits_attempted,s.credits_earned,
 totals.quality_points,s.cumulative_quality_points,'imported_transcript',now()
FROM public.gpa_snapshots s
JOIN (
 SELECT tenant_id,student_id,term_id,sum(quality_points)::numeric(9,2) quality_points
 FROM public.enrollments WHERE record_origin='imported_transcript'
 GROUP BY tenant_id,student_id,term_id
) totals ON totals.tenant_id=s.tenant_id AND totals.student_id=s.student_id AND totals.term_id=s.term_id
WHERE s.snapshot_source='imported_transcript'
AND s.term_quality_points IS DISTINCT FROM totals.quality_points
AND NOT EXISTS(
 SELECT 1 FROM public.gpa_snapshots newer
 WHERE newer.snapshot_source='imported_transcript'
 AND newer.tenant_id=s.tenant_id AND newer.student_id=s.student_id AND newer.term_id=s.term_id
 AND newer.term_quality_points=totals.quality_points
);
