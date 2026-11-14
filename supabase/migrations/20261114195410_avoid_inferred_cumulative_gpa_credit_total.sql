drop view public.student_academic_overview;
create view public.student_academic_overview
with (security_invoker = true)
as
with ranked_snapshots as (
  select
    gs.tenant_id,
    gs.student_id,
    gs.term_id,
    tr.name as term_name,
    tr.term_kind,
    tr.academic_year_id,
    gs.term_gpa,
    gs.cgpa as cumulative_gpa,
    gs.credits_attempted,
    gs.credits_earned,
    gs.term_quality_points,
    gs.cumulative_quality_points,
    gs.computed_at,
    row_number() over (
      partition by gs.tenant_id, gs.student_id
      order by tr.starts_on desc nulls last, gs.computed_at desc, gs.id desc
    ) as snapshot_rank
  from public.gpa_snapshots gs
  left join public.terms tr
    on tr.id = gs.term_id and tr.tenant_id = gs.tenant_id
)
select
  tenant_id,
  student_id,
  cumulative_gpa,
  null::bigint as cumulative_courses_counted,
  null::numeric as cumulative_gpa_credits,
  cumulative_quality_points,
  term_id as latest_term_id,
  term_name as latest_term_name,
  term_kind as latest_term_kind,
  academic_year_id as latest_academic_year_id,
  term_gpa as latest_term_gpa,
  null::bigint as term_courses_counted,
  credits_attempted as term_gpa_credits,
  term_quality_points,
  credits_earned as latest_term_credits_earned,
  computed_at as gpa_computed_at
from ranked_snapshots
where snapshot_rank = 1;

grant select on public.student_academic_overview to authenticated;
