-- ECU GPA calculation engine: grade mapping, attempt eligibility, highest-attempt GPA.
-- This migration keeps every enrollment attempt; it only derives grade fields and read models.

alter table public.course_offerings
  add column if not exists grading_basis text not null default 'letter_graded';

alter table public.course_offerings
  drop constraint if exists course_offerings_grading_basis_check;

alter table public.course_offerings
  add constraint course_offerings_grading_basis_check
  check (grading_basis in ('letter_graded', 'pass_fail', 'audit'));

comment on column public.course_offerings.grading_basis is
  'How this offering is graded. pass_fail and audit offerings are excluded from GPA under ECU Article 39.';

alter table public.enrollments
  add column if not exists gpa_exclusion_reason text;

alter table public.enrollments
  drop constraint if exists enrollments_gpa_exclusion_reason_check;

alter table public.enrollments
  add constraint enrollments_gpa_exclusion_reason_check
  check (gpa_exclusion_reason is null or gpa_exclusion_reason = 'excused_incomplete');

comment on column public.enrollments.gpa_exclusion_reason is
  'Explicit GPA exclusion approved by the faculty. Currently supports excused_incomplete under ECU Article 39.';

-- Configure ECU's official Article 38 grade scale.
do $$
declare
  v_tenant_id uuid := '97325228-75cb-4a36-b103-9da28968c660';
  v_scale_id uuid;
begin
  insert into public.grade_scales (tenant_id, name, max_grade_points, is_default)
  values (v_tenant_id, 'ECU Article 38', 4.0, true)
  on conflict (tenant_id, name)
  do update set max_grade_points = excluded.max_grade_points, is_default = true
  returning id into v_scale_id;

  update public.grade_scales
     set is_default = false
   where tenant_id = v_tenant_id
     and id <> v_scale_id
     and is_default;

  insert into public.grade_scale_bands
    (tenant_id, scale_id, letter, min_percentage, grade_points, is_passing)
  values
    (v_tenant_id, v_scale_id, 'A+', 97, 4.0, true),
    (v_tenant_id, v_scale_id, 'A',  93, 4.0, true),
    (v_tenant_id, v_scale_id, 'A-', 89, 3.7, true),
    (v_tenant_id, v_scale_id, 'B+', 84, 3.3, true),
    (v_tenant_id, v_scale_id, 'B',  80, 3.0, true),
    (v_tenant_id, v_scale_id, 'B-', 76, 2.7, true),
    (v_tenant_id, v_scale_id, 'C+', 73, 2.3, true),
    (v_tenant_id, v_scale_id, 'C',  70, 2.0, true),
    (v_tenant_id, v_scale_id, 'C-', 67, 1.7, true),
    (v_tenant_id, v_scale_id, 'D+', 64, 1.3, true),
    (v_tenant_id, v_scale_id, 'D',  60, 1.0, true),
    (v_tenant_id, v_scale_id, 'F',   0, 0.0, false)
  on conflict (scale_id, letter)
  do update set
    min_percentage = excluded.min_percentage,
    grade_points = excluded.grade_points,
    is_passing = excluded.is_passing;
end;
$$;

create or replace function private.apply_enrollment_grade_scale()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_grading_basis text;
  v_scale_id uuid;
  v_letter text;
  v_points numeric;
