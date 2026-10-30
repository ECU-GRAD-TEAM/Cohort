-- Learning and assessment (paper 4.1, 4.2, 6.5, 6.9, 7.3, 7.4): course materials, topics and
-- learning outcomes, the question bank, assessments, rubrics, model answers, attempts and
-- answers, scores and grade appeals.
--
-- Two rules shape this migration:
--   * answer keys and scores live in their own tables, so a student who can read a question
--     or their own answer never sees the key or a score before release;
--   * students start and submit attempts only through functions, so the timer runs on the
--     server and answers stop saving at the deadline.

create type public.material_kind as enum ('file', 'link', 'page', 'video');
-- Every generated item is labelled (paper 7.4).
create type public.content_origin as enum ('teacher', 'ai_generated', 'ai_edited');
create type public.topic_kind as enum ('topic', 'outcome');
create type public.assessment_kind as enum ('assignment', 'quiz', 'midterm', 'final_exam', 'project', 'lab');
create type public.assessment_delivery as enum ('online', 'in_hall', 'upload');
create type public.assessment_status as enum ('draft', 'published', 'closed', 'archived');
create type public.ai_assistance_mode as enum ('allowed', 'hints_only', 'disabled');
create type public.question_type as enum (
  'mcq_single', 'mcq_multi', 'true_false', 'matching', 'short_answer', 'essay', 'problem', 'programming'
);
create type public.difficulty as enum ('easy', 'medium', 'hard');
create type public.question_status as enum ('draft', 'approved', 'retired');
create type public.submission_status as enum ('in_progress', 'submitted', 'graded');
create type public.score_source as enum ('auto', 'teacher', 'ai_accepted', 'ai_modified');
create type public.review_status as enum ('open', 'in_review', 'upheld', 'changed', 'rejected');

create table public.material_folders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  parent_id uuid,
  name text not null,
  position integer not null default 0,
  release_at timestamptz,
  unique (id, tenant_id),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (parent_id, tenant_id) references public.material_folders (id, tenant_id) on delete cascade
);
create index on public.material_folders (offering_id, tenant_id);
create index on public.material_folders (parent_id, tenant_id);

create table public.materials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  folder_id uuid,
  title text not null,
  description text,
  kind public.material_kind not null,
  origin public.content_origin not null default 'teacher',
  is_published boolean not null default false,
  release_at timestamptz,
  -- Teachers can keep a material out of the study assistant's corpus (paper 4.1.1).
  ai_indexable boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (folder_id, tenant_id) references public.material_folders (id, tenant_id) on delete set null (folder_id)
);
create index on public.materials (offering_id, tenant_id);
create index on public.materials (folder_id, tenant_id);

create table public.material_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  material_id uuid not null,
  version integer not null check (version > 0),
  -- Object-storage key for files, or a URL for links and videos.
  storage_path text,
  url text,
  content_type text,
  size_bytes bigint check (size_bytes >= 0),
  checksum text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (material_id, version),
  check (storage_path is not null or url is not null),
  foreign key (material_id, tenant_id) references public.materials (id, tenant_id) on delete cascade
);
create index on public.material_versions (material_id, tenant_id);

-- Topics and learning outcomes belong to the course, so tags survive from term to term and
-- feed the understanding heatmap (paper 7.5).
create table public.topics (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  course_id uuid not null,
  parent_id uuid,
  kind public.topic_kind not null default 'topic',
  name text not null,
  description text,
  unique (id, tenant_id),
  unique (course_id, kind, name),
  foreign key (course_id, tenant_id) references public.courses (id, tenant_id) on delete cascade,
  foreign key (parent_id, tenant_id) references public.topics (id, tenant_id) on delete set null (parent_id)
);
create index on public.topics (course_id, tenant_id);
create index on public.topics (parent_id, tenant_id);

create table public.rubrics (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  title text not null,
  origin public.content_origin not null default 'teacher',
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade
);
create index on public.rubrics (offering_id, tenant_id);

