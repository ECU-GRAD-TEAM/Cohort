-- Configurable academic calendars, academic years, and term scheduling.
-- Academic progression levels remain independent from calendar terms.

create type public.academic_year_status as enum ('planned', 'active', 'completed', 'archived');
create type public.academic_term_kind as enum ('regular', 'summer', 'intensive', 'short', 'block', 'other');

create table public.academic_calendars (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  faculty_id uuid,
  code text not null,
  name text not null,
  timezone text not null,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (tenant_id, code),
  foreign key (faculty_id, tenant_id) references public.faculties(id, tenant_id) on delete cascade,
  check (length(trim(code)) > 0),
  check (length(trim(name)) > 0),
  check (length(trim(timezone)) > 0)
);

create unique index academic_calendars_one_default_per_tenant
  on public.academic_calendars(tenant_id) where is_default and faculty_id is null;
create unique index academic_calendars_one_default_per_faculty
  on public.academic_calendars(tenant_id, faculty_id) where is_default and faculty_id is not null;
create index academic_calendars_faculty_tenant_idx
  on public.academic_calendars(faculty_id, tenant_id);

create table public.academic_years (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  calendar_id uuid not null,
  code text not null,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  status public.academic_year_status not null default 'planned',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, tenant_id),
  unique (calendar_id, code),
  foreign key (calendar_id, tenant_id) references public.academic_calendars(id, tenant_id) on delete cascade,
  check (ends_on > starts_on),
  check (length(trim(code)) > 0),
  check (length(trim(name)) > 0)
);
create index academic_years_tenant_dates_idx
  on public.academic_years(tenant_id, starts_on, ends_on);
create index academic_years_calendar_tenant_idx
  on public.academic_years(calendar_id, tenant_id);
create unique index academic_years_one_active_per_calendar
  on public.academic_years(calendar_id) where status = 'active';

alter table public.terms
  add column academic_year_id uuid,
  add column term_kind public.academic_term_kind not null default 'regular',
  add column sequence_number integer,
  add column instructional_starts_on date,
  add column instructional_ends_on date,
  add constraint terms_academic_year_tenant_fk
    foreign key (academic_year_id, tenant_id)
    references public.academic_years(id, tenant_id) on delete restrict,
  add constraint terms_sequence_number_positive
    check (sequence_number is null or sequence_number > 0),
  add constraint terms_instructional_dates_valid
    check (
      (instructional_starts_on is null and instructional_ends_on is null)
      or
      (instructional_starts_on is not null and instructional_ends_on is not null
       and instructional_ends_on >= instructional_starts_on
       and instructional_starts_on >= starts_on
       and instructional_ends_on <= ends_on)
    );

create unique index terms_academic_year_sequence_unique
  on public.terms(academic_year_id, sequence_number)
  where academic_year_id is not null and sequence_number is not null;
create index terms_academic_year_tenant_idx
  on public.terms(academic_year_id, tenant_id);

create or replace function private.validate_term_academic_year_dates()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_year_start date;
  v_year_end date;
begin
  if new.academic_year_id is null then
    return new;
  end if;

  select ay.starts_on, ay.ends_on
    into v_year_start, v_year_end
  from public.academic_years ay
  where ay.id = new.academic_year_id
    and ay.tenant_id = new.tenant_id;

  if not found then
    raise exception 'Academic year does not exist for this tenant'
      using errcode = '23503';
  end if;

  if new.starts_on < v_year_start or new.ends_on > v_year_end then
    raise exception 'Term dates must fall within the selected academic year'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger terms_validate_academic_year_dates
before insert or update of academic_year_id, tenant_id, starts_on, ends_on
on public.terms
for each row execute function private.validate_term_academic_year_dates();

create or replace function private.validate_academic_year_term_dates()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.terms t
    where t.academic_year_id = new.id
      and t.tenant_id = new.tenant_id
      and (t.starts_on < new.starts_on or t.ends_on > new.ends_on)
  ) then
    raise exception 'Academic year dates cannot exclude dates of existing terms'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger academic_years_validate_term_dates
before update of starts_on, ends_on
on public.academic_years
for each row execute function private.validate_academic_year_term_dates();

alter type public.calendar_event_kind add value if not exists 'orientation';
alter type public.calendar_event_kind add value if not exists 'midterm_exam';
alter type public.calendar_event_kind add value if not exists 'final_exam';
alter type public.calendar_event_kind add value if not exists 'result_publication';
alter type public.calendar_event_kind add value if not exists 'graduation';
alter type public.calendar_event_kind add value if not exists 'admissions';
alter type public.calendar_event_kind add value if not exists 'financial_deadline';

alter table public.academic_calendar_events
  add column description text,
  add column location text,
  add column created_at timestamptz not null default now(),
  add column updated_at timestamptz not null default now();

alter table public.academic_calendars enable row level security;
alter table public.academic_years enable row level security;

create policy "members read academic calendars"
  on public.academic_calendars for select
  using (tenant_id = (select private.tenant_id()));

create policy "academic managers manage academic calendars"
  on public.academic_calendars for all
  using (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('academic.manage'))
  )
  with check (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('academic.manage'))
  );

create policy "members read academic years"
  on public.academic_years for select
  using (tenant_id = (select private.tenant_id()));

create policy "academic managers manage academic years"
  on public.academic_years for all
  using (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('academic.manage'))
  )
  with check (
    tenant_id = (select private.tenant_id())
    and (select private.has_permission('academic.manage'))
  );

comment on table public.academic_calendars is
  'Tenant or faculty scoped academic calendar definitions; timezone is the calendar local timezone.';
comment on table public.academic_years is
  'Academic years belonging to a calendar. Actual term dates are configured separately.';
comment on column public.terms.academic_year_id is
  'Optional for legacy terms; new configured terms should belong to an academic year.';
comment on column public.terms.term_kind is
  'Calendar classification of this term; independent of student academic progression levels.';
