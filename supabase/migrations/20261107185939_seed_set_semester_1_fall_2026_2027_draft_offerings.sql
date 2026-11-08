-- Create draft Fall 2026/2027 offerings for the SET programme's required curriculum Semester 1 courses.
-- This does not create sections, assign instructors, publish registration, or invent timetable details.
INSERT INTO public.course_offerings (tenant_id, course_id, term_id, status)
SELECT DISTINCT
  pcc.tenant_id,
  pcc.course_id,
  t.id,
  'draft'::public.offering_status
FROM public.program_curriculum_courses AS pcc
JOIN public.academic_semesters AS semester
  ON semester.id = pcc.academic_level_id
JOIN public.programs AS programme
  ON programme.id = pcc.program_id
JOIN public.terms AS t
  ON t.tenant_id = pcc.tenant_id
 AND t.code = '2026-2027-FALL'
WHERE pcc.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
  AND programme.id = '85dddcad-cc84-4b6a-b262-77f435c8f2f8'
  AND pcc.is_active = true
  AND pcc.requirement_type = 'required'
  AND semester.sequence_number = 1
ON CONFLICT (course_id, term_id) DO NOTHING;