create table public.rubric_criteria (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  rubric_id uuid not null,
  position integer not null default 0,
  title text not null,
  description text,
  max_points numeric(7, 2) not null check (max_points > 0),
  -- Optional performance levels: [{"label": "...", "points": n, "description": "..."}].
  levels jsonb not null default '[]'::jsonb,
  unique (id, tenant_id),
  foreign key (rubric_id, tenant_id) references public.rubrics (id, tenant_id) on delete cascade
);
create index on public.rubric_criteria (rubric_id, tenant_id);

create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  -- Null when the assessment is for every section of the offering.
  section_id uuid,
  component_id uuid,
  rubric_id uuid,
  kind public.assessment_kind not null,
  delivery public.assessment_delivery not null,
  title text not null,
  instructions text,
  opens_at timestamptz,
  due_at timestamptz,
  -- Last moment a late submission is accepted. Defaults to due_at when not set.
  closes_at timestamptz,
  time_limit_minutes integer check (time_limit_minutes > 0),
  max_attempts integer not null default 1 check (max_attempts > 0),
  late_policy jsonb not null default '{}'::jsonb,
  shuffle_questions boolean not null default false,
  shuffle_options boolean not null default false,
  -- Draw this many questions at random from the assessment's pool for each attempt.
  questions_per_attempt integer check (questions_per_attempt > 0),
  max_score numeric(7, 2) check (max_score > 0),
  ai_assistance public.ai_assistance_mode not null default 'hints_only',
  origin public.content_origin not null default 'teacher',
  status public.assessment_status not null default 'draft',
  grades_released_at timestamptz,
  model_answers_release_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  check (due_at is null or opens_at is null or due_at > opens_at),
  check (closes_at is null or due_at is null or closes_at >= due_at),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (section_id, tenant_id, offering_id) references public.sections (id, tenant_id, offering_id),
  foreign key (component_id, tenant_id) references public.grade_components (id, tenant_id) on delete set null (component_id),
  foreign key (rubric_id, tenant_id) references public.rubrics (id, tenant_id) on delete set null (rubric_id)
);
create index on public.assessments (offering_id, tenant_id);
create index on public.assessments (section_id, tenant_id, offering_id);
create index on public.assessments (component_id, tenant_id);
create index on public.assessments (rubric_id, tenant_id);

alter table public.grade_entries
  add foreign key (assessment_id, tenant_id) references public.assessments (id, tenant_id);
create index on public.grade_entries (assessment_id, tenant_id);

-- The question bank belongs to the course and is reused across terms.
-- content holds what the student sees (options, pairs); never the answer.
create table public.questions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  course_id uuid not null,
  type public.question_type not null,
  stem text not null,
  content jsonb not null default '{}'::jsonb,
  default_points numeric(7, 2) not null default 1 check (default_points > 0),
  difficulty public.difficulty,
  origin public.content_origin not null default 'teacher',
  status public.question_status not null default 'draft',
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (course_id, tenant_id) references public.courses (id, tenant_id) on delete cascade
);
create index on public.questions (course_id, tenant_id);

create table public.question_answer_keys (
  question_id uuid primary key,
  tenant_id uuid not null,
  -- mcq_single: "b"; mcq_multi: ["a", "c"]; true_false: true; matching: {"1": "c", "2": "a"};
  -- free-text types: a reference answer for graders.
  answer jsonb not null,
  explanation text,
  foreign key (question_id, tenant_id) references public.questions (id, tenant_id) on delete cascade
);

create table public.question_tags (
  question_id uuid not null,
  topic_id uuid not null,
  tenant_id uuid not null,
  primary key (question_id, topic_id),
  foreign key (question_id, tenant_id) references public.questions (id, tenant_id) on delete cascade,
  foreign key (topic_id, tenant_id) references public.topics (id, tenant_id) on delete cascade
);
create index on public.question_tags (topic_id, tenant_id);

create table public.assessment_questions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  assessment_id uuid not null,
  question_id uuid not null,
  position integer not null default 0,
  points numeric(7, 2) not null check (points > 0),
  rubric_id uuid,
  unique (id, tenant_id),
  unique (assessment_id, question_id),
  foreign key (assessment_id, tenant_id) references public.assessments (id, tenant_id) on delete cascade,
  foreign key (question_id, tenant_id) references public.questions (id, tenant_id),
  foreign key (rubric_id, tenant_id) references public.rubrics (id, tenant_id) on delete set null (rubric_id)
);
create index on public.assessment_questions (assessment_id, tenant_id);
create index on public.assessment_questions (question_id, tenant_id);
create index on public.assessment_questions (rubric_id, tenant_id);

