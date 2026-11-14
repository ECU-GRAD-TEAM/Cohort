-- Fix student academic overview:
-- 1. Select the chronologically latest term using the academic-year code and term sequence,
--    not nullable terms.starts_on values.
-- 2. Distinguish cumulative credits earned from latest-term credits attempted.
-- 3. Keep official GPA values from the append-only GPA snapshots.

drop view public.student_academic_overview;

create view public.student_academic_overview
with (security_invoker = true)
as
with ranked_snapshots as (
  select
    gs.tenant_id,
    gs.student_id,
    gs.term_id,
    t.name as term_name,
    t.code as term_code,
    t.term_kind,
    t.academic_year_id,
    t.sequence_number,
    gs.term_gpa,
    gs.cgpa as cumulative_gpa,
    gs.credits_attempted as latest_term_credits_attempted,
    gs.credits_earned as cumulative_credits_earned,
    gs.term_quality_points,
    gs.cumulative_quality_points,
    gs.computed_at,
    row_number() over (
      partition by gs.tenant_id, gs.student_id
      order by
        split_part(t.code, '-', 1)::integer desc,
        t.sequence_number desc nulls last,
        gs.computed_at desc,
        gs.id desc
    ) as snapshot_rank
  from public.gpa_snapshots gs
  join public.terms t
    on t.id = gs.term_id
   and t.tenant_id = gs.tenant_id
)
select
  tenant_id,
  student_id,
  cumulative_gpa,
  null::bigint as cumulative_courses_counted,
  cumulative_credits_earned::numeric as cumulative_gpa_credits,
  cumulative_quality_points,
  term_id as latest_term_id,
  term_name as latest_term_name,
  term_code as latest_term_code,
  term_kind as latest_term_kind,
  academic_year_id as latest_academic_year_id,
  term_gpa as latest_term_gpa,
  null::bigint as term_courses_counted,
  latest_term_credits_attempted::numeric as term_gpa_credits,
  term_quality_points,
  cumulative_credits_earned,
  computed_at as gpa_computed_at
from ranked_snapshots
where snapshot_rank = 1;

revoke all on public.student_academic_overview from public, anon;
grant select on public.student_academic_overview to authenticated;
