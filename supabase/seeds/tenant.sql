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


-- Seed ECU's five annual academic progression levels separately from its ten curriculum semesters.
-- Credit thresholds are intentionally NULL until ECU provides the official cumulative requirements.
INSERT INTO public.academic_year_levels (
  tenant_id, faculty_id, code, name, sequence_number,
  curriculum_semester_start, curriculum_semester_end
)
SELECT t.id, f.id, 'LEVEL_' || n, 'Level ' || n, n, (n * 2) - 1, n * 2
FROM public.tenants AS t
JOIN public.faculties AS f ON f.tenant_id = t.id AND f.code = 'ENG'
CROSS JOIN generate_series(1, 5) AS n
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, faculty_id, code) DO UPDATE
SET name = EXCLUDED.name,
    sequence_number = EXCLUDED.sequence_number,
    curriculum_semester_start = EXCLUDED.curriculum_semester_start,
    curriculum_semester_end = EXCLUDED.curriculum_semester_end;

UPDATE public.faculty_academic_pathways AS p
SET department_selection_year_level_id = level_1.id,
    department_effective_year_level_id = level_2.id,
    expected_completion_year_level_id = level_5.id
FROM public.academic_year_levels AS level_1,
     public.academic_year_levels AS level_2,
     public.academic_year_levels AS level_5
WHERE level_1.tenant_id = p.tenant_id AND level_1.faculty_id = p.faculty_id AND level_1.sequence_number = 1
  AND level_2.tenant_id = p.tenant_id AND level_2.faculty_id = p.faculty_id AND level_2.sequence_number = 2
  AND level_5.tenant_id = p.tenant_id AND level_5.faculty_id = p.faculty_id AND level_5.sequence_number = 5;

UPDATE public.academic_progression_rules AS r
SET selection_year_level_id = level_1.id,
    effective_year_level_id = level_2.id
FROM public.academic_year_levels AS level_1,
     public.academic_year_levels AS level_2
WHERE level_1.tenant_id = r.tenant_id AND level_1.faculty_id = r.faculty_id AND level_1.sequence_number = 1
  AND level_2.tenant_id = r.tenant_id AND level_2.faculty_id = r.faculty_id AND level_2.sequence_number = 2
  AND r.action_key = 'department_selection';

-- Seed ECU's existing semester pathway into the generalized academic-level model.
-- The legacy semester columns remain populated for compatibility with older clients.
INSERT INTO public.academic_semesters (
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
UPDATE public.academic_semesters AS level
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
FROM public.academic_semesters AS sel,
     public.academic_semesters AS eff
WHERE sel.tenant_id = p.tenant_id AND sel.faculty_id = p.faculty_id
  AND sel.sequence_number = p.department_selection_semester
  AND eff.tenant_id = p.tenant_id AND eff.faculty_id = p.faculty_id
  AND eff.sequence_number = p.department_effective_semester;

UPDATE public.faculty_academic_pathways AS p
SET expected_completion_level_id = completion.id
FROM public.academic_semesters AS completion
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



-- Seed the confirmed first-semester ECU course catalogue records.
-- PHM courses are owned by the faculty; SET and MCE courses by their departments.
-- Resolve all owners through stable tenant/faculty/department natural keys.
INSERT INTO public.courses (
  tenant_id,
  faculty_id,
  department_id,
  code,
  title,
  credit_hours,
  level,
  lecture_hours,
  tutorial_hours,
  lab_hours,
  is_active
)
SELECT
  t.id,
  owner.faculty_id,
  owner.department_id,
  course.code,
  course.title,
  course.credit_hours,
  1,
  course.lecture_hours,
  course.tutorial_hours,
  course.lab_hours,
  true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('PHM 012', 'Calculus for Engineering (1)', 3::numeric, 2::numeric, 2::numeric, 0::numeric, 'faculty'::text, 'ENG'::text),
    ('PHM 032', 'Engineering Mechanics (1) - Statics', 3::numeric, 2::numeric, 2::numeric, 0::numeric, 'faculty'::text, 'ENG'::text),
    ('PHM 042', 'General Chemistry', 3::numeric, 2::numeric, 1::numeric, 1.5::numeric, 'faculty'::text, 'ENG'::text),
    ('SET 012', 'Engineering Computation', 3::numeric, 2::numeric, 0::numeric, 3::numeric, 'department'::text, 'SET'::text),
    ('MCE 061', 'Engineering Design and Graphics', 4::numeric, 2::numeric, 4::numeric, 0::numeric, 'department'::text, 'MCE'::text)
) AS course(code, title, credit_hours, lecture_hours, tutorial_hours, lab_hours, owner_type, owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type = 'faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type = 'department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id = f.tenant_id
   AND d.faculty_id = f.id
   AND d.code = course.owner_code
  WHERE f.tenant_id = t.id
    AND (
      (course.owner_type = 'faculty' AND f.code = course.owner_code)
      OR
      (course.owner_type = 'department' AND f.code = 'ENG' AND d.id IS NOT NULL)
    )
) AS owner ON true
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO UPDATE
SET faculty_id = EXCLUDED.faculty_id,
    department_id = EXCLUDED.department_id,
    title = EXCLUDED.title,
    credit_hours = EXCLUDED.credit_hours,
    level = EXCLUDED.level,
    lecture_hours = EXCLUDED.lecture_hours,
    tutorial_hours = EXCLUDED.tutorial_hours,
    lab_hours = EXCLUDED.lab_hours,
    is_active = EXCLUDED.is_active;


-- Seed the approved second-semester ECU course catalogue records.
-- PHM courses are faculty-owned; MCE 024 is owned by Mechatronics Engineering.
INSERT INTO public.courses (
  tenant_id,
  faculty_id,
  department_id,
  code,
  title,
  credit_hours,
  level,
  lecture_hours,
  tutorial_hours,
  lab_hours,
  is_active
)
SELECT
  t.id,
  owner.faculty_id,
  owner.department_id,
  course.code,
  course.title,
  course.credit_hours,
  2,
  course.lecture_hours,
  course.tutorial_hours,
  course.lab_hours,
  true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('PHM 013', 'Calculus for Engineering (2)', 3::numeric, 2::numeric, 2::numeric, 0::numeric, 'faculty'::text, 'ENG'::text),
    ('PHM 014', 'Linear Algebra and Analytical Geometry', 3::numeric, 2::numeric, 2::numeric, 0::numeric, 'faculty'::text, 'ENG'::text),
    ('PHM 022', 'Waves, Electricity, and Magnetic Fields', 3::numeric, 2::numeric, 0::numeric, 3::numeric, 'faculty'::text, 'ENG'::text),
    ('PHM 033', 'Engineering Mechanics (2) - Dynamics', 3::numeric, 2::numeric, 2::numeric, 0::numeric, 'faculty'::text, 'ENG'::text),
    ('MCE 024', 'Production Engineering', 3::numeric, 2::numeric, 0::numeric, 3::numeric, 'department'::text, 'MCE'::text)
) AS course(code, title, credit_hours, lecture_hours, tutorial_hours, lab_hours, owner_type, owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type = 'faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type = 'department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id = f.tenant_id
   AND d.faculty_id = f.id
   AND d.code = course.owner_code
  WHERE f.tenant_id = t.id
    AND (
      (course.owner_type = 'faculty' AND f.code = course.owner_code)
      OR
      (course.owner_type = 'department' AND f.code = 'ENG' AND d.id IS NOT NULL)
    )
) AS owner ON true
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO UPDATE
SET faculty_id = EXCLUDED.faculty_id,
    department_id = EXCLUDED.department_id,
    title = EXCLUDED.title,
    credit_hours = EXCLUDED.credit_hours,
    level = EXCLUDED.level,
    lecture_hours = EXCLUDED.lecture_hours,
    tutorial_hours = EXCLUDED.tutorial_hours,
    lab_hours = EXCLUDED.lab_hours,
    is_active = EXCLUDED.is_active;


