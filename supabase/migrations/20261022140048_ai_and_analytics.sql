-- AI and analytics (paper 4.2, 4.3, 6.5, 7.1 to 7.7): model registry, prompt templates, AI
-- feature switches and budgets, the document corpus with hybrid retrieval, interaction logs
-- and feedback, aggregated question clusters, AI grading suggestions and calibration, and
-- explainable risk scores with an action path.
--
-- Every AI answer or score stores the model version, the inputs used (document versions or
-- feature values) and the user action that followed (paper 6.5).
-- Ingestion, the AI gateway and the prediction service write with the service role;
-- signed-in users only read, review and give feedback.

create type public.model_provider as enum ('openai', 'anthropic', 'azure_openai', 'google', 'ollama', 'local', 'internal');
create type public.model_purpose as enum (
  'chat', 'embedding', 'reranker', 'grading', 'classification', 'transcription', 'risk_prediction', 'forecast'
);
create type public.model_status as enum ('active', 'deprecated', 'blocked');
create type public.ai_feature as enum (
  'student_assistant', 'study_assistant', 'teacher_generation', 'ai_grading', 'question_analyser',
  'risk_prediction', 'admin_assistant', 'feedback_intelligence', 'workflow_automation', 'it_anomaly_detection'
);
create type public.budget_scope as enum ('tenant', 'role', 'user');
create type public.budget_period as enum ('day', 'month');
create type public.document_kind as enum (
  'regulation', 'policy', 'faq', 'calendar', 'fees', 'registration', 'admission', 'internship',
  'grading_criteria', 'course_material', 'other'
);
create type public.document_scope as enum ('tenant', 'department', 'offering');
create type public.document_status as enum ('draft', 'published', 'archived');
-- The five question families of paper 4.1.1, each with its own data path.
create type public.question_family as enum (
  'personal_facts', 'institutional_knowledge', 'course_content', 'advising', 'people_and_events', 'other'
);
create type public.interaction_status as enum ('answered', 'declined', 'fallback', 'blocked', 'error');
create type public.suggestion_status as enum ('pending_review', 'accepted', 'modified', 'rejected');
create type public.calibration_decision as enum ('proceed', 'adjust_rubric', 'disable');
create type public.risk_band as enum ('low', 'medium', 'high');
create type public.risk_alert_status as enum ('open', 'contacted', 'resolved', 'dismissed');

create table public.model_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  provider public.model_provider not null,
  model_name text not null,
  version text not null,
  purpose public.model_purpose not null,
  is_local boolean not null default false,
  data_region text,
  -- Grading and prediction models fall in the EU AI Act's high-risk area (paper 8.1).
  is_high_risk boolean not null default false,
  -- One-page model card: purpose, data, users affected, known limits (paper 8.4).
  model_card jsonb not null default '{}'::jsonb,
  status public.model_status not null default 'active',
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, provider, model_name, version, purpose)
);

create table public.prompt_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  key text not null,
  description text,
  unique (id, tenant_id),
  unique (tenant_id, key)
);

create table public.prompt_template_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  template_id uuid not null,
  version integer not null check (version > 0),
  body text not null,
  is_active boolean not null default false,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (template_id, version),
  foreign key (template_id, tenant_id) references public.prompt_templates (id, tenant_id) on delete cascade
);
create unique index prompt_template_versions_one_active on public.prompt_template_versions (template_id) where is_active;
create index on public.prompt_template_versions (template_id, tenant_id);

-- AI features can be switched on or off per role and per course (paper 4.3, 8.2).
-- A row with role_key and offering_id null is the tenant default.
create table public.ai_feature_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  feature public.ai_feature not null,
  role_key text,
  offering_id uuid,
  enabled boolean not null,
  model_version_id uuid,
  -- Feature options, for example {"mode": "hints_first"} for the study assistant.
  settings jsonb not null default '{}'::jsonb,
  consent_text text,
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (tenant_id, feature, role_key, offering_id),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (model_version_id, tenant_id) references public.model_versions (id, tenant_id) on delete set null (model_version_id)
);
create index on public.ai_feature_settings (offering_id, tenant_id);
create index on public.ai_feature_settings (model_version_id, tenant_id);

