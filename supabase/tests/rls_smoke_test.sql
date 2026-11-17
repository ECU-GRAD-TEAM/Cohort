-- Smoke test for tenant isolation, row-level security and the workflows the database enforces.
-- It runs in one transaction and rolls back, so it leaves nothing behind. Run it with
--
--   supabase test db                                   (local stack, through pg_prove)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_smoke_test.sql
--
-- Each check raises an error when it fails; a clean run reports "ok 1 - All smoke tests passed".
-- To act as a user the script sets the JWT claims Supabase would set, then SET ROLE authenticated.
--
-- Fixed ids:
--   tenants   0a..0a = University A, 0b..0b = University B
--   users     a..01 admin, a..02 teacher (teaches CS101 L1), a..03 other teacher, a..04 student 1,
--             a..05 student 2, a..06 advisor of student 1, a..07 data protection officer,
--             b..01 student at University B
--   catalogue 2..01 CS101, 2..02 CS201 (needs CS101), 2..11 / 2..12 their offerings,
--             2..21 / 2..22 their sections

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(1);

-- ===========================================================================
-- Seed, as the database owner (bypasses row-level security)
-- ===========================================================================

insert into public.tenants (id, slug, name, data_region) values
  ('0a000000-0000-4000-8000-00000000000a', 'smoke-uni-a', 'Smoke University A', 'eu-west-1'),
  ('0b000000-0000-4000-8000-00000000000b', 'smoke-uni-b', 'Smoke University B', 'eu-west-1');

-- Accounts are provisioned through Supabase Auth: trusted app_metadata names the university and the
-- user type (staff or non_staff), and the triggers create the users and their profiles. A confirmed
-- email makes the account active. Roles are never granted automatically.
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at) values
  ('a0000000-0000-4000-8000-000000000001', 'admin@a.test',
   '{"tenant_id": "0a000000-0000-4000-8000-00000000000a", "user_type": "staff"}', '{"full_name": "Ada Admin"}', now()),
  ('a0000000-0000-4000-8000-000000000002', 'teacher@a.test',
   '{"tenant_id": "0a000000-0000-4000-8000-00000000000a", "user_type": "staff"}', '{"full_name": "Tariq Teacher"}', now()),
  ('a0000000-0000-4000-8000-000000000003', 'other.teacher@a.test',
   '{"tenant_id": "0a000000-0000-4000-8000-00000000000a", "user_type": "staff"}', '{"full_name": "Tamer Other"}', now()),
  ('a0000000-0000-4000-8000-000000000004', 'sara@a.test',
   '{"tenant_id": "0a000000-0000-4000-8000-00000000000a", "user_type": "non_staff", "institutional_id": "S-1"}', '{"full_name": "Sara Student"}', now()),
  ('a0000000-0000-4000-8000-000000000005', 'samir@a.test',
   '{"tenant_id": "0a000000-0000-4000-8000-00000000000a", "user_type": "non_staff", "institutional_id": "S-2"}', '{"full_name": "Samir Student"}', now()),
  ('a0000000-0000-4000-8000-000000000006', 'advisor@a.test',
   '{"tenant_id": "0a000000-0000-4000-8000-00000000000a", "user_type": "staff"}', '{"full_name": "Amal Advisor"}', now()),
  ('a0000000-0000-4000-8000-000000000007', 'dpo@a.test',
   '{"tenant_id": "0a000000-0000-4000-8000-00000000000a", "user_type": "staff"}', '{"full_name": "Dina DPO"}', now()),
  ('b0000000-0000-4000-8000-000000000001', 'bob@b.test',
   '{"tenant_id": "0b000000-0000-4000-8000-00000000000b", "user_type": "non_staff"}', '{"full_name": "Bob Elsewhere"}', now());

do $$
begin
  assert (select count(*) from public.users where tenant_id = '0a000000-0000-4000-8000-00000000000a' and status = 'active') = 7,
    'the auth triggers create an active user for each confirmed account';
  assert (select display_name from public.user_profiles where user_id = 'a0000000-0000-4000-8000-000000000004') = 'Sara Student',
    'the profile takes the display name from user metadata';
  assert (select count(*) from public.roles where tenant_id = '0a000000-0000-4000-8000-00000000000a'
          and key in ('undergraduate', 'instructor', 'it_officer', 'academic_advisor')) = 4,
    'new tenants get the standard role catalogue';
  assert (select count(*) from public.user_roles where tenant_id = '0a000000-0000-4000-8000-00000000000a') = 0,
    'no role is granted automatically';
