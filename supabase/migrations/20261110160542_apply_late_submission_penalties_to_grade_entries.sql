-- Preserve the policy used at submission time and apply the stored deduction to grade entries.
alter table public.grade_entries
  add column raw_score numeric,
  add column late_penalty_amount numeric(10,2) not null default 0;

update public.grade_entries
set raw_score = score
where raw_score is null;

alter table public.grade_entries
  alter column raw_score set not null,
  add constraint grade_entries_raw_score_check check (raw_score >= 0),
  add constraint grade_entries_late_penalty_check check (late_penalty_amount >= 0);

create or replace function private.apply_grade_entry_late_penalty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_penalty numeric(10,2) := 0;
begin
  if tg_op = 'INSERT' then
    new.raw_score := coalesce(new.raw_score, new.score);
  elsif new.score is distinct from old.score
        and new.raw_score is not distinct from old.raw_score then
    new.raw_score := new.score;
  elsif new.raw_score is distinct from old.raw_score then
    new.score := new.raw_score;
  end if;

  if new.assessment_id is not null then
    select s.late_penalty_amount
      into v_penalty
    from public.submissions s
    where s.assessment_id = new.assessment_id
      and s.student_id = new.student_id
      and s.offering_id = new.offering_id
      and s.status in ('submitted','graded')
    order by s.attempt_no desc
    limit 1;
  end if;

  new.late_penalty_amount := coalesce(v_penalty, 0);
  new.score := greatest(0, new.raw_score - new.late_penalty_amount);
  return new;
end
$function$;

create trigger grade_entries_apply_late_penalty
before insert or update of score, raw_score, assessment_id, student_id, offering_id
on public.grade_entries
for each row
execute function private.apply_grade_entry_late_penalty();

revoke all on function private.apply_grade_entry_late_penalty() from public, anon, authenticated;

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
  elsif old.status <> 'in_progress' or new.status not in ('submitted','graded') then
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
    if v_assessment.max_score is not null then
      v_penalty := least(v_penalty, v_assessment.max_score);
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

alter table public.assessments
  add constraint assessments_late_policy_final_deadline_check
  check (
    not (late_policy ? 'final_deadline_at')
    or (
      jsonb_typeof(late_policy->'final_deadline_at') = 'string'
      and (late_policy->>'final_deadline_at')::timestamptz is not null
    )
  );