create table public.ai_budgets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  scope public.budget_scope not null,
  role_key text,
  user_id uuid,
  period public.budget_period not null,
  token_limit bigint check (token_limit > 0),
  cost_limit_usd numeric(12, 2) check (cost_limit_usd > 0),
  -- Running totals kept by the AI gateway for the current period.
  period_start date not null default current_date,
  spent_tokens bigint not null default 0,
  spent_usd numeric(12, 4) not null default 0,
  updated_at timestamptz not null default now(),
  check ((scope = 'role') = (role_key is not null)),
  check ((scope = 'user') = (user_id is not null)),
  check (token_limit is not null or cost_limit_usd is not null),
  unique nulls not distinct (tenant_id, scope, role_key, user_id, period),
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.ai_budgets (user_id, tenant_id);

-- Institutional and course documents the assistants answer from. Regulations and
-- announcements are versioned with effective dates (paper 4.3).
create table public.documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.document_kind not null,
  scope public.document_scope not null,
  department_id uuid,
  offering_id uuid,
  -- Set when the document is the indexed text of a course material.
  material_id uuid,
  title text not null,
  -- Role keys allowed to retrieve it; null means everyone in scope.
  audience_roles text[],
  status public.document_status not null default 'draft',
  owner_id uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  check ((scope = 'department') = (department_id is not null)),
  check ((scope = 'offering') = (offering_id is not null)),
  foreign key (department_id, tenant_id) references public.departments (id, tenant_id) on delete cascade,
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (material_id, tenant_id) references public.materials (id, tenant_id) on delete cascade
);
create index on public.documents (department_id, tenant_id);
create index on public.documents (offering_id, tenant_id);
create index on public.documents (material_id, tenant_id);

create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  document_id uuid not null,
  version integer not null check (version > 0),
  effective_from date not null,
  effective_until date,
  language text not null default 'en',
  storage_path text,
  content_hash text,
  published_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (document_id, version),
  check (effective_until is null or effective_until >= effective_from),
  foreign key (document_id, tenant_id) references public.documents (id, tenant_id) on delete cascade
);
create index on public.document_versions (document_id, tenant_id);

create table public.chunks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  document_version_id uuid not null,
  -- Copied from the document by trigger, so retrieval can filter without joins.
  document_id uuid not null,
  offering_id uuid,
  chunk_index integer not null,
  content text not null,
  token_count integer,
  -- 'simple' configuration: no stemming, so Arabic and English text are both searchable.
  fts tsvector generated always as (to_tsvector('simple'::regconfig, content)) stored,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (document_version_id, chunk_index),
  foreign key (document_version_id, tenant_id) references public.document_versions (id, tenant_id) on delete cascade,
  foreign key (document_id, tenant_id) references public.documents (id, tenant_id) on delete cascade,
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade
);
create index on public.chunks using gin (fts);
create index on public.chunks (document_version_id, tenant_id);
create index on public.chunks (document_id, tenant_id);
create index on public.chunks (offering_id, tenant_id);

create function private.fill_chunk_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select d.id, d.offering_id into new.document_id, new.offering_id
  from public.document_versions v join public.documents d on d.id = v.document_id
  where v.id = new.document_version_id;
  return new;
end;
$$;

create trigger chunks_fill_scope before insert or update of document_version_id on public.chunks
  for each row execute function private.fill_chunk_scope();

-- 1024 dimensions is offered by hosted embedding models (OpenAI text-embedding-3 with the
-- dimensions parameter, Voyage, Cohere) and by local ones (bge-m3, mxbai-embed-large).
-- Each embedding records the model that produced it, so models can be swapped and compared.
create table public.chunk_embeddings (
  chunk_id uuid not null,
  model_version_id uuid not null,
  tenant_id uuid not null,
  embedding extensions.vector(1024) not null,
  created_at timestamptz not null default now(),
  primary key (chunk_id, model_version_id),
  foreign key (chunk_id, tenant_id) references public.chunks (id, tenant_id) on delete cascade,
  foreign key (model_version_id, tenant_id) references public.model_versions (id, tenant_id)
);
create index on public.chunk_embeddings using hnsw (embedding extensions.vector_cosine_ops);
create index on public.chunk_embeddings (chunk_id, tenant_id);
create index on public.chunk_embeddings (model_version_id, tenant_id);

