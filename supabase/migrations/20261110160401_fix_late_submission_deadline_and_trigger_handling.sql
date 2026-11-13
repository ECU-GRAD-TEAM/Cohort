create or replace function private.owns_open_submission(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.submissions s
    join public.assessments a
      on a.id = s.assessment_id and a.tenant_id = s.tenant_id
    left join public.assessment_deadline_extensions x
      on x.assessment_id = s.assessment_id
     and x.student_id = s.student_id
     and x.tenant_id = s.tenant_id
    where s.id = p_submission
      and s.student_id = (select auth.uid())
      and s.status = 'in_progress'
      and (a.closes_at is null or a.closes_at > now())
      and (
        case coalesce(a.late_policy->>'mode', 'no_penalty')
          when 'disallowed' then
            coalesce(x.extended_deadline_at, s.deadline_at, a.due_at) is null
            or now() <= coalesce(x.extended_deadline_at, s.deadline_at, a.due_at)
              + make_interval(mins => coalesce((a.late_policy->>'grace_period_minutes')::integer, 0))
          else
            a.late_policy->>'final_deadline_at' is null
            or now() <= (a.late_policy->>'final_deadline_at')::timestamptz
        end
      )
  )
$function$;

create or replace function private.apply_submission_late_policy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_assessment public.assessments%rowtype;
  v_extension timestamptz;
  v_effective_deadline timestamptz;
  v_submitted_at timestamptz;
  v_late_minutes integer := 0;
  v_grace integer := 0;
  v_interval_minutes integer := 60;
  v_penalty numeric(10,2) := 0;
  v_units numeric;
  v_mode text;
  v_penalty_type text;
  v_amount numeric;
  v_max_penalty numeric;
begin
  if tg_op = 'INSERT' then
    if new.status not in ('submitted','graded') then
      return new;
    end if;
  elsif old.status <> 'in_progress' and new.submitted_at is not distinct from old.submitted_at then
    return new;
  elsif new.status not in ('submitted','graded') then
    return new;
  end if;

  select * into v_assessment
  from public.assessments
  where id = new.assessment_id and tenant_id = new.tenant_id;

  if not found then
    raise exception 'Assessment not found for submission';
  end if;

  select x.extended_deadline_at into v_extension
  from public.assessment_deadline_extensions x
  where x.assessment_id = new.assessment_id
    and x.student_id = new.student_id
    and x.tenant_id = new.tenant_id;

  v_effective_deadline := coalesce(v_extension, new.deadline_at, v_assessment.due_at);
  v_submitted_at := coalesce(new.submitted_at, now());
  v_mode := coalesce(v_assessment.late_policy->>'mode', 'no_penalty');
  v_grace := coalesce((v_assessment.late_policy->>'grace_period_minutes')::integer, 0);

  if v_effective_deadline is not null then
    v_late_minutes := greatest(
      0,
      floor(extract(epoch from (v_submitted_at - v_effective_deadline)) / 60)::integer - v_grace
    );
  end if;

  if v_late_minutes > 0 and v_mode = 'disallowed' then
    raise exception 'Late submission is not permitted for this assessment';
  end if;

  if v_assessment.closes_at is not null and v_submitted_at > v_assessment.closes_at then
    raise exception 'Assessment submission window has closed';
  end if;

  if v_assessment.late_policy ? 'final_deadline_at'
     and v_submitted_at > (v_assessment.late_policy->>'final_deadline_at')::timestamptz then
    raise exception 'Final late-submission deadline has passed';
  end if;

  if v_late_minutes > 0 and v_mode = 'penalty' then
    v_penalty_type := v_assessment.late_policy->>'penalty_type';
    v_amount := (v_assessment.late_policy->>'penalty_amount')::numeric;
    v_interval_minutes := case v_assessment.late_policy->>'penalty_interval'
      when 'day' then 1440 else 60 end;
    v_units := ceil(v_late_minutes::numeric / v_interval_minutes);
    if v_penalty_type = 'percentage' then
      v_penalty := coalesce(v_assessment.max_score, 0) * (v_amount / 100) * v_units;
    else
      v_penalty := v_amount * v_units;
    end if;
    v_max_penalty := nullif(v_assessment.late_policy->>'max_penalty', '')::numeric;
    if v_max_penalty is not null then
      v_penalty := least(v_penalty, v_max_penalty);
    end if;
  end if;

  new.submitted_at := v_submitted_at;
  new.deadline_at := v_effective_deadline;
  new.is_late := v_late_minutes > 0;
  new.late_minutes := v_late_minutes;
  new.late_penalty_amount := round(v_penalty, 2);
  new.late_policy_snapshot := v_assessment.late_policy;

  return new;
end
$function$;

revoke all on function private.apply_submission_late_policy() from public, anon, authenticated;
