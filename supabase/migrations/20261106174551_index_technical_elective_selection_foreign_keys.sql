-- Cover tenant-scoped foreign keys for technical elective selections.
CREATE INDEX student_technical_elective_student_fk_idx
  ON public.student_technical_elective_selections(student_id, tenant_id);
CREATE INDEX student_technical_elective_program_fk_idx
  ON public.student_technical_elective_selections(program_id, tenant_id);
CREATE INDEX student_technical_elective_specialization_fk_idx
  ON public.student_technical_elective_selections(specialization_id, program_id, tenant_id);
CREATE INDEX student_technical_elective_group_fk_idx
  ON public.student_technical_elective_selections(requirement_group_id, tenant_id);
CREATE INDEX student_technical_elective_course_fk_idx
  ON public.student_technical_elective_selections(course_id, tenant_id);
