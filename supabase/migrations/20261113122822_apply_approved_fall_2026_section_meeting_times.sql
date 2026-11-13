-- Apply the approved Fall 2026/2027 section meeting times.
-- Only the 27 reviewed meetings for this term are targeted.
do $$
declare
  v_updated integer;
begin
  with approved(day_of_week, course_code, group_code, meeting_type, starts_at, ends_at) as (
    values
      (0, 'SET 412', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time),
      (0, 'SET 412', 'DMC-G1', 'lecture', '10:30'::time, '12:30'::time),
      (0, 'SET 473', 'DMC-G1', 'lecture', '12:30'::time, '14:30'::time),
      (0, 'SET 497', 'SA-G1+G2', 'graduation_project', '10:30'::time, '14:30'::time),
      (0, 'SET 392', 'SA-G1+G2', 'lecture', '14:30'::time, '16:30'::time),
      (1, 'SET 392', 'SA-G1', 'tutorial', '08:30'::time, '11:30'::time),
      (1, 'SET 411', 'DMC-G1', 'tutorial_lab', '08:30'::time, '11:30'::time),
      (1, 'SET 412', 'SA-G2', 'tutorial_lab', '08:30'::time, '11:30'::time),
      (1, 'SET 392', 'SA-G2', 'tutorial', '11:30'::time, '14:30'::time),
      (1, 'SET 411', 'SA-G1', 'tutorial_lab', '11:30'::time, '14:30'::time),
      (1, 'SET 412', 'DMC-G1', 'tutorial_lab', '11:30'::time, '14:30'::time),
      (1, 'SET 412', 'SA-G1', 'tutorial_lab', '14:30'::time, '17:30'::time),
      (1, 'SET 411', 'SA-G2', 'tutorial_lab', '14:30'::time, '17:30'::time),
      (1, 'SET 473', 'DMC-G1', 'tutorial', '14:30'::time, '17:30'::time),
      (3, 'SET 411', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time),
      (3, 'SET 413', 'DMC-G1', 'tutorial_lab', '08:30'::time, '10:30'::time),
      (3, 'SET 411', 'DMC-G1', 'lecture', '10:30'::time, '12:30'::time),
      (3, 'SET 413', 'SA-G1', 'tutorial_lab', '10:30'::time, '12:30'::time),
      (3, 'SET 472', 'SA-G2', 'tutorial', '10:30'::time, '12:30'::time),
      (3, 'SET 413', 'SA-G2', 'tutorial_lab', '12:30'::time, '14:30'::time),
      (3, 'SET 472', 'SA-G1', 'tutorial', '12:30'::time, '14:30'::time),
      (3, 'SET 472', 'DMC-G1', 'tutorial', '14:30'::time, '16:30'::time),
      (4, 'SET 413', 'DMC-G1', 'lecture', '08:30'::time, '10:30'::time),
      (4, 'SET 472', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time),
      (4, 'SET 413', 'SA-G1+G2', 'lecture', '10:30'::time, '12:30'::time),
      (4, 'SET 472', 'DMC-G1', 'lecture', '12:30'::time, '14:30'::time),
      (0, 'SET 497', 'DMC-G1', 'graduation_project', '14:30'::time, '18:30'::time)
  ),
  updated as (
    update public.section_meetings sm
       set starts_at = a.starts_at,
           ends_at = a.ends_at
      from approved a, public.course_offerings co, public.courses c, public.sections s, public.terms t
     where t.code = '2026-2027-FALL'
       and co.term_id = t.id
       and c.id = co.course_id
       and c.code = a.course_code
       and s.id = sm.section_id
       and s.group_code = a.group_code
       and sm.offering_id = co.id
       and sm.day_of_week = a.day_of_week
       and sm.meeting_type = a.meeting_type
    returning sm.id
  )
  select count(*) into v_updated from updated;

  if v_updated <> 27 then
    raise exception 'Expected to update 27 approved meetings, but updated %; transaction rolled back', v_updated;
  end if;
end $$;
