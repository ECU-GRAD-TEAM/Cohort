create table public.student_financial_transactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  term_id uuid,
  transaction_type text not null check (transaction_type in ('charge','payment','scholarship','discount','refund')),
  status text not null default 'posted' check (status in ('pending','posted','void')),
  amount numeric(14,2) not null check (amount > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  description text not null check (length(btrim(description)) > 0),
  reference_number text,
  occurred_at timestamptz not null default now(),
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint student_financial_transactions_student_fk
    foreign key (student_id, tenant_id) references public.users(id, tenant_id) on delete restrict,
  constraint student_financial_transactions_term_fk
    foreign key (term_id, tenant_id) references public.terms(id, tenant_id) on delete restrict,
  constraint student_financial_transactions_posted_at_check
    check ((status = 'posted' and posted_at is not null) or status <> 'posted')
);

create index student_financial_transactions_student_time_idx
  on public.student_financial_transactions (tenant_id, student_id, occurred_at desc);
create index student_financial_transactions_student_status_idx
  on public.student_financial_transactions (tenant_id, student_id, status, currency_code);

alter table public.student_financial_transactions enable row level security;

create policy "students read their own financial transactions"
  on public.student_financial_transactions
  for select
  to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and student_id = (select auth.uid())
  );

revoke all on public.student_financial_transactions from anon, public;
grant select on public.student_financial_transactions to authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.student_financial_transactions from authenticated;

create or replace view public.student_financial_summary
with (security_invoker = true)
as
select
  t.tenant_id,
  t.student_id,
  t.currency_code,
  count(*) filter (where t.status = 'posted')::integer as posted_transaction_count,
  count(*) filter (where t.status = 'pending')::integer as pending_transaction_count,
  coalesce(sum(t.amount) filter (where t.status = 'posted' and t.transaction_type = 'charge'), 0)::numeric(14,2) as posted_charge_total,
  coalesce(sum(t.amount) filter (where t.status = 'posted' and t.transaction_type = 'payment'), 0)::numeric(14,2) as posted_payment_total,
  coalesce(sum(t.amount) filter (where t.status = 'posted' and t.transaction_type = 'scholarship'), 0)::numeric(14,2) as posted_scholarship_total,
  coalesce(sum(t.amount) filter (where t.status = 'posted' and t.transaction_type = 'discount'), 0)::numeric(14,2) as posted_discount_total,
  coalesce(sum(t.amount) filter (where t.status = 'posted' and t.transaction_type = 'refund'), 0)::numeric(14,2) as posted_refund_total,
  (
    coalesce(sum(t.amount) filter (where t.status = 'posted' and t.transaction_type in ('charge','refund')), 0)
    - coalesce(sum(t.amount) filter (where t.status = 'posted' and t.transaction_type in ('payment','scholarship','discount')), 0)
  )::numeric(14,2) as outstanding_balance,
  coalesce(sum(t.amount) filter (where t.status = 'pending'), 0)::numeric(14,2) as pending_transaction_amount,
  max(t.occurred_at) as latest_transaction_at
from public.student_financial_transactions as t
where t.student_id = (select auth.uid())
group by t.tenant_id, t.student_id, t.currency_code;

grant select on public.student_financial_summary to authenticated;
revoke all on public.student_financial_summary from anon, public;
