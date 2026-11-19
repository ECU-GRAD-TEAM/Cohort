create index student_financial_transactions_student_fk_idx
  on public.student_financial_transactions (student_id, tenant_id);
create index student_financial_transactions_term_fk_idx
  on public.student_financial_transactions (term_id, tenant_id);

revoke all on public.student_financial_summary from anon, authenticated, public;
grant select on public.student_financial_summary to authenticated;