end;
$$;

-- This university has no data protection role in its catalogue, so it adds one of its own.
insert into public.roles (tenant_id, key, name, is_system)
values ('0a000000-0000-4000-8000-00000000000a', 'data_protection_officer', 'Data Protection Officer', false);

-- Roles are granted explicitly: Ada administers (and registers students), the teachers teach, the
-- students study, Amal advises and Dina protects data.
insert into public.user_roles (user_id, role_id, tenant_id)
select u.id, r.id, r.tenant_id
from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, '0a000000-0000-4000-8000-00000000000a'::uuid, 'it_officer'),
  ('a0000000-0000-4000-8000-000000000002'::uuid, '0a000000-0000-4000-8000-00000000000a'::uuid, 'instructor'),
  ('a0000000-0000-4000-8000-000000000003'::uuid, '0a000000-0000-4000-8000-00000000000a'::uuid, 'instructor'),
  ('a0000000-0000-4000-8000-000000000004'::uuid, '0a000000-0000-4000-8000-00000000000a'::uuid, 'undergraduate'),
  ('a0000000-0000-4000-8000-000000000005'::uuid, '0a000000-0000-4000-8000-00000000000a'::uuid, 'undergraduate'),
  ('a0000000-0000-4000-8000-000000000006'::uuid, '0a000000-0000-4000-8000-00000000000a'::uuid, 'academic_advisor'),
  ('a0000000-0000-4000-8000-000000000007'::uuid, '0a000000-0000-4000-8000-00000000000a'::uuid, 'data_protection_officer'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, '0b000000-0000-4000-8000-00000000000b'::uuid, 'undergraduate')
) as u (id, tenant_id, role_key)
join public.roles r on r.tenant_id = u.tenant_id and r.key = u.role_key;

-- Role permissions are each university's to map. Here the administrator runs the university,
-- its registration and its exams, but not its grades, and sees individual records only through
-- break-glass; the data protection officer reads the audit log and manages retention.
insert into public.role_permissions (role_id, tenant_id, permission_key)
select r.id, r.tenant_id, p.key
from public.roles r
join public.permissions p on p.key not in ('grades.manage', 'audit.read', 'retention.manage')
where r.tenant_id = '0a000000-0000-4000-8000-00000000000a' and r.key = 'it_officer';
insert into public.role_permissions (role_id, tenant_id, permission_key)
select r.id, r.tenant_id, m.permission_key
from (values ('audit.read'), ('retention.manage')) as m (permission_key)
join public.roles r on r.tenant_id = '0a000000-0000-4000-8000-00000000000a' and r.key = 'data_protection_officer';

insert into public.faculties (id, tenant_id, code, name) values
  ('10000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', 'ENG', 'Engineering'),
  ('1b000000-0000-4000-8000-000000000001', '0b000000-0000-4000-8000-00000000000b', 'ENG', 'Engineering');
insert into public.departments (id, tenant_id, faculty_id, code, name) values
  ('10000000-0000-4000-8000-000000000002', '0a000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000001', 'SWE', 'Software Engineering'),
  ('1b000000-0000-4000-8000-000000000002', '0b000000-0000-4000-8000-00000000000b', '1b000000-0000-4000-8000-000000000001', 'SWE', 'Software Engineering');
insert into public.programs (id, tenant_id, department_id, code, name, degree_level) values
  ('10000000-0000-4000-8000-000000000003', '0a000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000002', 'BSE', 'BSc Software Engineering', 'bachelor');
insert into public.student_programs (student_id, program_id, tenant_id) values
  ('a0000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000003', '0a000000-0000-4000-8000-00000000000a'),
  ('a0000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000003', '0a000000-0000-4000-8000-00000000000a');
insert into public.buildings (id, tenant_id, code, name) values
  ('10000000-0000-4000-8000-000000000004', '0a000000-0000-4000-8000-00000000000a', 'B1', 'Main Building');
insert into public.rooms (id, tenant_id, building_id, code, room_type, capacity, exam_capacity) values
  ('10000000-0000-4000-8000-000000000005', '0a000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000004', '101', 'lecture_hall', 100, 1),
  ('10000000-0000-4000-8000-000000000007', '0a000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000004', '102', 'classroom', 40, 20);
