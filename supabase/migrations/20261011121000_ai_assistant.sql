-- AI assistant (Dual-RAG, spec §5.10): conversations with the assistant's full JSON
-- response, and a tenant-scoped knowledge base searchable by keyword (Postgres full-text,
-- Arabic or English) and meaning (pgvector), fused with reciprocal rank fusion.

create table app.ai_conversations (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references app.tenants (id),
  audience    text not null check (audience in ('admin', 'shopper')),
  staff_id    uuid,
  customer_id uuid references app.customers (id),
  branch_id   uuid,
  title       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, id),
  check ((audience = 'admin' and staff_id is not null and customer_id is null)
      or (audience = 'shopper' and customer_id is not null and staff_id is null)),
  foreign key (tenant_id, staff_id) references app.staff (tenant_id, id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);

create table app.ai_messages (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null,
  conversation_id      uuid not null,
  role                 text not null check (role in ('user', 'assistant', 'tool', 'system')),
  content              text not null default '',
  response             jsonb,
  pipeline             text check (pipeline in ('analytics', 'public', 'both', 'none')),
  task_type            text check (task_type in ('lookup', 'analysis', 'report', 'chitchat')),
  model                text,
  temperature          numeric(3,2) check (temperature between 0 and 2),
  top_p                numeric(3,2) check (top_p between 0 and 1),
  prompt_tokens        int check (prompt_tokens >= 0),
  completion_tokens    int check (completion_tokens >= 0),
  latency_ms           int check (latency_ms >= 0),
  retrieval_confidence numeric(5,4) check (retrieval_confidence between 0 and 1),
  abstained            boolean not null default false,
  escalated            boolean not null default false,
  created_at           timestamptz not null default now(),
  check (response is null or jsonb_typeof(response) = 'object'),
  check (role <> 'assistant' or coalesce(jsonb_typeof(response -> 'answer') = 'string', false)),
  check (response is null or not (response ? 'citations') or jsonb_typeof(response -> 'citations') = 'array'),
  foreign key (tenant_id, conversation_id) references app.ai_conversations (tenant_id, id) on delete cascade
);
comment on column app.ai_messages.response is
  'The assistant''s full structured output, e.g. {"answer", "citations":[{"chunk_id","document_id","quote"}], "sql", "result":{"columns","rows"}, "chart":{…}, "document":{…}, "abstained"}. Required for assistant messages.';
create index ai_messages_conversation_idx on app.ai_messages (conversation_id, created_at);

create table app.kb_documents (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references app.tenants (id),
  audience       text not null check (audience in ('admin', 'public')),
  doc_type       text not null check (doc_type in ('faq', 'policy', 'catalog', 'glossary', 'report', 'other')),
  title          text not null,
  source_uri     text,
  language       text not null default 'ar' check (language in ('ar', 'en')),
  status         text not null default 'published' check (status in ('draft', 'published', 'superseded')),
  effective_from date,
  effective_to   date,
  version        int not null default 1 check (version > 0),
  metadata       jsonb not null default '{}' check (jsonb_typeof(metadata) = 'object'),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (tenant_id, id),
  unique (id, audience),
  check (effective_to is null or effective_from is null or effective_to >= effective_from)
);

create table app.kb_chunks (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  document_id uuid not null,
  audience    text not null,
  chunk_index int not null check (chunk_index >= 0),
  content     text not null,
  language    text not null check (language in ('ar', 'en')),
  fts         tsvector generated always as (
                case language when 'ar' then to_tsvector('arabic', content)
                              else to_tsvector('english', content) end) stored,
  embedding   extensions.vector(1024),
  metadata    jsonb not null default '{}' check (jsonb_typeof(metadata) = 'object'),
  token_count int check (token_count >= 0),
  created_at  timestamptz not null default now(),
  unique (document_id, chunk_index),
  foreign key (tenant_id, document_id) references app.kb_documents (tenant_id, id) on delete cascade,
  foreign key (document_id, audience) references app.kb_documents (id, audience) on update cascade
);
comment on column app.kb_chunks.embedding is '1024 dimensions; must match the embedding model used for queries (e.g. bge-m3, Voyage, Cohere multilingual, or OpenAI v3 with dimensions=1024).';
create index kb_chunks_fts_idx on app.kb_chunks using gin (fts);
create index kb_chunks_embedding_idx on app.kb_chunks using hnsw (embedding extensions.vector_cosine_ops);
create index kb_chunks_scope_idx on app.kb_chunks (tenant_id, audience);