-- Seed the approved third-semester ECU course catalogue records.
-- PHM courses are faculty-owned; SET and MCE courses are department-owned.
-- Semester 3 corresponds to First Level (Sophomore).
INSERT INTO public.courses (
  tenant_id,
  faculty_id,
  department_id,
  code,
  title,
  credit_hours,
  level,
  lecture_hours,
  tutorial_hours,
  lab_hours,
  is_active
)
SELECT
  t.id,
  owner.faculty_id,
  owner.department_id,
  course.code,
  course.title,
  course.credit_hours,
  3,
  course.lecture_hours,
  course.tutorial_hours,
  course.lab_hours,
  true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('PHM 113', 'Calculus for Engineering (3)', 3::numeric, 2::numeric, 2::numeric, 0::numeric, 'faculty'::text, 'ENG'::text),
    ('PHM 115', 'Differential Equations and Partial Differential Equations', 3::numeric, 2::numeric, 2::numeric, 0::numeric, 'faculty'::text, 'ENG'::text),
    ('SET 111', 'Digital Design', 3::numeric, 2::numeric, 1::numeric, 1.5::numeric, 'department'::text, 'SET'::text),
    ('SET 112', 'Computer Programming (1)', 3::numeric, 2::numeric, 0::numeric, 3::numeric, 'department'::text, 'SET'::text),
    ('MCE 132', 'Structures and Properties of Materials', 3::numeric, 2::numeric, 1::numeric, 1.5::numeric, 'department'::text, 'MCE'::text),
    ('SET 113', 'Electrical and Electronic Circuits', 3::numeric, 2::numeric, 1::numeric, 1.5::numeric, 'department'::text, 'SET'::text)
) AS course(code, title, credit_hours, lecture_hours, tutorial_hours, lab_hours, owner_type, owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type = 'faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type = 'department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id = f.tenant_id
   AND d.faculty_id = f.id
   AND d.code = course.owner_code
  WHERE f.tenant_id = t.id
    AND (
      (course.owner_type = 'faculty' AND f.code = course.owner_code)
      OR
      (course.owner_type = 'department' AND f.code = 'ENG' AND d.id IS NOT NULL)
    )
) AS owner ON true
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO UPDATE
SET faculty_id = EXCLUDED.faculty_id,
    department_id = EXCLUDED.department_id,
    title = EXCLUDED.title,
    credit_hours = EXCLUDED.credit_hours,
    level = EXCLUDED.level,
    lecture_hours = EXCLUDED.lecture_hours,
    tutorial_hours = EXCLUDED.tutorial_hours,
    lab_hours = EXCLUDED.lab_hours,
    is_active = EXCLUDED.is_active;


-- Seed the confirmed Semester 4-10 course catalogue records. Unspecified weekly hours remain NULL.

-- Semester 4
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level,
  lecture_hours, tutorial_hours, lab_hours, is_active
)
SELECT t.id, owner.faculty_id, owner.department_id,
       course.code, course.title, course.credit_hours, 4,
       course.lecture_hours, course.tutorial_hours, course.lab_hours, true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('PHM 114','Statistics and Probability for Engineering',3::numeric,2::numeric,2::numeric,0::numeric,'faculty'::text,'ENG'::text),
    ('SET 121','Computer Architecture',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 122','Computer Programming (2)',3::numeric,2::numeric,0::numeric,3::numeric,'department'::text,'SET'::text),
    ('SET 123','Data Structures and Algorithms',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 124','Software Engineering (1)',3::numeric,2::numeric,2::numeric,0::numeric,'department'::text,'SET'::text)
) AS course(code,title,credit_hours,lecture_hours,tutorial_hours,lab_hours,owner_type,owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type='faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type='department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id=f.tenant_id AND d.faculty_id=f.id AND d.code=course.owner_code
  WHERE f.tenant_id=t.id
    AND ((course.owner_type='faculty' AND f.code=course.owner_code)
      OR (course.owner_type='department' AND f.code='ENG' AND d.id IS NOT NULL))
) AS owner ON true
WHERE t.slug='ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET faculty_id=EXCLUDED.faculty_id, department_id=EXCLUDED.department_id,
    title=EXCLUDED.title, credit_hours=EXCLUDED.credit_hours, level=EXCLUDED.level,
    lecture_hours=EXCLUDED.lecture_hours, tutorial_hours=EXCLUDED.tutorial_hours,
    lab_hours=EXCLUDED.lab_hours, is_active=EXCLUDED.is_active;

-- Semester 5
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level,
  lecture_hours, tutorial_hours, lab_hours, is_active
)
SELECT t.id, owner.faculty_id, owner.department_id,
       course.code, course.title, course.credit_hours, 5,
       course.lecture_hours, course.tutorial_hours, course.lab_hours, true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('MCE 112','Thermodynamics',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'MCE'::text),
    ('SET 211','Object-Oriented Analysis and Design',3::numeric,NULL::numeric,NULL::numeric,NULL::numeric,'department'::text,'SET'::text),
    ('SET 212','Software Engineering (2)',3::numeric,2::numeric,2::numeric,0::numeric,'department'::text,'SET'::text),
    ('SET 213','Operating Systems',3::numeric,NULL::numeric,NULL::numeric,NULL::numeric,'department'::text,'SET'::text),
    ('SET 214','Signals and Systems',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text)
) AS course(code,title,credit_hours,lecture_hours,tutorial_hours,lab_hours,owner_type,owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type='faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type='department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id=f.tenant_id AND d.faculty_id=f.id AND d.code=course.owner_code
  WHERE f.tenant_id=t.id
    AND ((course.owner_type='faculty' AND f.code=course.owner_code)
      OR (course.owner_type='department' AND f.code='ENG' AND d.id IS NOT NULL))
) AS owner ON true
WHERE t.slug='ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET faculty_id=EXCLUDED.faculty_id, department_id=EXCLUDED.department_id,
    title=EXCLUDED.title, credit_hours=EXCLUDED.credit_hours, level=EXCLUDED.level,
    lecture_hours=EXCLUDED.lecture_hours, tutorial_hours=EXCLUDED.tutorial_hours,
    lab_hours=EXCLUDED.lab_hours, is_active=EXCLUDED.is_active;

-- Semester 6
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level,
  lecture_hours, tutorial_hours, lab_hours, is_active
)
SELECT t.id, owner.faculty_id, owner.department_id,
       course.code, course.title, course.credit_hours, 6,
       course.lecture_hours, course.tutorial_hours, course.lab_hours, true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('SET 221','Electronic Design Automation',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 222','Design and Analysis of Algorithms',3::numeric,2::numeric,2::numeric,0::numeric,'department'::text,'SET'::text),
    ('SET 223','Software Testing, Validation, and Verification',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 224','Design of Compilers',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 225','Database Systems (1)',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 226','Control Engineering',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text)
) AS course(code,title,credit_hours,lecture_hours,tutorial_hours,lab_hours,owner_type,owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type='faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type='department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id=f.tenant_id AND d.faculty_id=f.id AND d.code=course.owner_code
  WHERE f.tenant_id=t.id
    AND ((course.owner_type='faculty' AND f.code=course.owner_code)
      OR (course.owner_type='department' AND f.code='ENG' AND d.id IS NOT NULL))
) AS owner ON true
WHERE t.slug='ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET faculty_id=EXCLUDED.faculty_id, department_id=EXCLUDED.department_id,
    title=EXCLUDED.title, credit_hours=EXCLUDED.credit_hours, level=EXCLUDED.level,
    lecture_hours=EXCLUDED.lecture_hours, tutorial_hours=EXCLUDED.tutorial_hours,
    lab_hours=EXCLUDED.lab_hours, is_active=EXCLUDED.is_active;

-- Semester 7
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level,
  lecture_hours, tutorial_hours, lab_hours, is_active
)
SELECT t.id, owner.faculty_id, owner.department_id,
       course.code, course.title, course.credit_hours, 7,
       course.lecture_hours, course.tutorial_hours, course.lab_hours, true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('SET 311','Microcontrollers and Interfacing',3::numeric,2::numeric,0::numeric,3::numeric,'department'::text,'SET'::text),
    ('SET 312','Agile Software Engineering',3::numeric,2::numeric,2::numeric,0::numeric,'department'::text,'SET'::text),
    ('SET 313','Computer Networks',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 314','Computer Vision',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text)
) AS course(code,title,credit_hours,lecture_hours,tutorial_hours,lab_hours,owner_type,owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type='faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type='department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id=f.tenant_id AND d.faculty_id=f.id AND d.code=course.owner_code
  WHERE f.tenant_id=t.id
    AND ((course.owner_type='faculty' AND f.code=course.owner_code)
      OR (course.owner_type='department' AND f.code='ENG' AND d.id IS NOT NULL))
) AS owner ON true
WHERE t.slug='ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET faculty_id=EXCLUDED.faculty_id, department_id=EXCLUDED.department_id,
    title=EXCLUDED.title, credit_hours=EXCLUDED.credit_hours, level=EXCLUDED.level,
    lecture_hours=EXCLUDED.lecture_hours, tutorial_hours=EXCLUDED.tutorial_hours,
    lab_hours=EXCLUDED.lab_hours, is_active=EXCLUDED.is_active;