insert into public.terms (id, tenant_id, code, name, starts_on, ends_on, registration_opens_at, registration_closes_at, add_drop_ends_at, status) values
  ('10000000-0000-4000-8000-000000000006', '0a000000-0000-4000-8000-00000000000a', 'SMOKE', 'Smoke term',
   current_date - 30, current_date + 90, now() - interval '1 day', now() + interval '7 days', now() + interval '14 days', 'registration');
insert into public.courses (id, tenant_id, department_id, code, title, credit_hours) values
  ('20000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000002', 'CS101', 'Programming I', 3),
  ('20000000-0000-4000-8000-000000000002', '0a000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000002', 'CS201', 'Programming II', 3),
  ('20000000-0000-4000-8000-000000000003', '0a000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000002', 'MA101', 'Calculus I', 3),
  ('2b000000-0000-4000-8000-000000000001', '0b000000-0000-4000-8000-00000000000b', '1b000000-0000-4000-8000-000000000002', 'CS101', 'Programming I', 3);
insert into public.course_prerequisites (course_id, prerequisite_course_id, tenant_id) values
  ('20000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a');
insert into public.course_offerings (id, tenant_id, course_id, term_id, status) values
  ('20000000-0000-4000-8000-000000000011', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000006', 'draft'),
  ('20000000-0000-4000-8000-000000000012', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000006', 'draft'),
  ('20000000-0000-4000-8000-000000000013', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000006', 'draft');
-- An offering is published only once its grading components total 100 percent.
insert into public.grade_components (tenant_id, offering_id, name, category, weight)
select '0a000000-0000-4000-8000-00000000000a', o.id, c.name, c.category::public.grade_category, c.weight
from (values ('20000000-0000-4000-8000-000000000011'::uuid), ('20000000-0000-4000-8000-000000000012'::uuid),
             ('20000000-0000-4000-8000-000000000013'::uuid)) as o (id)
cross join (values ('Midterm', 'midterm', 30), ('Final exam', 'final_exam', 70)) as c (name, category, weight);
update public.course_offerings set status = 'published' where tenant_id = '0a000000-0000-4000-8000-00000000000a';
insert into public.sections (id, tenant_id, offering_id, code, capacity, waitlist_capacity) values
  ('20000000-0000-4000-8000-000000000021', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000011', 'L1', 1, 1),
  ('20000000-0000-4000-8000-000000000022', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000012', 'L1', 30, 0),
  ('20000000-0000-4000-8000-000000000023', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000013', 'L1', 30, 0);
insert into public.section_instructors (section_id, user_id, tenant_id) values
  ('20000000-0000-4000-8000-000000000021', 'a0000000-0000-4000-8000-000000000002', '0a000000-0000-4000-8000-00000000000a');
insert into public.timetable_entries (tenant_id, section_id, room_id, weekday, starts_at, ends_at, valid_from, valid_until) values
  ('0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000005',
   1, '09:00', '10:30', current_date - 30, current_date + 90),
  -- MA101 meets in another room but overlaps CS101 L1 on Monday morning.
  ('0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000023', '10000000-0000-4000-8000-000000000007',
   1, '10:00', '11:00', current_date - 30, current_date + 90);
-- Class meetings, which registrars assign students to (Monday is day 1).
insert into public.section_meetings (id, tenant_id, section_id, offering_id, room_id, day_of_week, starts_at, ends_at, meeting_type) values
  ('20000000-0000-4000-8000-000000000031', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000021', '20000000-0000-4000-8000-000000000011',
   '10000000-0000-4000-8000-000000000005', 1, '09:00', '10:30', 'lecture'),
  ('20000000-0000-4000-8000-000000000033', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000023', '20000000-0000-4000-8000-000000000013',
   '10000000-0000-4000-8000-000000000007', 1, '10:00', '11:00', 'lecture');
insert into public.advisor_assignments (advisor_id, student_id, tenant_id) values
  ('a0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000004', '0a000000-0000-4000-8000-00000000000a');

-- ===========================================================================
-- Tenant isolation
-- ===========================================================================

-- Even the owner, bypassing RLS, cannot make a row point at another tenant's data.
do $$
declare
  failed boolean := false;
begin
  begin
    insert into public.section_instructors (section_id, user_id, tenant_id)
    values ('20000000-0000-4000-8000-000000000021', 'b0000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a');
  exception when foreign_key_violation then
    failed := true;
  end;
  assert failed, 'composite foreign keys block cross-tenant references';
end;
$$;

select set_config('request.jwt.claims', '{"sub": "b0000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  assert (select count(*) from public.tenants) = 1, 'a user sees only their own tenant';
  assert (select count(*) from public.courses) = 1, 'a user sees only their own tenant''s catalogue';
  begin
    insert into public.lost_items (tenant_id, kind, title, reporter_id)
    values ('0a000000-0000-4000-8000-00000000000a', 'lost', 'Umbrella', 'b0000000-0000-4000-8000-000000000001');
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'a user cannot write into another tenant';
end;
$$;
reset role;

set local role anon;
do $$
declare
  failed boolean := false;
begin
  begin
    perform 1 from public.courses;
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'anon cannot read anything';
end;
$$;
reset role;

-- ===========================================================================
-- Enrolment: registrars enrol students and assign their class meetings
-- ===========================================================================

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  begin
    perform public.enroll_in_section('20000000-0000-4000-8000-000000000021');
  exception when feature_not_supported then
    failed := true;
  end;
  assert failed, 'students cannot register themselves';

  failed := false;
  begin
    insert into public.enrollments (tenant_id, student_id, offering_id, status)
    values ('0a000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000011', 'enrolled');
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'students cannot write enrolments directly';
end;
$$;
reset role;

-- The registrar enrols both students in CS101 and assigns them to the meetings of section L1.
select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  v_student uuid;
  v_enrollment uuid;
begin
  foreach v_student in array array['a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000005']::uuid[] loop
    insert into public.enrollments (tenant_id, student_id, offering_id, status)
    values ('0a000000-0000-4000-8000-00000000000a', v_student, '20000000-0000-4000-8000-000000000011', 'enrolled')
    returning id into v_enrollment;
    insert into public.student_meetings (tenant_id, enrollment_id, meeting_id)
    select m.tenant_id, v_enrollment, m.id from public.section_meetings m
    where m.section_id = '20000000-0000-4000-8000-000000000021';
    if v_student = 'a0000000-0000-4000-8000-000000000004' then
      perform set_config('smoke.enrollment_id', v_enrollment::text, true);
    end if;
  end loop;
  assert (select count(*) from public.student_meetings) = 2, 'the registrar assigns each student the section''s meeting';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.enrollments) = 1, 'students see only their own enrolments';
  assert private.enrolled_in_section('20000000-0000-4000-8000-000000000021'), 'the student is in the section of their meetings';
  assert not private.enrolled_in_section('20000000-0000-4000-8000-000000000023'), 'and in no other section';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.enrollments) = 2, 'a teacher reads the enrolments of the students they teach';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.enrollments) = 0, 'other teachers read none of them';
end;
$$;
reset role;

-- ===========================================================================
-- Course chat follows enrolment
-- ===========================================================================

do $$
begin
  assert (
    select count(*) from public.channel_members cm
    join public.channels c on c.id = cm.channel_id
    where c.offering_id = '20000000-0000-4000-8000-000000000011'
  ) = 3, 'both students and the teacher are in the course channel';
  assert (
    select cm.role from public.channel_members cm
    join public.channels c on c.id = cm.channel_id
    where c.offering_id = '20000000-0000-4000-8000-000000000011' and cm.user_id = 'a0000000-0000-4000-8000-000000000002'
  ) = 'moderator', 'teachers moderate their course channel';
end;
$$;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
insert into public.messages (tenant_id, channel_id, sender_id, body)
select c.tenant_id, c.id, 'a0000000-0000-4000-8000-000000000004', 'Is the quiz open-book?'
from public.channels c where c.offering_id = '20000000-0000-4000-8000-000000000011';
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  update public.channel_members set last_read_at = now() where user_id = 'a0000000-0000-4000-8000-000000000004';
  begin
    update public.channel_members set role = 'moderator' where user_id = 'a0000000-0000-4000-8000-000000000004';
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'members cannot promote themselves';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.messages) = 0, 'non-members cannot read a course channel';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000005", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.messages) = 1, 'classmates read the course channel';
end;
$$;
reset role;

-- ===========================================================================
-- Grades: draft, publish, immutable history, who can see them
-- ===========================================================================

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  v_grade uuid;
begin
  insert into public.grade_entries (tenant_id, enrollment_id, student_id, offering_id, score, max_score)
  select e.tenant_id, e.id, e.student_id, e.offering_id, 70, 100
  from public.enrollments e
  where e.student_id = 'a0000000-0000-4000-8000-000000000004' and e.offering_id = '20000000-0000-4000-8000-000000000011'
  returning id into v_grade;
  perform set_config('smoke.grade_id', v_grade::text, true);
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.grade_entries) = 0, 'students do not see draft grades';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  v_grade uuid := current_setting('smoke.grade_id')::uuid;
  failed boolean := false;
begin
  update public.grade_entries set status = 'published' where id = v_grade;

  begin
    update public.grade_entries set score = 90 where id = v_grade;
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'published grades cannot be edited';

  insert into public.grade_entries (tenant_id, enrollment_id, student_id, offering_id, score, max_score, status, supersedes_id, change_reason)
  select tenant_id, enrollment_id, student_id, offering_id, 75, 100, 'published', id, 'Re-marked question 3'
  from public.grade_entries where id = v_grade;
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.grade_entries) = 2, 'the student sees the full published history';
  assert (select count(*) from public.published_grades) = 1, 'the current view shows one grade per item';
  assert (select score from public.published_grades) = 75, 'the correction is the current grade';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000005", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.grade_entries) = 0, 'classmates cannot see each other''s grades';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  assert (select count(*) from public.grade_entries) = 0, 'other teachers cannot see the course''s grades';
  begin
    insert into public.grade_entries (tenant_id, enrollment_id, student_id, offering_id, score, max_score)
    values ('0a000000-0000-4000-8000-00000000000a', current_setting('smoke.enrollment_id')::uuid,
            'a0000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000011', 100, 100);
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'other teachers cannot add grades';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000006", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.published_grades) = 1, 'advisors see their advisee''s published grades';
end;
$$;
reset role;

-- Administrators see individual records only through the audited break-glass action.
select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.grade_entries) = 0, 'administrators do not see individual grades by default';
  perform public.open_record_access('a0000000-0000-4000-8000-000000000004', 'Reviewing grade appeal 42', 30);
  assert (select count(*) from public.grade_entries) = 2, 'break-glass opens the student''s record';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.data_access_log where action = 'break_glass_opened') = 1,
    'students can see who opened their record';
  assert (select count(*) from public.audit_log) = 0, 'students cannot read the audit log';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000007", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.audit_log where table_name = 'grade_entries') >= 2,
    'grade changes are in the audit log';
