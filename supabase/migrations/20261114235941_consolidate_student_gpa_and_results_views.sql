-- Keep exactly four student-facing public views:
-- student_gpa, student_gpa_counted_attempts, student_results, student_timetable.
-- Official GPA snapshots are the source of historical term and cumulative GPA values.

create or replace view public.student_gpa with (security_invoker = true) as
with ranked as (
  select gs.*, row_number() over (
    partition by gs.tenant_id, gs.student_id, gs.term_id
    order by gs.computed_at desc, gs.id desc
  ) as snapshot_rank
  from public.gpa_snapshots gs
), latest_per_term as (
  select gs.tenant_id, gs.student_id,
    ay.id as academic_year_id, ay.code as academic_year_code, ay.name as academic_year_name,
    t.id as term_id, t.code as term_code, t.name as term_name,
    t.term_kind, t.sequence_number as term_sequence,
    gs.term_gpa, gs.cgpa as cumulative_gpa,
    gs.credits_attempted as term_credits_attempted,
    gs.credits_earned as cumulative_credits_earned,
    gs.term_quality_points, gs.cumulative_quality_points,
    gs.computed_at as gpa_computed_at,
    coalesce(ay.code, split_part(t.code, '-', 1) || '-' || split_part(t.code, '-', 2)) as academic_year_sort
  from ranked gs
  join public.terms t on t.id=gs.term_id and t.tenant_id=gs.tenant_id
  left join public.academic_years ay on ay.id=t.academic_year_id and ay.tenant_id=t.tenant_id
  where gs.snapshot_rank=1
)
select tenant_id, student_id, academic_year_id, academic_year_code, academic_year_name,
  term_id, term_code, term_name, term_kind, term_sequence,
  term_gpa, cumulative_gpa, term_credits_attempted, cumulative_credits_earned,
  term_quality_points, cumulative_quality_points, gpa_computed_at,
  sum(term_credits_attempted) over (
    partition by tenant_id,student_id
    order by academic_year_sort,term_sequence,gpa_computed_at
    rows between unbounded preceding and current row
  ) as cumulative_credits_attempted
from latest_per_term;

create or replace view public.student_results with (security_invoker = true) as
select
  e.id as result_id,e.tenant_id,e.student_id,e.id as enrollment_id,e.offering_id,
  coalesce(e.course_id,o.course_id) as course_id,c.code as course_code,c.title as course_title,
  coalesce(c.credit_hours,e.credit_hours_attempted)::numeric(8,2) as credit_hours,
  coalesce(e.term_id,o.term_id) as term_id,t.code as term_code,t.name as term_name,
  ay.code as academic_year_code,ay.name as academic_year_name,
  'course_final'::text as result_type,'course'::text as component_type,
  'Final course grade'::text as component_name,null::uuid as component_id,
  null::uuid as assessment_id,null::text as assessment_title,
  e.final_percentage::numeric as score,100::numeric as max_score,
  e.final_grade_letter as grade_letter,e.final_grade_points::numeric as grade_points,
  e.status::text as result_status,null::text as attendance_status,
  e.gpa_exclusion_reason,coalesce(e.status_changed_at,e.enrolled_at) as recorded_at
from public.enrollments e
left join public.course_offerings o on o.id=e.offering_id and o.tenant_id=e.tenant_id
join public.courses c on c.id=coalesce(e.course_id,o.course_id) and c.tenant_id=e.tenant_id
join public.terms t on t.id=coalesce(e.term_id,o.term_id) and t.tenant_id=e.tenant_id
left join public.academic_years ay on ay.id=t.academic_year_id and ay.tenant_id=t.tenant_id
union all
select
  g.id,g.tenant_id,g.student_id,g.enrollment_id,g.offering_id,o.course_id,
  c.code,c.title,c.credit_hours::numeric(8,2),o.term_id,t.code,t.name,ay.code,ay.name,
  'assessment_component'::text,'assessment'::text,coalesce(gc.name,a.title,'Assessment')::text,
  g.component_id,g.assessment_id,a.title,g.score::numeric,g.max_score::numeric,
  null::text,null::numeric,g.status::text,null::text,null::text,g.published_at
from public.grade_entries g
join public.course_offerings o on o.id=g.offering_id and o.tenant_id=g.tenant_id
join public.courses c on c.id=o.course_id and c.tenant_id=o.tenant_id
join public.terms t on t.id=o.term_id and t.tenant_id=o.tenant_id
left join public.academic_years ay on ay.id=t.academic_year_id and ay.tenant_id=t.tenant_id
left join public.grade_components gc on gc.id=g.component_id and gc.tenant_id=g.tenant_id
left join public.assessments a on a.id=g.assessment_id and a.tenant_id=g.tenant_id
where g.status='published'::public.grade_status
and not exists(select 1 from public.grade_entries newer
  where newer.supersedes_id=g.id and newer.status='published'::public.grade_status)
union all
select
  ar.id,ar.tenant_id,ar.student_id,e.id,o.id,o.course_id,c.code,c.title,
  c.credit_hours::numeric(8,2),o.term_id,t.code,t.name,ay.code,ay.name,
  'attendance_component'::text,'attendance'::text,'Attendance'::text,
  null::uuid,null::uuid,null::text,null::numeric,null::numeric,null::text,null::numeric,
  ar.status::text,ar.status::text,null::text,
  coalesce(ar.confirmed_at,ar.checked_in_at,ats.starts_at)
from public.attendance_records ar
join public.attendance_sessions ats on ats.id=ar.session_id and ats.tenant_id=ar.tenant_id
join public.sections s on s.id=ats.section_id and s.tenant_id=ats.tenant_id
join public.course_offerings o on o.id=s.offering_id and o.tenant_id=s.tenant_id
join public.enrollments e on e.student_id=ar.student_id and e.offering_id=o.id and e.tenant_id=ar.tenant_id
join public.courses c on c.id=o.course_id and c.tenant_id=o.tenant_id
join public.terms t on t.id=o.term_id and t.tenant_id=o.tenant_id
left join public.academic_years ay on ay.id=t.academic_year_id and ay.tenant_id=t.tenant_id;

revoke all on public.student_gpa,public.student_results from public,anon;
grant select on public.student_gpa,public.student_results to authenticated;

drop view if exists public.student_assessment_results;
drop view if exists public.published_grades;
drop view if exists public.student_academic_overview;
drop view if exists public.student_term_gpa;
drop view if exists public.student_cumulative_gpa;
drop view if exists public.student_course_results;
drop view if exists public.student_attendance_summary;
