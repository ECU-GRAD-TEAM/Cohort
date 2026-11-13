-- Prevent direct insertion of published offerings without an approved grading configuration.
create or replace function private.require_approved_grading_config_before_publish()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
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

drop trigger if exists course_offerings_require_approved_grading_config on public.course_offerings;
create trigger course_offerings_require_approved_grading_config
before insert or update of status on public.course_offerings
for each row execute function private.require_approved_grading_config_before_publish();

create index course_grading_config_reviews_offering_fk_idx
  on public.course_grading_config_reviews(offering_id, tenant_id);
create index course_grading_config_reviews_policy_fk_idx
  on public.course_grading_config_reviews(grading_policy_id, tenant_id);
create index course_grading_config_reviews_submitter_fk_idx
  on public.course_grading_config_reviews(submitted_by, tenant_id);
create index course_grading_config_reviews_reviewer_fk_idx
  on public.course_grading_config_reviews(reviewed_by, tenant_id);