end;
$$;
reset role;

do $$
declare
  failed boolean := false;
begin
  begin
    update public.audit_log set action = 'tampered';
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'the audit log is append-only even for the owner';
end;
$$;

-- ===========================================================================
-- Online quiz: hidden keys, server-side timer, autosave, scoring, release
-- ===========================================================================

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
insert into public.questions (id, tenant_id, course_id, type, stem, content, status) values
  ('30000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000001',
   'mcq_single', 'What is 2 + 2?', '{"options": {"a": "3", "b": "4"}}', 'approved');
insert into public.question_answer_keys (question_id, tenant_id, answer) values
  ('30000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', '"b"');
insert into public.assessments (id, tenant_id, offering_id, kind, delivery, title, opens_at, due_at, time_limit_minutes, status) values
  ('30000000-0000-4000-8000-000000000002', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000011',
   'quiz', 'online', 'Quiz 1', now() - interval '1 hour', now() + interval '1 hour', 20, 'published');
insert into public.assessment_questions (tenant_id, assessment_id, question_id, points) values
  ('0a000000-0000-4000-8000-00000000000a', '30000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 5);
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  v_sub public.submissions;
  v_rows integer;
  failed boolean := false;
begin
  assert (select count(*) from public.questions) = 0, 'questions stay hidden until dealt';
  v_sub := public.start_attempt('30000000-0000-4000-8000-000000000002');
  assert v_sub.deadline_at <= now() + interval '20 minutes', 'the time limit is set on the server';
  assert (public.start_attempt('30000000-0000-4000-8000-000000000002')).id = v_sub.id, 'reconnecting resumes the same attempt';
  assert (select count(*) from public.questions) = 1, 'the dealt question is visible';
  assert (select count(*) from public.question_answer_keys) = 0, 'answer keys are hidden';

  update public.submission_answers set response = '"b"', saved_at = now() where submission_id = v_sub.id;
  get diagnostics v_rows = row_count;
  assert v_rows = 1, 'autosave works before the deadline';

  begin
    update public.submission_answers set position = 9 where submission_id = v_sub.id;
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'students can change only their response';

  v_sub := public.submit_attempt(v_sub.id);
  assert v_sub.status = 'submitted', 'the attempt is submitted';
  assert (select count(*) from public.answer_scores) = 0, 'scores stay hidden until release';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select points from public.answer_scores) = 5 and (select is_correct from public.answer_scores),
    'multiple choice is scored on submission';
  update public.assessments set grades_released_at = now(), model_answers_release_at = now()
  where id = '30000000-0000-4000-8000-000000000002';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.answer_scores) = 1, 'scores are visible after release';
  assert (select count(*) from public.question_answer_keys) = 1, 'answer keys are visible after release';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000005", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.submissions) = 0, 'students cannot see each other''s attempts';
  perform public.start_attempt('30000000-0000-4000-8000-000000000002');
