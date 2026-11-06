-- Programme selection timing is unspecified in ECU's supplied curriculum.
ALTER TABLE public.faculty_academic_pathways
  DROP CONSTRAINT IF EXISTS faculty_academic_pathways_programme_semester_check;

ALTER TABLE public.faculty_academic_pathways
  ADD CONSTRAINT faculty_academic_pathways_programme_semester_check
  CHECK (
    programme_selection_semester IS NULL
    OR programme_selection_semester BETWEEN department_effective_semester AND 10
  );
