create or replace view public.student_course_results
with (security_invoker = true)
as
select
  e.id as enrollment_id,
  e.tenant_id,
  e.student_id,
  e.offering_id,
  o.course_id,
  c.code as course_code,
  c.title as course_title,
  c.credit_hours,
  o.term_id,
  t.code as term_code,
  t.name as term_name,
  t.academic_year_id,
  e.status as enrollment_status,
  e.enrolled_at,
  e.status_changed_at,
  e.final_percentage,
  e.final_grade_letter,
  e.final_grade_points,
  e.gpa_exclusion_reason,
  e.credit_hours_attempted,
  e.quality_points
from public.enrollments e
join public.course_offerings o
  on o.id = e.offering_id and o.tenant_id = e.tenant_id
join public.courses c
  on c.id = o.course_id and c.tenant_id = o.tenant_id
join public.terms t
  on t.id = o.term_id and t.tenant_id = o.tenant_id;

create or replace view public.student_assessment_results
with (security_invoker = true)
as
select
  g.id as grade_entry_id,
  g.tenant_id,
  g.student_id,
  g.enrollment_id,
  g.offering_id,
  o.course_id,
  c.code as course_code,
  c.title as course_title,
  o.term_id,
  t.code as term_code,
  t.name as term_name,
  g.component_id,
  gc.name as component_name,
  g.assessment_id,
  a.title as assessment_title,
  a.kind as assessment_kind,
  g.score,
  g.max_score,
  g.feedback,
  g.published_at
from public.published_grades g
join public.course_offerings o
  on o.id = g.offering_id and o.tenant_id = g.tenant_id
join public.courses c
  on c.id = o.course_id and c.tenant_id = o.tenant_id
join public.terms t
  on t.id = o.term_id and t.tenant_id = o.tenant_id
left join public.grade_components gc
  on gc.id = g.component_id and gc.tenant_id = g.tenant_id
left join public.assessments a
  on a.id = g.assessment_id and a.tenant_id = g.tenant_id;

create or replace view public.student_attendance_summary
with (security_invoker = true)
as
with student_sections as (
  select distinct
    e.tenant_id,
    e.student_id,
    e.id as enrollment_id,
    o.id as offering_id,
    o.course_id,
    c.code as course_code,
    c.title as course_title,
    o.term_id,
    t.code as term_code,
    t.name as term_name,
    s.id as section_id,
    s.code as section_code
  from public.enrollments e
  join public.course_offerings o
    on o.id = e.offering_id and o.tenant_id = e.tenant_id
  join public.courses c
    on c.id = o.course_id and c.tenant_id = o.tenant_id
  join public.terms t
    on t.id = o.term_id and t.tenant_id = o.tenant_id
  join public.student_meetings sm
    on sm.enrollment_id = e.id and sm.tenant_id = e.tenant_id
  join public.section_meetings m
    on m.id = sm.meeting_id and m.tenant_id = sm.tenant_id
  join public.sections s
    on s.id = m.section_id and s.tenant_id = m.tenant_id
   and s.offering_id = o.id
),
session_attendance as (
  select
    ss.tenant_id,
    ss.student_id,
    ss.enrollment_id,
    ss.offering_id,
    ss.course_id,
    ss.course_code,
    ss.course_title,
    ss.term_id,
    ss.term_code,
    ss.term_name,
    ss.section_id,
    ss.section_code,
    ats.id as session_id,
    ats.starts_at,
    ar.id as attendance_record_id,
    ar.status as attendance_status,
    ar.confirmation
  from student_sections ss
  join public.attendance_sessions ats
    on ats.section_id = ss.section_id and ats.tenant_id = ss.tenant_id
  left join public.attendance_records ar
    on ar.session_id = ats.id
   and ar.tenant_id = ats.tenant_id
   and ar.student_id = ss.student_id
)
select
  tenant_id,
  student_id,
  enrollment_id,
  offering_id,
  course_id,
  course_code,
  course_title,
  term_id,
  term_code,
  term_name,
  section_id,
  section_code,
  count(distinct session_id) as total_sessions,
  count(distinct session_id) filter (where attendance_record_id is null) as unrecorded_sessions,
  count(distinct session_id) filter (where attendance_status = 'present'::public.attendance_status) as present_count,
  count(distinct session_id) filter (where attendance_status = 'late'::public.attendance_status) as late_count,
  count(distinct session_id) filter (where attendance_status = 'absent'::public.attendance_status) as absent_count,
  count(distinct session_id) filter (where attendance_status = 'excused'::public.attendance_status) as excused_count,
  round(
    100.0 * (
      count(distinct session_id) filter (where attendance_status in ('present'::public.attendance_status, 'late'::public.attendance_status))
    ) / nullif(
      count(distinct session_id) filter (where attendance_status in ('present'::public.attendance_status, 'late'::public.attendance_status, 'absent'::public.attendance_status)),
      0
    ),
    2
  ) as attendance_percentage,
  max(starts_at) as last_session_at
