create or replace function private.assert_offering_grading_scheme(
  p_offering_id uuid,
  p_tenant_id uuid,
  p_policy_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
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
  if v_remainder_weight > v_remainder_expected then
    raise exception 'Policy allows up to % percent for configurable components, but offering % assigns % percent.',
      v_remainder_expected, p_offering_id, v_remainder_weight
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(gc.weight),0) into v_total_weight
  from public.grade_components gc
  where gc.offering_id = p_offering_id and gc.tenant_id = p_tenant_id;
  if v_total_weight > v_policy_total then
    raise exception 'Grading components for offering % cannot exceed % percent; found %.',
      p_offering_id, v_policy_total, v_total_weight
      using errcode = 'check_violation';
  end if;
end;
$function$;