-- Released to students after the deadline, written by the teacher or drafted by AI and
-- approved by the teacher (paper 4.2).
create table public.model_answers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  assessment_id uuid not null,
  -- Null for a model answer to the whole assessment.
  question_id uuid,
  body text,
  storage_path text,
  origin public.content_origin not null default 'teacher',
  approved_by uuid,
  approved_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (body is not null or storage_path is not null),
  check (origin = 'teacher' or approved_at is null or approved_by is not null),
  foreign key (assessment_id, tenant_id) references public.assessments (id, tenant_id) on delete cascade,
  foreign key (question_id, tenant_id) references public.questions (id, tenant_id)
);
create index on public.model_answers (assessment_id, tenant_id);
create index on public.model_answers (question_id, tenant_id);

-- One row per attempt.
create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  assessment_id uuid not null,
  offering_id uuid not null,
  student_id uuid not null,
  attempt_no integer not null check (attempt_no > 0),
  status public.submission_status not null default 'in_progress',
  started_at timestamptz not null default now(),
  -- Server-side end of the attempt: the earlier of the time limit and the closing time.
  deadline_at timestamptz,
  submitted_at timestamptz,
  is_late boolean not null default false,
  unique (id, tenant_id),
  unique (assessment_id, student_id, attempt_no),
  foreign key (assessment_id, tenant_id) references public.assessments (id, tenant_id) on delete cascade,
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id)
);
create unique index submissions_one_open_attempt on public.submissions (assessment_id, student_id)
  where status = 'in_progress';
create index on public.submissions (offering_id, tenant_id);
create index on public.submissions (student_id, tenant_id);

create table public.submission_answers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  submission_id uuid not null,
  assessment_question_id uuid not null,
  question_id uuid not null,
  position integer not null,
  response jsonb,
  response_text text,
  saved_at timestamptz,
  unique (id, tenant_id),
  unique (submission_id, assessment_question_id),
  foreign key (submission_id, tenant_id) references public.submissions (id, tenant_id) on delete cascade,
  foreign key (assessment_question_id, tenant_id) references public.assessment_questions (id, tenant_id),
  foreign key (question_id, tenant_id) references public.questions (id, tenant_id)
);
create index on public.submission_answers (assessment_question_id, tenant_id);
create index on public.submission_answers (question_id, tenant_id);

-- Uploaded work, including photographs of handwritten answers.
create table public.submission_files (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  submission_id uuid not null,
  submission_answer_id uuid,
  storage_path text not null,
  file_name text not null,
  content_type text,
  size_bytes bigint check (size_bytes >= 0),
  uploaded_at timestamptz not null default now(),
  foreign key (submission_id, tenant_id) references public.submissions (id, tenant_id) on delete cascade,
  foreign key (submission_answer_id, tenant_id) references public.submission_answers (id, tenant_id) on delete cascade
);
create index on public.submission_files (submission_id, tenant_id);
create index on public.submission_files (submission_answer_id, tenant_id);

-- Score for one answer: automatic for deterministic types, otherwise set by the teacher
-- (possibly by accepting an AI suggestion).
create table public.answer_scores (
  submission_answer_id uuid primary key,
  tenant_id uuid not null,
  points numeric(7, 2) not null check (points >= 0),
  is_correct boolean,
  source public.score_source not null,
  feedback text,
  scored_by uuid,
  scored_at timestamptz not null default now(),
  foreign key (submission_answer_id, tenant_id) references public.submission_answers (id, tenant_id) on delete cascade
);

create table public.rubric_scores (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  submission_answer_id uuid not null,
  criterion_id uuid not null,
  points numeric(7, 2) not null check (points >= 0),
  comment text,
  source public.score_source not null default 'teacher',
  scored_by uuid default auth.uid(),
  scored_at timestamptz not null default now(),
  unique (submission_answer_id, criterion_id),
  foreign key (submission_answer_id, tenant_id) references public.submission_answers (id, tenant_id) on delete cascade,
  foreign key (criterion_id, tenant_id) references public.rubric_criteria (id, tenant_id)
);
create index on public.rubric_scores (criterion_id, tenant_id);

