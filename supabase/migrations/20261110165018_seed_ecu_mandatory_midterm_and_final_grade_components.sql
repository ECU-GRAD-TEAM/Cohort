-- Seed the two mandatory ECU grading components for every existing draft offering.
-- The remaining 40% is intentionally left for instructors to configure.

do $precheck$
declare
  v_offering_count integer;
  v_existing_count integer;
begin
  select count(*) into v_offering_count
  from public.course_offerings co
  join public.grading_policies gp
    on gp.id = co.grading_policy_id and gp.tenant_id = co.tenant_id
  where co.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'::uuid
    and gp.name = 'ECU Standard Assessment Policy'
    and gp.version = 1
    and gp.status = 'active'
    and co.status = 'draft';

  if v_offering_count <> 56 then
    raise exception 'Expected 56 ECU draft offerings assigned to ECU Standard Assessment Policy v1; found %.', v_offering_count;
  end if;

  select count(*) into v_existing_count
  from public.grade_components gc
  join public.course_offerings co on co.id = gc.offering_id and co.tenant_id = gc.tenant_id
  where co.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'::uuid;

  if v_existing_count <> 0 then
    raise exception 'Expected no existing grade components before seeding; found %.', v_existing_count;
  end if;
end;
$precheck$;

insert into public.grade_components (tenant_id, offering_id, name, category, weight)
select co.tenant_id, co.id, component.name, component.category::public.grade_category, component.weight
from public.course_offerings co
join public.grading_policies gp
  on gp.id = co.grading_policy_id and gp.tenant_id = co.tenant_id
cross join (
  values
    ('Midterm Examination', 'midterm', 20.00::numeric),
    ('Final Examination', 'final_exam', 40.00::numeric)
) as component(name, category, weight)
where co.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'::uuid
  and gp.name = 'ECU Standard Assessment Policy'
  and gp.version = 1
  and gp.status = 'active'
  and co.status = 'draft'
on conflict do nothing;

do $verify$
declare
  v_offering_count integer;
  v_component_count integer;
  v_invalid_count integer;
begin
  select count(*) into v_offering_count
  from public.course_offerings co
  join public.grading_policies gp
    on gp.id = co.grading_policy_id and gp.tenant_id = co.tenant_id
  where co.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'::uuid
    and gp.name = 'ECU Standard Assessment Policy'
    and gp.version = 1
    and gp.status = 'active'
    and co.status = 'draft';

  select count(*) into v_component_count
  from public.grade_components gc
  join public.course_offerings co on co.id = gc.offering_id and co.tenant_id = gc.tenant_id
  where co.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'::uuid
    and gc.name in ('Midterm Examination', 'Final Examination');

  select count(*) into v_invalid_count
  from public.course_offerings co
  join public.grading_policies gp
    on gp.id = co.grading_policy_id and gp.tenant_id = co.tenant_id
  where co.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'::uuid
    and gp.name = 'ECU Standard Assessment Policy'
    and gp.version = 1
    and gp.status = 'active'
    and co.status = 'draft'
    and (
      (select count(*) from public.grade_components gc
       where gc.offering_id = co.id and gc.tenant_id = co.tenant_id) <> 2
      or not exists (
        select 1 from public.grade_components gc
        where gc.offering_id = co.id and gc.tenant_id = co.tenant_id
          and gc.name = 'Midterm Examination'
          and gc.category = 'midterm'::public.grade_category
          and gc.weight = 20
      )
      or not exists (
        select 1 from public.grade_components gc
        where gc.offering_id = co.id and gc.tenant_id = co.tenant_id
          and gc.name = 'Final Examination'
          and gc.category = 'final_exam'::public.grade_category
          and gc.weight = 40
      )
    );

  if v_offering_count <> 56 or v_component_count <> 112 or v_invalid_count <> 0 then
    raise exception 'ECU grade-component seed verification failed: offerings %, named components %, invalid offerings %.',
      v_offering_count, v_component_count, v_invalid_count;
  end if;
end;
$verify$;
