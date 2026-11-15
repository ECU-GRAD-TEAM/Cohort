create or replace view public.student_profile
with (security_invoker = true)
as
select
    u.tenant_id,
    u.id as student_id,
    coalesce(nullif(btrim(up.display_name), ''), nullif(btrim(concat_ws(' ', up.first_name, up.last_name)), '')) as full_name,
    u.email,
    prog.id as program_id,
    prog.name as program_name,
    confirmed_spec.specialization_id,
    confirmed_spec.specialization_name,
    dept.id as department_id,
    dept.name as department_name,
    fac.id as faculty_id,
    fac.name as faculty_name,
    coalesce(nullif(btrim(year_level.display_name), ''), nullif(btrim(year_level.name), '')) as academic_level,
    u.status::text as enrollment_status,
    u.institutional_id
from public.users u
left join public.user_profiles up on up.user_id = u.id and up.tenant_id = u.tenant_id
left join public.departments dept on dept.id = up.department_id and dept.tenant_id = up.tenant_id
left join public.faculties fac on fac.id = up.faculty_id and fac.tenant_id = up.tenant_id
left join public.student_academic_progressions progression on progression.student_id = u.id and progression.tenant_id = u.tenant_id
left join public.academic_year_levels year_level on year_level.id = progression.current_year_level_id and year_level.tenant_id = progression.tenant_id
left join lateral (
    select p.id, p.name
    from public.student_programs membership
    join public.programs p on p.id = membership.program_id and p.tenant_id = membership.tenant_id
    where membership.student_id = u.id and membership.tenant_id = u.tenant_id
      and membership.status = 'active'::public.program_membership_status
    order by membership.admitted_on desc nulls last, membership.program_id
    limit 1
) prog on true
left join lateral (
    select assignment.specialization_id, s.name as specialization_name
    from public.student_specializations assignment
    join public.specializations s on s.id = assignment.specialization_id
      and s.program_id = assignment.program_id and s.tenant_id = assignment.tenant_id
    where assignment.student_id = u.id and assignment.tenant_id = u.tenant_id
      and assignment.status = 'active'::public.program_membership_status
      and (assignment.starts_on is null or assignment.starts_on <= current_date)
      and (assignment.ends_on is null or assignment.ends_on >= current_date)
      and prog.id is not null and assignment.program_id = prog.id
    order by assignment.starts_on desc nulls last, assignment.specialization_id
    limit 1
) confirmed_spec on true
where u.id = (select auth.uid())
  and u.user_type = 'non_staff'::public.user_type;