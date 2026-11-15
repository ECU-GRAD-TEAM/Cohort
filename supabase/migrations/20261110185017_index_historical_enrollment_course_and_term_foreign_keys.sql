CREATE INDEX enrollments_course_id_tenant_id_idx
  ON public.enrollments(course_id,tenant_id)
  WHERE course_id IS NOT NULL;

CREATE INDEX enrollments_term_id_tenant_id_idx
  ON public.enrollments(term_id,tenant_id)
  WHERE term_id IS NOT NULL;
