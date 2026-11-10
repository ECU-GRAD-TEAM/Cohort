-- Tenant-configurable, versioned assessment grading policies.

create table public.grading_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  version integer not null default 1 check (version > 0),
  status text not null default 'draft' check (status in ('draft','active','retired')),
  total_weight numeric(5,2) not null default 100 check (total_weight > 0 and total_weight <= 100),
  configurable_remainder_weight numeric(5,2) not null default 0
    check (configurable_remainder_weight >= 0 and configurable_remainder_weight <= total_weight),
  allow_instructor_configurable_remainder boolean not null default false,
  effective_from date not null default current_date,
  effective_until date,
  created_at timestamptz not null default now(),
  constraint grading_policies_effective_dates_check check (effective_until is null or effective_until >= effective_from),
  constraint grading_policies_id_tenant_key unique (id, tenant_id),
  constraint grading_policies_tenant_name_version_key unique (tenant_id, name, version)
);

create unique index grading_policies_one_active_per_tenant
  on public.grading_policies (tenant_id) where status = 'active';
create index grading_policies_tenant_status_effective_idx
  on public.grading_policies (tenant_id, status, effective_from, effective_until);

create table public.grading_policy_component_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  grading_policy_id uuid not null,
  category public.grade_category not null,
  required_count integer not null check (required_count >= 0),
  required_weight numeric(5,2) check (required_weight >= 0 and required_weight <= 100),
  allow_instructor_weight_adjustment boolean not null default false,
  created_at timestamptz not null default now(),
  constraint grading_policy_component_rules_policy_fk
    foreign key (grading_policy_id, tenant_id)
    references public.grading_policies(id, tenant_id) on delete cascade,
  constraint grading_policy_component_rules_policy_category_key unique (grading_policy_id, category)
);
create index grading_policy_component_rules_tenant_policy_idx
  on public.grading_policy_component_rules (tenant_id, grading_policy_id);

alter table public.grading_policies enable row level security;
alter table public.grading_policy_component_rules enable row level security;

create or replace function private.can_manage_grading_policies()
returns boolean language sql stable security definer set search_path = ''
as $function$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id and r.tenant_id = ur.tenant_id
    where ur.user_id = (select auth.uid())
      and ur.tenant_id = private.tenant_id()
      and ur.scope_type = 'university'
      and r.key in ('president','vice_president')
      and ur.assignment_status = 'active' and ur.status = 'active'
      and ur.starts_at <= now() and (ur.ends_at is null or ur.ends_at > now())
      and ur.revoked_at is null
  );
$function$;
revoke all on function private.can_manage_grading_policies() from public, anon;
grant execute on function private.can_manage_grading_policies() to authenticated;

create policy "tenant members read grading policies" on public.grading_policies
  for select to authenticated using (tenant_id = (select private.tenant_id()));
create policy "university leadership manages grading policies" on public.grading_policies
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()))
  with check (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));

create policy "tenant members read grading policy component rules" on public.grading_policy_component_rules
  for select to authenticated using (tenant_id = (select private.tenant_id()));
create policy "university leadership manages grading policy component rules" on public.grading_policy_component_rules
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()))
  with check (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));

grant select, insert, update, delete on public.grading_policies to authenticated;
grant select, insert, update, delete on public.grading_policy_component_rules to authenticated;
grant all on public.grading_policies to service_role;
grant all on public.grading_policy_component_rules to service_role;

alter table public.course_offerings add column grading_policy_id uuid;
alter table public.course_offerings
  add constraint course_offerings_grading_policy_tenant_fk
  foreign key (grading_policy_id, tenant_id) references public.grading_policies(id, tenant_id);
create index course_offerings_grading_policy_tenant_idx
  on public.course_offerings (grading_policy_id, tenant_id) where grading_policy_id is not null;

create or replace function private.prevent_grading_policy_content_mutation()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if exists (select 1 from public.course_offerings co where co.grading_policy_id = old.id)
     and (
       new.tenant_id is distinct from old.tenant_id
       or new.name is distinct from old.name
       or new.version is distinct from old.version
       or new.total_weight is distinct from old.total_weight
       or new.configurable_remainder_weight is distinct from old.configurable_remainder_weight
       or new.allow_instructor_configurable_remainder is distinct from old.allow_instructor_configurable_remainder
       or new.effective_from is distinct from old.effective_from
     ) then
    raise exception 'An assigned grading policy is immutable; create a new policy version.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;
create trigger grading_policies_prevent_content_mutation
before update on public.grading_policies
for each row execute function private.prevent_grading_policy_content_mutation();

create or replace function private.prevent_grading_policy_rule_mutation()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare v_policy_id uuid;
begin
  if tg_op = 'DELETE' then v_policy_id := old.grading_policy_id;
  else v_policy_id := new.grading_policy_id;
  end if;
  if exists (select 1 from public.course_offerings co where co.grading_policy_id = v_policy_id)
     or (tg_op = 'UPDATE' and exists (
       select 1 from public.course_offerings co where co.grading_policy_id = old.grading_policy_id
     )) then
    raise exception 'Rules for an assigned grading policy are immutable; create a new policy version.'
      using errcode = 'check_violation';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;