-- Appeals: every grade has a review path that records who changed what and why (paper 7.3).
create table public.grade_reviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  grade_entry_id uuid not null,
  student_id uuid not null,
  offering_id uuid not null,
  reason text not null,
  status public.review_status not null default 'open',
  reviewer_id uuid,
  resolution text,
  resulting_grade_entry_id uuid,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (status in ('open', 'in_review') or resolution is not null),
  foreign key (grade_entry_id, tenant_id) references public.grade_entries (id, tenant_id),
  foreign key (resulting_grade_entry_id, tenant_id) references public.grade_entries (id, tenant_id),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id)
);
create index on public.grade_reviews (grade_entry_id, tenant_id);
create index on public.grade_reviews (resulting_grade_entry_id, tenant_id);
create index on public.grade_reviews (student_id, tenant_id);
create index on public.grade_reviews (offering_id, tenant_id);

create trigger materials_touch before update on public.materials
  for each row execute function private.touch_updated_at();
create trigger assessments_touch before update on public.assessments
  for each row execute function private.touch_updated_at();
create trigger questions_touch before update on public.questions
  for each row execute function private.touch_updated_at();

create trigger answer_scores_audit after insert or update or delete on public.answer_scores
  for each row execute function private.audit_row_change();
create trigger rubric_scores_audit after insert or update or delete on public.rubric_scores
  for each row execute function private.audit_row_change();
create trigger grade_reviews_audit after insert or update on public.grade_reviews
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------------
-- Attempts (paper 6.9)
-- ---------------------------------------------------------------------------

