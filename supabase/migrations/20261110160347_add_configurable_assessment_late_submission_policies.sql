-- Configurable late-submission rules and per-student deadline extensions.
alter table public.assessments
  alter column late_policy set default '{"mode":"no_penalty","grace_period_minutes":0}'::jsonb;

alter table public.assessments
  add constraint assessments_late_policy_object_check
  check (
    jsonb_typeof(late_policy) = 'object'
    and coalesce(late_policy->>'mode', 'no_penalty') in ('no_penalty','penalty','disallowed')
    and (
      not (late_policy ? 'grace_period_minutes')
      or (
        jsonb_typeof(late_policy->'grace_period_minutes') = 'number'
        and (late_policy->>'grace_period_minutes')::numeric >= 0
        and (late_policy->>'grace_period_minutes')::numeric = trunc((late_policy->>'grace_period_minutes')::numeric)
      )
    )
    and (
      coalesce(late_policy->>'mode', 'no_penalty') <> 'penalty'
      or (
        late_policy->>'penalty_type' in ('percentage','fixed_marks')
        and late_policy->>'penalty_interval' in ('hour','day')
        and jsonb_typeof(late_policy->'penalty_amount') = 'number'
        and (late_policy->>'penalty_amount')::numeric >= 0
        and (
          not (late_policy ? 'max_penalty')
          or (
            jsonb_typeof(late_policy->'max_penalty') = 'number'
            and (late_policy->>'max_penalty')::numeric >= 0
          )
        )
      )
    )
  );

create table public.assessment_deadline_extensions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  assessment_id uuid not null,
  student_id uuid not null,
  extended_deadline_at timestamptz not null,
  reason text,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint assessment_deadline_extensions_assessment_student_key unique (assessment_id, student_id),
  constraint assessment_deadline_extensions_assessment_fk
    foreign key (assessment_id, tenant_id)
    references public.assessments(id, tenant_id) on delete cascade,
  constraint assessment_deadline_extensions_student_fk
    foreign key (student_id, tenant_id)
    references public.users(id, tenant_id)
);

create index assessment_deadline_extensions_student_idx
  on public.assessment_deadline_extensions (tenant_id, student_id, assessment_id);

alter table public.assessment_deadline_extensions enable row level security;

create policy "students and teachers read deadline extensions"
on public.assessment_deadline_extensions
for select to authenticated
using (
  tenant_id = (select private.tenant_id())
  and (
    student_id = (select auth.uid())
    or private.teaches_offering(
      (select a.offering_id from public.assessments a
       where a.id = assessment_deadline_extensions.assessment_id
         and a.tenant_id = assessment_deadline_extensions.tenant_id)
    )
  )
);

create policy "teachers manage deadline extensions"
on public.assessment_deadline_extensions
for all to authenticated
using (
  tenant_id = (select private.tenant_id())
  and private.teaches_offering(
    (select a.offering_id from public.assessments a
     where a.id = assessment_deadline_extensions.assessment_id
       and a.tenant_id = assessment_deadline_extensions.tenant_id)
  )
)
with check (
  tenant_id = (select private.tenant_id())
  and private.teaches_offering(
    (select a.offering_id from public.assessments a
     where a.id = assessment_deadline_extensions.assessment_id
       and a.tenant_id = assessment_deadline_extensions.tenant_id)
  )
);

grant select, insert, update, delete on public.assessment_deadline_extensions to authenticated;

alter table public.submissions
  add column late_minutes integer not null default 0,
  add column late_penalty_amount numeric(10,2) not null default 0,
  add column late_policy_snapshot jsonb not null default '{}'::jsonb;

alter table public.submissions
  add constraint submissions_late_minutes_check check (late_minutes >= 0),
  add constraint submissions_late_penalty_check check (late_penalty_amount >= 0),
  add constraint submissions_late_policy_snapshot_object_check check (jsonb_typeof(late_policy_snapshot) = 'object');

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
            now() <= coalesce(x.extended_deadline_at, s.deadline_at)
              + make_interval(mins => coalesce((a.late_policy->>'grace_period_minutes')::integer, 0))
          else
            (
              (a.late_policy->>'final_deadline_at' is null
               or now() <= (a.late_policy->>'final_deadline_at')::timestamptz)
            )
            and (
              now() <= coalesce(x.extended_deadline_at, s.deadline_at)
                + make_interval(mins => coalesce((a.late_policy->>'grace_period_minutes')::integer, 0))
              or coalesce(a.late_policy->>'mode', 'no_penalty') in ('no_penalty','penalty')
            )
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
  if new.status in ('submitted','graded')
     and (tg_op = 'INSERT' or old.status = 'in_progress' or new.submitted_at is distinct from old.submitted_at) then
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
    v_mode := coalesce(v_assessment.late_policy->>'mode', 'no_penalty');
    v_grace := coalesce((v_assessment.late_policy->>'grace_period_minutes')::integer, 0);

    if v_effective_deadline is not null then
      v_late_minutes := greatest(
        0,
        floor(extract(epoch from (coalesce(new.submitted_at, now()) - v_effective_deadline)) / 60)::integer - v_grace
      );
    end if;

    if v_late_minutes > 0 and v_mode = 'disallowed' then
      raise exception 'Late submission is not permitted for this assessment';
    end if;

    if v_assessment.closes_at is not null and coalesce(new.submitted_at, now()) > v_assessment.closes_at then
      raise exception 'Assessment submission window has closed';
    end if;

    if v_assessment.late_policy ? 'final_deadline_at'
       and coalesce(new.submitted_at, now()) > (v_assessment.late_policy->>'final_deadline_at')::timestamptz then
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

    new.submitted_at := coalesce(new.submitted_at, now());
    new.deadline_at := v_effective_deadline;
    new.is_late := v_late_minutes > 0;
    new.late_minutes := v_late_minutes;
    new.late_penalty_amount := round(v_penalty, 2);
    new.late_policy_snapshot := v_assessment.late_policy;
  end if;

  return new;
end
$function$;

create trigger submissions_apply_late_policy
before insert or update of status, submitted_at
on public.submissions
for each row
execute function private.apply_submission_late_policy();

revoke all on function private.apply_submission_late_policy() from public, anon, authenticated;