-- Semester 8
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level,
  lecture_hours, tutorial_hours, lab_hours, is_active
)
SELECT t.id, owner.faculty_id, owner.department_id,
       course.code, course.title, course.credit_hours, 8,
       course.lecture_hours, course.tutorial_hours, course.lab_hours, true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('SET 321','Software Formal Specifications',3::numeric,2::numeric,2::numeric,0::numeric,'department'::text,'SET'::text),
    ('SET 322','Distributed Computing',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 323','Real-Time and Embedded Systems Design',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text)
) AS course(code,title,credit_hours,lecture_hours,tutorial_hours,lab_hours,owner_type,owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type='faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type='department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id=f.tenant_id AND d.faculty_id=f.id AND d.code=course.owner_code
  WHERE f.tenant_id=t.id
    AND ((course.owner_type='faculty' AND f.code=course.owner_code)
      OR (course.owner_type='department' AND f.code='ENG' AND d.id IS NOT NULL))
) AS owner ON true
WHERE t.slug='ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET faculty_id=EXCLUDED.faculty_id, department_id=EXCLUDED.department_id,
    title=EXCLUDED.title, credit_hours=EXCLUDED.credit_hours, level=EXCLUDED.level,
    lecture_hours=EXCLUDED.lecture_hours, tutorial_hours=EXCLUDED.tutorial_hours,
    lab_hours=EXCLUDED.lab_hours, is_active=EXCLUDED.is_active;

-- Semester 9
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level,
  lecture_hours, tutorial_hours, lab_hours, is_active
)
SELECT t.id, owner.faculty_id, owner.department_id,
       course.code, course.title, course.credit_hours, 9,
       course.lecture_hours, course.tutorial_hours, course.lab_hours, true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('SET 411','High-Performance Computing',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 412','Software Design Patterns',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text),
    ('SET 413','Computer and Network Security',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text)
) AS course(code,title,credit_hours,lecture_hours,tutorial_hours,lab_hours,owner_type,owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type='faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type='department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id=f.tenant_id AND d.faculty_id=f.id AND d.code=course.owner_code
  WHERE f.tenant_id=t.id
    AND ((course.owner_type='faculty' AND f.code=course.owner_code)
      OR (course.owner_type='department' AND f.code='ENG' AND d.id IS NOT NULL))
) AS owner ON true
WHERE t.slug='ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET faculty_id=EXCLUDED.faculty_id, department_id=EXCLUDED.department_id,
    title=EXCLUDED.title, credit_hours=EXCLUDED.credit_hours, level=EXCLUDED.level,
    lecture_hours=EXCLUDED.lecture_hours, tutorial_hours=EXCLUDED.tutorial_hours,
    lab_hours=EXCLUDED.lab_hours, is_active=EXCLUDED.is_active;

-- Semester 10
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level,
  lecture_hours, tutorial_hours, lab_hours, is_active
)
SELECT t.id, owner.faculty_id, owner.department_id,
       course.code, course.title, course.credit_hours, 10,
       course.lecture_hours, course.tutorial_hours, course.lab_hours, true
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('SET 421','Software Maintenance and Evolution',3::numeric,2::numeric,2::numeric,0::numeric,'department'::text,'SET'::text),
    ('SET 422','Software Project Management',2::numeric,1::numeric,2::numeric,0::numeric,'department'::text,'SET'::text),
    ('SET 423','Mobile Computing',3::numeric,2::numeric,1::numeric,1.5::numeric,'department'::text,'SET'::text)
) AS course(code,title,credit_hours,lecture_hours,tutorial_hours,lab_hours,owner_type,owner_code)
JOIN LATERAL (
  SELECT
    CASE WHEN course.owner_type='faculty' THEN f.id END AS faculty_id,
    CASE WHEN course.owner_type='department' THEN d.id END AS department_id
  FROM public.faculties AS f
  LEFT JOIN public.departments AS d
    ON d.tenant_id=f.tenant_id AND d.faculty_id=f.id AND d.code=course.owner_code
  WHERE f.tenant_id=t.id
    AND ((course.owner_type='faculty' AND f.code=course.owner_code)
      OR (course.owner_type='department' AND f.code='ENG' AND d.id IS NOT NULL))
) AS owner ON true
WHERE t.slug='ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET faculty_id=EXCLUDED.faculty_id, department_id=EXCLUDED.department_id,
    title=EXCLUDED.title, credit_hours=EXCLUDED.credit_hours, level=EXCLUDED.level,
    lecture_hours=EXCLUDED.lecture_hours, tutorial_hours=EXCLUDED.tutorial_hours,
    lab_hours=EXCLUDED.lab_hours, is_active=EXCLUDED.is_active;


-- Seed confirmed ECU programme course prerequisites.
-- Only prerequisites explicitly listed in the supplied curriculum are included.
-- Course references resolve by tenant-scoped course codes for portable local seeds.
INSERT INTO public.course_prerequisites (
  tenant_id,
  course_id,
  prerequisite_course_id,
  kind
)
SELECT
  t.id,
  course.id,
  prerequisite.id,
  'prerequisite'::public.prerequisite_kind
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('PHM 013', 'PHM 012'),
    ('PHM 033', 'PHM 032'),
    ('PHM 113', 'PHM 013'),
    ('PHM 115', 'PHM 013'),
    ('MCE 132', 'PHM 042'),
    ('PHM 114', 'PHM 013'),
    ('SET 121', 'SET 111'),
    ('SET 122', 'SET 112'),
    ('SET 123', 'SET 112'),
    ('SET 124', 'SET 112'),
    ('MCE 112', 'PHM 012'),
    ('SET 211', 'SET 122'),
    ('SET 212', 'SET 124'),
    ('SET 213', 'SET 121'),
    ('SET 214', 'PHM 114'),
    ('SET 221', 'SET 121'),
    ('SET 222', 'SET 123'),
    ('SET 223', 'SET 212'),
    ('SET 224', 'SET 213'),
    ('SET 225', 'SET 123'),
    ('SET 226', 'SET 214'),
    ('SET 311', 'SET 121'),
    ('SET 312', 'SET 212'),
    ('SET 314', 'SET 214'),
    ('SET 321', 'SET 124'),
    ('SET 322', 'SET 212'),
    ('SET 322', 'SET 313'),
    ('SET 323', 'SET 213'),
    ('SET 323', 'SET 311'),
    ('SET 412', 'SET 212'),
    ('SET 413', 'SET 213'),
    ('SET 413', 'SET 313'),
    ('SET 421', 'SET 223'),
    ('SET 422', 'SET 212'),
    ('SET 423', 'SET 322')
) AS prerequisite_pair(course_code, prerequisite_code)
JOIN public.courses AS course
  ON course.tenant_id = t.id
 AND course.code = prerequisite_pair.course_code
JOIN public.courses AS prerequisite
  ON prerequisite.tenant_id = t.id
 AND prerequisite.code = prerequisite_pair.prerequisite_code
WHERE t.slug = 'ecu'
ON CONFLICT (course_id, prerequisite_course_id) DO UPDATE
SET tenant_id = EXCLUDED.tenant_id,
    kind = EXCLUDED.kind;


-- Seed the four confirmed ECU specialization course catalogues.
-- All specialization courses carry 3 credit hours as confirmed.
-- Semester/level placement and weekly workload hours are left unset because they were not specified.
INSERT INTO public.courses (
  tenant_id, department_id, code, title, credit_hours, level, is_active
)
SELECT t.id, d.id, v.code, v.title, 3, NULL, true
FROM public.tenants AS t
JOIN public.departments AS d
  ON d.tenant_id = t.id AND d.code = 'SET'
CROSS JOIN (
  VALUES
    ('SET 361','Pattern Recognition'),
    ('SET 362','Digital Image Processing'),
    ('SET 363','Computer Graphics'),
    ('SET 364','Human-Computer Interaction'),
    ('SET 461','Visualization'),
    ('SET 462','Multimedia Engineering'),
    ('SET 463','Computer Animation'),
    ('SET 464','Selected Topics in Multimedia and Computer Graphics'),
    ('SET 465','Game Design and Development'),
    ('SET 371','Parallel and Cluster Computing'),
    ('SET 372','Internet Programming'),
    ('SET 373','Parallel and Distributed Algorithms'),
    ('SET 374','Network Operation and Management'),
    ('SET 471','Selected Topics in Distributed and Mobile Computing'),
    ('SET 472','Cloud Computing'),
    ('SET 473','Wireless Networks'),
    ('SET 474','Computer and Network Forensics'),
    ('SET 475','Pervasive Computing'),
    ('SET 381','Program Analysis'),
    ('SET 382','Software Engineering Process Management'),
    ('SET 383','Dependability and Reliability of Software Systems'),
    ('SET 384','Business Process Modeling'),
    ('SET 481','Selected Topics in Software Product Lines'),
    ('SET 482','Software Performance Evaluation'),
    ('SET 483','Aspect- and Service-Oriented Software Systems'),
    ('SET 484','Secure Code Development'),
    ('SET 485','Software Quality Assurance'),
    ('SET 391','Database Systems (2)'),
    ('SET 392','Simulation of Engineering Systems'),
    ('SET 393','Data Mining and Business Intelligence'),
    ('SET 394','Artificial Intelligence'),
    ('SET 491','Selected Topics in Software Applications'),
    ('SET 492','Embedded Operating Systems'),
    ('SET 493','Bioinformatics'),
    ('SET 494','Ontologies and the Semantic Web'),
    ('SET 495','E-learning Systems')
) AS v(code,title)
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id,code) DO UPDATE
SET department_id = EXCLUDED.department_id,
    title = EXCLUDED.title,
    credit_hours = EXCLUDED.credit_hours,
    is_active = true;

