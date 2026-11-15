-- Student-level technical elective choices, constrained by approved specialization,
-- semester-specific requirement slots, prerequisite completion, and non-reuse.
CREATE TABLE public.student_technical_elective_selections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  student_id uuid NOT NULL,
  program_id uuid NOT NULL,
  specialization_id uuid NOT NULL,
  requirement_group_id uuid NOT NULL,
  course_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'selected' CHECK (status IN ('selected', 'withdrawn')),
  selected_at timestamptz NOT NULL DEFAULT now(),
  withdrawn_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT student_technical_elective_selections_student_fk
    FOREIGN KEY (student_id, tenant_id) REFERENCES public.users(id, tenant_id) ON DELETE CASCADE,
  CONSTRAINT student_technical_elective_selections_program_fk
    FOREIGN KEY (program_id, tenant_id) REFERENCES public.programs(id, tenant_id) ON DELETE RESTRICT,
  CONSTRAINT student_technical_elective_selections_specialization_fk
    FOREIGN KEY (specialization_id, program_id, tenant_id)
    REFERENCES public.specializations(id, program_id, tenant_id) ON DELETE RESTRICT,
  CONSTRAINT student_technical_elective_selections_group_fk
    FOREIGN KEY (requirement_group_id, tenant_id)
    REFERENCES public.curriculum_requirement_groups(id, tenant_id) ON DELETE RESTRICT,
  CONSTRAINT student_technical_elective_selections_course_fk
    FOREIGN KEY (course_id, tenant_id) REFERENCES public.courses(id, tenant_id) ON DELETE RESTRICT,
  CONSTRAINT student_technical_elective_selections_withdrawn_at_check
    CHECK ((status = 'withdrawn' AND withdrawn_at IS NOT NULL) OR (status = 'selected' AND withdrawn_at IS NULL))
);
CREATE UNIQUE INDEX student_technical_elective_one_active_course_per_slot_idx
  ON public.student_technical_elective_selections(tenant_id, student_id, requirement_group_id) WHERE status = 'selected';
CREATE UNIQUE INDEX student_technical_elective_no_course_reuse_idx
  ON public.student_technical_elective_selections(tenant_id, student_id, course_id) WHERE status = 'selected';
CREATE INDEX student_technical_elective_student_idx
  ON public.student_technical_elective_selections(tenant_id, student_id, selected_at DESC);
CREATE INDEX student_technical_elective_group_idx
  ON public.student_technical_elective_selections(tenant_id, requirement_group_id) WHERE status = 'selected';
ALTER TABLE public.student_technical_elective_selections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "students read own technical elective selections"
  ON public.student_technical_elective_selections FOR SELECT TO authenticated
  USING (tenant_id = (SELECT private.tenant_id()) AND student_id = (SELECT auth.uid()));
CREATE POLICY "students create own technical elective selections"
  ON public.student_technical_elective_selections FOR INSERT TO authenticated
  WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND student_id = (SELECT auth.uid()));
CREATE POLICY "students update own technical elective selections"
  ON public.student_technical_elective_selections FOR UPDATE TO authenticated
  USING (tenant_id = (SELECT private.tenant_id()) AND student_id = (SELECT auth.uid()))
  WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND student_id = (SELECT auth.uid()));
CREATE POLICY "academic managers read technical elective selections"
  ON public.student_technical_elective_selections FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT private.tenant_id())
    AND EXISTS (
      SELECT 1 FROM public.programs p
      WHERE p.id = student_technical_elective_selections.program_id
        AND p.tenant_id = student_technical_elective_selections.tenant_id
        AND (SELECT private.has_permission_for_department('academic.manage', p.department_id))
    )
  );
GRANT SELECT, INSERT, UPDATE ON public.student_technical_elective_selections TO authenticated;
GRANT ALL ON public.student_technical_elective_selections TO service_role;

