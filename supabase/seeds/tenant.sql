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
