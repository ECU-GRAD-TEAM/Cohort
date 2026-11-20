-- Phase 2: private source-document storage and a tenant-scoped Gemini embedding model.
-- The existing match_chunks() function performs hybrid retrieval under the caller's RLS.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'university-documents',
  'university-documents',
  false,
  52428800,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

insert into public.model_versions (
  tenant_id, provider, model_name, version, purpose, is_local, data_region, is_high_risk, model_card, status
)
select
  t.id,
  'google'::public.model_provider,
  'gemini-embedding-001',
  'gemini-embedding-001-1024-v1',
  'embedding'::public.model_purpose,
  false,
  'google-ai',
  false,
  jsonb_build_object(
    'purpose', 'Multilingual document and query embeddings for student-facing retrieval',
    'dimensions', 1024,
    'task_types', jsonb_build_array('RETRIEVAL_DOCUMENT', 'RETRIEVAL_QUERY'),
    'source', 'Google Gemini API'
  ),
  'active'::public.model_status
from public.tenants t
on conflict (tenant_id, provider, model_name, version, purpose) do nothing;

drop policy if exists "students read published university documents" on storage.objects;
create policy "students read published university documents"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'university-documents'
  and exists (
    select 1
    from public.document_versions dv
    join public.documents d
      on d.id = dv.document_id
     and d.tenant_id = dv.tenant_id
    where dv.storage_path = storage.objects.name
      and dv.published_at is not null
      and dv.effective_from <= current_date
      and (dv.effective_until is null or dv.effective_until >= current_date)
      and d.status = 'published'::public.document_status
      and d.tenant_id = (select private.tenant_id())
  )
);

comment on policy "students read published university documents" on storage.objects is
  'Students may download only published, effective document versions visible in their tenant; document RLS applies to the linked rows.';
