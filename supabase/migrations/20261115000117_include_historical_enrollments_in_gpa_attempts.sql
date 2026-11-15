-- Include imported transcript enrollments as well as live course-offering enrollments
-- when exposing each student's best eligible GPA attempt per course.

drop view public.student_gpa_counted_attempts;
create view public.student_gpa_counted_attempts
with (security_invoker = true)
as
with all_attempts as (
  select e.id as enrollment_id,e.tenant_id,e.student_id,o.course_id,
    c.code as course_code,c.title as course_title,c.credit_hours,
    e.offering_id,t.id as term_id,t.name as term_name,t.term_kind,t.academic_year_id,
    e.status as enrollment_status,e.final_percentage,e.final_grade_letter,
    e.final_grade_points,e.enrolled_at
  from public.enrollments e
  join public.course_offerings o on o.id=e.offering_id and o.tenant_id=e.tenant_id
  join public.courses c on c.id=o.course_id and c.tenant_id=o.tenant_id
  join public.terms t on t.id=o.term_id and t.tenant_id=o.tenant_id
  where e.offering_id is not null and o.grading_basis='letter_graded'
    and e.status in ('completed','failed') and e.gpa_exclusion_reason is null
    and e.final_grade_points is not null and e.final_grade_letter not in ('AU','P')
  union all
  select e.id,e.tenant_id,e.student_id,e.course_id,c.code,c.title,e.credit_hours_attempted,
    e.offering_id,t.id,t.name,t.term_kind,t.academic_year_id,e.status,e.final_percentage,
    e.final_grade_letter,e.final_grade_points,e.enrolled_at
  from public.enrollments e
  join public.courses c on c.id=e.course_id and c.tenant_id=e.tenant_id
  join public.terms t on t.id=e.term_id and t.tenant_id=e.tenant_id
  where e.offering_id is null and e.course_id is not null and e.term_id is not null
    and e.status in ('completed','failed') and e.gpa_exclusion_reason is null
    and e.final_grade_points is not null and e.final_grade_letter not in ('AU','P')
),
ranked_attempts as (
  select a.*,
    row_number() over (
      partition by a.tenant_id,a.student_id,a.course_id
      order by a.final_grade_points desc,a.final_percentage desc nulls last,
               a.enrolled_at desc,a.enrollment_id desc
    ) as attempt_rank
  from all_attempts a
)
select enrollment_id,tenant_id,student_id,course_id,course_code,course_title,
  credit_hours,offering_id,term_id,term_name,term_kind,academic_year_id,
  enrollment_status,final_percentage,final_grade_letter,final_grade_points,enrolled_at
from ranked_attempts where attempt_rank=1;

grant select on public.student_gpa_counted_attempts to authenticated;
