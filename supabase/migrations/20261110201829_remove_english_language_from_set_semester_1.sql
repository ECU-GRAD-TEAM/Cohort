-- Remove HUM 011 (English Language) from Semester 1 of the SET program.
-- The course catalogue record is retained; only the curriculum mapping is removed.
DELETE FROM public.program_curriculum_courses
WHERE id = '5e71339b-70f1-4ba9-821d-b98b6775ea4b'
  AND tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
  AND program_id = '85dddcad-cc84-4b6a-b262-77f435c8f2f8'
  AND course_id = '2b29cc2e-2cc3-4b58-b1a2-11ee0591a71d'
  AND academic_level_id = 'dc7c0850-9320-4a93-a521-5119e22e261c';
