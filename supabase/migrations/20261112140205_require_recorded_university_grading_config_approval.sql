-- An offering cannot self-declare approval. Approval must correspond to a
-- completed university review snapshot for the current configuration version.

create or replace function private.require_approved_grading_config_before_publish()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.grading_config_status = 'approved' then
    if not exists (
      select 1
      from public.course_grading_config_reviews r
      where r.offering_id = new.id
        and r.tenant_id = new.tenant_id
        and r.version = new.grading_config_version
        and r.status = 'approved'
    ) then
      raise exception 'A course grading configuration can only be marked approved by a recorded university review.'
        using errcode = 'check_violation';
    end if;
  end if;

  if new.status = 'published'::public.offering_status
     and (tg_op = 'INSERT' or old.status is distinct from new.status)
     and new.grading_policy_id is not null
     and new.grading_config_status is distinct from 'approved' then
    raise exception 'The course grading configuration must be approved by university leadership before publishing the offering.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;