create table public.ai_interactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid not null,
  feature public.ai_feature not null,
  question_family public.question_family,
  conversation_id uuid,
  offering_id uuid,
  request_text text,
  response_text text,
  status public.interaction_status not null,
  model_version_id uuid,
  prompt_template_version_id uuid,
  -- Tools called and the scope each ran with, never the raw records returned.
  tool_calls jsonb not null default '[]'::jsonb,
  -- Result of the claim-support check (paper 7.2 step 6).
  verification jsonb,
  latency_ms integer check (latency_ms >= 0),
  input_tokens integer check (input_tokens >= 0),
  output_tokens integer check (output_tokens >= 0),
  cost_usd numeric(12, 6) check (cost_usd >= 0),
  -- What the user did next: accepted, edited, escalated to a person, ignored.
  user_action text,
  created_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete set null (offering_id),
  foreign key (model_version_id, tenant_id) references public.model_versions (id, tenant_id),
  foreign key (prompt_template_version_id, tenant_id) references public.prompt_template_versions (id, tenant_id)
);
create index on public.ai_interactions (user_id, tenant_id, created_at desc);
create index on public.ai_interactions (tenant_id, created_at desc);
create index on public.ai_interactions (offering_id, tenant_id);
create index on public.ai_interactions (model_version_id, tenant_id);
create index on public.ai_interactions (prompt_template_version_id, tenant_id);
create index on public.ai_interactions (conversation_id);

create table public.ai_interaction_sources (
  interaction_id uuid not null,
  chunk_id uuid not null,
  tenant_id uuid not null,
  document_version_id uuid not null,
  rank smallint not null,
  score double precision,
  primary key (interaction_id, chunk_id),
  foreign key (interaction_id, tenant_id) references public.ai_interactions (id, tenant_id) on delete cascade,
  foreign key (chunk_id, tenant_id) references public.chunks (id, tenant_id),
  foreign key (document_version_id, tenant_id) references public.document_versions (id, tenant_id)
);
create index on public.ai_interaction_sources (chunk_id, tenant_id);
create index on public.ai_interaction_sources (document_version_id, tenant_id);
create index on public.ai_interaction_sources (interaction_id, tenant_id);

create table public.ai_feedback (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  interaction_id uuid not null,
  user_id uuid not null default auth.uid(),
  rating smallint not null check (rating in (-1, 1)),
  comment text,
  created_at timestamptz not null default now(),
  unique (interaction_id, user_id),
  foreign key (interaction_id, tenant_id) references public.ai_interactions (id, tenant_id) on delete cascade,
  foreign key (user_id, tenant_id) references public.users (id, tenant_id) on delete cascade
);
create index on public.ai_feedback (interaction_id, tenant_id);
create index on public.ai_feedback (user_id, tenant_id);

-- Output of the student-question analyser: aggregated and de-identified before a teacher
-- sees it (paper 4.2, 7.5).
create table public.ai_question_clusters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  offering_id uuid not null,
  topic_id uuid,
  period_start date not null,
  period_end date not null,
  label text not null,
  summary text,
  question_count integer not null check (question_count >= 0),
  -- Paraphrased examples with personal details removed.
  example_questions jsonb not null default '[]'::jsonb,
  model_version_id uuid,
  created_at timestamptz not null default now(),
  check (period_end >= period_start),
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (topic_id, tenant_id) references public.topics (id, tenant_id) on delete set null (topic_id),
  foreign key (model_version_id, tenant_id) references public.model_versions (id, tenant_id)
);
create index on public.ai_question_clusters (offering_id, tenant_id, period_end desc);
create index on public.ai_question_clusters (topic_id, tenant_id);
create index on public.ai_question_clusters (model_version_id, tenant_id);

