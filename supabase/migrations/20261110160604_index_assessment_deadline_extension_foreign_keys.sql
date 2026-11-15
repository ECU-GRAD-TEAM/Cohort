create index assessment_deadline_extensions_assessment_tenant_idx
  on public.assessment_deadline_extensions (assessment_id, tenant_id);

create index assessment_deadline_extensions_student_tenant_idx
  on public.assessment_deadline_extensions (student_id, tenant_id);
