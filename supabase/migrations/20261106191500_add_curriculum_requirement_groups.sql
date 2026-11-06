-- Add configurable programme curriculum requirement groups for non-coded elective slots and graduation projects.
CREATE TABLE public.curriculum_requirement_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  program_id uuid NOT NULL,
  academic_level_id uuid NOT NULL,
  code text NOT NULL,
  title text NOT NULL,
  category text NOT NULL CHECK (category IN ('humanities_elective','technical_elective','graduation_project')),
  required_course_count smallint NOT NULL DEFAULT 1 CHECK (required_course_count > 0),
  minimum_credit_hours numeric(6,2),
  maximum_credit_hours numeric(6,2),
  is_required boolean NOT NULL DEFAULT true,
  sort_order smallint NOT NULL DEFAULT 0,
  notes text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT curriculum_requirement_groups_program_code_key UNIQUE (program_id, code),
  CONSTRAINT curriculum_requirement_groups_id_tenant_key UNIQUE (id, tenant_id),
  CONSTRAINT curriculum_requirement_groups_program_fk
    FOREIGN KEY (program_id, tenant_id) REFERENCES public.programs(id, tenant_id) ON DELETE CASCADE,
  CONSTRAINT curriculum_requirement_groups_level_fk
    FOREIGN KEY (academic_level_id, tenant_id) REFERENCES public.academic_levels(id, tenant_id) ON DELETE RESTRICT,
  CONSTRAINT curriculum_requirement_groups_credit_range_check CHECK (
    (minimum_credit_hours IS NULL OR minimum_credit_hours > 0)
    AND (maximum_credit_hours IS NULL OR maximum_credit_hours > 0)
    AND (minimum_credit_hours IS NULL OR maximum_credit_hours IS NULL OR minimum_credit_hours <= maximum_credit_hours)
  ),
  CONSTRAINT curriculum_requirement_groups_code_check CHECK (length(btrim(code)) > 0),
  CONSTRAINT curriculum_requirement_groups_title_check CHECK (length(btrim(title)) > 0)
);

CREATE TABLE public.curriculum_requirement_group_courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  requirement_group_id uuid NOT NULL,
  course_id uuid NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT curriculum_requirement_group_courses_group_course_key UNIQUE (requirement_group_id, course_id),
  CONSTRAINT curriculum_requirement_group_courses_group_fk
    FOREIGN KEY (requirement_group_id, tenant_id)
    REFERENCES public.curriculum_requirement_groups(id, tenant_id) ON DELETE CASCADE,
  CONSTRAINT curriculum_requirement_group_courses_course_fk
    FOREIGN KEY (course_id, tenant_id)
    REFERENCES public.courses(id, tenant_id) ON DELETE RESTRICT
);

CREATE INDEX curriculum_requirement_groups_level_idx
  ON public.curriculum_requirement_groups(tenant_id, academic_level_id)
  WHERE is_active;
CREATE INDEX curriculum_requirement_groups_program_category_idx
  ON public.curriculum_requirement_groups(tenant_id, program_id, category)
  WHERE is_active;
CREATE INDEX curriculum_requirement_group_courses_course_idx
  ON public.curriculum_requirement_group_courses(tenant_id, course_id)
  WHERE is_active;

ALTER TABLE public.curriculum_requirement_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_requirement_group_courses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read curriculum requirement groups"
  ON public.curriculum_requirement_groups FOR SELECT TO authenticated
  USING (tenant_id = (SELECT private.tenant_id()));
CREATE POLICY "academic managers manage curriculum requirement groups"
  ON public.curriculum_requirement_groups FOR ALL TO authenticated
  USING (
    tenant_id = (SELECT private.tenant_id())
    AND (SELECT private.has_permission_for_department(
      'academic.manage',
      (SELECT p.department_id FROM public.programs p
       WHERE p.id = curriculum_requirement_groups.program_id
         AND p.tenant_id = curriculum_requirement_groups.tenant_id)
    ))
  )
  WITH CHECK (
    tenant_id = (SELECT private.tenant_id())
    AND (SELECT private.has_permission_for_department(
      'academic.manage',
      (SELECT p.department_id FROM public.programs p
       WHERE p.id = curriculum_requirement_groups.program_id
         AND p.tenant_id = curriculum_requirement_groups.tenant_id)
    ))
  );

CREATE POLICY "members read curriculum requirement group courses"
  ON public.curriculum_requirement_group_courses FOR SELECT TO authenticated
  USING (tenant_id = (SELECT private.tenant_id()));
CREATE POLICY "academic managers manage curriculum requirement group courses"
  ON public.curriculum_requirement_group_courses FOR ALL TO authenticated
  USING (
    tenant_id = (SELECT private.tenant_id())
    AND EXISTS (
      SELECT 1
      FROM public.curriculum_requirement_groups rg
      JOIN public.programs p
        ON p.id = rg.program_id AND p.tenant_id = rg.tenant_id
      WHERE rg.id = curriculum_requirement_group_courses.requirement_group_id
        AND rg.tenant_id = curriculum_requirement_group_courses.tenant_id
        AND (SELECT private.has_permission_for_department('academic.manage', p.department_id))
    )
  )
  WITH CHECK (
    tenant_id = (SELECT private.tenant_id())
    AND EXISTS (
      SELECT 1
      FROM public.curriculum_requirement_groups rg
      JOIN public.programs p
        ON p.id = rg.program_id AND p.tenant_id = rg.tenant_id
      WHERE rg.id = curriculum_requirement_group_courses.requirement_group_id
        AND rg.tenant_id = curriculum_requirement_group_courses.tenant_id
        AND (SELECT private.has_permission_for_department('academic.manage', p.department_id))
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.curriculum_requirement_groups TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.curriculum_requirement_group_courses TO authenticated;
GRANT ALL ON public.curriculum_requirement_groups TO service_role;
GRANT ALL ON public.curriculum_requirement_group_courses TO service_role;