end;
$$;
reset role;

-- Late answers are allowed unless the assessment's late policy disallows them; this quiz does.
update public.assessments set late_policy = '{"mode": "disallowed"}'
where id = '30000000-0000-4000-8000-000000000002';
update public.submissions set deadline_at = now() - interval '1 second'
where student_id = 'a0000000-0000-4000-8000-000000000005';

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000005", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  v_rows integer;
begin
  update public.submission_answers set response = '"a"';
  get diagnostics v_rows = row_count;
  assert v_rows = 0, 'answers stop saving at the deadline when late answers are disallowed';
end;
$$;
reset role;

-- ===========================================================================
-- Attendance by rotating QR code
-- ===========================================================================

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
insert into public.attendance_sessions (id, tenant_id, section_id, starts_at, ends_at, checkin_opens_at, checkin_closes_at) values
  ('40000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000021',
   now() - interval '5 minutes', now() + interval '1 hour', now() - interval '10 minutes', now() + interval '30 minutes');
select set_config('smoke.qr_token', (select token from public.attendance_qr_token('40000000-0000-4000-8000-000000000001')), true);
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  r public.attendance_records;
  failed boolean := false;
begin
  begin
    perform public.check_in('40000000-0000-4000-8000-000000000001', 'not-the-code');
  exception when check_violation then
    failed := true;
  end;
  assert failed, 'a wrong code is rejected';

  r := public.check_in('40000000-0000-4000-8000-000000000001', current_setting('smoke.qr_token'));
  assert r.status = 'present' and r.method = 'qr' and r.confirmation = 'confirmed', 'a valid code checks the student in';

  failed := false;
  begin
    perform 1 from private.attendance_secrets;
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'QR secrets are unreadable';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000005", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  r public.attendance_records;
begin
  r := public.check_in('40000000-0000-4000-8000-000000000001');
  assert r.method = 'name_entry' and r.confirmation = 'pending', 'name entry waits for the teacher';
