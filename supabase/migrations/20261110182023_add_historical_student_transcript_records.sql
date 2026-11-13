-- Preserve official historical transcript data without fabricating current-term offerings or enrolments.
create table if not exists public.student_transcript_imports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  student_id uuid not null,
  source_document_name text not null,
  transcript_issued_on date,
  status text not null default 'verified' check (status in ('draft','verified','superseded')),
  cumulative_gpa numeric(5,2) not null check (cumulative_gpa between 0 and 4),
  total_quality_points numeric(10,2) not null check (total_quality_points >= 0),
  total_passed_credit_hours numeric(8,2) not null check (total_passed_credit_hours >= 0),
  imported_by uuid,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  notes text,
  constraint student_transcript_imports_student_fk
    foreign key (student_id, tenant_id) references public.users(id, tenant_id) on delete cascade,
  constraint student_transcript_imports_importer_fk
    foreign key (imported_by, tenant_id) references public.users(id, tenant_id) on delete set null (imported_by),
  constraint student_transcript_imports_id_tenant_key unique (id, tenant_id)
);
create table if not exists public.student_transcript_terms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  import_id uuid not null,
  term_name text not null,
  term_order smallint not null check (term_order > 0),
  term_gpa numeric(5,2) not null check (term_gpa between 0 and 4),
  registered_credit_hours numeric(8,2) not null check (registered_credit_hours >= 0),
  cumulative_gpa numeric(5,2) not null check (cumulative_gpa between 0 and 4),
  cumulative_passed_credit_hours numeric(8,2) not null check (cumulative_passed_credit_hours >= 0),
  cumulative_quality_points numeric(10,2) not null check (cumulative_quality_points >= 0),
  constraint student_transcript_terms_import_fk
    foreign key (import_id, tenant_id) references public.student_transcript_imports(id, tenant_id) on delete cascade,
  constraint student_transcript_terms_order_key unique (import_id, term_order),
  constraint student_transcript_terms_id_tenant_key unique (id, tenant_id)
);
create table if not exists public.student_transcript_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  import_id uuid not null,
  term_id uuid not null,
  course_id uuid not null,
  course_code_snapshot text not null,
  course_title_snapshot text not null,
  credit_hours numeric(6,2) not null check (credit_hours >= 0),
  quality_points numeric(8,2) not null check (quality_points >= 0),
  grade_letter text not null,
  grade_points numeric(5,2) check (grade_points between 0 and 4),
  is_passed boolean not null,
  created_at timestamptz not null default now(),
  constraint student_transcript_entries_import_fk
    foreign key (import_id, tenant_id) references public.student_transcript_imports(id, tenant_id) on delete cascade,
  constraint student_transcript_entries_term_fk
    foreign key (term_id, tenant_id) references public.student_transcript_terms(id, tenant_id) on delete cascade,
  constraint student_transcript_entries_course_fk
    foreign key (course_id, tenant_id) references public.courses(id, tenant_id),
  constraint student_transcript_entries_term_course_key unique (term_id, course_id)
);
create index if not exists student_transcript_imports_student_idx on public.student_transcript_imports (tenant_id, student_id, created_at desc);
create index if not exists student_transcript_terms_import_idx on public.student_transcript_terms (tenant_id, import_id, term_order);
create index if not exists student_transcript_entries_import_idx on public.student_transcript_entries (tenant_id, import_id, term_id);
alter table public.student_transcript_imports enable row level security;
alter table public.student_transcript_terms enable row level security;
alter table public.student_transcript_entries enable row level security;
create policy "students and authorized staff read transcript imports" on public.student_transcript_imports for select to authenticated using (
 tenant_id = (select private.tenant_id()) and (student_id = (select auth.uid()) or private.can_view_student(student_id) or private.has_permission_for_student('enrollment.manage', student_id))
);
create policy "registrars manage transcript imports" on public.student_transcript_imports for all to authenticated using (
 tenant_id = (select private.tenant_id()) and private.has_permission_for_student('enrollment.manage', student_id)
) with check (tenant_id = (select private.tenant_id()) and private.has_permission_for_student('enrollment.manage', student_id));
create policy "students and authorized staff read transcript terms" on public.student_transcript_terms for select to authenticated using (
 tenant_id = (select private.tenant_id()) and exists (select 1 from public.student_transcript_imports i where i.id = import_id and i.tenant_id = tenant_id and (i.student_id = (select auth.uid()) or private.can_view_student(i.student_id) or private.has_permission_for_student('enrollment.manage', i.student_id)))
);
create policy "registrars manage transcript terms" on public.student_transcript_terms for all to authenticated using (
 tenant_id = (select private.tenant_id()) and exists (select 1 from public.student_transcript_imports i where i.id = import_id and i.tenant_id = tenant_id and private.has_permission_for_student('enrollment.manage', i.student_id))
) with check (tenant_id = (select private.tenant_id()) and exists (select 1 from public.student_transcript_imports i where i.id = import_id and i.tenant_id = tenant_id and private.has_permission_for_student('enrollment.manage', i.student_id)));
create policy "students and authorized staff read transcript entries" on public.student_transcript_entries for select to authenticated using (
 tenant_id = (select private.tenant_id()) and exists (select 1 from public.student_transcript_imports i where i.id = import_id and i.tenant_id = tenant_id and (i.student_id = (select auth.uid()) or private.can_view_student(i.student_id) or private.has_permission_for_student('enrollment.manage', i.student_id)))
);
create policy "registrars manage transcript entries" on public.student_transcript_entries for all to authenticated using (
 tenant_id = (select private.tenant_id()) and exists (select 1 from public.student_transcript_imports i where i.id = import_id and i.tenant_id = tenant_id and private.has_permission_for_student('enrollment.manage', i.student_id))
) with check (tenant_id = (select private.tenant_id()) and exists (select 1 from public.student_transcript_imports i where i.id = import_id and i.tenant_id = tenant_id and private.has_permission_for_student('enrollment.manage', i.student_id)));