CREATE OR REPLACE FUNCTION public.validate_technical_elective_selection()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE
  group_program_id uuid;
  group_category text;
  group_active boolean;
  group_min_credits numeric;
  group_max_credits numeric;
  group_level integer;
  course_credits numeric;
  active_specialization_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> NEW.student_id THEN
    RAISE EXCEPTION 'You may only select technical electives for your own student account' USING ERRCODE = '42501';
  END IF;
  IF NEW.status = 'withdrawn' THEN
    NEW.withdrawn_at := COALESCE(NEW.withdrawn_at, now());
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  NEW.withdrawn_at := NULL;
  SELECT rg.program_id, rg.category, rg.is_active, rg.minimum_credit_hours, rg.maximum_credit_hours, al.sequence_number
    INTO group_program_id, group_category, group_active, group_min_credits, group_max_credits, group_level
  FROM public.curriculum_requirement_groups rg
  JOIN public.academic_levels al ON al.id = rg.academic_level_id AND al.tenant_id = rg.tenant_id
  WHERE rg.id = NEW.requirement_group_id AND rg.tenant_id = NEW.tenant_id;
  IF NOT FOUND OR group_program_id <> NEW.program_id OR group_category <> 'technical_elective'
     OR group_active IS NOT TRUE OR group_level NOT BETWEEN 7 AND 10 THEN
    RAISE EXCEPTION 'The selected requirement group is not an active technical-elective slot in semesters 7-10 for this programme' USING ERRCODE = '23514';
  END IF;
  SELECT s.specialization_id INTO active_specialization_id
  FROM public.student_specialization_selections s
  WHERE s.tenant_id = NEW.tenant_id AND s.student_id = NEW.student_id AND s.program_id = NEW.program_id
    AND s.status = 'approved'
    AND (s.starts_on IS NULL OR s.starts_on <= CURRENT_DATE)
    AND (s.ends_on IS NULL OR s.ends_on >= CURRENT_DATE)
  ORDER BY s.starts_on DESC NULLS LAST, s.reviewed_at DESC, s.requested_at DESC LIMIT 1;
  IF active_specialization_id IS NULL OR active_specialization_id <> NEW.specialization_id THEN
    RAISE EXCEPTION 'An active approved specialization selection matching this course choice is required' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.specialization_courses sc
    WHERE sc.tenant_id = NEW.tenant_id AND sc.program_id = NEW.program_id
      AND sc.specialization_id = NEW.specialization_id AND sc.course_id = NEW.course_id
  ) THEN
    RAISE EXCEPTION 'The course is not part of the student approved specialization' USING ERRCODE = '23514';
  END IF;
  SELECT c.credit_hours INTO course_credits FROM public.courses c
  WHERE c.id = NEW.course_id AND c.tenant_id = NEW.tenant_id;
  IF course_credits IS NULL OR (group_min_credits IS NOT NULL AND course_credits < group_min_credits)
     OR (group_max_credits IS NOT NULL AND course_credits > group_max_credits) THEN
    RAISE EXCEPTION 'The course credit hours do not satisfy this technical-elective slot' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.course_prerequisites cp
    WHERE cp.tenant_id = NEW.tenant_id AND cp.course_id = NEW.course_id AND cp.kind::text = 'prerequisite'
      AND NOT EXISTS (
        SELECT 1 FROM public.enrollments e
        JOIN public.course_offerings co ON co.id = e.offering_id AND co.tenant_id = e.tenant_id
        WHERE e.tenant_id = NEW.tenant_id AND e.student_id = NEW.student_id
          AND co.course_id = cp.prerequisite_course_id AND e.status::text = 'completed'
          AND (cp.minimum_grade_points IS NULL OR e.final_grade_points >= cp.minimum_grade_points)
      )
  ) THEN
    RAISE EXCEPTION 'One or more course prerequisites have not been completed with the required grade' USING ERRCODE = '23514';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER validate_technical_elective_selection
  BEFORE INSERT OR UPDATE ON public.student_technical_elective_selections
  FOR EACH ROW EXECUTE FUNCTION public.validate_technical_elective_selection();
REVOKE ALL ON FUNCTION public.validate_technical_elective_selection() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_available_technical_electives(p_requirement_group_id uuid)
RETURNS TABLE (course_id uuid, course_code text, course_title text, credit_hours numeric, specialization_code text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $$
  SELECT c.id, c.code, c.title, c.credit_hours, sp.code
  FROM public.curriculum_requirement_groups rg
  JOIN public.academic_levels al ON al.id = rg.academic_level_id AND al.tenant_id = rg.tenant_id
  JOIN public.student_specialization_selections ss
    ON ss.tenant_id = rg.tenant_id AND ss.program_id = rg.program_id AND ss.student_id = (SELECT auth.uid())
   AND ss.status = 'approved'
   AND (ss.starts_on IS NULL OR ss.starts_on <= CURRENT_DATE)
   AND (ss.ends_on IS NULL OR ss.ends_on >= CURRENT_DATE)
  JOIN public.specializations sp
    ON sp.id = ss.specialization_id AND sp.program_id = ss.program_id AND sp.tenant_id = ss.tenant_id AND sp.is_active
  JOIN public.specialization_courses sc
    ON sc.tenant_id = sp.tenant_id AND sc.program_id = sp.program_id AND sc.specialization_id = sp.id
  JOIN public.courses c ON c.id = sc.course_id AND c.tenant_id = sc.tenant_id
  WHERE rg.id = p_requirement_group_id AND rg.tenant_id = (SELECT private.tenant_id())
    AND rg.program_id = ss.program_id AND rg.category = 'technical_elective' AND rg.is_active
    AND al.sequence_number BETWEEN 7 AND 10
    AND (rg.minimum_credit_hours IS NULL OR c.credit_hours >= rg.minimum_credit_hours)
    AND (rg.maximum_credit_hours IS NULL OR c.credit_hours <= rg.maximum_credit_hours)
    AND NOT EXISTS (
      SELECT 1 FROM public.student_technical_elective_selections chosen
      WHERE chosen.tenant_id = rg.tenant_id AND chosen.student_id = (SELECT auth.uid())
        AND chosen.course_id = c.id AND chosen.status = 'selected'
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.course_prerequisites cp
      WHERE cp.tenant_id = rg.tenant_id AND cp.course_id = c.id AND cp.kind::text = 'prerequisite'
        AND NOT EXISTS (
          SELECT 1 FROM public.enrollments e
          JOIN public.course_offerings co ON co.id = e.offering_id AND co.tenant_id = e.tenant_id
          WHERE e.tenant_id = rg.tenant_id AND e.student_id = (SELECT auth.uid())
            AND co.course_id = cp.prerequisite_course_id AND e.status::text = 'completed'
            AND (cp.minimum_grade_points IS NULL OR e.final_grade_points >= cp.minimum_grade_points)
        )
    )
  ORDER BY c.code;
$$;
REVOKE ALL ON FUNCTION public.get_available_technical_electives(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_available_technical_electives(uuid) TO authenticated;
