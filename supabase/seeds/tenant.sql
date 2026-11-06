-- Seed the Egyptian Chinese University tenant for local development.
-- Idempotent: existing tenant, faculty, and department records are left unchanged.

INSERT INTO public.tenants (
  name,
  slug,
  country_code,
  data_region
)
VALUES (
  'Egyptian Chinese University',
  'ecu',
  'EG',
  'egypt'
)
ON CONFLICT (slug) DO NOTHING;

-- Seed ECU's Engineering and Technology faculty.
-- Resolve tenant_id by slug so this works with locally generated tenant UUIDs.
INSERT INTO public.faculties (
  tenant_id,
  code,
  name
)
SELECT
  id,
  'ENG',
  'Engineering and Technology'
FROM public.tenants
WHERE slug = 'ecu'
ON CONFLICT (tenant_id, code) DO NOTHING;

-- Seed departments belonging to ECU's Engineering and Technology faculty.
-- Resolve both tenant_id and faculty_id by stable natural keys rather than UUIDs.
INSERT INTO public.departments (
  tenant_id,
  faculty_id,
  code,
  name
)
SELECT
  t.id,
  f.id,
  department.code,
  department.name
FROM public.tenants AS t
JOIN public.faculties AS f
  ON f.tenant_id = t.id
 AND f.code = 'ENG'
CROSS JOIN (
  VALUES
    ('SET', 'Software Engineering & Information Technology'),
    ('MCE', 'Mechatronics Engineering'),
    ('ERG', 'Energy and Renewable Energy Engineering'),
    ('CBE', 'Construction and Building Engineering')
) AS department(code, name)
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO NOTHING;


-- ECU Engineering and Technology academic progression:
-- shared preparatory semesters 1-2, department from semester 3, programme from semester 8.
INSERT INTO public.faculty_academic_pathways (
  tenant_id,
  faculty_id,
  department_selection_semester,
  department_effective_semester,
  programme_selection_semester
)
SELECT
  t.id,
  f.id,
  2,
  3,
  8
FROM public.tenants AS t
JOIN public.faculties AS f
  ON f.tenant_id = t.id
 AND f.code = 'ENG'
WHERE t.slug = 'ecu'
ON CONFLICT (faculty_id, tenant_id) DO UPDATE
SET department_selection_semester = EXCLUDED.department_selection_semester,
    department_effective_semester = EXCLUDED.department_effective_semester,
    programme_selection_semester = EXCLUDED.programme_selection_semester;


-- Seed ECU's existing semester pathway into the generalized academic-level model.
-- The legacy semester columns remain populated for compatibility with older clients.
INSERT INTO public.academic_levels (
  tenant_id, faculty_id, code, name, sequence_number, period_unit, stage_key, is_terminal
)
SELECT
  t.id,
  f.id,
  'SEMESTER_' || n,
  'Semester ' || n,
  n,
  'semester',
  CASE
    WHEN n <= 2 THEN 'preparatory'
    WHEN n <= 7 THEN 'departmental'
    ELSE 'programme'
  END,
  n = 10
FROM public.tenants AS t
JOIN public.faculties AS f ON f.tenant_id = t.id AND f.code = 'ENG'
CROSS JOIN generate_series(1, 10) AS n
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, faculty_id, code) DO NOTHING;

-- Semester 10 is the completion endpoint; semester 8 is the programme-selection point.
UPDATE public.academic_levels AS level
SET is_terminal = (level.sequence_number = 10),
    stage_key = CASE WHEN level.sequence_number <= 2 THEN 'preparatory'
                     WHEN level.sequence_number <= 7 THEN 'departmental'
                     ELSE 'programme' END,
    is_active = true
FROM public.tenants AS t, public.faculties AS f
WHERE level.tenant_id = t.id AND t.slug = 'ecu'
  AND level.faculty_id = f.id AND f.tenant_id = t.id AND f.code = 'ENG'
  AND level.sequence_number BETWEEN 8 AND 10;

UPDATE public.faculty_academic_pathways AS p
SET department_selection_level_id = sel.id,
    department_effective_level_id = eff.id,
    programme_selection_level_id = prog.id
FROM public.academic_levels AS sel,
     public.academic_levels AS eff,
     public.academic_levels AS prog
WHERE sel.tenant_id = p.tenant_id AND sel.faculty_id = p.faculty_id
  AND sel.sequence_number = p.department_selection_semester
  AND eff.tenant_id = p.tenant_id AND eff.faculty_id = p.faculty_id
  AND eff.sequence_number = p.department_effective_semester
  AND prog.tenant_id = p.tenant_id AND prog.faculty_id = p.faculty_id
  AND prog.sequence_number = p.programme_selection_semester;

UPDATE public.faculty_academic_pathways AS p
SET expected_completion_level_id = completion.id
FROM public.academic_levels AS completion
WHERE completion.tenant_id = p.tenant_id
  AND completion.faculty_id = p.faculty_id
  AND completion.sequence_number = 10;

INSERT INTO public.academic_progression_rules (
  tenant_id, faculty_id, action_key, selection_level_id, effective_level_id,
  minimum_credits, requires_department_assignment
)
SELECT p.tenant_id, p.faculty_id, 'department_selection',
       p.department_selection_level_id, p.department_effective_level_id, 0, false
FROM public.faculty_academic_pathways AS p
WHERE p.department_selection_level_id IS NOT NULL
ON CONFLICT (tenant_id, faculty_id, action_key) DO UPDATE
SET selection_level_id = EXCLUDED.selection_level_id,
    effective_level_id = EXCLUDED.effective_level_id;

INSERT INTO public.academic_progression_rules (
  tenant_id, faculty_id, action_key, selection_level_id, effective_level_id,
  minimum_credits, requires_department_assignment
)
SELECT p.tenant_id, p.faculty_id, 'programme_selection',
       p.programme_selection_level_id, p.programme_selection_level_id, 0, true
FROM public.faculty_academic_pathways AS p
WHERE p.programme_selection_level_id IS NOT NULL
ON CONFLICT (tenant_id, faculty_id, action_key) DO UPDATE
SET selection_level_id = EXCLUDED.selection_level_id,
    effective_level_id = EXCLUDED.effective_level_id;
