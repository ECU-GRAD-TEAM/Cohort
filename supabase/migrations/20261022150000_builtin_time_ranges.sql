-- Replace the custom time range type with built-in ranges.
-- On Supabase the constructor functions of a custom range type are created as supabase_admin,
-- so a migration cannot take EXECUTE on them away from anon. Built-in ranges avoid the issue.

-- Weekly slots are compared as timestamps on a fixed reference date.
alter table public.timetable_entries drop constraint timetable_entries_no_room_clash;
alter table public.timetable_entries add constraint timetable_entries_no_room_clash exclude using gist (
  room_id with =,
  weekday with =,
  tsrange(date '2000-01-03' + starts_at, date '2000-01-03' + ends_at) with &&,
  daterange(valid_from, valid_until, '[]') with &&
);

create or replace function public.enroll_in_section(p_section uuid)
returns public.enrollments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_tenant uuid := private.tenant_id();
  v_section public.sections;
  v_offering public.course_offerings;
  v_course public.courses;
  v_term public.terms;
  v_enrolled integer;
  v_waiting integer;
  v_credits numeric;
  v_status public.enrollment_status;
  v_position integer;
  v_result public.enrollments;
begin
  if v_tenant is null or private.user_type() <> 'student' then
    raise exception 'Only students can register themselves' using errcode = 'insufficient_privilege';
  end if;

  -- Locking the section serialises concurrent registrations for its seats.
  select * into v_section from public.sections where id = p_section and tenant_id = v_tenant for update;
  if not found then
    raise exception 'Section not found' using errcode = 'no_data_found';
  end if;
  select * into v_offering from public.course_offerings where id = v_section.offering_id;
  select * into v_course from public.courses where id = v_offering.course_id;
  select * into v_term from public.terms where id = v_offering.term_id;

  if v_offering.status <> 'published' then
    raise exception 'This course is not open for registration' using errcode = 'check_violation';
  end if;
  if v_term.registration_opens_at is null
     or now() < v_term.registration_opens_at
     or now() > coalesce(v_term.add_drop_ends_at, v_term.registration_closes_at, 'infinity') then
    raise exception 'Registration is closed for this term' using errcode = 'check_violation';
  end if;

  if exists (
    select 1 from public.enrollments e
    join public.sections s on s.id = e.section_id
    where e.student_id = v_me and e.offering_id = v_offering.id and s.kind = v_section.kind
      and e.status in ('enrolled', 'waitlisted')
  ) then
    raise exception 'Already registered in a % section of this course', v_section.kind
      using errcode = 'unique_violation';
  end if;

  if exists (
    select 1 from public.course_prerequisites p
    where p.course_id = v_course.id
      and not exists (
        select 1 from public.enrollments e
        join public.course_offerings o on o.id = e.offering_id
        where e.student_id = v_me
          and o.course_id = p.prerequisite_course_id
          and (e.status = 'completed'
               or (p.kind = 'corequisite' and e.status = 'enrolled' and o.term_id = v_term.id))
      )
  ) then
    raise exception 'Prerequisites for % are not met', v_course.code using errcode = 'check_violation';
  end if;

  select coalesce(sum(c.credit_hours), 0) into v_credits
  from public.courses c
  where c.id in (
    select o.course_id from public.enrollments e
    join public.course_offerings o on o.id = e.offering_id
    where e.student_id = v_me and o.term_id = v_term.id and e.status = 'enrolled'
  ) and c.id <> v_course.id;
  if v_credits + v_course.credit_hours > (select t.max_credits_per_term from public.tenants t where t.id = v_tenant) then
    raise exception 'Registering would exceed the credit limit for the term' using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.timetable_entries mine
    join public.enrollments e on e.section_id = mine.section_id
    join public.course_offerings o on o.id = e.offering_id
    join public.timetable_entries new_slot on new_slot.section_id = p_section
    where e.student_id = v_me and e.status = 'enrolled' and o.term_id = v_term.id
      and mine.weekday = new_slot.weekday
      and mine.starts_at < new_slot.ends_at and new_slot.starts_at < mine.ends_at
      and daterange(mine.valid_from, mine.valid_until, '[]') && daterange(new_slot.valid_from, new_slot.valid_until, '[]')
  ) then
    raise exception 'This section clashes with your timetable' using errcode = 'check_violation';
  end if;

  select count(*) filter (where e.status = 'enrolled'), count(*) filter (where e.status = 'waitlisted')
  into v_enrolled, v_waiting
  from public.enrollments e where e.section_id = p_section;

  if v_section.capacity is null or v_enrolled < v_section.capacity then
    v_status := 'enrolled';
  elsif v_waiting < v_section.waitlist_capacity then
    v_status := 'waitlisted';
    v_position := v_waiting + 1;
  else
    raise exception 'This section is full' using errcode = 'check_violation';
  end if;

  insert into public.enrollments (tenant_id, student_id, section_id, offering_id, status, waitlist_position)
  values (v_tenant, v_me, p_section, v_offering.id, v_status, v_position)
  on conflict (student_id, section_id) do update
    set status = excluded.status,
        waitlist_position = excluded.waitlist_position,
        status_changed_at = now()
  returning * into v_result;

  return v_result;
end;
$$;

drop type public.timerange;
