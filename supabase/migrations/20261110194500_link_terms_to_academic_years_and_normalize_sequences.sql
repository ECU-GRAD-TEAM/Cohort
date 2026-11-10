-- Attach every ECU term to its academic year and normalize term order within each year.
begin;
set local lock_timeout = '5s';

with year_codes as (
  select distinct
    substring(t.code from '^(\d{4}-\d{4})-') as year_code,
    t.tenant_id
  from public.terms t
  where t.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
    and t.code ~ '^\d{4}-\d{4}-'
)
insert into public.academic_years (
  tenant_id, calendar_id, code, name, status
)
select
  yc.tenant_id,
  ac.id,
  yc.year_code,
  'Academic Year ' || replace(yc.year_code, '-', '/'),
  case
    when split_part(yc.year_code, '-', 1)::integer < 2026 then 'completed'::public.academic_year_status
    else 'planned'::public.academic_year_status
  end
from year_codes yc
join public.academic_calendars ac
  on ac.tenant_id = yc.tenant_id
 and ac.code = 'ECU_MAIN'
on conflict (calendar_id, code) do update
set name = excluded.name;

update public.terms t
set academic_year_id = ay.id,
    sequence_number = case t.term_kind::text
      when 'fall' then 1
      when 'spring' then 2
      when 'summer' then 3
      else t.sequence_number
    end
from public.academic_years ay
where ay.tenant_id = t.tenant_id
  and ay.calendar_id = (
    select ac.id
    from public.academic_calendars ac
    where ac.tenant_id = t.tenant_id
      and ac.code = 'ECU_MAIN'
  )
  and ay.code = substring(t.code from '^(\d{4}-\d{4})-')
  and t.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
  and t.code ~ '^\d{4}-\d{4}-';

create unique index if not exists terms_academic_year_sequence_unique
  on public.terms (academic_year_id, sequence_number)
  where academic_year_id is not null and sequence_number is not null;

commit;