end;
$$;
reset role;

-- ===========================================================================
-- AI grading suggestions and risk predictions
-- ===========================================================================

insert into public.model_versions (id, tenant_id, provider, model_name, version, purpose, is_high_risk) values
  ('50000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', 'local', 'bge-m3', '1', 'embedding', false),
  ('50000000-0000-4000-8000-000000000002', '0a000000-0000-4000-8000-00000000000a', 'anthropic', 'grader', '1', 'grading', true),
  ('50000000-0000-4000-8000-000000000003', '0a000000-0000-4000-8000-00000000000a', 'internal', 'risk-gbt', '1', 'risk_prediction', true);

insert into public.ai_grade_suggestions (tenant_id, submission_answer_id, offering_id, model_version_id, total_points, confidence)
select sa.tenant_id, sa.id, s.offering_id, '50000000-0000-4000-8000-000000000002', 4, 0.8
from public.submission_answers sa join public.submissions s on s.id = sa.submission_id
where s.student_id = 'a0000000-0000-4000-8000-000000000004';

insert into public.risk_scores (id, tenant_id, student_id, model_version_id, band, score, features) values
  ('50000000-0000-4000-8000-000000000011', '0a000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000004',
   '50000000-0000-4000-8000-000000000003', 'medium', 0.55, '{"attendance_rate": 0.7, "late_submissions": 2}');