-- AI-proposed scores. Visible only to the teacher until approved; students see the
-- teacher-approved score in answer_scores and rubric_scores (paper 7.3).
create table public.ai_grade_suggestions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  submission_answer_id uuid not null,
  offering_id uuid not null,
  model_version_id uuid not null,
  prompt_template_version_id uuid,
  -- [{"criterion_id": ..., "points": n, "rationale": "...", "quote": "..."}]
  criterion_scores jsonb not null default '[]'::jsonb,
  total_points numeric(7, 2) not null check (total_points >= 0),
  -- Agreement across independent passes with shuffled order lowers or raises this.
  confidence numeric(4, 3) not null check (confidence between 0 and 1),
  passes smallint not null default 1 check (passes > 0),
  -- Machine transcription of handwritten work, for the teacher to check.
  transcription text,
  flags jsonb not null default '[]'::jsonb,
  status public.suggestion_status not null default 'pending_review',
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (status = 'pending_review' or (reviewed_by is not null and reviewed_at is not null)),
  foreign key (submission_answer_id, tenant_id) references public.submission_answers (id, tenant_id) on delete cascade,
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id),
  foreign key (model_version_id, tenant_id) references public.model_versions (id, tenant_id),
  foreign key (prompt_template_version_id, tenant_id) references public.prompt_template_versions (id, tenant_id)
);
create index on public.ai_grade_suggestions (submission_answer_id, tenant_id);
create index on public.ai_grade_suggestions (offering_id, tenant_id, status);
create index on public.ai_grade_suggestions (model_version_id, tenant_id);
create index on public.ai_grade_suggestions (prompt_template_version_id, tenant_id);

-- Before release the teacher grades a sample; the system reports agreement and the teacher
-- decides whether to proceed (paper 7.3).
create table public.grading_calibrations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  assessment_id uuid not null,
  question_id uuid,
  model_version_id uuid not null,
  sample_size integer not null check (sample_size > 0),
  agreement_rate numeric(4, 3) check (agreement_rate between 0 and 1),
  mean_abs_difference numeric(7, 2),
  decision public.calibration_decision,
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (assessment_id, tenant_id) references public.assessments (id, tenant_id) on delete cascade,
  foreign key (question_id, tenant_id) references public.questions (id, tenant_id),
  foreign key (model_version_id, tenant_id) references public.model_versions (id, tenant_id)
);
create index on public.grading_calibrations (assessment_id, tenant_id);
create index on public.grading_calibrations (question_id, tenant_id);
create index on public.grading_calibrations (model_version_id, tenant_id);

-- A risk band plus the factors behind it, never only a number (paper 7.6).
create table public.risk_scores (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  student_id uuid not null,
  -- Null for programme-level risk; otherwise risk in one course.
  offering_id uuid,
  term_id uuid,
  model_version_id uuid not null,
  band public.risk_band not null,
  score numeric(5, 4) not null check (score between 0 and 1),
  -- Feature values used, so the score can be explained and contested later.
  features jsonb not null,
  computed_at timestamptz not null default now(),
  unique (id, tenant_id),
  foreign key (student_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (offering_id, tenant_id) references public.course_offerings (id, tenant_id) on delete cascade,
  foreign key (term_id, tenant_id) references public.terms (id, tenant_id),
  foreign key (model_version_id, tenant_id) references public.model_versions (id, tenant_id)
);
create index on public.risk_scores (student_id, tenant_id, computed_at desc);
create index on public.risk_scores (offering_id, tenant_id, band);
create index on public.risk_scores (term_id, tenant_id);
create index on public.risk_scores (model_version_id, tenant_id);

create table public.risk_factors (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  risk_score_id uuid not null,
  rank smallint not null,
  factor text not null,
  contribution numeric(6, 4) not null,
  explanation text not null,
  unique (risk_score_id, rank),
  foreign key (risk_score_id, tenant_id) references public.risk_scores (id, tenant_id) on delete cascade
);
create index on public.risk_factors (risk_score_id, tenant_id);

-- Every alert has an owner and a next step; an alert nobody must act on is noise (paper 7.6).
create table public.risk_alerts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  risk_score_id uuid not null,
  student_id uuid not null,
  owner_id uuid not null,
  next_step text not null,
  status public.risk_alert_status not null default 'open',
  due_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  foreign key (risk_score_id, tenant_id) references public.risk_scores (id, tenant_id) on delete cascade,
  foreign key (student_id, tenant_id) references public.users (id, tenant_id) on delete cascade,
  foreign key (owner_id, tenant_id) references public.users (id, tenant_id)
);
create index on public.risk_alerts (owner_id, tenant_id, status);
create index on public.risk_alerts (student_id, tenant_id);
create index on public.risk_alerts (risk_score_id, tenant_id);