-- Associate each specialization course with its ECU specialization.
-- is_required is omitted and therefore retains its schema default (false).
INSERT INTO public.specialization_courses (
  tenant_id, program_id, specialization_id, course_id
)
SELECT t.id, s.program_id, s.id, c.id
FROM public.tenants AS t
JOIN public.specializations AS s ON s.tenant_id = t.id
CROSS JOIN (
  VALUES
    ('MCG','SET 361'),('MCG','SET 362'),('MCG','SET 363'),('MCG','SET 364'),
    ('MCG','SET 461'),('MCG','SET 462'),('MCG','SET 463'),('MCG','SET 464'),('MCG','SET 465'),
    ('DMC','SET 371'),('DMC','SET 372'),('DMC','SET 373'),('DMC','SET 374'),
    ('DMC','SET 471'),('DMC','SET 472'),('DMC','SET 473'),('DMC','SET 474'),('DMC','SET 475'),
    ('SPL','SET 381'),('SPL','SET 382'),('SPL','SET 383'),('SPL','SET 384'),
    ('SPL','SET 481'),('SPL','SET 482'),('SPL','SET 483'),('SPL','SET 484'),('SPL','SET 485'),
    ('SA','SET 391'),('SA','SET 392'),('SA','SET 393'),('SA','SET 394'),
    ('SA','SET 491'),('SA','SET 492'),('SA','SET 493'),('SA','SET 494'),('SA','SET 495')
) AS mapping(specialization_code,course_code)
JOIN public.courses AS c
  ON c.tenant_id = t.id AND c.code = mapping.course_code
WHERE t.slug = 'ecu' AND s.code = mapping.specialization_code
ON CONFLICT (specialization_id,course_id) DO NOTHING;

-- Seed only specialization prerequisites explicitly stated in the ECU curriculum.
-- SET 484 also lists SET 414 in the source, but SET 414 is not in the confirmed
-- course catalogue; that unresolved reference is intentionally not fabricated.
INSERT INTO public.course_prerequisites (
  tenant_id, course_id, prerequisite_course_id, kind
)
SELECT t.id, c.id, p.id, 'prerequisite'::public.prerequisite_kind
FROM public.tenants AS t
CROSS JOIN (
  VALUES
    ('SET 361','SET 214'),('SET 362','SET 214'),
    ('SET 363','PHM 113'),('SET 363','SET 122'),
    ('SET 364','SET 212'),('SET 461','SET 363'),('SET 462','SET 362'),
    ('SET 463','SET 363'),('SET 465','SET 363'),
    ('SET 371','SET 121'),('SET 372','SET 122'),('SET 373','SET 222'),
    ('SET 374','SET 313'),('SET 472','SET 322'),('SET 473','SET 313'),
    ('SET 474','SET 413'),('SET 475','SET 322'),
    ('SET 381','SET 122'),('SET 382','SET 212'),('SET 383','SET 212'),
    ('SET 384','SET 212'),('SET 482','SET 212'),('SET 483','SET 212'),
    ('SET 484','SET 122'),('SET 485','SET 212'),
    ('SET 391','SET 225'),('SET 392','PHM 114'),
    ('SET 393','PHM 114'),('SET 393','SET 225'),
    ('SET 394','PHM 114'),('SET 394','SET 112'),
    ('SET 492','SET 323'),('SET 493','SET 225'),
    ('SET 494','SET 394'),('SET 495','SET 394')
) AS pair(course_code,prerequisite_code)
JOIN public.courses AS c
  ON c.tenant_id = t.id AND c.code = pair.course_code
JOIN public.courses AS p
  ON p.tenant_id = t.id AND p.code = pair.prerequisite_code
WHERE t.slug = 'ecu'
ON CONFLICT (course_id,prerequisite_course_id) DO UPDATE
SET tenant_id = EXCLUDED.tenant_id,
    kind = EXCLUDED.kind;


-- Seed ECU programme curriculum requirement groups for uncoded elective slots
-- and graduation-project components. No placeholder course records are created.
-- Graduation-project courses and credits are confirmed: SET 497 and SET 498, 3 credits each.
INSERT INTO public.curriculum_requirement_groups (
  tenant_id, program_id, academic_level_id, code, title, category,
  required_course_count, minimum_credit_hours, maximum_credit_hours,
  is_required, sort_order, notes, is_active
)
SELECT
  t.id, p.id, al.id,
  requirement.code, requirement.title, requirement.category,
  1, requirement.minimum_credit_hours, NULL,
  true, requirement.sort_order, requirement.notes, true
FROM public.tenants AS t
JOIN public.programs AS p
  ON p.tenant_id = t.id AND p.code = 'SET'
JOIN public.departments AS d
  ON d.id = p.department_id AND d.tenant_id = p.tenant_id
CROSS JOIN (
  VALUES
    ('HUM_ELECTIVE_1','Humanities Elective (1)','humanities_elective',1,3::numeric,1,NULL::text),
    ('HUM_ELECTIVE_2','Humanities Elective (2)','humanities_elective',2,3::numeric,2,NULL::text),
    ('HUM_ELECTIVE_3','Humanities Elective (3)','humanities_elective',4,3::numeric,3,NULL::text),
    ('HUM_ELECTIVE_4','Humanities Elective (4)','humanities_elective',5,3::numeric,4,NULL::text),
    ('HUM_ELECTIVE_5','Humanities Elective (5)','humanities_elective',7,3::numeric,5,NULL::text),
    ('HUM_ELECTIVE_6','Humanities Elective (6)','humanities_elective',8,3::numeric,6,NULL::text),
    ('TECHNICAL_ELECTIVE_1','Technical Elective (1)','technical_elective',7,3::numeric,7,NULL::text),
    ('TECHNICAL_ELECTIVE_2','Technical Elective (2)','technical_elective',8,3::numeric,8,NULL::text),
    ('TECHNICAL_ELECTIVE_3','Technical Elective (3)','technical_elective',8,3::numeric,9,NULL::text),
    ('TECHNICAL_ELECTIVE_4','Technical Elective (4)','technical_elective',9,3::numeric,10,NULL::text),
    ('TECHNICAL_ELECTIVE_5','Technical Elective (5)','technical_elective',9,3::numeric,11,NULL::text),
    ('TECHNICAL_ELECTIVE_6','Technical Elective (6)','technical_elective',10,3::numeric,12,NULL::text),
    ('TECHNICAL_ELECTIVE_7','Technical Elective (7)','technical_elective',10,3::numeric,13,NULL::text),
    ('GRADUATION_PROJECT_1','Graduation Project (1)','graduation_project',9,3::numeric,14,'SET 497; 3 credits; Semester 9.'),
    ('GRADUATION_PROJECT_2','Graduation Project (2)','graduation_project',10,3::numeric,15,'SET 498; 3 credits; Semester 10; prerequisite SET 497.')
) AS requirement(code,title,category,semester_number,minimum_credit_hours,sort_order,notes)
JOIN public.academic_semesters AS al
  ON al.tenant_id = t.id
 AND al.faculty_id = d.faculty_id
 AND al.sequence_number = requirement.semester_number
WHERE t.slug = 'ecu'
ON CONFLICT (program_id, code) DO UPDATE
SET academic_level_id = EXCLUDED.academic_level_id,
    title = EXCLUDED.title,
    category = EXCLUDED.category,
    required_course_count = EXCLUDED.required_course_count,
    minimum_credit_hours = EXCLUDED.minimum_credit_hours,
    maximum_credit_hours = EXCLUDED.maximum_credit_hours,
    is_required = EXCLUDED.is_required,
    sort_order = EXCLUDED.sort_order,
    notes = EXCLUDED.notes,
    is_active = true;


-- Seed the transcript-listed English Language course.
-- It carries zero credit hours, so it is catalogued as a faculty course
-- but is not mapped to one of the six credit-bearing Humanities elective slots.
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level, is_active
)
SELECT
  t.id, f.id, NULL, 'HUM 011', 'English Language', 0, NULL, true
FROM public.tenants AS t
JOIN public.faculties AS f
  ON f.tenant_id = t.id AND f.code = 'ENG'
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO UPDATE
SET faculty_id = EXCLUDED.faculty_id,
    department_id = NULL,
    title = EXCLUDED.title,
    credit_hours = EXCLUDED.credit_hours,
    level = EXCLUDED.level,
    is_active = true;


-- Seed the six transcript-confirmed ECU Humanities elective courses.
-- These are faculty-owned courses (not department-owned) and map one-to-one
-- to the six Humanities elective requirement groups in the SET programme.
INSERT INTO public.courses (
  tenant_id, faculty_id, department_id, code, title, credit_hours, level, is_active
)
SELECT
  t.id, f.id, NULL, humanities.code, humanities.title,
  3, humanities.semester_number, true
