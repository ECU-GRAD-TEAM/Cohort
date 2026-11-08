-- Seed draft offerings for the remaining SET curriculum semesters (2-10) in ECU 2026/2027.
-- Odd curriculum semesters are planned in Fall; even curriculum semesters in Spring.
-- Include active required core mappings and the single currently mapped course for each
-- humanities-elective requirement group. Do not offer all technical-elective alternatives:
-- those courses are student-selected from specialization pools and require term scheduling decisions.
WITH curriculum_courses AS (
  SELECT DISTINCT
    pcc.tenant_id,
    pcc.course_id,
    t.id AS term_id
  FROM public.program_curriculum_courses AS pcc
  JOIN public.academic_semesters AS semester
    ON semester.id = pcc.academic_level_id
  JOIN public.programs AS programme
    ON programme.id = pcc.program_id
  JOIN public.terms AS t
    ON t.tenant_id = pcc.tenant_id
   AND t.code = CASE
      WHEN semester.sequence_number % 2 = 1 THEN '2026-2027-FALL'
      ELSE '2026-2027-SPRING'
   END
  WHERE pcc.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
    AND programme.id = '85dddcad-cc84-4b6a-b262-77f435c8f2f8'
    AND pcc.is_active = true
    AND pcc.requirement_type = 'required'
    AND semester.sequence_number BETWEEN 2 AND 10

  UNION

  SELECT DISTINCT
    rgc.tenant_id,
    rgc.course_id,
    t.id AS term_id
  FROM public.curriculum_requirement_groups AS rg
  JOIN public.curriculum_requirement_group_courses AS rgc
    ON rgc.requirement_group_id = rg.id
   AND rgc.tenant_id = rg.tenant_id
  JOIN public.academic_semesters AS semester
    ON semester.id = rg.academic_level_id
  JOIN public.terms AS t
    ON t.tenant_id = rg.tenant_id
   AND t.code = CASE
      WHEN semester.sequence_number % 2 = 1 THEN '2026-2027-FALL'
      ELSE '2026-2027-SPRING'
   END
  WHERE rg.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
    AND rg.program_id = '85dddcad-cc84-4b6a-b262-77f435c8f2f8'
    AND rg.category = 'humanities_elective'
    AND rg.is_required = true
    AND rg.is_active = true
    AND rgc.is_active = true
    AND semester.sequence_number BETWEEN 2 AND 10
)
INSERT INTO public.course_offerings (tenant_id, course_id, term_id, status)
SELECT tenant_id, course_id, term_id, 'draft'::public.offering_status
FROM curriculum_courses
ON CONFLICT (course_id, term_id) DO NOTHING;
