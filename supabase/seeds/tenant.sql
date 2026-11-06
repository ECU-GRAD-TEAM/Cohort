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
-- PDF stages: General (1-2), First (3-4), Second (5-6), Third (7-8), Fourth (9-10).
-- Department choice follows semester 2 and takes effect in semester 3.
-- Programme selection timing is intentionally unconfigured because the PDF does not specify it.
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
  NULL
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
  CASE
    WHEN n <= 2 THEN 'General Level (Freshman)'
    WHEN n <= 4 THEN 'First Level (Sophomore)'
    WHEN n <= 6 THEN 'Second Level (Junior)'
    WHEN n <= 8 THEN 'Third Level (Senior-1)'
    ELSE 'Fourth Level (Senior-2)'
  END || ' - Semester ' || n,
  n,
  'semester',
  CASE
    WHEN n <= 2 THEN 'general_level'
    WHEN n <= 4 THEN 'first_level'
    WHEN n <= 6 THEN 'second_level'
    WHEN n <= 8 THEN 'third_level'
    ELSE 'fourth_level'
  END,
  n = 10
FROM public.tenants AS t
JOIN public.faculties AS f ON f.tenant_id = t.id AND f.code = 'ENG'
CROSS JOIN generate_series(1, 10) AS n
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, faculty_id, code) DO NOTHING;

-- Apply the five academic-level labels from the ECU curriculum PDF.
UPDATE public.academic_levels AS level
SET name = CASE
      WHEN level.sequence_number BETWEEN 1 AND 2 THEN 'General Level (Freshman)'
      WHEN level.sequence_number BETWEEN 3 AND 4 THEN 'First Level (Sophomore)'
      WHEN level.sequence_number BETWEEN 5 AND 6 THEN 'Second Level (Junior)'
      WHEN level.sequence_number BETWEEN 7 AND 8 THEN 'Third Level (Senior-1)'
      WHEN level.sequence_number BETWEEN 9 AND 10 THEN 'Fourth Level (Senior-2)'
    END || ' - Semester ' || level.sequence_number,
    is_terminal = (level.sequence_number = 10),
    stage_key = CASE
      WHEN level.sequence_number BETWEEN 1 AND 2 THEN 'general_level'
      WHEN level.sequence_number BETWEEN 3 AND 4 THEN 'first_level'
      WHEN level.sequence_number BETWEEN 5 AND 6 THEN 'second_level'
      WHEN level.sequence_number BETWEEN 7 AND 8 THEN 'third_level'
      WHEN level.sequence_number BETWEEN 9 AND 10 THEN 'fourth_level'
    END,
    is_active = true
FROM public.tenants AS t, public.faculties AS f
WHERE level.tenant_id = t.id AND t.slug = 'ecu'
  AND level.faculty_id = f.id AND f.tenant_id = t.id AND f.code = 'ENG'
  AND level.sequence_number BETWEEN 1 AND 10;

UPDATE public.faculty_academic_pathways AS p
SET department_selection_level_id = sel.id,
    department_effective_level_id = eff.id,
    programme_selection_level_id = NULL
FROM public.academic_levels AS sel,
     public.academic_levels AS eff
WHERE sel.tenant_id = p.tenant_id AND sel.faculty_id = p.faculty_id
  AND sel.sequence_number = p.department_selection_semester
  AND eff.tenant_id = p.tenant_id AND eff.faculty_id = p.faculty_id
  AND eff.sequence_number = p.department_effective_semester;

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



-- Seed ECU's Software Engineering and Information Technology bachelor's programme.
-- Resolve tenant and department IDs through stable natural keys.
INSERT INTO public.programs (
  tenant_id,
  department_id,
  code,
  name,
  degree_level
)
SELECT
  t.id,
  d.id,
  'SET',
  'Software Engineering and Information Technology',
  'bachelor'::public.degree_level
FROM public.tenants AS t
JOIN public.departments AS d
  ON d.tenant_id = t.id
 AND d.code = 'SET'
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO UPDATE
SET department_id = EXCLUDED.department_id,
    name = EXCLUDED.name,
    degree_level = EXCLUDED.degree_level;

-- Seed the four ECU-approved specializations under the SET programme.
-- Specialization selection timing remains configurable; no student selections are seeded.
INSERT INTO public.specializations (
  tenant_id,
  program_id,
  code,
  name
)
SELECT
  t.id,
  p.id,
  specialization.code,
  specialization.name
FROM public.tenants AS t
JOIN public.programs AS p
  ON p.tenant_id = t.id
 AND p.code = 'SET'
CROSS JOIN (
  VALUES
    ('MCG', 'Multimedia and Computer Graphics'),
    ('DMC', 'Distributed and Mobile Computing'),
    ('SPL', 'Software Product Lines'),
    ('SA',  'Software Applications')
) AS specialization(code, name)
WHERE t.slug = 'ecu'
ON CONFLICT (program_id, tenant_id, code) DO UPDATE
SET name = EXCLUDED.name,
    is_active = true;

