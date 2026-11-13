-- Enforce ECU's mandatory assessment structure when a course offering is published.
-- Draft offerings remain configurable until publication.

create or replace function private.assert_ecu_offering_grading_scheme(p_offering_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_midterm_count integer;
  v_midterm_weight numeric;
  v_final_count integer;
  v_final_weight numeric;
  v_total_weight numeric;
  v_mismatched_exam_assessments integer;
begin
  perform 1 from public.course_offerings co where co.id = p_offering_id for update;
  if not found then return; end if;

  select
    count(*) filter (where gc.category = 'midterm'::public.grade_category),
    coalesce(sum(gc.weight) filter (where gc.category = 'midterm'::public.grade_category), 0),
    count(*) filter (where gc.category = 'final_exam'::public.grade_category),
    coalesce(sum(gc.weight) filter (where gc.category = 'final_exam'::public.grade_category), 0),
    coalesce(sum(gc.weight), 0)
  into v_midterm_count, v_midterm_weight, v_final_count, v_final_weight, v_total_weight
  from public.grade_components gc
  where gc.offering_id = p_offering_id;

  if v_midterm_count <> 1 or v_midterm_weight <> 20 then
    raise exception
      'ECU grading rule: offering % must have exactly one midterm component weighted 20 percent (found %, total weight %).',
      p_offering_id, v_midterm_count, v_midterm_weight
      using errcode = 'check_violation';
  end if;

  if v_final_count <> 1 or v_final_weight <> 40 then
    raise exception
      'ECU grading rule: offering % must have exactly one final-exam component weighted 40 percent (found %, total weight %).',
      p_offering_id, v_final_count, v_final_weight
      using errcode = 'check_violation';
  end if;

  if v_total_weight <> 100 then
    raise exception
      'ECU grading rule: all grading components for offering % must total exactly 100 percent (found %).',
      p_offering_id, v_total_weight
      using errcode = 'check_violation';
  end if;

  select count(*)
  into v_mismatched_exam_assessments
  from public.assessments a
  where a.offering_id = p_offering_id
    and a.kind in ('midterm'::public.assessment_kind, 'final_exam'::public.assessment_kind)
    and (
      a.component_id is null
      or not exists (
        select 1 from public.grade_components gc
        where gc.id = a.component_id
          and gc.tenant_id = a.tenant_id
          and gc.offering_id = a.offering_id
          and gc.category::text = a.kind::text
      )
    );

  if v_mismatched_exam_assessments > 0 then
    raise exception
      'ECU grading rule: offering % has % midterm/final assessment(s) not linked to the matching grading component.',
      p_offering_id, v_mismatched_exam_assessments
      using errcode = 'check_violation';
  end if;
end;
$function$;

create or replace function private.enforce_ecu_grading_scheme_on_offering_publish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'published'::public.offering_status
     and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    perform private.assert_ecu_offering_grading_scheme(new.id);
  end if;
  return new;
end;
$function$;

create trigger course_offerings_ecu_grading_scheme_before_publish
before insert or update on public.course_offerings
for each row
execute function private.enforce_ecu_grading_scheme_on_offering_publish();

create or replace function private.recheck_ecu_grading_scheme_after_component_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_offering_id uuid;
  v_status public.offering_status;
begin
  if tg_op = 'DELETE' then v_offering_id := old.offering_id;
  else v_offering_id := new.offering_id;
  end if;

  select co.status into v_status
  from public.course_offerings co where co.id = v_offering_id;

  if v_status = 'published'::public.offering_status then
    perform private.assert_ecu_offering_grading_scheme(v_offering_id);
  end if;

  if tg_op = 'UPDATE' and old.offering_id is distinct from new.offering_id then
    select co.status into v_status
    from public.course_offerings co where co.id = old.offering_id;
    if v_status = 'published'::public.offering_status then
      perform private.assert_ecu_offering_grading_scheme(old.offering_id);
    end if;
  end if;
  return null;
end;
$function$;

create constraint trigger grade_components_ecu_scheme_deferred
after insert or update or delete on public.grade_components
deferrable initially deferred
for each row
execute function private.recheck_ecu_grading_scheme_after_component_change();

create unique index assessments_one_midterm_per_section
on public.assessments (offering_id, (coalesce(section_id, '00000000-0000-0000-0000-000000000000'::uuid)))
where kind = 'midterm'::public.assessment_kind;

create unique index assessments_one_final_exam_per_section
on public.assessments (offering_id, (coalesce(section_id, '00000000-0000-0000-0000-000000000000'::uuid)))
where kind = 'final_exam'::public.assessment_kind;

create or replace function private.validate_exam_assessment_component()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_component_category public.grade_category;
  v_component_offering_id uuid;
  v_component_tenant_id uuid;
begin
  if new.kind in ('midterm'::public.assessment_kind, 'final_exam'::public.assessment_kind) then
    if new.component_id is null then
      raise exception
        'ECU grading rule: midterm and final-exam assessments must be linked to their grading component.'
        using errcode = 'check_violation';
    end if;

    select gc.category, gc.offering_id, gc.tenant_id
    into v_component_category, v_component_offering_id, v_component_tenant_id
    from public.grade_components gc where gc.id = new.component_id;

    if not found
       or v_component_category::text <> new.kind::text
       or v_component_offering_id <> new.offering_id
       or v_component_tenant_id <> new.tenant_id then
      raise exception
        'ECU grading rule: a % assessment must be linked to the matching grading component in the same course offering.',
        new.kind
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$function$;

create trigger assessments_validate_exam_component
before insert or update of offering_id, tenant_id, component_id, kind
on public.assessments
for each row
execute function private.validate_exam_assessment_component();

revoke all on function private.assert_ecu_offering_grading_scheme(uuid) from public, anon, authenticated;
revoke all on function private.enforce_ecu_grading_scheme_on_offering_publish() from public, anon, authenticated;
revoke all on function private.recheck_ecu_grading_scheme_after_component_change() from public, anon, authenticated;
revoke all on function private.validate_exam_assessment_component() from public, anon, authenticated;