create trigger documents_touch before update on public.documents
  for each row execute function private.touch_updated_at();
create trigger ai_feature_settings_touch before update on public.ai_feature_settings
  for each row execute function private.touch_updated_at();
create trigger ai_budgets_touch before update on public.ai_budgets
  for each row execute function private.touch_updated_at();
create trigger risk_scores_append_only before update or delete on public.risk_scores
  for each row execute function private.reject_change();
create trigger risk_factors_append_only before update or delete on public.risk_factors
  for each row execute function private.reject_change();

create trigger model_versions_audit after insert or update or delete on public.model_versions
  for each row execute function private.audit_row_change();
create trigger prompt_template_versions_audit after insert or update on public.prompt_template_versions
  for each row execute function private.audit_row_change();
create trigger ai_feature_settings_audit after insert or update or delete on public.ai_feature_settings
  for each row execute function private.audit_row_change();
create trigger ai_budgets_audit after insert or delete or update of token_limit, cost_limit_usd on public.ai_budgets
  for each row execute function private.audit_row_change();
create trigger ai_grade_suggestions_audit after update of status on public.ai_grade_suggestions
  for each row execute function private.audit_row_change();
create trigger grading_calibrations_audit after update of decision on public.grading_calibrations
  for each row execute function private.audit_row_change();
create trigger risk_alerts_audit after insert or update on public.risk_alerts
  for each row execute function private.audit_row_change();

-- ---------------------------------------------------------------------------
-- Retrieval (paper 7.2). The function runs with the caller's rights, so row-level security
-- on chunks restricts the search to documents the caller may see before anything is
-- retrieved: their tenant, their courses, their department and roles, the effective date.
-- Hybrid search: vector and keyword results fused by reciprocal rank.
-- ---------------------------------------------------------------------------

create function private.has_any_role(p_role_keys text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = (select auth.uid())
      and r.key = any (p_role_keys)
      and (ur.expires_at is null or ur.expires_at > now())
  )
$$;