create function private.answer_matches(p_type public.question_type, p_response jsonb, p_key jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_response is null or p_key is null then false
    -- Order of the chosen options does not matter.
    when p_type = 'mcq_multi' then
      (select coalesce(jsonb_agg(e order by e), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(p_response) = 'array' then p_response else jsonb_build_array(p_response) end) e)
      = (select coalesce(jsonb_agg(e order by e), '[]'::jsonb)
           from jsonb_array_elements(case when jsonb_typeof(p_key) = 'array' then p_key else jsonb_build_array(p_key) end) e)
    else p_response = p_key
  end
$$;

-- Starts an attempt, or resumes the open one after a lost connection.
create function public.start_attempt(p_assessment uuid)
returns public.submissions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_assessment public.assessments;
  v_submission public.submissions;
  v_attempts integer;
  v_closes timestamptz;
  v_deadline timestamptz;
begin
  select * into v_assessment
  from public.assessments
  where id = p_assessment and tenant_id = private.tenant_id();
  if not found then
    raise exception 'Assessment not found' using errcode = 'no_data_found';
  end if;
  if not private.enrolled_in_offering(v_assessment.offering_id)
     or (v_assessment.section_id is not null and not private.enrolled_in_section(v_assessment.section_id)) then
    raise exception 'You are not enrolled for this assessment' using errcode = 'insufficient_privilege';
  end if;
  if v_assessment.status <> 'published' then
    raise exception 'This assessment is not open' using errcode = 'check_violation';
  end if;

  select * into v_submission
  from public.submissions
  where assessment_id = p_assessment and student_id = v_me and status = 'in_progress';
  if found then
    return v_submission;
  end if;

  v_closes := coalesce(v_assessment.closes_at, v_assessment.due_at);
  if (v_assessment.opens_at is not null and now() < v_assessment.opens_at)
     or (v_closes is not null and now() >= v_closes) then
    raise exception 'This assessment is not open' using errcode = 'check_violation';
  end if;

  select count(*) into v_attempts
  from public.submissions
  where assessment_id = p_assessment and student_id = v_me;
  if v_attempts >= v_assessment.max_attempts then
    raise exception 'No attempts left' using errcode = 'check_violation';
  end if;

  v_deadline := case
    when v_assessment.time_limit_minutes is null then v_closes
    else least(coalesce(v_closes, 'infinity'), now() + make_interval(mins => v_assessment.time_limit_minutes))
  end;

  insert into public.submissions (tenant_id, assessment_id, offering_id, student_id, attempt_no, deadline_at)
  values (v_assessment.tenant_id, v_assessment.id, v_assessment.offering_id, v_me, v_attempts + 1, v_deadline)
  returning * into v_submission;

  insert into public.submission_answers (tenant_id, submission_id, assessment_question_id, question_id, position)
  select v_assessment.tenant_id, v_submission.id, picked.id, picked.question_id,
         row_number() over (order by case when v_assessment.shuffle_questions then random() else picked.position end)
  from (
    select aq.id, aq.question_id, aq.position::double precision as position
    from public.assessment_questions aq
    where aq.assessment_id = v_assessment.id
    order by case when v_assessment.questions_per_attempt is not null then random() else aq.position end
    limit v_assessment.questions_per_attempt
  ) picked;

  return v_submission;
end;
$$;

-- Finishes an attempt and scores the deterministic questions straight away (paper 6.9 step 4).
-- Scores stay hidden from the student until the teacher releases grades.
create function public.submit_attempt(p_submission uuid)
returns public.submissions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_submission public.submissions;
  v_assessment public.assessments;
begin
  select * into v_submission
  from public.submissions
  where id = p_submission and student_id = auth.uid()
  for update;
  if not found then
    raise exception 'Submission not found' using errcode = 'no_data_found';
  end if;
  if v_submission.status <> 'in_progress' then
    raise exception 'This attempt has already been submitted' using errcode = 'check_violation';
  end if;
  select * into v_assessment from public.assessments where id = v_submission.assessment_id;

  insert into public.answer_scores (submission_answer_id, tenant_id, points, is_correct, source)
  select sa.id, sa.tenant_id,
         case when private.answer_matches(q.type, sa.response, k.answer) then aq.points else 0 end,
         private.answer_matches(q.type, sa.response, k.answer),
         'auto'
  from public.submission_answers sa
  join public.questions q on q.id = sa.question_id
  join public.question_answer_keys k on k.question_id = q.id
  join public.assessment_questions aq on aq.id = sa.assessment_question_id
  where sa.submission_id = v_submission.id
    and q.type in ('mcq_single', 'mcq_multi', 'true_false', 'matching')
  on conflict (submission_answer_id) do nothing;

  update public.submissions
  set status = 'submitted',
      submitted_at = now(),
      is_late = v_assessment.due_at is not null and now() > v_assessment.due_at
  where id = v_submission.id
  returning * into v_submission;

  return v_submission;
end;
$$;

revoke execute on function public.start_attempt(uuid), public.submit_attempt(uuid) from public, anon;
grant execute on function public.start_attempt(uuid), public.submit_attempt(uuid) to authenticated;

-- Helpers that keep the policies below short. They bypass RLS, so each one checks the caller.
create function private.owns_open_submission(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.submissions s
    where s.id = p_submission
      and s.student_id = (select auth.uid())
      and s.status = 'in_progress'
      and (s.deadline_at is null or s.deadline_at > now())
  )
$$;

create function private.teaches_submission(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.submissions s
    where s.id = p_submission and private.teaches_offering(s.offering_id)
  )
$$;

-- The caller's own answer, in an assessment whose grades have been released.
create function private.released_own_answer(p_submission_answer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.submission_answers sa
    join public.submissions s on s.id = sa.submission_id
    join public.assessments a on a.id = s.assessment_id
    where sa.id = p_submission_answer
      and s.student_id = (select auth.uid())
      and a.grades_released_at <= now()
  )
$$;

create function private.teaches_submission_answer(p_submission_answer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.submission_answers sa
    join public.submissions s on s.id = sa.submission_id
    where sa.id = p_submission_answer and private.teaches_offering(s.offering_id)
  )
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.material_folders enable row level security;
alter table public.materials enable row level security;
alter table public.material_versions enable row level security;
alter table public.topics enable row level security;
alter table public.rubrics enable row level security;
alter table public.rubric_criteria enable row level security;
alter table public.assessments enable row level security;
alter table public.questions enable row level security;
alter table public.question_answer_keys enable row level security;
alter table public.question_tags enable row level security;
alter table public.assessment_questions enable row level security;
alter table public.model_answers enable row level security;
alter table public.submissions enable row level security;
alter table public.submission_answers enable row level security;
alter table public.submission_files enable row level security;
alter table public.answer_scores enable row level security;
alter table public.rubric_scores enable row level security;
alter table public.grade_reviews enable row level security;

create policy "teachers and released-to students read folders" on public.material_folders
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.teaches_offering(offering_id)
      or (private.enrolled_in_offering(offering_id) and (release_at is null or release_at <= now()))
    )
  );
