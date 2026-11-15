-- Allow a tenant to operate without a grading policy.
-- Published offerings without a policy must still have assessment weights totaling 100%.

create or replace function private.assert_offering_grading_scheme(
  p_offering_id uuid, p_tenant_id uuid, p_policy_id uuid
)
returns void language plpgsql security definer set search_path = ''
as $function$
declare
  v_total_weight numeric(8,2);
  v_remainder_weight numeric(8,2);
  v_policy_total numeric(5,2);
  v_remainder_expected numeric(5,2);
  v_allow_remainder boolean;
  v_rule record;
  v_actual_count integer;
  v_actual_weight numeric(8,2);
begin
  if p_policy_id is null then
    select coalesce(sum(gc.weight),0) into v_total_weight
    from public.grade_components gc
    where gc.offering_id = p_offering_id and gc.tenant_id = p_tenant_id;

    if v_total_weight <> 100 then
      raise exception 'Without a grading policy, assessment components for offering % must total 100 percent; found %.',
        p_offering_id, v_total_weight
        using errcode = 'check_violation';
    end if;
    return;
  end if;

  select gp.total_weight, gp.configurable_remainder_weight, gp.allow_instructor_configurable_remainder
  into v_policy_total, v_remainder_expected, v_allow_remainder
  from public.grading_policies gp
  where gp.id = p_policy_id and gp.tenant_id = p_tenant_id;
  if not found then
    raise exception 'The course offering has no grading policy belonging to its university.'
      using errcode = 'check_violation';
  end if;

  for v_rule in
    select r.category, r.required_count, r.required_weight, r.allow_instructor_weight_adjustment
    from public.grading_policy_component_rules r
    where r.grading_policy_id = p_policy_id and r.tenant_id = p_tenant_id
  loop
    select count(*), coalesce(sum(gc.weight),0)
    into v_actual_count, v_actual_weight
    from public.grade_components gc
    where gc.offering_id = p_offering_id and gc.tenant_id = p_tenant_id
      and gc.category = v_rule.category;

    if v_actual_count <> v_rule.required_count then
      raise exception 'Policy requires % component(s) in category %, but offering % has %.',
        v_rule.required_count, v_rule.category, p_offering_id, v_actual_count
        using errcode = 'check_violation';
    end if;
    if v_rule.required_weight is not null and not v_rule.allow_instructor_weight_adjustment
       and v_actual_weight <> v_rule.required_weight then
      raise exception 'Policy requires category % to total % percent, but offering % has %.',
        v_rule.category, v_rule.required_weight, p_offering_id, v_actual_weight
        using errcode = 'check_violation';
    end if;
  end loop;

  select coalesce(sum(gc.weight),0) into v_remainder_weight
  from public.grade_components gc
  where gc.offering_id = p_offering_id and gc.tenant_id = p_tenant_id
    and not exists (
      select 1 from public.grading_policy_component_rules r
      where r.grading_policy_id = p_policy_id and r.tenant_id = p_tenant_id
        and r.category = gc.category
    );

  if not v_allow_remainder and v_remainder_weight <> 0 then
    raise exception 'This grading policy does not allow instructor-configurable components.'
      using errcode = 'check_violation';
  end if;
  if v_remainder_weight <> v_remainder_expected then
    raise exception 'Policy allows % percent for configurable components, but offering % assigns % percent.',
      v_remainder_expected, p_offering_id, v_remainder_weight
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(gc.weight),0) into v_total_weight
  from public.grade_components gc
  where gc.offering_id = p_offering_id and gc.tenant_id = p_tenant_id;
  if v_total_weight <> v_policy_total then
    raise exception 'Grading components for offering % must total % percent; found %.',
      p_offering_id, v_policy_total, v_total_weight
      using errcode = 'check_violation';
  end if;
end;
$function$;

create or replace function private.enforce_grading_policy_on_offering_publish()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_policy_active boolean;
begin
  if new.grading_policy_id is null then
    select gp.id into new.grading_policy_id
    from public.grading_policies gp
    where gp.tenant_id = new.tenant_id and gp.status = 'active'
      and gp.effective_from <= current_date
      and (gp.effective_until is null or gp.effective_until >= current_date)
    order by gp.version desc limit 1;
  end if;

  if new.status = 'published'::public.offering_status
     and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    select (gp.status = 'active' and gp.effective_from <= current_date
      and (gp.effective_until is null or gp.effective_until >= current_date))
    into v_policy_active
    from public.grading_policies gp
    where gp.id = new.grading_policy_id and gp.tenant_id = new.tenant_id;

    if coalesce(v_policy_active,false) is not true then
      -- No active policy means this university is operating without a standard policy.
      -- A draft that still points at a retired/ineffective version is detached.
      new.grading_policy_id := null;
    end if;

    perform private.assert_offering_grading_scheme(new.id, new.tenant_id, new.grading_policy_id);
  end if;

  if tg_op = 'UPDATE' and old.status <> 'draft'
     and new.grading_policy_id is distinct from old.grading_policy_id then
    raise exception 'A non-draft course offering cannot be reassigned to another grading policy version.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

create or replace function private.validate_exam_assessment_component()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_component_category public.grade_category;
  v_component_offering_id uuid;
  v_component_tenant_id uuid;
  v_policy_id uuid;
  v_required_count integer;
  v_existing_count integer;
begin
  if new.kind in ('midterm'::public.assessment_kind, 'final_exam'::public.assessment_kind) then
    if new.component_id is null then
      raise exception 'Exam assessments must be linked to a grading component.'
        using errcode = 'check_violation';
    end if;

    select gc.category, gc.offering_id, gc.tenant_id
    into v_component_category, v_component_offering_id, v_component_tenant_id
    from public.grade_components gc where gc.id = new.component_id;
    if not found or v_component_category::text <> new.kind::text
       or v_component_offering_id <> new.offering_id or v_component_tenant_id <> new.tenant_id then
      raise exception 'A % assessment must link to a matching component in the same offering.',
        new.kind using errcode = 'check_violation';
    end if;

    select co.grading_policy_id into v_policy_id
    from public.course_offerings co where co.id = new.offering_id and co.tenant_id = new.tenant_id;

    -- With no assigned policy, exam counts are configured freely by the instructor.
    if v_policy_id is not null then
      select r.required_count into v_required_count
      from public.grading_policy_component_rules r
      where r.grading_policy_id = v_policy_id and r.tenant_id = new.tenant_id
        and r.category::text = new.kind::text;
      if v_required_count is null or v_required_count = 0 then
        raise exception 'The assigned grading policy does not permit % assessments.', new.kind
          using errcode = 'check_violation';
      end if;

      select count(*) into v_existing_count
      from public.assessments a
      where a.offering_id = new.offering_id and a.tenant_id = new.tenant_id
        and a.section_id is not distinct from new.section_id and a.kind = new.kind
        and (tg_op = 'INSERT' or a.id <> new.id);
      if v_existing_count >= v_required_count then
        raise exception 'The assigned grading policy permits at most % % assessment(s) per section.',
          v_required_count, new.kind using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function private.assert_offering_grading_scheme(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function private.enforce_grading_policy_on_offering_publish() from public, anon, authenticated;
revoke all on function private.validate_exam_assessment_component() from public, anon, authenticated;
