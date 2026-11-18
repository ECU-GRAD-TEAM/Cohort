REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.student_exam_schedule FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_exam_schedule TO authenticated;