FROM public.tenants AS t
JOIN public.faculties AS f
  ON f.tenant_id = t.id AND f.code = 'ENG'
CROSS JOIN (
  VALUES
    ('HUM 012', 'Chinese Language', 1::smallint),
    ('HUM 014', 'Engineering Profession, Practice, and Responsibilities', 2::smallint),
    ('HUM 212', 'Introduction to Marketing', 4::smallint),
    ('HUM 312', 'Human Resource Management', 5::smallint),
    ('HUM 113', 'Security and Safety in Profession', 7::smallint),
    ('HUM 112', 'Health and Wellness', 8::smallint)
) AS humanities(code, title, semester_number)
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO UPDATE
SET faculty_id = EXCLUDED.faculty_id,
    department_id = NULL,
    title = EXCLUDED.title,
    credit_hours = EXCLUDED.credit_hours,
    level = EXCLUDED.level,
    is_active = true;

-- Map each confirmed Humanities course to its corresponding elective slot.
INSERT INTO public.curriculum_requirement_group_courses (
  tenant_id, requirement_group_id, course_id, is_active
)
SELECT
  t.id, requirement_group.id, course.id, true
FROM public.tenants AS t
JOIN public.courses AS course
  ON course.tenant_id = t.id
JOIN public.curriculum_requirement_groups AS requirement_group
  ON requirement_group.tenant_id = t.id
 AND requirement_group.code = CASE course.code
   WHEN 'HUM 012' THEN 'HUM_ELECTIVE_1'
   WHEN 'HUM 014' THEN 'HUM_ELECTIVE_2'
   WHEN 'HUM 212' THEN 'HUM_ELECTIVE_3'
   WHEN 'HUM 312' THEN 'HUM_ELECTIVE_4'
   WHEN 'HUM 113' THEN 'HUM_ELECTIVE_5'
   WHEN 'HUM 112' THEN 'HUM_ELECTIVE_6'
 END
WHERE t.slug = 'ecu'
  AND course.code IN ('HUM 012', 'HUM 014', 'HUM 212', 'HUM 312', 'HUM 113', 'HUM 112')
ON CONFLICT (requirement_group_id, course_id)
DO UPDATE SET is_active = true;


-- Seed the confirmed ECU graduation project courses and their progression prerequisite.
-- User-confirmed curriculum correction supersedes the inconsistent project codes in the older PDF.
INSERT INTO public.courses (
  tenant_id, department_id, code, title, credit_hours, level, is_active
)
SELECT t.id, d.id, project.code, project.title, 3, project.level, true
FROM public.tenants AS t
JOIN public.departments AS d
  ON d.tenant_id = t.id AND d.code = 'SET'
CROSS JOIN (
  VALUES
    ('SET 497', 'Graduation Project (1)', 9::smallint),
    ('SET 498', 'Graduation Project (2)', 10::smallint)
) AS project(code, title, level)
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO UPDATE
SET department_id = EXCLUDED.department_id,
    title = EXCLUDED.title,
    credit_hours = EXCLUDED.credit_hours,
    level = EXCLUDED.level,
    is_active = true;

INSERT INTO public.course_prerequisites (
  tenant_id, course_id, prerequisite_course_id, kind
)
SELECT t.id, project_two.id, project_one.id,
       'prerequisite'::public.prerequisite_kind
FROM public.tenants AS t
JOIN public.courses AS project_one
  ON project_one.tenant_id = t.id AND project_one.code = 'SET 497'
JOIN public.courses AS project_two
  ON project_two.tenant_id = t.id AND project_two.code = 'SET 498'
WHERE t.slug = 'ecu'
ON CONFLICT (course_id, prerequisite_course_id) DO UPDATE
SET tenant_id = EXCLUDED.tenant_id,
    kind = EXCLUDED.kind;


-- Map the confirmed SET programme core curriculum to its ten academic semesters.
-- Shared faculty-level Semester 1-2 courses remain faculty-owned in the course catalogue.
-- Humanities placeholders are omitted until official course codes are confirmed.
-- Technical electives remain represented by curriculum_requirement_groups and
-- specialization eligibility; they are not duplicated as required core mappings.
INSERT INTO public.program_curriculum_courses (
  tenant_id, program_id, course_id, academic_level_id, requirement_type, is_active
)
SELECT
  t.id,
  p.id,
  c.id,
  al.id,
  'required',
  true
FROM public.tenants AS t
JOIN public.programs AS p
  ON p.tenant_id = t.id AND p.code = 'SET'
JOIN public.departments AS d
  ON d.id = p.department_id AND d.tenant_id = p.tenant_id
JOIN public.faculties AS f
  ON f.id = d.faculty_id AND f.tenant_id = d.tenant_id
CROSS JOIN (
  VALUES
    ('PHM 012',1),('PHM 032',1),('PHM 042',1),('SET 012',1),('MCE 061',1),
    ('PHM 013',2),('PHM 014',2),('PHM 022',2),('PHM 033',2),('MCE 024',2),
    ('PHM 113',3),('PHM 115',3),('SET 111',3),('SET 112',3),('MCE 132',3),('SET 113',3),
    ('PHM 114',4),('SET 121',4),('SET 122',4),('SET 123',4),('SET 124',4),
    ('MCE 112',5),('SET 211',5),('SET 212',5),('SET 213',5),('SET 214',5),
    ('SET 221',6),('SET 222',6),('SET 223',6),('SET 224',6),('SET 225',6),('SET 226',6),
    ('SET 311',7),('SET 312',7),('SET 313',7),('SET 314',7),
    ('SET 321',8),('SET 322',8),('SET 323',8),
    ('SET 411',9),('SET 412',9),('SET 413',9),('SET 497',9),
    ('SET 421',10),('SET 422',10),('SET 423',10),('SET 498',10)
) AS curriculum(course_code, semester_number)
JOIN public.courses AS c
  ON c.tenant_id = t.id AND c.code = curriculum.course_code
JOIN public.academic_semesters AS al
  ON al.tenant_id = t.id
 AND al.faculty_id = f.id
 AND al.sequence_number = curriculum.semester_number
WHERE t.slug = 'ecu'
ON CONFLICT (program_id, course_id) DO UPDATE
SET academic_level_id = EXCLUDED.academic_level_id,
    requirement_type = EXCLUDED.requirement_type,
    is_active = true;


-- Technical elective eligibility: every specialization course is eligible for every S7-S10 elective slot.
-- Student selection validation still restricts each student to courses from
-- their own active, approved specialization and enforces prerequisites.
-- All seven slots accept the full 36-course specialization catalogue.
INSERT INTO public.curriculum_requirement_group_courses (
  tenant_id,
  requirement_group_id,
  course_id,
  is_active
)
SELECT
  tenant.id,
  requirement_group.id,
  specialization_course.course_id,
  true
FROM public.tenants AS tenant
JOIN public.curriculum_requirement_groups AS requirement_group
  ON requirement_group.tenant_id = tenant.id
JOIN public.academic_semesters AS academic_level
  ON academic_level.id = requirement_group.academic_level_id
 AND academic_level.tenant_id = tenant.id
JOIN public.specializations AS specialization
  ON specialization.tenant_id = tenant.id
 AND specialization.program_id = requirement_group.program_id
JOIN public.specialization_courses AS specialization_course
  ON specialization_course.specialization_id = specialization.id
JOIN public.courses AS course
  ON course.id = specialization_course.course_id
 AND course.tenant_id = tenant.id
WHERE tenant.slug = 'ecu'
  AND requirement_group.program_id = (
    SELECT program.id
    FROM public.programs AS program
    WHERE program.tenant_id = tenant.id
      AND program.code = 'SET'
    LIMIT 1
  )
  AND requirement_group.category = 'technical_elective'
  AND requirement_group.is_active = true
  AND academic_level.sequence_number BETWEEN 7 AND 10
  AND course.credit_hours >= 3
ON CONFLICT (requirement_group_id, course_id)
DO UPDATE SET is_active = true;