create function private.can_write_document(p_document uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('ai.knowledge.manage')
    or exists (
      select 1 from public.documents d
      where d.id = p_document and d.scope = 'offering' and private.teaches_offering(d.offering_id)
    )
$$;

create function private.min_group_size()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select t.min_group_size from public.tenants t where t.id = private.tenant_id()
$$;

create function public.match_chunks(
  p_model_version uuid,
  p_query_embedding extensions.vector(1024),
  p_query_text text,
  p_match_count integer default 8,
  p_offering uuid default null,
  p_on date default current_date
)
returns table (
  chunk_id uuid,
  document_id uuid,
  document_version_id uuid,
  content text,
  score double precision
)
language plpgsql
set search_path = ''
as $$
begin
  -- Keep scanning the HNSW index until enough rows survive the policy filters (pgvector 0.8+).
  if exists (select 1 from pg_catalog.pg_settings where name = 'hnsw.iterative_scan') then
    perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  end if;

  return query
  with eligible as (
    select c.id
    from public.chunks c
    join public.document_versions v on v.id = c.document_version_id
    where v.published_at is not null
      and v.effective_from <= p_on
      and (v.effective_until is null or v.effective_until >= p_on)
      and (p_offering is null or c.offering_id = p_offering)
  ),
  semantic as (
    select e.chunk_id as id,
           row_number() over (order by e.embedding operator(extensions.<=>) p_query_embedding) as rank
    from public.chunk_embeddings e
    where e.model_version_id = p_model_version
      and e.chunk_id in (select id from eligible)
    order by e.embedding operator(extensions.<=>) p_query_embedding
    limit p_match_count * 4
  ),
  keyword as (
    select c.id,
           row_number() over (order by ts_rank_cd(c.fts, q.query) desc) as rank
    from public.chunks c
    cross join websearch_to_tsquery('simple'::regconfig, coalesce(p_query_text, '')) as q (query)
    where c.fts @@ q.query
      and c.id in (select id from eligible)
    order by ts_rank_cd(c.fts, q.query) desc
    limit p_match_count * 4
  )
  select c.id, c.document_id, c.document_version_id, c.content,
         (coalesce(1.0 / (60 + s.rank), 0) + coalesce(1.0 / (60 + k.rank), 0))::double precision as score
  from semantic s
  full join keyword k on k.id = s.id
  join public.chunks c on c.id = coalesce(s.id, k.id)
  order by score desc
  limit p_match_count;
end;
$$;

revoke execute on function public.match_chunks(uuid, extensions.vector, text, integer, uuid, date) from public, anon;
grant execute on function public.match_chunks(uuid, extensions.vector, text, integer, uuid, date) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.model_versions enable row level security;
alter table public.prompt_templates enable row level security;
alter table public.prompt_template_versions enable row level security;
alter table public.ai_feature_settings enable row level security;
alter table public.ai_budgets enable row level security;
alter table public.documents enable row level security;
alter table public.document_versions enable row level security;
alter table public.chunks enable row level security;
alter table public.chunk_embeddings enable row level security;
alter table public.ai_interactions enable row level security;
alter table public.ai_interaction_sources enable row level security;
alter table public.ai_feedback enable row level security;
alter table public.ai_question_clusters enable row level security;
alter table public.ai_grade_suggestions enable row level security;
alter table public.grading_calibrations enable row level security;
alter table public.risk_scores enable row level security;
alter table public.risk_factors enable row level security;
alter table public.risk_alerts enable row level security;

-- Users can see which models serve them (transparency); only AI managers change them.
create policy "members read the model registry" on public.model_versions
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "AI managers manage the model registry" on public.model_versions
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')));

-- Prompts stay with AI managers, which limits system prompt leakage (paper 7.9).
create policy "AI managers manage prompt templates" on public.prompt_templates
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')));
create policy "AI managers manage prompt versions" on public.prompt_template_versions
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')));

create policy "members read AI feature settings" on public.ai_feature_settings
  for select to authenticated
  using (tenant_id = (select private.tenant_id()));
create policy "AI managers write AI feature settings" on public.ai_feature_settings
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')));
-- A teacher can switch student-facing AI off, or into a stricter mode, for their course.
-- The gateway treats an offering row as narrowing what the tenant and role rows allow,
-- never widening it.
create policy "teachers set course-level AI switches" on public.ai_feature_settings
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and offering_id is not null
    and private.teaches_offering(offering_id)
    and feature in ('student_assistant', 'study_assistant', 'question_analyser')
  )
  with check (
    tenant_id = (select private.tenant_id())
    and offering_id is not null
    and private.teaches_offering(offering_id)
    and feature in ('student_assistant', 'study_assistant', 'question_analyser')
    and model_version_id is null
  );

create policy "AI managers and budget holders read budgets" on public.ai_budgets
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and ((select private.has_permission('ai.settings.manage')) or user_id = (select auth.uid()))
  );
create policy "AI managers write budgets" on public.ai_budgets
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')))
  with check (tenant_id = (select private.tenant_id()) and (select private.has_permission('ai.settings.manage')));

create policy "documents are visible within their scope" on public.documents
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      private.can_write_document(id)
      or (
        status = 'published'
        and (audience_roles is null or private.has_any_role(audience_roles))
        and (
          scope = 'tenant'
          or (scope = 'department' and private.in_department(department_id))
          or (scope = 'offering' and private.enrolled_in_offering(offering_id))
        )
      )
    )
  );
create policy "knowledge managers and course teachers write documents" on public.documents
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('ai.knowledge.manage'))
      or (scope = 'offering' and private.teaches_offering(offering_id))
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and (
      (select private.has_permission('ai.knowledge.manage'))
      or (scope = 'offering' and private.teaches_offering(offering_id))
    )
  );

create policy "readers of a document read its published versions" on public.document_versions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.documents d
      where d.id = document_versions.document_id
        and (document_versions.published_at is not null or private.can_write_document(d.id))
    )
  );