insert into public.risk_factors (tenant_id, risk_score_id, rank, factor, contribution, explanation) values
  ('0a000000-0000-4000-8000-00000000000a', '50000000-0000-4000-8000-000000000011', 1, 'attendance_rate', 0.21, 'Attendance has dropped to 70%');

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  assert (select count(*) from public.ai_grade_suggestions) = 1, 'teachers see AI suggestions for their course';
  update public.ai_grade_suggestions
  set status = 'accepted', reviewed_by = 'a0000000-0000-4000-8000-000000000002', reviewed_at = now();
  begin
    update public.ai_grade_suggestions set total_points = 5;
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'teachers cannot rewrite what the model proposed';
  assert (select count(*) from public.risk_scores) = 0, 'programme-level risk is for advisors, not course teachers';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000006", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.risk_scores) = 1 and (select count(*) from public.risk_factors) = 1,
    'advisors see their advisee''s risk and its factors';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select count(*) from public.ai_grade_suggestions) = 0, 'students never see AI grade suggestions';
  assert (select count(*) from public.risk_scores) = 0, 'students see their prediction only after opting in';
  insert into public.consent_records (tenant_id, user_id, purpose, granted, policy_version)
  values ('0a000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000004', 'risk_prediction_display', true, 'v1');
  assert (select count(*) from public.risk_scores) = 1, 'after opting in the student sees their prediction';
end;
$$;
reset role;

insert into public.prompt_templates (id, tenant_id, key) values
  ('50000000-0000-4000-8000-000000000021', '0a000000-0000-4000-8000-00000000000a', 'smoke.prompt');
insert into public.prompt_template_versions (tenant_id, template_id, version, body, is_active) values
  ('0a000000-0000-4000-8000-00000000000a', '50000000-0000-4000-8000-000000000021', 1, 'v1', true),
  ('0a000000-0000-4000-8000-00000000000a', '50000000-0000-4000-8000-000000000021', 2, 'v2', false);
do $$
declare
  failed boolean := false;
begin
  begin
    update public.prompt_template_versions set is_active = true where version = 2
      and template_id = '50000000-0000-4000-8000-000000000021';
  exception when exclusion_violation then
    failed := true;
  end;
  assert failed, 'only one version of a prompt template can be active';
end;
$$;

-- ===========================================================================
-- Retrieval is filtered by permission before search
-- ===========================================================================

insert into public.documents (id, tenant_id, kind, scope, offering_id, title, status) values
  ('60000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', 'regulation', 'tenant', null, 'Attendance regulation', 'published'),
  ('60000000-0000-4000-8000-000000000002', '0a000000-0000-4000-8000-00000000000a', 'course_material', 'offering',
   '20000000-0000-4000-8000-000000000012', 'CS201 notes', 'published');
insert into public.document_versions (id, tenant_id, document_id, version, effective_from, published_at) values
  ('60000000-0000-4000-8000-000000000011', '0a000000-0000-4000-8000-00000000000a', '60000000-0000-4000-8000-000000000001', 1, current_date - 1, now()),
  ('60000000-0000-4000-8000-000000000012', '0a000000-0000-4000-8000-00000000000a', '60000000-0000-4000-8000-000000000002', 1, current_date - 1, now());
insert into public.chunks (id, tenant_id, document_version_id, chunk_index, content) values
  ('60000000-0000-4000-8000-000000000021', '0a000000-0000-4000-8000-00000000000a', '60000000-0000-4000-8000-000000000011', 0,
   'Students must attend at least 75 percent of lectures in each course.'),
  ('60000000-0000-4000-8000-000000000022', '0a000000-0000-4000-8000-00000000000a', '60000000-0000-4000-8000-000000000012', 0,
   'Students should attend the recursion lab before the CS201 midterm.');
insert into public.chunk_embeddings (chunk_id, model_version_id, tenant_id, embedding)
select c.id, '50000000-0000-4000-8000-000000000001', c.tenant_id, array_fill(0.01::real, array[1024])::extensions.vector
from public.chunks c where c.tenant_id = '0a000000-0000-4000-8000-00000000000a';

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  v_ids uuid[];
begin
  assert (select count(*) from public.chunks) = 1, 'students see institutional chunks but not other courses''';
  select array_agg(m.chunk_id) into v_ids
  from public.match_chunks(
    '50000000-0000-4000-8000-000000000001',
    array_fill(0.01::real, array[1024])::extensions.vector,
    'attend',
    5
  ) m;
  assert v_ids = array['60000000-0000-4000-8000-000000000021'::uuid], 'hybrid search returns only permitted chunks';
