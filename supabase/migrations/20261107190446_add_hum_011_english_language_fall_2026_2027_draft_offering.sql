-- Add HUM 011 (English Language) as a draft offering in Fall 2026/2027.
-- This reflects the confirmed Semester 1 placement; it does not alter the course catalogue
-- or invent credit hours, sections, staffing, or timetable details.
INSERT INTO public.course_offerings (tenant_id, course_id, term_id, status)
SELECT
  c.tenant_id,
  c.id,
  t.id,
  'draft'::public.offering_status
FROM public.courses AS c
JOIN public.terms AS t
  ON t.tenant_id = c.tenant_id
 AND t.code = '2026-2027-FALL'
WHERE c.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
  AND c.code = 'HUM 011'
  AND c.title = 'English Language'
ON CONFLICT (course_id, term_id) DO NOTHING;
