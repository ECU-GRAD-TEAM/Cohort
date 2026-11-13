-- Allow draft offerings to adopt a newer active policy when an earlier policy is retired.
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

    if coalesce(v_policy_active,false) is not true and tg_op = 'UPDATE' and old.status = 'draft' then
      select gp.id into new.grading_policy_id
      from public.grading_policies gp
      where gp.tenant_id = new.tenant_id and gp.status = 'active'
        and gp.effective_from <= current_date
        and (gp.effective_until is null or gp.effective_until >= current_date)
      order by gp.version desc limit 1;

      select (gp.status = 'active' and gp.effective_from <= current_date
        and (gp.effective_until is null or gp.effective_until >= current_date))
      into v_policy_active
      from public.grading_policies gp
      where gp.id = new.grading_policy_id and gp.tenant_id = new.tenant_id;
    end if;

    if coalesce(v_policy_active,false) is not true then
      raise exception 'No active, effective grading policy is assigned to this course offering.'
        using errcode = 'check_violation';
    end if;
    perform private.assert_offering_grading_scheme(new.id, new.tenant_id, new.grading_policy_id);
  end if;

  if tg_op = 'UPDATE' and old.status <> 'draft'
     and old.grading_policy_id is not null
     and new.grading_policy_id is distinct from old.grading_policy_id then
    raise exception 'A non-draft course offering cannot be reassigned to another grading policy version.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

revoke all on function private.enforce_grading_policy_on_offering_publish() from public, anon, authenticated;