-- ---------------------------------------------------------------------------
-- Current ECU role catalogue.
-- The tenant bootstrap trigger from the identity migration creates legacy
-- roles and permission mappings. Normalize that bootstrap to the approved
-- catalogue. Permission definitions remain migration-owned; all role-to-
-- permission mappings are intentionally empty per the current project setup.
-- ---------------------------------------------------------------------------
DO $role_seed$
DECLARE
  v_tenant_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM public.tenants WHERE slug = 'ecu';
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'ECU tenant must exist before seeding its role catalogue';
  END IF;

  -- Never delete a role definition that is already referenced by an account
  -- or appointment. A fresh local seed has no such references.
  IF EXISTS (
    SELECT 1
    FROM public.roles r
    WHERE r.tenant_id = v_tenant_id
      AND r.key IN (
        'administrator','admission_officer','hr_manager','hr_officer',
        'lab_technician','laboratory_technician','quality_assurance_director',
        'registrar','support_technician','system_administrator',
        'data_protection_officer'
      )
      AND (
        EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.role_id = r.id)
        OR EXISTS (SELECT 1 FROM public.personnel_appointments pa WHERE pa.role_id = r.id)
      )
  ) THEN
    RAISE EXCEPTION 'A role scheduled for removal is already assigned; clean up assignments explicitly before running this seed';
  END IF;

  DELETE FROM public.role_permissions rp
  USING public.roles role_definition
  WHERE rp.role_id = role_definition.id
    AND rp.tenant_id = v_tenant_id
    AND role_definition.tenant_id = v_tenant_id;

  ALTER TABLE public.roles DISABLE TRIGGER roles_guard_identity_fields;

  DELETE FROM public.roles
  WHERE tenant_id = v_tenant_id
    AND key IN (
      'administrator','admission_officer','hr_manager','hr_officer',
      'lab_technician','laboratory_technician','quality_assurance_director',
      'registrar','support_technician','system_administrator',
      'data_protection_officer'
    );

  UPDATE public.roles SET key = 'academic_advisor', name = 'Academic Advisor'
  WHERE tenant_id = v_tenant_id AND key = 'advisor';

  UPDATE public.roles SET key = 'it_officer', name = 'IT Officer'
  WHERE tenant_id = v_tenant_id AND key = 'it_staff';

  UPDATE public.roles SET key = 'president', name = 'President'
  WHERE tenant_id = v_tenant_id AND key = 'university_president';

  UPDATE public.roles SET name = 'Teaching Assistant'
  WHERE tenant_id = v_tenant_id AND key = 'teaching_assistant';

  INSERT INTO public.roles
    (tenant_id, key, name, description, is_system, role_type, category, is_academic_rank, is_active)
  SELECT
    v_tenant_id, seed.key, seed.name, seed.description, true,
    seed.role_type, seed.category, seed.is_academic_rank, true
  FROM (VALUES
    ('academic_advisor','Academic Advisor',NULL::text,'system'::text,NULL::text,false),
    ('assistant_professor','Assistant Professor','Academic rank.','position'::text,'academic'::text,true),
    ('associate_professor','Associate Professor','Academic rank.','position'::text,'academic'::text,true),
    ('dean','Dean','Faculty-scoped academic leadership position.','both'::text,'academic'::text,false),
    ('department_head','Department Head','Department-scoped academic leadership position.','both'::text,'academic'::text,false),
    ('finance_manager','Finance Manager','Finance management position.','position'::text,'administrative'::text,false),
    ('finance_officer','Finance Officer','Finance operations position.','position'::text,'administrative'::text,false),
    ('instructor','Instructor','Teaching role without an academic professorial rank.','both'::text,'academic'::text,false),
    ('it_administrator','IT Administrator','University technology administration position.','position'::text,'technical'::text,false),
    ('it_director','IT Director','University technology leadership position.','position'::text,'technical'::text,false),
    ('it_officer','IT Officer',NULL::text,'system'::text,NULL::text,false),
    ('lecturer','Lecturer','Academic teaching position.','position'::text,'academic'::text,true),
    ('librarian','Librarian','Library services position.','position'::text,'support'::text,false),
    ('president','President','University-wide leadership position.','position'::text,'academic'::text,false),
    ('professor','Professor','Senior academic rank.','position'::text,'academic'::text,true),
    ('programme_coordinator','Programme Coordinator','Academic programme coordination position.','position'::text,'academic'::text,false),
    ('programme_director','Programme Director','Academic programme leadership position.','position'::text,'academic'::text,false),
    ('student','Student',NULL::text,'system'::text,NULL::text,false),
    ('student_affairs_officer','Student Affairs Officer','Student affairs administration position.','position'::text,'administrative'::text,false),
    ('teaching_assistant','Teaching Assistant','Academic teaching support position.','both'::text,'academic'::text,false),
    ('vice_dean','Vice Dean','Faculty-scoped deputy academic leadership position.','both'::text,'academic'::text,false),
    ('vice_president','Vice President','University-wide deputy leadership position.','position'::text,'academic'::text,false)
  ) AS seed(key,name,description,role_type,category,is_academic_rank)
  ON CONFLICT (tenant_id, key) DO UPDATE
  SET name = EXCLUDED.name,
      description = coalesce(EXCLUDED.description, public.roles.description),
      is_system = true,
      role_type = EXCLUDED.role_type,
      category = EXCLUDED.category,
      is_academic_rank = EXCLUDED.is_academic_rank,
      is_active = true;

  ALTER TABLE public.roles ENABLE TRIGGER roles_guard_identity_fields;
END
$role_seed$;

-- The five annual progression levels have stable display labels.
UPDATE public.academic_year_levels AS level
SET name = labels.level_name,
    display_name = labels.level_name
FROM (VALUES
  (1,'General Level'),
  (2,'First Level'),
  (3,'Second Level'),
  (4,'Third Level'),
  (5,'Fourth Level')
) AS labels(sequence_number,level_name)
JOIN public.tenants AS t ON t.slug = 'ecu'
JOIN public.faculties AS f ON f.tenant_id = t.id AND f.code = 'ENG'
WHERE level.tenant_id = t.id
  AND level.faculty_id = f.id
  AND level.sequence_number = labels.sequence_number;

-- ---------------------------------------------------------------------------
-- ECU academic calendar skeleton for 2026/2027.
-- Official dates were not provided, so date and registration fields remain NULL.
-- ---------------------------------------------------------------------------
DO $calendar_seed$
DECLARE
  v_tenant_id uuid;
  v_calendar_id uuid;
  v_year_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM public.tenants WHERE slug = 'ecu';

  SELECT id INTO v_calendar_id
  FROM public.academic_calendars
  WHERE tenant_id = v_tenant_id AND code = 'ECU_MAIN';

  IF v_calendar_id IS NULL THEN
    INSERT INTO public.academic_calendars
      (tenant_id, faculty_id, code, name, timezone, is_default, is_active)
    VALUES
      (v_tenant_id, NULL, 'ECU_MAIN', 'ECU Academic Calendar', 'Africa/Cairo', true, true)
    RETURNING id INTO v_calendar_id;
  END IF;

  SELECT id INTO v_year_id
  FROM public.academic_years
  WHERE tenant_id = v_tenant_id
    AND calendar_id = v_calendar_id
    AND code = '2026-2027';

  IF v_year_id IS NULL THEN
    INSERT INTO public.academic_years
      (tenant_id, calendar_id, code, name, starts_on, ends_on, status)
    VALUES
      (v_tenant_id, v_calendar_id, '2026-2027',
       'Academic Year 2026/2027', NULL, NULL, 'planned')
    RETURNING id INTO v_year_id;
  END IF;

  INSERT INTO public.terms
    (tenant_id, code, name, starts_on, ends_on, status,
     academic_year_id, term_kind, sequence_number,
     instructional_starts_on, instructional_ends_on,
     registration_opens_at, registration_closes_at, add_drop_ends_at)
  SELECT v_tenant_id, seed.code, seed.name, NULL, NULL, 'planned',
         v_year_id, seed.term_kind, seed.sequence_number,
         NULL, NULL, NULL, NULL, NULL
  FROM (VALUES
    ('2026-2027-FALL','Fall 2026/2027','fall'::public.academic_term_kind,1),
    ('2026-2027-SPRING','Spring 2026/2027','spring'::public.academic_term_kind,2),
    ('2026-2027-SUMMER','Summer 2026/2027','summer'::public.academic_term_kind,3)
  ) AS seed(code,name,term_kind,sequence_number)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.terms existing
    WHERE existing.tenant_id = v_tenant_id AND existing.code = seed.code
  );
END
$calendar_seed$;

