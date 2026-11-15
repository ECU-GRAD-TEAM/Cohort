-- Give each semester its official PDF academic-level label.
UPDATE public.academic_levels AS level
SET name = CASE
      WHEN level.sequence_number BETWEEN 1 AND 2 THEN 'General Level (Freshman)'
      WHEN level.sequence_number BETWEEN 3 AND 4 THEN 'First Level (Sophomore)'
      WHEN level.sequence_number BETWEEN 5 AND 6 THEN 'Second Level (Junior)'
      WHEN level.sequence_number BETWEEN 7 AND 8 THEN 'Third Level (Senior-1)'
      WHEN level.sequence_number BETWEEN 9 AND 10 THEN 'Fourth Level (Senior-2)'
    END || ' - Semester ' || level.sequence_number
FROM public.tenants AS tenant,
     public.faculties AS faculty
WHERE level.tenant_id = tenant.id
  AND tenant.slug = 'ecu'
  AND level.faculty_id = faculty.id
  AND faculty.tenant_id = tenant.id
  AND faculty.code = 'ENG'
  AND level.sequence_number BETWEEN 1 AND 10;
