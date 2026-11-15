-- Harden GPA eligibility and keep existing enrollment grades aligned when an
-- offering switches between grading bases or grade scales.

create or replace function private.recalculate_offering_enrollment_grades()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.grade_scale_id is distinct from old.grade_scale_id
     or new.grading_basis is distinct from old.grading_basis then
    update public.enrollments
       set final_percentage = final_percentage
     where tenant_id = new.tenant_id
       and offering_id = new.id
       and final_percentage is not null
       and new.grading_basis = 'letter_graded';
  end if;
  return new;
end;
$$;

drop trigger if exists course_offerings_recalculate_enrollment_grades
  on public.course_offerings;
create trigger course_offerings_recalculate_enrollment_grades
after update of grade_scale_id, grading_basis
on public.course_offerings
for each row
execute function private.recalculate_offering_enrollment_grades();

create or replace view public.student_gpa_counted_attempts
with (security_invoker = true)
as
with eligible_attempts as (
  select
    e.id as enrollment_id,
    e.tenant_id,
    e.student_id,
    o.course_id,
    c.code as course_code,
    c.title as course_title,
    c.credit_hours,
    e.offering_id,
    t.id as term_id,
    t.name as term_name,
    t.term_kind,
    t.academic_year_id,
    e.status as enrollment_status,
    e.final_percentage,
    e.final_grade_letter,
    e.final_grade_points,
    e.enrolled_at,
    row_number() over (
      partition by e.tenant_id, e.student_id, o.course_id
      order by e.final_grade_points desc,
               e.final_percentage desc nulls last,
               e.enrolled_at desc,
               e.id desc
    ) as attempt_rank
  from public.enrollments e
  join public.course_offerings o
    on o.id = e.offering_id and o.tenant_id = e.tenant_id
  join public.courses c
    on c.id = o.course_id and c.tenant_id = o.tenant_id
  join public.terms t
    on t.id = o.term_id and t.tenant_id = o.tenant_id
  where o.grading_basis = 'letter_graded'
    and e.status in ('completed', 'failed')
    and e.gpa_exclusion_reason is null
    and e.final_grade_points is not null
    and e.final_grade_letter not in ('AU', 'P')
)
select
  enrollment_id, tenant_id, student_id, course_id, course_code, course_title,
  credit_hours, offering_id, term_id, term_name, term_kind, academic_year_id,
  enrollment_status, final_percentage, final_grade_letter, final_grade_points,
  enrolled_at
from eligible_attempts
where attempt_rank = 1;

create or replace view public.student_term_gpa
with (security_invoker = true)
as
with ranked as (
  select
    e.tenant_id,
    e.student_id,
    o.course_id,
    t.id as term_id,
    t.name as term_name,
    t.term_kind,
    t.academic_year_id,
    c.credit_hours,
    e.final_grade_points,
    row_number() over (
      partition by e.tenant_id, e.student_id, o.course_id, t.id
      order by e.final_grade_points desc,
               e.final_percentage desc nulls last,
               e.enrolled_at desc,
               e.id desc
    ) as attempt_rank
  from public.enrollments e
  join public.course_offerings o
    on o.id = e.offering_id and o.tenant_id = e.tenant_id
  join public.courses c
    on c.id = o.course_id and c.tenant_id = o.tenant_id
  join public.terms t
    on t.id = o.term_id and t.tenant_id = o.tenant_id
  where o.grading_basis = 'letter_graded'
    and e.status in ('completed', 'failed')
    and e.gpa_exclusion_reason is null
    and e.final_grade_points is not null
    and e.final_grade_letter not in ('AU', 'P')
),
term_totals as (
  select
    tenant_id, student_id, term_id, term_name, term_kind, academic_year_id,
    sum(credit_hours) as gpa_credits,
    sum(credit_hours * final_grade_points) as quality_points,
    count(*) as courses_counted
  from ranked
  where attempt_rank = 1
  group by tenant_id, student_id, term_id, term_name, term_kind, academic_year_id
)
select
  tenant_id, student_id, term_id, term_name, term_kind, academic_year_id,
  courses_counted, gpa_credits, quality_points,
  round(quality_points / nullif(gpa_credits, 0), 3) as term_gpa
from term_totals;

create or replace view public.student_cumulative_gpa
with (security_invoker = true)
as
select
  tenant_id, student_id,
  count(*) as courses_counted,
  sum(credit_hours) as gpa_credits,
  sum(credit_hours * final_grade_points) as quality_points,
  round(sum(credit_hours * final_grade_points) / nullif(sum(credit_hours), 0), 3)
    as cumulative_gpa
from public.student_gpa_counted_attempts
group by tenant_id, student_id;