-- ---------------------------------------------------------------------------
-- ECU Article 38 grade scale. Permission mappings remain intentionally empty;
-- grade scales are academic grading data, not authorization mappings.
-- ---------------------------------------------------------------------------
DO $grade_scale_seed$
DECLARE
  v_tenant_id uuid;
  v_scale_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM public.tenants WHERE slug = 'ecu';

  INSERT INTO public.grade_scales (tenant_id, name, max_grade_points, is_default)
  VALUES (v_tenant_id, 'ECU Article 38', 4.0, true)
  ON CONFLICT (tenant_id, name)
  DO UPDATE SET max_grade_points = EXCLUDED.max_grade_points, is_default = true
  RETURNING id INTO v_scale_id;

  UPDATE public.grade_scales
  SET is_default = false
  WHERE tenant_id = v_tenant_id AND id <> v_scale_id AND is_default;

  INSERT INTO public.grade_scale_bands
    (tenant_id, scale_id, letter, min_percentage, grade_points, is_passing)
  VALUES
    (v_tenant_id,v_scale_id,'A+',97,4.0,true),
    (v_tenant_id,v_scale_id,'A',93,4.0,true),
    (v_tenant_id,v_scale_id,'A-',89,3.7,true),
    (v_tenant_id,v_scale_id,'B+',84,3.3,true),
    (v_tenant_id,v_scale_id,'B',80,3.0,true),
    (v_tenant_id,v_scale_id,'B-',76,2.7,true),
    (v_tenant_id,v_scale_id,'C+',73,2.3,true),
    (v_tenant_id,v_scale_id,'C',70,2.0,true),
    (v_tenant_id,v_scale_id,'C-',67,1.7,true),
    (v_tenant_id,v_scale_id,'D+',64,1.3,true),
    (v_tenant_id,v_scale_id,'D',60,1.0,true),
    (v_tenant_id,v_scale_id,'F',0,0.0,false)
  ON CONFLICT (scale_id, letter) DO UPDATE
  SET min_percentage = EXCLUDED.min_percentage,
      grade_points = EXCLUDED.grade_points,
      is_passing = EXCLUDED.is_passing;
END
$grade_scale_seed$;

-- ---------------------------------------------------------------------------
-- 2026/2027 draft course offerings.
-- Odd curriculum semesters are offered in Fall; even semesters in Spring.
-- Summer is retained as a term for approved retakes/additional offerings.
-- ---------------------------------------------------------------------------
INSERT INTO public.course_offerings
  (tenant_id, course_id, term_id, status, grade_scale_id, grading_basis)
