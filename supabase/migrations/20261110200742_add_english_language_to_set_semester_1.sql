-- Add English Language (HUM 011) to SET Semester 1.
insert into public.program_curriculum_courses (
  tenant_id,
  program_id,
  course_id,
  academic_level_id,
  requirement_type,
  is_active
)
select
  '97325228-75cb-4a36-b103-9da28968c660'::uuid,
  '85dddcad-cc84-4b6a-b262-77f435c8f2f8'::uuid,
  '2b29cc2e-2cc3-4b58-b1a2-11ee0591a71d'::uuid,
  'dc7c0850-9320-4a93-a521-5119e22e261c'::uuid,
  'required',
  true
where not exists (
  select 1
  from public.program_curriculum_courses
  where tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
    and program_id = '85dddcad-cc84-4b6a-b262-77f435c8f2f8'
    and course_id = '2b29cc2e-2cc3-4b58-b1a2-11ee0591a71d'
);