create policy "teachers write folders" on public.material_folders
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

create policy "teachers and released-to students read materials" on public.materials
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.teaches_offering(offering_id)
      or (
        is_published
        and (release_at is null or release_at <= now())
        and private.enrolled_in_offering(offering_id)
      )
    )
  );
create policy "teachers write materials" on public.materials
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

-- Child rows follow their parent: the EXISTS sub-query runs under the parent's own policies.
create policy "readers of a material read its versions" on public.material_versions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.materials m where m.id = material_versions.material_id)
  );
create policy "teachers write material versions" on public.material_versions
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.materials m
      where m.id = material_versions.material_id and private.teaches_offering(m.offering_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.materials m
      where m.id = material_versions.material_id and private.teaches_offering(m.offering_id)
    )
  );

create policy "members read topics" on public.topics
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "teachers and academic managers write topics" on public.topics
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (private.teaches_course(course_id) or (select private.has_permission('academic.manage')))
  )
  with check (
    tenant_id = (select private.tenant_id())
    and (private.teaches_course(course_id) or (select private.has_permission('academic.manage')))
  );

create policy "teachers and enrolled students read rubrics" on public.rubrics
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (private.teaches_offering(offering_id) or private.enrolled_in_offering(offering_id))
  );
create policy "teachers write rubrics" on public.rubrics
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

create policy "readers of a rubric read its criteria" on public.rubric_criteria
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.rubrics r where r.id = rubric_criteria.rubric_id)
  );
create policy "teachers write rubric criteria" on public.rubric_criteria
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.rubrics r
      where r.id = rubric_criteria.rubric_id and private.teaches_offering(r.offering_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.rubrics r
      where r.id = rubric_criteria.rubric_id and private.teaches_offering(r.offering_id)
    )
  );

create policy "teachers and enrolled students read assessments" on public.assessments
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.teaches_offering(offering_id)
      or (
        status <> 'draft'
        and private.enrolled_in_offering(offering_id)
        and (section_id is null or private.enrolled_in_section(section_id))
      )
    )
  );
create policy "teachers write assessments" on public.assessments
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

-- A student sees a question only once it has been dealt to them in one of their attempts.
create policy "teachers and students who were dealt it read a question" on public.questions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.teaches_course(course_id)
      or exists (
        select 1 from public.submission_answers sa
        join public.submissions s on s.id = sa.submission_id
        where sa.question_id = questions.id and s.student_id = (select auth.uid())
      )
    )
  );
create policy "teachers write questions" on public.questions
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_course(course_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_course(course_id));

create policy "teachers, and students after release, read answer keys" on public.question_answer_keys
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      exists (
        select 1 from public.questions q
        where q.id = question_answer_keys.question_id and private.teaches_course(q.course_id)
      )
      or exists (
        select 1
        from public.submission_answers sa
        join public.submissions s on s.id = sa.submission_id
        join public.assessments a on a.id = s.assessment_id
        where sa.question_id = question_answer_keys.question_id
          and s.student_id = (select auth.uid())
          and a.model_answers_release_at <= now()
      )
    )
  );
create policy "teachers write answer keys" on public.question_answer_keys
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.questions q
      where q.id = question_answer_keys.question_id and private.teaches_course(q.course_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.questions q
      where q.id = question_answer_keys.question_id and private.teaches_course(q.course_id)
    )
  );

create policy "readers of a question read its tags" on public.question_tags
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.questions q where q.id = question_tags.question_id)
  );
create policy "teachers write question tags" on public.question_tags
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.questions q
      where q.id = question_tags.question_id and private.teaches_course(q.course_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.questions q
      where q.id = question_tags.question_id and private.teaches_course(q.course_id)
    )
  );