create policy "document writers write versions" on public.document_versions
  for all to authenticated
  using (tenant_id = (select private.tenant_id()) and private.can_write_document(document_id))
  with check (tenant_id = (select private.tenant_id()) and private.can_write_document(document_id));

create policy "readers of a version read its chunks" on public.chunks
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.document_versions v where v.id = chunks.document_version_id)
  );
create policy "readers of a chunk read its embeddings" on public.chunk_embeddings
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.chunks c where c.id = chunk_embeddings.chunk_id)
  );

-- Individual chats are not shown to teachers (paper 7.5); auditors can read them.
create policy "users and auditors read interactions" on public.ai_interactions
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (user_id = (select auth.uid()) or (select private.has_permission('audit.read')))
  );
create policy "users record what they did with an answer" on public.ai_interactions
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));

create policy "readers of an interaction read its sources" on public.ai_interaction_sources
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.ai_interactions i where i.id = ai_interaction_sources.interaction_id)
  );

create policy "users and AI managers read feedback" on public.ai_feedback
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (user_id = (select auth.uid()) or (select private.has_permission('ai.settings.manage')))
  );
create policy "users rate their own answers" on public.ai_feedback
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and user_id = (select auth.uid())
    and exists (
      select 1 from public.ai_interactions i
      where i.id = ai_feedback.interaction_id and i.user_id = (select auth.uid())
    )
  );
create policy "users change their own rating" on public.ai_feedback
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and user_id = (select auth.uid()));

-- Small groups are suppressed to prevent re-identification (paper 8.2).
create policy "teachers and analysts read large enough clusters" on public.ai_question_clusters
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and question_count >= (select private.min_group_size())
    and (private.teaches_offering(offering_id) or (select private.has_permission('analytics.view')))
  );

create policy "teachers review AI grade suggestions" on public.ai_grade_suggestions
  for select to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id));
create policy "teachers decide on AI grade suggestions" on public.ai_grade_suggestions
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and private.teaches_offering(offering_id))
  with check (
    tenant_id = (select private.tenant_id())
    and private.teaches_offering(offering_id)
    and (status = 'pending_review' or reviewed_by = (select auth.uid()))
  );

create policy "teachers manage grading calibration" on public.grading_calibrations
  for all to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.assessments a
      where a.id = grading_calibrations.assessment_id and private.teaches_offering(a.offering_id)
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and exists (
      select 1 from public.assessments a
      where a.id = grading_calibrations.assessment_id and private.teaches_offering(a.offering_id)
    )
  );

-- Students see their own prediction only if they opted in (paper 7.6).
create policy "advisors, teachers and consenting students read risk" on public.risk_scores
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      (student_id = (select auth.uid()) and private.has_consent(student_id, 'risk_prediction_display'))
      or private.advises(student_id)
      or (offering_id is not null and private.teaches_offering(offering_id))
      or private.has_record_grant(student_id)
    )
  );
create policy "readers of a risk score read its factors" on public.risk_factors
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and exists (select 1 from public.risk_scores r where r.id = risk_factors.risk_score_id)
  );

create policy "owners and advisors read risk alerts" on public.risk_alerts
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (owner_id = (select auth.uid()) or private.advises(student_id) or private.has_record_grant(student_id))
  );
create policy "owners work their risk alerts" on public.risk_alerts
  for update to authenticated
  using (tenant_id = (select private.tenant_id()) and owner_id = (select auth.uid()))
  with check (tenant_id = (select private.tenant_id()) and owner_id = (select auth.uid()));

-- Users may only record the follow-up action on their own interactions.
revoke update on public.ai_interactions from authenticated;
grant update (user_action) on public.ai_interactions to authenticated;
-- Teachers decide on a suggestion; they cannot rewrite what the model proposed.
revoke update on public.ai_grade_suggestions from authenticated;
grant update (status, reviewed_by, reviewed_at) on public.ai_grade_suggestions to authenticated;
-- Alert owners record progress, not who owns the alert or what it was about.
revoke update on public.risk_alerts from authenticated;
grant update (status, notes, resolved_at) on public.risk_alerts to authenticated;
