create index student_department_assignments_student_fk_idx
  on public.student_department_assignments (student_id, tenant_id);
create index student_programme_selections_student_fk_idx
  on public.student_programme_selections (student_id, tenant_id);
