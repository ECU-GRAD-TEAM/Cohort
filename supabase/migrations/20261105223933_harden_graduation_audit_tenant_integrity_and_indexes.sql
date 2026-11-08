ALTER TABLE public.program_academic_policies ADD CONSTRAINT program_academic_policies_id_tenant_key UNIQUE (id, tenant_id);
ALTER TABLE public.graduation_audits DROP CONSTRAINT graduation_audits_policy_fk;
ALTER TABLE public.graduation_audits ADD CONSTRAINT graduation_audits_policy_tenant_fk
 FOREIGN KEY (policy_id, tenant_id) REFERENCES public.program_academic_policies(id, tenant_id) ON DELETE SET NULL (policy_id);
CREATE INDEX IF NOT EXISTS graduation_audits_policy_tenant_idx ON public.graduation_audits(policy_id, tenant_id) WHERE policy_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS graduation_audits_program_tenant_idx ON public.graduation_audits(program_id, tenant_id);
CREATE INDEX IF NOT EXISTS graduation_audits_student_tenant_idx ON public.graduation_audits(student_id, tenant_id);
CREATE INDEX IF NOT EXISTS program_academic_policies_program_tenant_idx ON public.program_academic_policies(program_id, tenant_id);
CREATE INDEX IF NOT EXISTS program_curriculum_courses_program_tenant_idx ON public.program_curriculum_courses(program_id, tenant_id);
CREATE INDEX IF NOT EXISTS course_prerequisites_min_grade_idx ON public.course_prerequisites(tenant_id, prerequisite_course_id) WHERE minimum_grade_points IS NOT NULL;