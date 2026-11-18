CREATE POLICY "students read own graduation audits"
ON public.graduation_audits
FOR SELECT
TO authenticated
USING (
  student_id = (SELECT auth.uid())
  AND tenant_id = (SELECT private.tenant_id())
);

CREATE OR REPLACE VIEW public.student_graduation_audit
WITH (security_invoker = true)
AS
SELECT
  ga.id AS audit_id,
  p.id AS program_id,
  p.code AS program_code,
  p.name AS program_name,
  p.degree_level::text AS degree_level,
  ga.audit_status,
  ga.credits_earned,
  ga.cgpa,
  ga.unmet_requirements,
  ga.audited_at,
  ga.created_at,
  pol.minimum_total_credits,
  pol.minimum_cgpa,
  pol.minimum_attendance_percentage,
  pol.require_all_core_courses,
  pol.block_unresolved_incomplete_grades,
  pol.effective_from AS policy_effective_from,
  pol.effective_until AS policy_effective_until
FROM public.graduation_audits AS ga
JOIN public.programs AS p
  ON p.id = ga.program_id
 AND p.tenant_id = ga.tenant_id
LEFT JOIN public.program_academic_policies AS pol
  ON pol.id = ga.policy_id
 AND pol.tenant_id = ga.tenant_id
WHERE ga.student_id = (SELECT auth.uid())
  AND ga.tenant_id = (SELECT private.tenant_id());

REVOKE ALL ON public.student_graduation_audit FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.student_graduation_audit FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_graduation_audit TO authenticated;