create policy "teachers and students who were dealt it read assessment items" on public.assessment_questions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      exists (
        select 1 from public.assessments a
        where a.id = assessment_questions.assessment_id and private.teaches_offering(a.offering_id)
      )
      or exists (
        select 1 from public.submission_answers sa
        join public.submissions s on s.id = sa.submission_id
        where sa.assessment_question_id = assessment_questions.id and s.student_id = (select auth.uid())
      )
    )
  );
create policy "teachers write assessment items" on public.assessment_questions
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.assessments a
      where a.id = assessment_questions.assessment_id and private.teaches_offering(a.offering_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.assessments a
      where a.id = assessment_questions.assessment_id and private.teaches_offering(a.offering_id)
    )
  );

create policy "teachers, and students after release, read model answers" on public.model_answers
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.assessments a
      where a.id = model_answers.assessment_id
        and (
          private.teaches_offering(a.offering_id)
          or (
            model_answers.approved_at is not null
            and a.model_answers_release_at <= now()
            and private.enrolled_in_offering(a.offering_id)
          )
        )
    )
  );
create policy "teachers write model answers" on public.model_answers
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.assessments a
      where a.id = model_answers.assessment_id and private.teaches_offering(a.offering_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.assessments a
      where a.id = model_answers.assessment_id and private.teaches_offering(a.offering_id)
    )
  );

-- Students create and finish attempts only through start_attempt and submit_attempt.
create policy "students, their teachers and record holders read attempts" on public.submissions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      student_id = (select auth.uid())
      or private.teaches_offering(offering_id)
      or private.has_record_grant(student_id)
    )
  );
create policy "teachers update attempts" on public.submissions
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

create policy "students and their teachers read answers" on public.submission_answers
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      exists (
        select 1 from public.submissions s
        where s.id = submission_answers.submission_id and s.student_id = (select auth.uid())
      )
      or private.teaches_submission(submission_id)
    )
  );
-- Autosave. Column privileges below limit students to the response fields.
create policy "students save answers until the deadline" on public.submission_answers
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.owns_open_submission(submission_id))
  with check (tenant_id = (select private.tenant_id()) and private.owns_open_submission(submission_id));

create policy "students and their teachers read uploads" on public.submission_files
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      exists (
        select 1 from public.submissions s
        where s.id = submission_files.submission_id and s.student_id = (select auth.uid())
      )
      or private.teaches_submission(submission_id)
    )
  );
create policy "students upload until the deadline" on public.submission_files
  for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and private.owns_open_submission(submission_id));
create policy "students remove uploads until the deadline" on public.submission_files
  for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and private.owns_open_submission(submission_id));

create policy "teachers, and students after release, read answer scores" on public.answer_scores
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.teaches_submission_answer(submission_answer_id)
      or private.released_own_answer(submission_answer_id)
    )
  );
create policy "teachers write answer scores" on public.answer_scores
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_submission_answer(submission_answer_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_submission_answer(submission_answer_id));

create policy "teachers, and students after release, read rubric scores" on public.rubric_scores
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.teaches_submission_answer(submission_answer_id)
      or private.released_own_answer(submission_answer_id)
    )
  );
create policy "teachers write rubric scores" on public.rubric_scores
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_submission_answer(submission_answer_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_submission_answer(submission_answer_id));

create policy "students and their teachers read grade reviews" on public.grade_reviews
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (student_id = (select auth.uid()) or private.teaches_offering(offering_id))
  );
create policy "students appeal their own published grades" on public.grade_reviews
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and student_id = (select auth.uid())
    and status = 'open'
    and reviewer_id is null
    and resolution is null
    and resulting_grade_entry_id is null
    and exists (
      select 1 from public.grade_entries g
      where g.id = grade_reviews.grade_entry_id
        and g.student_id = (select auth.uid())
        and g.offering_id = grade_reviews.offering_id
        and g.status = 'published'
    )
  );
create policy "teachers resolve grade reviews" on public.grade_reviews
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));

-- Students may only change the response fields of their own answers.
revoke update on public.submission_answers from authenticated;
grant update (response, response_text, saved_at) on public.submission_answers to authenticated;
-- Teachers move an attempt to graded; who made it and when stay fixed.
revoke update on public.submissions from authenticated;
grant update (status) on public.submissions to authenticated;
