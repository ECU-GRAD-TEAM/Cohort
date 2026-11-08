-- Separate five annual academic levels from the ten curriculum semesters.
create table public.academic_year_levels (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  faculty_id uuid not null,
  code text not null,
  name text not null,
  sequence_number integer not null check (sequence_number between 1 and 5),
  curriculum_semester_start integer not null check (curriculum_semester_start between 1 and 10),
  curriculum_semester_end integer not null check (curriculum_semester_end between 1 and 10),
  minimum_cumulative_credits numeric(7,2),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint academic_year_levels_semester_range_check check (curriculum_semester_start <= curriculum_semester_end),
  constraint academic_year_levels_credit_threshold_check check (minimum_cumulative_credits is null or minimum_cumulative_credits >= 0),
  constraint academic_year_levels_tenant_faculty_fk foreign key (faculty_id, tenant_id) references public.faculties(id, tenant_id) on delete restrict,
  constraint academic_year_levels_tenant_code_unique unique (tenant_id, faculty_id, code),
  constraint academic_year_levels_tenant_sequence_unique unique (tenant_id, faculty_id, sequence_number),
  constraint academic_year_levels_id_tenant_unique unique (id, tenant_id)
);

comment on table public.academic_year_levels is 'Annual academic progression levels, distinct from curriculum semester records in academic_levels.';
comment on column public.academic_year_levels.minimum_cumulative_credits is 'Minimum total successfully earned credits required to enter this level. NULL means the official threshold is not configured; automated promotion must not infer one.';

alter table public.student_academic_progressions add column current_year_level_id uuid;
alter table public.student_academic_progressions
  add constraint student_progressions_current_year_level_fkey
  foreign key (current_year_level_id, tenant_id) references public.academic_year_levels(id, tenant_id) on delete restrict;

alter table public.faculty_academic_pathways
  add column department_selection_year_level_id uuid,
  add column department_effective_year_level_id uuid,
  add column programme_selection_year_level_id uuid,
  add column expected_completion_year_level_id uuid;

alter table public.faculty_academic_pathways
  add constraint faculty_pathways_department_selection_year_level_fkey foreign key (department_selection_year_level_id, tenant_id) references public.academic_year_levels(id, tenant_id) on delete restrict,
  add constraint faculty_pathways_department_effective_year_level_fkey foreign key (department_effective_year_level_id, tenant_id) references public.academic_year_levels(id, tenant_id) on delete restrict,
  add constraint faculty_pathways_programme_selection_year_level_fkey foreign key (programme_selection_year_level_id, tenant_id) references public.academic_year_levels(id, tenant_id) on delete restrict,
  add constraint faculty_pathways_expected_completion_year_level_fkey foreign key (expected_completion_year_level_id, tenant_id) references public.academic_year_levels(id, tenant_id) on delete restrict;

insert into public.academic_year_levels (tenant_id, faculty_id, code, name, sequence_number, curriculum_semester_start, curriculum_semester_end)
select t.id, f.id, 'LEVEL_' || n, 'Level ' || n, n, (n * 2) - 1, n * 2
from public.tenants t
join public.faculties f on f.tenant_id=t.id and f.code='ENG'
cross join generate_series(1,5) as n
where t.slug='ecu';

create index academic_year_levels_faculty_idx on public.academic_year_levels (tenant_id, faculty_id, sequence_number);
alter table public.academic_year_levels enable row level security;

create policy "members read academic year levels" on public.academic_year_levels
for select to authenticated
using (
  tenant_id = (select private.tenant_id())
  and (
    private.has_permission('enrollment.manage'::text, 'faculty'::text, faculty_id)
    or exists (
      select 1 from public.student_academic_progressions p
      where p.tenant_id=academic_year_levels.tenant_id
        and p.faculty_id=academic_year_levels.faculty_id
        and p.current_year_level_id=academic_year_levels.id
        and p.student_id=(select auth.uid())
    )
  )
);

create policy "registrars manage academic year levels" on public.academic_year_levels
for all to authenticated
using (tenant_id=(select private.tenant_id()) and private.has_permission('enrollment.manage'::text,'faculty'::text,faculty_id))
with check (tenant_id=(select private.tenant_id()) and private.has_permission('enrollment.manage'::text,'faculty'::text,faculty_id));

grant select, insert, update, delete on public.academic_year_levels to authenticated;

update public.faculty_academic_pathways f
set department_selection_year_level_id=y1.id,
    department_effective_year_level_id=y2.id,
    expected_completion_year_level_id=y5.id,
    updated_at=now()
from public.academic_year_levels y1
join public.academic_year_levels y2 on y2.tenant_id=y1.tenant_id and y2.faculty_id=y1.faculty_id and y2.sequence_number=2
join public.academic_year_levels y5 on y5.tenant_id=y1.tenant_id and y5.faculty_id=y1.faculty_id and y5.sequence_number=5
where f.tenant_id=y1.tenant_id and f.faculty_id=y1.faculty_id and y1.sequence_number=1;

alter table public.academic_progression_rules
  add column selection_year_level_id uuid,
  add column effective_year_level_id uuid;

alter table public.academic_progression_rules
  add constraint academic_progression_rules_selection_year_level_fkey foreign key (selection_year_level_id,tenant_id) references public.academic_year_levels(id,tenant_id) on delete restrict,
  add constraint academic_progression_rules_effective_year_level_fkey foreign key (effective_year_level_id,tenant_id) references public.academic_year_levels(id,tenant_id) on delete restrict;

update public.academic_progression_rules r
set selection_year_level_id=y1.id,effective_year_level_id=y2.id,updated_at=now()
from public.academic_year_levels y1
join public.academic_year_levels y2 on y2.tenant_id=y1.tenant_id and y2.faculty_id=y1.faculty_id and y2.sequence_number=2
where r.tenant_id=y1.tenant_id and r.faculty_id=y1.faculty_id
  and r.action_key='department_selection' and y1.sequence_number=1;

alter type public.academic_term_kind add value if not exists 'fall';
alter type public.academic_term_kind add value if not exists 'spring';