create trigger ai_conversations_updated_at before update on app.ai_conversations
  for each row execute function app.set_updated_at();
create trigger kb_documents_updated_at before update on app.kb_documents
  for each row execute function app.set_updated_at();

-- Hybrid retrieval: keyword (ts_rank_cd) and vector (cosine) rankings fused with RRF.
-- Security invoker, so RLS applies; the tenant filter also sits inside the query itself
-- (the addendum's "mandatory metadata pre-filter").
create function app.kb_hybrid_search(
  p_query_text       text,
  p_query_embedding  extensions.vector(1024),
  p_match_count      int default 10,
  p_audience         text default null,
  p_full_text_weight float8 default 1,
  p_semantic_weight  float8 default 1,
  p_rrf_k            int default 50
) returns table (chunk_id uuid, document_id uuid, content text, score float8)
language sql
stable
set search_path = pg_catalog, extensions
as $$
  with candidates as (
    select c.id, c.document_id, c.content, c.fts, c.embedding, c.language
      from app.kb_chunks c
      join app.kb_documents d on d.id = c.document_id
     where c.tenant_id = app.current_tenant_id()
       and (p_audience is null or c.audience = p_audience)
       and d.status = 'published'
       and (d.effective_from is null or d.effective_from <= current_date)
       and (d.effective_to is null or d.effective_to >= current_date)
  ),
  queries as (
    select websearch_to_tsquery('arabic', p_query_text) as q_ar,
           websearch_to_tsquery('english', p_query_text) as q_en
  ),
  keyword as (
    select c.id,
           row_number() over (order by ts_rank_cd(c.fts, case c.language when 'ar' then q.q_ar else q.q_en end) desc,
                                       c.id) as rank_ix
      from candidates c, queries q
     where (c.language = 'ar' and c.fts @@ q.q_ar) or (c.language = 'en' and c.fts @@ q.q_en)
     order by rank_ix
     limit least(p_match_count, 30) * 2
  ),
  semantic as (
    select c.id, row_number() over (order by c.embedding <=> p_query_embedding, c.id) as rank_ix
      from candidates c
     where c.embedding is not null
     order by rank_ix
     limit least(p_match_count, 30) * 2
  )
  select c.id, c.document_id, c.content,
         coalesce(p_full_text_weight / (p_rrf_k + k.rank_ix), 0.0)
       + coalesce(p_semantic_weight / (p_rrf_k + s.rank_ix), 0.0) as score
    from keyword k
    full outer join semantic s on s.id = k.id
    join candidates c on c.id = coalesce(k.id, s.id)
   order by score desc, c.id
   limit least(p_match_count, 30)
$$;

alter table app.ai_conversations enable row level security;
alter table app.ai_messages enable row level security;
alter table app.kb_documents enable row level security;
alter table app.kb_chunks enable row level security;

-- A conversation belongs to the staff member or shopper who started it.
create policy ai_conversations_owner on app.ai_conversations for all
  using (tenant_id = (select app.current_tenant_id())
         and ((staff_id is not null and staff_id = (select app.current_staff_id()))
              or (customer_id is not null and customer_id = (select app.current_customer_id()))))
  with check (tenant_id = (select app.current_tenant_id())
              and ((audience = 'admin' and staff_id = (select app.current_staff_id()) and (select app.is_internal()))
                   or (audience = 'shopper' and customer_id = (select app.current_customer_id()))));

create policy ai_messages_via_conversation on app.ai_messages for all
  using (tenant_id = (select app.current_tenant_id())
         and exists (select 1 from app.ai_conversations c where c.id = conversation_id))
  with check (tenant_id = (select app.current_tenant_id())
              and exists (select 1 from app.ai_conversations c where c.id = conversation_id));

-- Shoppers only ever reach published public documents (addendum §3.2, §3.5).
create policy kb_documents_read on app.kb_documents for select
  using (tenant_id = (select app.current_tenant_id())
         and ((select app.is_internal()) or (audience = 'public' and status = 'published')));
create policy kb_documents_write on app.kb_documents for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

create policy kb_chunks_read on app.kb_chunks for select
  using (tenant_id = (select app.current_tenant_id())
         and ((select app.is_internal())
              or (audience = 'public'
                  and exists (select 1 from app.kb_documents d where d.id = document_id and d.status = 'published'))));
create policy kb_chunks_write on app.kb_chunks for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

grant select, insert, update, delete on app.ai_conversations, app.kb_documents, app.kb_chunks to market_backend;
grant select, insert on app.ai_messages to market_backend;
grant update (escalated) on app.ai_messages to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
