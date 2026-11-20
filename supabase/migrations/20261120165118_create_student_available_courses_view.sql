create or replace view public.student_available_courses
with (security_invoker = true)
as
select
    c.id as course_id,
    c.code as course_code,
    c.title as course_title,
    c.description as course_description,
    c.credit_hours,
    c.level as course_level,
    c.is_active,
    d.code as department_code,
    d.name as department_name,
    o.id as offering_id,
    o.status::text as offering_status,
    t.id as term_id,
    t.code as term_code,
    t.name as term_name,
    t.status::text as term_status,
    t.starts_on as term_starts_on,
    t.ends_on as term_ends_on,
    t.registration_opens_at,
    t.registration_closes_at,
    t.add_drop_ends_at,
    ay.code as academic_year_code,
    ay.name as academic_year_name,
    case when o.id is null then 'catalog_only' else 'published_offering' end as offering_visibility,
    case
        when o.id is null then null
        when t.status <> 'registration'::term_status then false
        when t.registration_opens_at is null or t.registration_closes_at is null then null
        else now() between t.registration_opens_at and t.registration_closes_at
    end as registration_window_open,
    coalesce(sec.sections, '[]'::jsonb) as sections,
    coalesce(pre.prerequisites, '[]'::jsonb) as prerequisites
from public.courses c
left join public.departments d
    on d.id = c.department_id and d.tenant_id = c.tenant_id
left join public.course_offerings o
    on o.course_id = c.id
   and o.tenant_id = c.tenant_id
   and o.status = 'published'::offering_status
left join public.terms t
    on t.id = o.term_id and t.tenant_id = o.tenant_id
left join public.academic_years ay
    on ay.id = t.academic_year_id and ay.tenant_id = t.tenant_id
left join lateral (
    select jsonb_agg(
        jsonb_build_object(
            'section_code', s.code,
            'section_kind', s.kind::text,
            'capacity', s.capacity,
            'waitlist_capacity', s.waitlist_capacity
        ) order by s.code
    ) as sections
    from public.sections s
    where s.offering_id = o.id and s.tenant_id = o.tenant_id
) sec on true
left join lateral (
    select jsonb_agg(
        jsonb_build_object(
            'course_code', pc.code,
            'course_title', pc.title,
            'kind', cp.kind::text,
            'minimum_grade_points', cp.minimum_grade_points
        ) order by pc.code
    ) as prerequisites
    from public.course_prerequisites cp
    join public.courses pc
      on pc.id = cp.prerequisite_course_id and pc.tenant_id = cp.tenant_id
    where cp.course_id = c.id and cp.tenant_id = c.tenant_id
) pre on true
where c.is_active = true;

revoke all on public.student_available_courses from public, anon, authenticated;
grant select on public.student_available_courses to authenticated;