end;
$$;
reset role;

-- ===========================================================================
-- Scheduling constraints, directory privacy, seats, surveys
-- ===========================================================================

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  begin
    insert into public.timetable_entries (tenant_id, section_id, room_id, weekday, starts_at, ends_at, valid_from, valid_until)
    values ('0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000022', '10000000-0000-4000-8000-000000000005',
            1, '10:00', '11:00', current_date, current_date + 60);
  exception when exclusion_violation then
    failed := true;
  end;
  assert failed, 'a room cannot be double-booked';

  insert into public.exam_sessions (id, tenant_id, offering_id, title, mode, starts_at, ends_at, seats_released_at) values
    ('70000000-0000-4000-8000-000000000001', '0a000000-0000-4000-8000-00000000000a', '20000000-0000-4000-8000-000000000011',
     'CS101 final', 'in_hall', now() + interval '10 days', now() + interval '10 days 2 hours', now() + interval '5 days');
  insert into public.seat_assignments (tenant_id, exam_session_id, student_id, room_id, seat_number) values
    ('0a000000-0000-4000-8000-00000000000a', '70000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000004',
     '10000000-0000-4000-8000-000000000005', 'A1');
  failed := false;
  begin
    insert into public.seat_assignments (tenant_id, exam_session_id, student_id, room_id, seat_number) values
      ('0a000000-0000-4000-8000-00000000000a', '70000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000005',
       '10000000-0000-4000-8000-000000000005', 'A2');
  exception when check_violation then
    failed := true;
  end;
  assert failed, 'seats never exceed the room''s exam capacity';

  insert into public.surveys (id, tenant_id, title, questions, opens_at, closes_at) values
    ('70000000-0000-4000-8000-000000000002', '0a000000-0000-4000-8000-00000000000a', 'Campus services survey',
     '[{"key": "q1", "type": "rating", "prompt": "How satisfied are you?"}]', now() - interval '1 hour', now() + interval '1 day');
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  assert (select count(*) from public.seat_assignments) = 0, 'seat numbers stay hidden until released';

  perform public.submit_survey_response('70000000-0000-4000-8000-000000000002', '{"q1": 4}');
  begin
    perform public.submit_survey_response('70000000-0000-4000-8000-000000000002', '{"q1": 5}');
  exception when unique_violation then
    failed := true;
  end;
  assert failed, 'each person answers a survey once';
end;
$$;
reset role;

do $$
begin
  assert (select respondent_id from public.survey_responses where survey_id = '70000000-0000-4000-8000-000000000002') is null,
    'anonymous survey answers carry no user id';
end;
$$;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000005", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  assert (select count(*) from public.directory_search('Sara')) = 1, 'the directory finds classmates';
  assert (select email from public.directory_search('Sara')) is null, 'student emails are hidden from other students';

  update public.user_profiles set bio = 'Second-year SWE' where user_id = 'a0000000-0000-4000-8000-000000000005';
  begin
    update public.user_profiles set department_id = '10000000-0000-4000-8000-000000000002'
    where user_id = 'a0000000-0000-4000-8000-000000000005';
  exception when insufficient_privilege then
    failed := true;
  end;
  assert failed, 'students cannot move themselves into a department';
end;
$$;
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;
do $$
begin
  assert (select email from public.directory_search('Sara')) = 'sara@a.test', 'staff see student emails';
end;
$$;
reset role;

-- Office-hour bookings cannot overlap for the same member of staff.
select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;
insert into public.appointments (tenant_id, staff_id, requester_id, starts_at, ends_at) values
  ('0a000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000004',
   date_trunc('hour', now()) + interval '1 day', date_trunc('hour', now()) + interval '1 day 15 minutes');
reset role;

select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000005", "role": "authenticated"}', true);
set local role authenticated;
do $$
declare
  failed boolean := false;
begin
  begin
    insert into public.appointments (tenant_id, staff_id, requester_id, starts_at, ends_at) values
      ('0a000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000005',
       date_trunc('hour', now()) + interval '1 day', date_trunc('hour', now()) + interval '1 day 15 minutes');
  exception when exclusion_violation then
    failed := true;
  end;
  assert failed, 'a staff member cannot be double-booked';
end;
$$;
reset role;

select ok(true, 'All smoke tests passed');
select * from finish();

rollback;
