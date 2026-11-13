-- Course-level grading configuration and university approval workflow.
-- University policy components remain fixed; instructors configure only the permitted remainder.

alter table public.course_offerings
  add column grading_config_status text not null default 'draft'
    check (grading_config_status in ('draft','submitted','approved','changes_requested')),
  add column grading_config_version integer not null default 0
    check (grading_config_version >= 0);

create table public.course_grading_config_reviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  offering_id uuid not null,
  version integer not null check (version > 0),
  grading_policy_id uuid,
  policy_version integer,
  status text not null default 'submitted'
    check (status in ('submitted','approved','changes_requested')),
  components_snapshot jsonb not null,
  submitted_by uuid not null,
  submitted_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_notes text,
  constraint course_grading_config_reviews_offering_fk
    foreign key (offering_id, tenant_id)
    references public.course_offerings(id, tenant_id) on delete cascade,
  constraint course_grading_config_reviews_policy_fk
    foreign key (grading_policy_id, tenant_id)
    references public.grading_policies(id, tenant_id),
  constraint course_grading_config_reviews_submitter_fk
    foreign key (submitted_by, tenant_id)
    references public.users(id, tenant_id),
  constraint course_grading_config_reviews_reviewer_fk
    foreign key (reviewed_by, tenant_id)
    references public.users(id, tenant_id),
  constraint course_grading_config_reviews_offering_version_key
    unique (offering_id, version)
);

create index course_grading_config_reviews_tenant_offering_idx
  on public.course_grading_config_reviews(tenant_id, offering_id, version desc);

alter table public.course_grading_config_reviews enable row level security;

create policy "teachers and university leadership read course grading reviews"
on public.course_grading_config_reviews
for select to authenticated
using (
  tenant_id = (select private.tenant_id())
  and (
    private.teaches_offering(offering_id)
    or (select private.can_manage_grading_policies())
    or (status = 'approved' and private.enrolled_in_offering(offering_id))
  )
);

revoke all on public.course_grading_config_reviews from anon, authenticated;
grant select on public.course_grading_config_reviews to authenticated;

create or replace function public.submit_course_grading_config(p_offering_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_offering public.course_offerings%rowtype;
  v_policy public.grading_policies%rowtype;
  v_version integer;
  v_snapshot jsonb;
  v_review_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  select * into v_offering
  from public.course_offerings
  where id = p_offering_id and tenant_id = (select private.tenant_id())
  for update;

  if not found or not private.teaches_offering(p_offering_id) then
    raise exception 'You are not assigned to teach this course offering.' using errcode = '42501';
  end if;

  if v_offering.grading_config_status = 'submitted' then
    raise exception 'This grading configuration is already awaiting review.' using errcode = 'check_violation';
  end if;

  if v_offering.grading_policy_id is null then
    raise exception 'This offering must inherit an active university grading policy before submission.' using errcode = 'check_violation';
  end if;

  select * into v_policy
  from public.grading_policies
  where id = v_offering.grading_policy_id and tenant_id = v_offering.tenant_id
    and status = 'active' and effective_from <= current_date
    and (effective_until is null or effective_until >= current_date);

  if not found then
    raise exception 'The assigned university grading policy is not currently active.' using errcode = 'check_violation';
  end if;

  perform private.assert_offering_grading_scheme(v_offering.id, v_offering.tenant_id, v_offering.grading_policy_id);

  select coalesce(max(r.version), 0) + 1 into v_version
  from public.course_grading_config_reviews r
  where r.offering_id = v_offering.id and r.tenant_id = v_offering.tenant_id;

  select jsonb_build_object(
    'policy', jsonb_build_object(
      'id', v_policy.id, 'name', v_policy.name, 'version', v_policy.version,
      'total_weight', v_policy.total_weight,
      'configurable_remainder_weight', v_policy.configurable_remainder_weight
    ),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', gc.id, 'name', gc.name, 'category', gc.category,
        'weight', gc.weight, 'drop_lowest', gc.drop_lowest
      ) order by gc.category, gc.name)
      from public.grade_components gc
      where gc.offering_id = v_offering.id and gc.tenant_id = v_offering.tenant_id
    ), '[]'::jsonb)
  ) into v_snapshot;

  insert into public.course_grading_config_reviews (
    tenant_id, offering_id, version, grading_policy_id, policy_version,
    status, components_snapshot, submitted_by
  ) values (
    v_offering.tenant_id, v_offering.id, v_version, v_policy.id, v_policy.version,
    'submitted', v_snapshot, auth.uid()
  ) returning id into v_review_id;

  update public.course_offerings
  set grading_config_status = 'submitted', grading_config_version = v_version
  where id = v_offering.id and tenant_id = v_offering.tenant_id;

  return v_review_id;