SELECT t.id, c.id, term.id, 'draft'::public.offering_status, gs.id, 'letter_graded'
FROM public.tenants t
JOIN (VALUES
  ('HUM 011','2026-2027-FALL'),
  ('HUM 113','2026-2027-FALL'),
  ('HUM 312','2026-2027-FALL'),
  ('MCE 061','2026-2027-FALL'),
  ('MCE 112','2026-2027-FALL'),
  ('MCE 132','2026-2027-FALL'),
  ('PHM 012','2026-2027-FALL'),
  ('PHM 032','2026-2027-FALL'),
  ('PHM 042','2026-2027-FALL'),
  ('PHM 113','2026-2027-FALL'),
  ('PHM 115','2026-2027-FALL'),
  ('SET 012','2026-2027-FALL'),
  ('SET 111','2026-2027-FALL'),
  ('SET 112','2026-2027-FALL'),
  ('SET 113','2026-2027-FALL'),
  ('SET 211','2026-2027-FALL'),
  ('SET 212','2026-2027-FALL'),
  ('SET 213','2026-2027-FALL'),
  ('SET 214','2026-2027-FALL'),
  ('SET 311','2026-2027-FALL'),
  ('SET 312','2026-2027-FALL'),
  ('SET 313','2026-2027-FALL'),
  ('SET 314','2026-2027-FALL'),
  ('SET 392','2026-2027-FALL'),
  ('SET 411','2026-2027-FALL'),
  ('SET 412','2026-2027-FALL'),
  ('SET 413','2026-2027-FALL'),
  ('SET 472','2026-2027-FALL'),
  ('SET 473','2026-2027-FALL'),
  ('SET 497','2026-2027-FALL'),
  ('HUM 014','2026-2027-SPRING'),
  ('HUM 112','2026-2027-SPRING'),
  ('HUM 212','2026-2027-SPRING'),
  ('MCE 024','2026-2027-SPRING'),
  ('PHM 013','2026-2027-SPRING'),
  ('PHM 014','2026-2027-SPRING'),
  ('PHM 022','2026-2027-SPRING'),
  ('PHM 033','2026-2027-SPRING'),
  ('PHM 114','2026-2027-SPRING'),
  ('SET 121','2026-2027-SPRING'),
  ('SET 122','2026-2027-SPRING'),
  ('SET 123','2026-2027-SPRING'),
  ('SET 124','2026-2027-SPRING'),
  ('SET 221','2026-2027-SPRING'),
  ('SET 222','2026-2027-SPRING'),
  ('SET 223','2026-2027-SPRING'),
  ('SET 224','2026-2027-SPRING'),
  ('SET 225','2026-2027-SPRING'),
  ('SET 226','2026-2027-SPRING'),
  ('SET 321','2026-2027-SPRING'),
  ('SET 322','2026-2027-SPRING'),
  ('SET 323','2026-2027-SPRING'),
  ('SET 421','2026-2027-SPRING'),
  ('SET 422','2026-2027-SPRING'),
  ('SET 423','2026-2027-SPRING'),
  ('SET 498','2026-2027-SPRING')
) AS seed(course_code,term_code) ON true
JOIN public.courses c ON c.tenant_id = t.id AND c.code = seed.course_code
JOIN public.terms term ON term.tenant_id = t.id AND term.code = seed.term_code
JOIN public.grade_scales gs ON gs.tenant_id = t.id AND gs.name = 'ECU Article 38'
WHERE t.slug = 'ecu'
ON CONFLICT (course_id, term_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Fall 2026 SET timetable: buildings, rooms, sections, and meetings.
-- Instructor identities/assignments are not invented because the timetable
-- source does not provide verified personnel-directory mappings.
-- ---------------------------------------------------------------------------
DO $room_seed$
DECLARE
  v_tenant_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM public.tenants WHERE slug = 'ecu';

  INSERT INTO public.buildings (tenant_id,code,name)
  VALUES (v_tenant_id,'A','Building A'),(v_tenant_id,'D','Building D')
  ON CONFLICT (tenant_id,code) DO UPDATE SET name = EXCLUDED.name;

  INSERT INTO public.rooms (tenant_id,building_id,code,name,room_type)
  SELECT v_tenant_id,b.id,r.room_code,r.room_code,'classroom'::public.room_type
  FROM (VALUES
    ('A','202'),('A','206'),('A','207'),('A','208'),('A','308'),
    ('A','311'),('A','312'),('A','313'),
    ('D','101'),('D','103'),('D','104'),('D','110'),('D','208')
  ) AS r(building_code,room_code)
  JOIN public.buildings b
    ON b.tenant_id = v_tenant_id AND b.code = r.building_code
  ON CONFLICT (building_id,code) DO UPDATE SET name = EXCLUDED.name;
END
$room_seed$;

CREATE TEMP TABLE IF NOT EXISTS seed_fall_2026_meetings (
  course_code text NOT NULL,
  group_code text NOT NULL,
  section_kind public.section_kind NOT NULL,
  day_of_week smallint NOT NULL,
  starts_at time NOT NULL,
  ends_at time NOT NULL,
  building_code text,
  room_code text,
  meeting_type text NOT NULL
);
TRUNCATE TABLE seed_fall_2026_meetings;

INSERT INTO seed_fall_2026_meetings
  (course_code,group_code,section_kind,day_of_week,starts_at,ends_at,building_code,room_code,meeting_type)
VALUES
('SET 412','SA-G1+G2','lecture',0,'08:30','09:30','A','308','lecture'),
('SET 497','SA-G1+G2','lecture',0,'09:30','13:30',NULL,NULL,'graduation_project'),
('SET 392','SA-G1+G2','lecture',0,'14:30','16:30','A','207','lecture'),
('SET 412','DMC-G1','lecture',0,'10:30','11:30','D','104','lecture'),
('SET 473','DMC-G1','lecture',0,'11:30','13:30','D','110','lecture'),
('SET 497','DMC-G1','lecture',0,'13:30','17:30',NULL,NULL,'graduation_project'),
('SET 392','SA-G1','tutorial',1,'08:30','09:30','A','311','tutorial'),
('SET 411','SA-G1','lab',1,'10:30','12:30','A','311','tutorial_lab'),
('SET 412','SA-G1','lab',1,'14:30','16:30','A','311','tutorial_lab'),
('SET 412','SA-G2','lab',1,'08:30','10:30','A','313','tutorial_lab'),
('SET 392','SA-G2','tutorial',1,'10:30','11:30','A','313','tutorial'),
('SET 411','SA-G2','lab',1,'14:30','16:30','A','313','tutorial_lab'),
('SET 411','DMC-G1','lab',1,'08:30','10:30','A','206','tutorial_lab'),
('SET 412','DMC-G1','lab',1,'10:30','12:30','A','206','tutorial_lab'),
('SET 473','DMC-G1','tutorial',1,'14:30','15:30','A','206','tutorial'),
('SET 411','SA-G1+G2','lecture',3,'08:30','09:30','A','312','lecture'),
('SET 413','SA-G1','lab',3,'10:30','11:30','A','311','tutorial_lab'),
('SET 472','SA-G1','tutorial',3,'13:30','14:30','D','101','tutorial'),
('SET 472','SA-G2','tutorial',3,'10:30','11:30','D','101','tutorial'),
('SET 413','SA-G2','lab',3,'12:30','13:30','A','311','tutorial_lab'),
('SET 413','DMC-G1','lab',3,'08:30','09:30','A','311','tutorial_lab'),
('SET 411','DMC-G1','lecture',3,'09:30','11:30','D','110','lecture'),
('SET 472','DMC-G1','tutorial',3,'14:30','15:30','D','101','tutorial'),
('SET 472','SA-G1+G2','lecture',4,'08:30','09:30','A','202','lecture'),
('SET 413','SA-G1+G2','lecture',4,'09:30','11:30','A','208','lecture'),
('SET 413','DMC-G1','lecture',4,'08:30','09:30','D','103','lecture'),
('SET 472','DMC-G1','lecture',4,'13:30','14:30','D','208','lecture');

INSERT INTO public.sections (tenant_id,offering_id,code,kind,group_code)
SELECT DISTINCT
  o.tenant_id,
  o.id,
  replace(m.group_code,'+','-') || '-' ||
    regexp_replace(upper(c.code),'[^A-Z0-9]','','g') || '-' ||
    upper(m.section_kind::text),
  m.section_kind,
  m.group_code
FROM seed_fall_2026_meetings m
JOIN public.courses c
  ON regexp_replace(upper(c.code),'[^A-Z0-9]','','g') =
     regexp_replace(upper(m.course_code),'[^A-Z0-9]','','g')
 AND c.tenant_id = (SELECT id FROM public.tenants WHERE slug='ecu')
JOIN public.course_offerings o ON o.course_id = c.id
JOIN public.terms term ON term.id = o.term_id AND term.code = '2026-2027-FALL'
ON CONFLICT (offering_id,code)
DO UPDATE SET group_code = EXCLUDED.group_code, kind = EXCLUDED.kind;

INSERT INTO public.section_meetings
  (tenant_id,section_id,offering_id,room_id,day_of_week,starts_at,ends_at,meeting_type)
SELECT
  o.tenant_id,
  s.id,
  o.id,
  room.id,
  m.day_of_week,
  m.starts_at,
  m.ends_at,
  m.meeting_type
FROM seed_fall_2026_meetings m
JOIN public.courses c
  ON regexp_replace(upper(c.code),'[^A-Z0-9]','','g') =
     regexp_replace(upper(m.course_code),'[^A-Z0-9]','','g')
 AND c.tenant_id = (SELECT id FROM public.tenants WHERE slug='ecu')
JOIN public.course_offerings o ON o.course_id = c.id
JOIN public.terms term ON term.id = o.term_id AND term.code = '2026-2027-FALL'
JOIN public.sections s
  ON s.offering_id = o.id
 AND s.group_code = m.group_code
 AND s.kind = m.section_kind
 AND s.code = replace(m.group_code,'+','-') || '-' ||
      regexp_replace(upper(c.code),'[^A-Z0-9]','','g') || '-' ||
      upper(m.section_kind::text)
LEFT JOIN public.buildings b
  ON b.tenant_id = o.tenant_id AND b.code = m.building_code
LEFT JOIN public.rooms room
  ON room.tenant_id = o.tenant_id
 AND room.building_id = b.id
 AND room.code = m.room_code
WHERE NOT EXISTS (
  SELECT 1
  FROM public.section_meetings existing
  WHERE existing.section_id = s.id
    AND existing.offering_id = o.id
    AND existing.day_of_week = m.day_of_week
    AND existing.starts_at = m.starts_at
    AND existing.ends_at = m.ends_at
    AND existing.meeting_type = m.meeting_type
);

DROP TABLE seed_fall_2026_meetings;

-- Staff accounts are provisioned separately through Supabase Auth. If the approved
-- 15 SET staff accounts already exist, seed their verified position assignments
-- and Rania's separate Head of Department appointment. With no Auth accounts,
-- this block is a no-op; partial directories fail loudly instead of guessing.
DO $staff_appointment_seed$
DECLARE
  v_tenant_id uuid;
  v_staff_count integer;
  v_professor_count integer;
  v_ta_count integer;
  v_department_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM public.tenants WHERE slug = 'ecu';
  SELECT id INTO v_department_id
  FROM public.departments
  WHERE tenant_id = v_tenant_id AND code = 'SET';

  SELECT count(*),
         count(*) FILTER (WHERE profile.title = 'Professor'),
         count(*) FILTER (WHERE profile.title = 'Teaching Assistant')
  INTO v_staff_count, v_professor_count, v_ta_count
  FROM public.users account
  JOIN public.person_profiles profile ON profile.user_id = account.id
  WHERE account.tenant_id = v_tenant_id
    AND lower(account.email) IN (
      'rswief@ecu.edu.eg','mayar.ali@ecu.edu.eg','islam.mohammed@ecu.edu.eg',
      'doaa.amin@ecu.edu.eg','hmhussen@ecu.edu.eg','norhan.mamdoh@ecu.edu.eg',
      'mohamed.mohamed@ecu.edu.eg','maiada.alaaeldin@ecu.edu.eg','ramobark@ecu.edu.eg',
      'asmaa.elwihady@ecu.edu.eg','reem.waleed@ecu.edu.eg','fady.romany@ecu.edu.eg',
      'mohamed.taha@ecu.edu.eg','rahma.ali@ecu.edu.eg','amira.ali@ecu.edu.eg'
    );

  IF v_staff_count = 0 THEN
    RAISE NOTICE 'SET staff assignments skipped: Auth accounts have not been provisioned.';
    RETURN;
  END IF;

  IF v_staff_count <> 15 OR v_professor_count <> 3 OR v_ta_count <> 12
     OR v_department_id IS NULL THEN
    RAISE EXCEPTION
      'SET staff assignment seed requires all 15 approved accounts (3 professors, 12 teaching assistants) and the SET department; found %, %, %',
      v_staff_count, v_professor_count, v_ta_count;
  END IF;

  INSERT INTO public.user_roles
    (tenant_id,user_id,role_id,appointment_type,scope_type,scope_id,status,appointed_by,notes)
  SELECT
    account.tenant_id,
    account.id,
    role_definition.id,
    'position',
    'department',
    v_department_id,
    'active',
    NULL,
    'Initial SET staff directory appointment; seeded from the approved staff directory.'
  FROM public.users account
  JOIN public.person_profiles profile ON profile.user_id = account.id
  JOIN public.roles role_definition
    ON role_definition.tenant_id = account.tenant_id
   AND role_definition.key = CASE profile.title
     WHEN 'Professor' THEN 'professor'
     WHEN 'Teaching Assistant' THEN 'teaching_assistant'
   END
   AND role_definition.role_type IN ('position','both')
   AND role_definition.is_active
  WHERE account.tenant_id = v_tenant_id
    AND lower(account.email) IN (
      'rswief@ecu.edu.eg','mayar.ali@ecu.edu.eg','islam.mohammed@ecu.edu.eg',
      'doaa.amin@ecu.edu.eg','hmhussen@ecu.edu.eg','norhan.mamdoh@ecu.edu.eg',
      'mohamed.mohamed@ecu.edu.eg','maiada.alaaeldin@ecu.edu.eg','ramobark@ecu.edu.eg',
      'asmaa.elwihady@ecu.edu.eg','reem.waleed@ecu.edu.eg','fady.romany@ecu.edu.eg',
      'mohamed.taha@ecu.edu.eg','rahma.ali@ecu.edu.eg','amira.ali@ecu.edu.eg'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_roles existing
      WHERE existing.tenant_id = account.tenant_id
        AND existing.user_id = account.id
        AND existing.role_id = role_definition.id
        AND existing.appointment_type = 'position'
        AND existing.scope_type = 'department'
        AND existing.scope_id = v_department_id
        AND existing.status = 'active'
    );

  -- Rania's Head of SET Department appointment is separate from her Professor role.
  INSERT INTO public.user_roles
    (tenant_id,user_id,role_id,appointment_type,scope_type,scope_id,status,appointed_by,notes)
  SELECT
    account.tenant_id,
    account.id,
    role_definition.id,
    'leadership',
    'department',
    v_department_id,
    'active',
    NULL,
    'Head of SET Department leadership appointment; seeded from the approved staff directory.'
  FROM public.users account
  JOIN public.roles role_definition
    ON role_definition.tenant_id = account.tenant_id
   AND role_definition.key = 'department_head'
   AND role_definition.role_type IN ('position','both')
   AND role_definition.is_active
  WHERE account.tenant_id = v_tenant_id
    AND lower(account.email) = 'rswief@ecu.edu.eg'
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_roles existing
      WHERE existing.tenant_id = account.tenant_id
        AND existing.user_id = account.id
        AND existing.role_id = role_definition.id
        AND existing.appointment_type = 'leadership'
        AND existing.scope_type = 'department'
        AND existing.scope_id = v_department_id
        AND existing.status = 'active'
    );
END
$staff_appointment_seed$;

-- The permission catalogue is defined by migrations. Role-to-permission
-- mappings intentionally remain empty for the ECU tenant.
