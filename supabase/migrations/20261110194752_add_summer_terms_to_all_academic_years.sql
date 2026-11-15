-- Add missing summer terms to each existing ECU academic year.
-- Dates remain NULL because the source academic-year records do not define dates;
-- administrators can set the official summer calendar dates later.
begin;
set local lock_timeout = '5s';

insert into public.terms (
  tenant_id,
  academic_year_id,
  code,
  name,
  term_kind,
  status
)
select
  ay.tenant_id,
  ay.id,
  ay.code || '-SUMMER',
  'Summer ' || replace(ay.code, '-', '/'),
  'summer'::public.academic_term_kind,
  case
    when ay.status = 'completed'::public.academic_year_status
      then 'completed'::public.term_status
    else 'planned'::public.term_status
  end
from public.academic_years ay
where ay.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
  and not exists (
    select 1
    from public.terms t
    where t.tenant_id = ay.tenant_id
      and t.academic_year_id = ay.id
      and t.term_kind = 'summer'::public.academic_term_kind
  )
on conflict (tenant_id, code) do nothing;

commit;