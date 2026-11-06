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
JOIN public.academic_levels AS al
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
JOIN public.academic_levels AS al
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
JOIN public.academic_levels AS academic_level
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
