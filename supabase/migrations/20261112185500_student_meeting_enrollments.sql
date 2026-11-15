begin;

-- A meeting is now the assignment unit; an enrollment remains at course-offering level.
alter table public.section_meetings
  add constraint section_meetings_id_tenant_key unique (id, tenant_id);

create table public.student_meetings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  enrollment_id uuid not null,
  meeting_id uuid not null,
  assigned_at timestamptz not null default now(),
  constraint student_meetings_enrollment_fk
    foreign key (enrollment_id, tenant_id)
    references public.enrollments (id, tenant_id) on delete cascade,
  constraint student_meetings_meeting_fk
    foreign key (meeting_id, tenant_id)
    references public.section_meetings (id, tenant_id) on delete cascade,
  constraint student_meetings_enrollment_meeting_key
    unique (enrollment_id, meeting_id)
);

create index student_meetings_meeting_tenant_idx
  on public.student_meetings (meeting_id, tenant_id);
create index student_meetings_enrollment_tenant_idx
  on public.student_meetings (enrollment_id, tenant_id);

alter table public.student_meetings enable row level security;
grant select, insert, update, delete on public.student_meetings to authenticated;

drop policy if exists "registrars manage historical enrolments" on public.enrollments;
drop policy if exists "students, teachers, advisors and registrars read enrolments" on public.enrollments;

create policy "students, teachers, advisors and registrars read enrolments"
on public.enrollments for select to authenticated
using (
  tenant_id = (select private.tenant_id())
  and (
    student_id = (select auth.uid())
    or private.advises(student_id)
    or private.has_record_grant(student_id)
    or private.has_permission_for_offering('enrollment.manage'::text, offering_id)
    or exists (
      select 1
      from public.student_meetings sm
      join public.section_meetings m
        on m.id = sm.meeting_id and m.tenant_id = sm.tenant_id
      where sm.enrollment_id = enrollments.id
        and sm.tenant_id = enrollments.tenant_id
        and private.teaches_section(m.section_id)
    )
  )
);

-- Preserve the historical-grade and active-offering record shapes without section_id.
alter table public.enrollments
  drop constraint if exists enrollments_record_shape_check;
alter table public.enrollments
  add constraint enrollments_record_shape_check check (
    (
      offering_id is null
      and course_id is not null
      and term_id is not null
      and credit_hours_attempted is not null
      and final_grade_letter is not null
      and final_grade_points is not null
      and quality_points is not null
    )
    or
    (
      offering_id is not null
      and course_id is null
      and term_id is null
      and credit_hours_attempted is null
      and quality_points is null
    )
  );

alter table public.enrollments
  drop constraint if exists enrollments_section_id_tenant_id_offering_id_fkey;
alter table public.enrollments
  drop constraint if exists enrollments_student_id_section_id_key;
alter table public.enrollments
  drop column if exists section_id;

create policy "students and academic staff read assigned meetings"
on public.student_meetings for select to authenticated
using (
  tenant_id = (select private.tenant_id())
  and exists (
    select 1
    from public.enrollments e
    where e.id = student_meetings.enrollment_id
      and e.tenant_id = student_meetings.tenant_id
      and (
        e.student_id = (select auth.uid())
        or private.advises(e.student_id)
        or private.has_record_grant(e.student_id)
        or private.has_permission_for_offering('enrollment.manage'::text, e.offering_id)
        or private.teaches_section((
          select m.section_id
          from public.section_meetings m
          where m.id = student_meetings.meeting_id
            and m.tenant_id = student_meetings.tenant_id
        ))
      )
  )
);

create policy "registrars assign student meetings"
on public.student_meetings for all to authenticated
using (
  tenant_id = (select private.tenant_id())
  and exists (
    select 1
    from public.enrollments e
    where e.id = student_meetings.enrollment_id
      and e.tenant_id = student_meetings.tenant_id
      and private.has_permission_for_offering('enrollment.manage'::text, e.offering_id)
  )
)
with check (
  tenant_id = (select private.tenant_id())
  and exists (
    select 1
    from public.enrollments e
    join public.section_meetings m
      on m.id = student_meetings.meeting_id
     and m.tenant_id = student_meetings.tenant_id
    where e.id = student_meetings.enrollment_id
      and e.tenant_id = student_meetings.tenant_id
      and e.offering_id = m.offering_id
      and private.has_permission_for_offering('enrollment.manage'::text, e.offering_id)
  )
);

commit;