create trigger grading_policy_component_rules_immutable
before insert or update or delete on public.grading_policy_component_rules
for each row execute function private.prevent_grading_policy_rule_mutation();

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
declare v_policy_active boolean;
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
      raise exception 'No active, effective grading policy is assigned to this course offering.'
        using errcode = 'check_violation';
    end if;
    perform private.assert_offering_grading_scheme(new.id, new.tenant_id, new.grading_policy_id);
  end if;

  if tg_op = 'UPDATE' and old.grading_policy_id is not null
     and new.grading_policy_id is distinct from old.grading_policy_id then
    raise exception 'A course offering cannot be reassigned to another grading policy version.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

drop trigger if exists course_offerings_ecu_grading_scheme_before_publish on public.course_offerings;
create trigger course_offerings_grading_policy_before_publish
before insert or update of status, grading_policy_id on public.course_offerings
for each row execute function private.enforce_grading_policy_on_offering_publish();

create or replace function private.recheck_grading_policy_after_component_change()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_offering_id uuid;
  v_tenant_id uuid;
  v_policy_id uuid;
  v_status public.offering_status;
begin
  if tg_op = 'DELETE' then v_offering_id := old.offering_id; v_tenant_id := old.tenant_id;
  else v_offering_id := new.offering_id; v_tenant_id := new.tenant_id;
  end if;

  select co.grading_policy_id, co.status into v_policy_id, v_status
  from public.course_offerings co
  where co.id = v_offering_id and co.tenant_id = v_tenant_id;
  if v_status = 'published'::public.offering_status then
    perform private.assert_offering_grading_scheme(v_offering_id, v_tenant_id, v_policy_id);
  end if;

  if tg_op = 'UPDATE' and old.offering_id is distinct from new.offering_id then
    select co.grading_policy_id, co.status into v_policy_id, v_status
    from public.course_offerings co where co.id = old.offering_id and co.tenant_id = old.tenant_id;
    if v_status = 'published'::public.offering_status then
      perform private.assert_offering_grading_scheme(old.offering_id, old.tenant_id, v_policy_id);
    end if;
  end if;
  return null;
end;
$function$;

drop trigger if exists grade_components_ecu_scheme_deferred on public.grade_components;
create constraint trigger grade_components_grading_policy_deferred
after insert or update or delete on public.grade_components
deferrable initially deferred for each row
execute function private.recheck_grading_policy_after_component_change();

drop index if exists public.assessments_one_midterm_per_section;
drop index if exists public.assessments_one_final_exam_per_section;
create unique index assessments_one_exam_per_component_section
on public.assessments (
  offering_id,
  (coalesce(section_id, '00000000-0000-0000-0000-000000000000'::uuid)),
  component_id
)
where kind in ('midterm'::public.assessment_kind, 'final_exam'::public.assessment_kind);

drop trigger if exists assessments_validate_exam_component on public.assessments;
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
  return new;
end;
$function$;

create trigger assessments_validate_exam_component
before insert or update of offering_id, tenant_id, component_id, kind, section_id
on public.assessments for each row
execute function private.validate_exam_assessment_component();

-- Seed ECU's initial policy and attach existing offerings to this immutable version.
do $seed$
declare v_tenant_id uuid; v_policy_id uuid;
begin
  select t.id into v_tenant_id from public.tenants t where t.slug = 'ecu';
  if v_tenant_id is not null then
    select gp.id into v_policy_id from public.grading_policies gp
    where gp.tenant_id = v_tenant_id and gp.name = 'ECU Standard Assessment Policy' and gp.version = 1;
    if v_policy_id is null then
      insert into public.grading_policies (
        tenant_id,name,version,status,total_weight,configurable_remainder_weight,
        allow_instructor_configurable_remainder
      ) values (
        v_tenant_id,'ECU Standard Assessment Policy',1,'active',100,40,true
      ) returning id into v_policy_id;
    end if;
    insert into public.grading_policy_component_rules (
      tenant_id,grading_policy_id,category,required_count,required_weight,allow_instructor_weight_adjustment
    ) values
      (v_tenant_id,v_policy_id,'midterm'::public.grade_category,1,20,false),
      (v_tenant_id,v_policy_id,'final_exam'::public.grade_category,1,40,false)
    on conflict (grading_policy_id,category) do nothing;
    update public.course_offerings set grading_policy_id = v_policy_id
    where tenant_id = v_tenant_id and grading_policy_id is null;
  end if;
end;
$seed$;

revoke all on function private.prevent_grading_policy_content_mutation() from public, anon, authenticated;
revoke all on function private.prevent_grading_policy_rule_mutation() from public, anon, authenticated;
revoke all on function private.assert_offering_grading_scheme(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function private.enforce_grading_policy_on_offering_publish() from public, anon, authenticated;
revoke all on function private.recheck_grading_policy_after_component_change() from public, anon, authenticated;
revoke all on function private.validate_exam_assessment_component() from public, anon, authenticated;