end;
$function$;

create or replace function public.review_course_grading_config(
  p_offering_id uuid, p_approved boolean, p_review_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_offering public.course_offerings%rowtype;
  v_review public.course_grading_config_reviews%rowtype;
  v_new_status text;
begin
  if auth.uid() is null or not (select private.can_manage_grading_policies()) then
    raise exception 'University grading-policy management permission is required.' using errcode = '42501';
  end if;

  select * into v_offering
  from public.course_offerings
  where id = p_offering_id and tenant_id = (select private.tenant_id())
  for update;

  if not found then
    raise exception 'Course offering not found in your university.' using errcode = 'P0002';
  end if;

  select * into v_review
  from public.course_grading_config_reviews
  where offering_id = v_offering.id and tenant_id = v_offering.tenant_id
    and version = v_offering.grading_config_version and status = 'submitted'
  for update;

  if not found or v_offering.grading_config_status <> 'submitted' then
    raise exception 'There is no submitted grading configuration awaiting review.' using errcode = 'check_violation';
  end if;

  if p_approved then
    perform private.assert_offering_grading_scheme(v_offering.id, v_offering.tenant_id, v_offering.grading_policy_id);
    v_new_status := 'approved';
  else
    v_new_status := 'changes_requested';
  end if;

  update public.course_grading_config_reviews
  set status = v_new_status, reviewed_by = auth.uid(), reviewed_at = now(),
      review_notes = nullif(btrim(p_review_notes), '')
  where id = v_review.id
  returning * into v_review;

  update public.course_offerings
  set grading_config_status = v_new_status
  where id = v_offering.id and tenant_id = v_offering.tenant_id;

  return v_review.id;
end;
$function$;

revoke all on function public.submit_course_grading_config(uuid) from public, anon;
revoke all on function public.review_course_grading_config(uuid, boolean, text) from public, anon;
grant execute on function public.submit_course_grading_config(uuid) to authenticated;
grant execute on function public.review_course_grading_config(uuid, boolean, text) to authenticated;

create or replace function private.guard_course_grading_component_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_offering_id uuid;
  v_tenant_id uuid;
  v_config_status text;
begin
  if tg_op = 'DELETE' then
    v_offering_id := old.offering_id;
    v_tenant_id := old.tenant_id;
  else
    v_offering_id := new.offering_id;
    v_tenant_id := new.tenant_id;
  end if;

  select co.grading_config_status into v_config_status
  from public.course_offerings co
  where co.id = v_offering_id and co.tenant_id = v_tenant_id;

  if v_config_status = 'submitted' then
    raise exception 'The grading configuration is locked while university review is pending.'
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from public.grade_entries ge
    where ge.offering_id = v_offering_id and ge.tenant_id = v_tenant_id
      and ge.status = 'published'
  ) then
    raise exception 'Assessment components cannot change after grades have been published.'
      using errcode = 'check_violation';
  end if;

  if v_config_status = 'approved' then
    update public.course_offerings set grading_config_status = 'draft'
    where id = v_offering_id and tenant_id = v_tenant_id;
  end if;

  if tg_op = 'UPDATE' and old.offering_id is distinct from new.offering_id then
    if exists (
      select 1 from public.grade_entries ge
      where ge.offering_id = old.offering_id and ge.tenant_id = old.tenant_id
        and ge.status = 'published'
    ) then
      raise exception 'Assessment components cannot move after grades have been published.'
        using errcode = 'check_violation';
    end if;
    update public.course_offerings set grading_config_status = 'draft'
    where id = old.offering_id and tenant_id = old.tenant_id
      and grading_config_status = 'approved';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

create trigger grade_components_guard_course_config
before insert or update or delete on public.grade_components
for each row execute function private.guard_course_grading_component_changes();

create or replace function private.require_approved_grading_config_before_publish()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.status = 'published'::public.offering_status
     and old.status is distinct from new.status
     and new.grading_policy_id is not null
     and new.grading_config_status is distinct from 'approved' then
    raise exception 'The course grading configuration must be approved by university leadership before publishing the offering.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

create trigger course_offerings_require_approved_grading_config
before update of status on public.course_offerings
for each row execute function private.require_approved_grading_config_before_publish();

comment on column public.course_offerings.grading_config_status is
  'Course-level assessment configuration workflow state under the inherited university grading policy.';
comment on column public.course_offerings.grading_config_version is
  'Latest submitted course grading configuration version; version snapshots are stored in course_grading_config_reviews.';
