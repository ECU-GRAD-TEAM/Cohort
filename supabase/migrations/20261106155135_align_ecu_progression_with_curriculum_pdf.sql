-- Align ECU Engineering and Technology progression stages with the official 10-semester curriculum.
-- The PDF defines five academic levels and does not specify a programme-selection semester.

ALTER TABLE public.faculty_academic_pathways
  ALTER COLUMN programme_selection_semester DROP NOT NULL;

ALTER TABLE public.student_programme_selections
  ALTER COLUMN selection_semester DROP NOT NULL;

-- Keep the ten semester records, but label them by the five curriculum levels.
UPDATE public.academic_levels AS level
SET stage_key = CASE
      WHEN level.sequence_number BETWEEN 1 AND 2 THEN 'general_level'
      WHEN level.sequence_number BETWEEN 3 AND 4 THEN 'first_level'
      WHEN level.sequence_number BETWEEN 5 AND 6 THEN 'second_level'
      WHEN level.sequence_number BETWEEN 7 AND 8 THEN 'third_level'
      WHEN level.sequence_number BETWEEN 9 AND 10 THEN 'fourth_level'
    END,
    is_terminal = (level.sequence_number = 10),
    is_active = true
FROM public.tenants AS tenant,
     public.faculties AS faculty
WHERE level.tenant_id = tenant.id
  AND tenant.slug = 'ecu'
  AND level.faculty_id = faculty.id
  AND faculty.tenant_id = tenant.id
  AND faculty.code = 'ENG'
  AND level.sequence_number BETWEEN 1 AND 10;

-- Retain the confirmed department choice after semester 2, effective from semester 3.
-- Remove the unsupported programme-selection timing and preserve semester 10 completion.
UPDATE public.faculty_academic_pathways AS pathway
SET department_selection_semester = 2,
    department_effective_semester = 3,
    department_selection_level_id = selection_level.id,
    department_effective_level_id = effective_level.id,
    programme_selection_semester = NULL,
    programme_selection_level_id = NULL,
    expected_completion_level_id = completion_level.id,
    updated_at = now()
FROM public.tenants AS tenant,
     public.faculties AS faculty,
     public.academic_levels AS selection_level,
     public.academic_levels AS effective_level,
     public.academic_levels AS completion_level
WHERE pathway.tenant_id = tenant.id
  AND tenant.slug = 'ecu'
  AND pathway.faculty_id = faculty.id
  AND faculty.tenant_id = tenant.id
  AND faculty.code = 'ENG'
  AND selection_level.tenant_id = tenant.id
  AND selection_level.faculty_id = faculty.id
  AND selection_level.sequence_number = 2
  AND effective_level.tenant_id = tenant.id
  AND effective_level.faculty_id = faculty.id
  AND effective_level.sequence_number = 3
  AND completion_level.tenant_id = tenant.id
  AND completion_level.faculty_id = faculty.id
  AND completion_level.sequence_number = 10;

-- No programme-selection timing is configured until ECU supplies an official rule.
DELETE FROM public.academic_progression_rules AS rule
USING public.tenants AS tenant,
      public.faculties AS faculty
WHERE rule.tenant_id = tenant.id
  AND tenant.slug = 'ecu'
  AND rule.faculty_id = faculty.id
  AND faculty.tenant_id = tenant.id
  AND faculty.code = 'ENG'
  AND rule.action_key = 'programme_selection';