from session_attendance
group by
  tenant_id, student_id, enrollment_id, offering_id, course_id, course_code,
  course_title, term_id, term_code, term_name, section_id, section_code;

create or replace view public.student_timetable
with (security_invoker = true)
as
select
  sm.id as student_meeting_id,
  sm.tenant_id,
  e.student_id,
  e.id as enrollment_id,
  o.id as offering_id,
  o.course_id,
  c.code as course_code,
  c.title as course_title,
  o.term_id,
  t.code as term_code,
  t.name as term_name,
  s.id as section_id,
  s.code as section_code,
  m.id as meeting_id,
  m.day_of_week,
  m.starts_at,
  m.ends_at,
  m.meeting_type,
  r.id as room_id,
  r.code as room_code,
  r.name as room_name,
  b.code as building_code,
  b.name as building_name,
  sm.assigned_at
from public.student_meetings sm
join public.enrollments e
  on e.id = sm.enrollment_id and e.tenant_id = sm.tenant_id
join public.section_meetings m
  on m.id = sm.meeting_id and m.tenant_id = sm.tenant_id
join public.sections s
  on s.id = m.section_id and s.tenant_id = m.tenant_id
join public.course_offerings o
  on o.id = e.offering_id and o.id = s.offering_id and o.tenant_id = e.tenant_id
join public.courses c
  on c.id = o.course_id and c.tenant_id = o.tenant_id
join public.terms t
  on t.id = o.term_id and t.tenant_id = o.tenant_id
left join public.rooms r
  on r.id = m.room_id and r.tenant_id = m.tenant_id
left join public.buildings b
  on b.id = r.building_id and b.tenant_id = r.tenant_id;

create or replace view public.student_academic_overview
with (security_invoker = true)
as
with student_ids as (
  select tenant_id, student_id from public.student_cumulative_gpa
  union
  select tenant_id, student_id from public.student_term_gpa
),
ranked_terms as (
  select
    st.tenant_id,
    st.student_id,
    st.term_id,
    st.term_name,
    st.term_kind,
    st.academic_year_id,
    st.term_gpa,
    st.courses_counted as term_courses_counted,
    st.gpa_credits as term_gpa_credits,
    st.quality_points as term_quality_points,
    row_number() over (
      partition by st.tenant_id, st.student_id
      order by tr.starts_on desc nulls last, st.term_id desc
    ) as term_rank
  from public.student_term_gpa st
  left join public.terms tr
    on tr.id = st.term_id and tr.tenant_id = st.tenant_id
)
select
  ids.tenant_id,
  ids.student_id,
  cg.cumulative_gpa,
  cg.courses_counted as cumulative_courses_counted,
  cg.gpa_credits as cumulative_gpa_credits,
  cg.quality_points as cumulative_quality_points,
  rt.term_id as latest_term_id,
  rt.term_name as latest_term_name,
  rt.term_kind as latest_term_kind,
  rt.academic_year_id as latest_academic_year_id,
  rt.term_gpa as latest_term_gpa,
  rt.term_courses_counted,
  rt.term_gpa_credits,
  rt.term_quality_points
from student_ids ids
left join public.student_cumulative_gpa cg
  on cg.tenant_id = ids.tenant_id and cg.student_id = ids.student_id
left join ranked_terms rt
  on rt.tenant_id = ids.tenant_id and rt.student_id = ids.student_id and rt.term_rank = 1;

revoke all on public.student_course_results,
  public.student_assessment_results,
  public.student_attendance_summary,
  public.student_timetable,
  public.student_academic_overview
from public, anon;

grant select on public.student_course_results,
  public.student_assessment_results,
  public.student_attendance_summary,
  public.student_timetable,
  public.student_academic_overview
to authenticated;
