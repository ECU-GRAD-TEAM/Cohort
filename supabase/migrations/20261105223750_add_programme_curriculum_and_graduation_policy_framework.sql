-- Configurable programme curriculum, credit policy and auditable graduation reviews.
ALTER TABLE public.course_prerequisites ADD COLUMN IF NOT EXISTS minimum_grade_points numeric(4,2);
ALTER TABLE public.course_prerequisites ADD CONSTRAINT course_prerequisites_minimum_grade_points_check CHECK (minimum_grade_points IS NULL OR minimum_grade_points >= 0);

CREATE TABLE IF NOT EXISTS public.program_curriculum_courses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, program_id uuid NOT NULL, course_id uuid NOT NULL,
 academic_level_id uuid, requirement_type text NOT NULL DEFAULT 'required' CHECK (requirement_type IN ('required','elective','restricted_elective')),
 minimum_grade_points numeric(4,2), is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT program_curriculum_courses_program_course_key UNIQUE(program_id,course_id),
 FOREIGN KEY(program_id,tenant_id) REFERENCES public.programs(id,tenant_id) ON DELETE CASCADE,
 FOREIGN KEY(course_id,tenant_id) REFERENCES public.courses(id,tenant_id) ON DELETE RESTRICT,
 FOREIGN KEY(academic_level_id,tenant_id) REFERENCES public.academic_levels(id,tenant_id) ON DELETE RESTRICT,
 CHECK(minimum_grade_points IS NULL OR minimum_grade_points >= 0)
);
CREATE TABLE IF NOT EXISTS public.program_academic_policies (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, program_id uuid NOT NULL UNIQUE,
 minimum_total_credits numeric(7,2), minimum_cgpa numeric(4,2), minimum_semester_credits numeric(6,2), maximum_semester_credits numeric(6,2),
 minimum_attendance_percentage numeric(5,2), require_all_core_courses boolean NOT NULL DEFAULT true,
 block_unresolved_incomplete_grades boolean NOT NULL DEFAULT true, effective_from date, effective_until date,
 is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(program_id,tenant_id) REFERENCES public.programs(id,tenant_id) ON DELETE CASCADE,
 CHECK((minimum_total_credits IS NULL OR minimum_total_credits > 0) AND (minimum_semester_credits IS NULL OR minimum_semester_credits >= 0)
 AND (maximum_semester_credits IS NULL OR maximum_semester_credits > 0)
 AND (minimum_semester_credits IS NULL OR maximum_semester_credits IS NULL OR minimum_semester_credits <= maximum_semester_credits)),
 CHECK(minimum_cgpa IS NULL OR minimum_cgpa >= 0),
 CHECK(minimum_attendance_percentage IS NULL OR minimum_attendance_percentage BETWEEN 0 AND 100),
 CHECK(effective_until IS NULL OR effective_from IS NULL OR effective_until >= effective_from)
);
CREATE TABLE IF NOT EXISTS public.graduation_audits (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, student_id uuid NOT NULL, program_id uuid NOT NULL, policy_id uuid,
 audit_status text NOT NULL DEFAULT 'pending' CHECK(audit_status IN ('pending','eligible','not_eligible','requires_manual_review')),
 credits_earned numeric(8,2), cgpa numeric(4,2), unmet_requirements jsonb NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(unmet_requirements)='array'),
 evidence_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(evidence_snapshot)='object'),
 audited_by uuid, audited_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(student_id,tenant_id) REFERENCES public.users(id,tenant_id) ON DELETE CASCADE,
 FOREIGN KEY(program_id,tenant_id) REFERENCES public.programs(id,tenant_id) ON DELETE RESTRICT,
 FOREIGN KEY(policy_id) REFERENCES public.program_academic_policies(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS program_curriculum_courses_course_idx ON public.program_curriculum_courses(course_id,tenant_id);
CREATE INDEX IF NOT EXISTS program_curriculum_courses_level_idx ON public.program_curriculum_courses(academic_level_id,tenant_id) WHERE academic_level_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS graduation_audits_student_time_idx ON public.graduation_audits(tenant_id,student_id,audited_at DESC);
CREATE INDEX IF NOT EXISTS graduation_audits_program_status_idx ON public.graduation_audits(tenant_id,program_id,audit_status);

ALTER TABLE public.program_curriculum_courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_academic_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.graduation_audits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members read programme curriculum" ON public.program_curriculum_courses FOR SELECT TO authenticated USING(tenant_id=(SELECT private.tenant_id()));
CREATE POLICY "academic managers manage programme curriculum" ON public.program_curriculum_courses FOR ALL TO authenticated
 USING(tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission_for_department('academic.manage',(SELECT p.department_id FROM public.programs p WHERE p.id=program_curriculum_courses.program_id AND p.tenant_id=program_curriculum_courses.tenant_id))))
 WITH CHECK(tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission_for_department('academic.manage',(SELECT p.department_id FROM public.programs p WHERE p.id=program_curriculum_courses.program_id AND p.tenant_id=program_curriculum_courses.tenant_id))));
CREATE POLICY "members read programme academic policies" ON public.program_academic_policies FOR SELECT TO authenticated USING(tenant_id=(SELECT private.tenant_id()));
CREATE POLICY "academic managers manage programme academic policies" ON public.program_academic_policies FOR ALL TO authenticated
 USING(tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission_for_department('academic.manage',(SELECT p.department_id FROM public.programs p WHERE p.id=program_academic_policies.program_id AND p.tenant_id=program_academic_policies.tenant_id))))
 WITH CHECK(tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission_for_department('academic.manage',(SELECT p.department_id FROM public.programs p WHERE p.id=program_academic_policies.program_id AND p.tenant_id=program_academic_policies.tenant_id))));
CREATE POLICY "academic managers read graduation audits" ON public.graduation_audits FOR SELECT TO authenticated USING(tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission('academic.manage')));
CREATE POLICY "academic managers create graduation audits" ON public.graduation_audits FOR INSERT TO authenticated WITH CHECK(tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission('academic.manage')));
