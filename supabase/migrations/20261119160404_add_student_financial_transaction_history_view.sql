create or replace view public.student_financial_transaction_history
with (security_invoker = true)
as
select
  t.tenant_id,
  t.student_id,
  t.id as transaction_id,
  t.transaction_type,
  t.status,
  t.amount,
  t.currency_code,
  t.description,
  t.reference_number,
  t.occurred_at,
  t.posted_at,
  term.id as term_id,
  term.code as term_code,
  term.name as term_name
from public.student_financial_transactions as t
left join public.terms as term
  on term.id = t.term_id
 and term.tenant_id = t.tenant_id
where t.student_id = (select auth.uid());

revoke all on public.student_financial_transaction_history from anon, authenticated, public;
grant select on public.student_financial_transaction_history to authenticated;