begin
  if new.final_percentage is null then
    return new;
  end if;

  if new.final_percentage < 0 or new.final_percentage > 100 then
    raise exception 'Final percentage must be between 0 and 100'
      using errcode = 'check_violation';
  end if;

  select o.tenant_id, o.grading_basis,
         coalesce(o.grade_scale_id, gs.id)
    into v_tenant_id, v_grading_basis, v_scale_id
  from public.course_offerings o
  left join public.grade_scales gs
    on gs.tenant_id = o.tenant_id
   and gs.is_default
  where o.id = new.offering_id
    and o.tenant_id = new.tenant_id;

  if not found then
    raise exception 'Course offering not found for enrollment'
      using errcode = 'foreign_key_violation';
  end if;

  -- Pass/fail and audit outcomes are entered as P/F/AU and are not
  -- converted using the Article 38 letter-grade percentage scale.
  if v_grading_basis <> 'letter_graded' then
    return new;
  end if;

  if v_scale_id is null then
    return new;
  end if;

  select b.letter, b.grade_points
    into v_letter, v_points
  from public.grade_scale_bands b
  where b.tenant_id = v_tenant_id
    and b.scale_id = v_scale_id
    and b.min_percentage <= new.final_percentage
  order by b.min_percentage desc
  limit 1;

  if not found then
    raise exception 'No grade-scale band covers percentage % for scale %',
      new.final_percentage, v_scale_id
      using errcode = 'check_violation';
  end if;

  new.final_grade_letter := v_letter;
  new.final_grade_points := v_points;
  return new;
end;
$$;

drop trigger if exists enrollments_00_apply_grade_scale on public.enrollments;
create trigger enrollments_00_apply_grade_scale
before insert or update of offering_id, final_percentage
on public.enrollments
for each row
execute function private.apply_enrollment_grade_scale();

-- If an academic manager changes an offering's grade scale, recalculate
-- percentages for existing attempts; the repeat-cap trigger still runs.
create or replace function private.recalculate_offering_enrollment_grades()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.grade_scale_id is distinct from old.grade_scale_id then
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
after update of grade_scale_id
on public.course_offerings
for each row
execute function private.recalculate_offering_enrollment_grades();

create index if not exists enrollments_gpa_student_status_idx
  on public.enrollments (tenant_id, student_id, status)
  include (offering_id, final_grade_points, final_percentage)
  where final_grade_points is not null;

-- Highest eligible attempt across the student's entire history for each course.
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
)
select
  enrollment_id,
  tenant_id,
  student_id,
  course_id,
  course_code,
  course_title,
  credit_hours,
  offering_id,
  term_id,
  term_name,
  term_kind,
  academic_year_id,
  enrollment_status,
  final_percentage,
  final_grade_letter,
  final_grade_points,
  enrolled_at
from eligible_attempts
where attempt_rank = 1;

comment on view public.student_gpa_counted_attempts is
  'One GPA-counted attempt per student/course: the highest eligible grade-point attempt. All source attempts remain in enrollments.';

-- Term GPA uses the highest eligible attempt for each course within that term.
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
)
,
term_totals as (
  select
    tenant_id,
    student_id,
    term_id,
    term_name,
    term_kind,
    academic_year_id,
    sum(credit_hours) as gpa_credits,
    sum(credit_hours * final_grade_points) as quality_points,
    count(*) as courses_counted
  from ranked
  where attempt_rank = 1
  group by tenant_id, student_id, term_id, term_name, term_kind, academic_year_id
)
select
  tenant_id,
  student_id,
  term_id,
  term_name,
  term_kind,
  academic_year_id,
  courses_counted,
  gpa_credits,
  quality_points,
  round(quality_points / nullif(gpa_credits, 0), 3) as term_gpa
from term_totals;

comment on view public.student_term_gpa is
  'Term GPA weighted by course credit hours, using each course highest eligible attempt within that teaching term.';

create or replace view public.student_cumulative_gpa
with (security_invoker = true)
as
select
  tenant_id,
  student_id,
  count(*) as courses_counted,
  sum(credit_hours) as gpa_credits,
  sum(credit_hours * final_grade_points) as quality_points,
  round(
    sum(credit_hours * final_grade_points) / nullif(sum(credit_hours), 0),
    3
  ) as cumulative_gpa
from public.student_gpa_counted_attempts
group by tenant_id, student_id;

comment on view public.student_cumulative_gpa is
  'CGPA weighted by credit hours, counting only the highest eligible attempt per student/course across all terms.';

grant select on public.student_gpa_counted_attempts to authenticated;
grant select on public.student_term_gpa to authenticated;
grant select on public.student_cumulative_gpa to authenticated;
