-- Apply the user-approved Fall 2026/2027 room assignments.
-- Resolve room UUIDs from tenant/building/room codes; do not hardcode generated IDs.
-- Graduation-project blocks intentionally remain without a room.
do $$
declare
  v_target_count integer;
  v_missing_room_count integer;
  v_updated_count integer;
begin
  with approved(day_of_week, course_code, group_code, meeting_type, starts_at, ends_at, building_code, room_code) as (
    values
      (0, 'SET 412', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time, 'A', '308'),
      (0, 'SET 412', 'DMC-G1', 'lecture', '10:30'::time, '12:30'::time, 'D', '104'),
      (0, 'SET 473', 'DMC-G1', 'lecture', '12:30'::time, '14:30'::time, 'D', '110'),
      (0, 'SET 497', 'SA-G1+G2', 'graduation_project', '10:30'::time, '14:30'::time, null::text, null::text),
      (0, 'SET 392', 'SA-G1+G2', 'lecture', '14:30'::time, '16:30'::time, 'A', '207'),
      (0, 'SET 497', 'DMC-G1', 'graduation_project', '14:30'::time, '18:30'::time, null::text, null::text),
      (1, 'SET 392', 'SA-G1', 'tutorial', '08:30'::time, '11:30'::time, 'A', '311'),
      (1, 'SET 411', 'DMC-G1', 'tutorial_lab', '08:30'::time, '11:30'::time, 'A', '206'),
      (1, 'SET 412', 'SA-G2', 'tutorial_lab', '08:30'::time, '11:30'::time, 'A', '313'),
      (1, 'SET 392', 'SA-G2', 'tutorial', '11:30'::time, '14:30'::time, 'A', '313'),
      (1, 'SET 411', 'SA-G1', 'tutorial_lab', '11:30'::time, '14:30'::time, 'A', '311'),
      (1, 'SET 412', 'DMC-G1', 'tutorial_lab', '11:30'::time, '14:30'::time, 'A', '206'),
      (1, 'SET 412', 'SA-G1', 'tutorial_lab', '14:30'::time, '17:30'::time, 'A', '311'),
      (1, 'SET 411', 'SA-G2', 'tutorial_lab', '14:30'::time, '17:30'::time, 'A', '313'),
      (1, 'SET 473', 'DMC-G1', 'tutorial', '14:30'::time, '17:30'::time, 'A', '206'),
      (3, 'SET 411', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time, 'A', '312'),
      (3, 'SET 413', 'DMC-G1', 'tutorial_lab', '08:30'::time, '10:30'::time, 'A', '311'),
      (3, 'SET 411', 'DMC-G1', 'lecture', '10:30'::time, '12:30'::time, 'D', '110'),
      (3, 'SET 413', 'SA-G1', 'tutorial_lab', '10:30'::time, '12:30'::time, 'A', '311'),
      (3, 'SET 472', 'SA-G2', 'tutorial', '10:30'::time, '12:30'::time, 'D', '101'),
      (3, 'SET 413', 'SA-G2', 'tutorial_lab', '12:30'::time, '14:30'::time, 'A', '311'),
      (3, 'SET 472', 'SA-G1', 'tutorial', '12:30'::time, '14:30'::time, 'D', '101'),
      (3, 'SET 472', 'DMC-G1', 'tutorial', '14:30'::time, '16:30'::time, 'D', '101'),
      (4, 'SET 413', 'DMC-G1', 'lecture', '08:30'::time, '10:30'::time, 'D', '103'),
      (4, 'SET 472', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time, 'A', '202'),
      (4, 'SET 413', 'SA-G1+G2', 'lecture', '10:30'::time, '12:30'::time, 'A', '208'),
      (4, 'SET 472', 'DMC-G1', 'lecture', '12:30'::time, '14:30'::time, 'D', '208')
  ),
  targets as (
    select sm.id, a.room_code, r.id as expected_room_id
    from approved a
    join public.terms t on t.code = '2026-2027-FALL'
    join public.course_offerings co on co.term_id = t.id
    join public.courses c on c.id = co.course_id and c.code = a.course_code
    join public.sections s on s.offering_id = co.id and s.group_code = a.group_code
    join public.section_meetings sm
      on sm.section_id = s.id and sm.offering_id = co.id
     and sm.day_of_week = a.day_of_week and sm.meeting_type = a.meeting_type
     and sm.starts_at = a.starts_at and sm.ends_at = a.ends_at
    left join public.buildings b on b.tenant_id = s.tenant_id and b.code = a.building_code
    left join public.rooms r on r.tenant_id = s.tenant_id and r.building_id = b.id and r.code = a.room_code
  )
  select count(*), count(*) filter (where room_code is not null and expected_room_id is null)
    into v_target_count, v_missing_room_count
    from targets;

  if v_target_count <> 27 then
    raise exception 'Expected 27 approved meeting matches, found %; room assignments not applied', v_target_count;
  end if;
  if v_missing_room_count <> 0 then
    raise exception 'One or more approved room codes could not be resolved; room assignments not applied';
  end if;

  with approved(day_of_week, course_code, group_code, meeting_type, starts_at, ends_at, building_code, room_code) as (
    values
      (0, 'SET 412', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time, 'A', '308'),
      (0, 'SET 412', 'DMC-G1', 'lecture', '10:30'::time, '12:30'::time, 'D', '104'),
      (0, 'SET 473', 'DMC-G1', 'lecture', '12:30'::time, '14:30'::time, 'D', '110'),
      (0, 'SET 497', 'SA-G1+G2', 'graduation_project', '10:30'::time, '14:30'::time, null::text, null::text),
      (0, 'SET 392', 'SA-G1+G2', 'lecture', '14:30'::time, '16:30'::time, 'A', '207'),
      (0, 'SET 497', 'DMC-G1', 'graduation_project', '14:30'::time, '18:30'::time, null::text, null::text),
      (1, 'SET 392', 'SA-G1', 'tutorial', '08:30'::time, '11:30'::time, 'A', '311'),
      (1, 'SET 411', 'DMC-G1', 'tutorial_lab', '08:30'::time, '11:30'::time, 'A', '206'),
      (1, 'SET 412', 'SA-G2', 'tutorial_lab', '08:30'::time, '11:30'::time, 'A', '313'),
      (1, 'SET 392', 'SA-G2', 'tutorial', '11:30'::time, '14:30'::time, 'A', '313'),
      (1, 'SET 411', 'SA-G1', 'tutorial_lab', '11:30'::time, '14:30'::time, 'A', '311'),
      (1, 'SET 412', 'DMC-G1', 'tutorial_lab', '11:30'::time, '14:30'::time, 'A', '206'),
      (1, 'SET 412', 'SA-G1', 'tutorial_lab', '14:30'::time, '17:30'::time, 'A', '311'),
      (1, 'SET 411', 'SA-G2', 'tutorial_lab', '14:30'::time, '17:30'::time, 'A', '313'),
      (1, 'SET 473', 'DMC-G1', 'tutorial', '14:30'::time, '17:30'::time, 'A', '206'),
      (3, 'SET 411', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time, 'A', '312'),
      (3, 'SET 413', 'DMC-G1', 'tutorial_lab', '08:30'::time, '10:30'::time, 'A', '311'),
      (3, 'SET 411', 'DMC-G1', 'lecture', '10:30'::time, '12:30'::time, 'D', '110'),
      (3, 'SET 413', 'SA-G1', 'tutorial_lab', '10:30'::time, '12:30'::time, 'A', '311'),
      (3, 'SET 472', 'SA-G2', 'tutorial', '10:30'::time, '12:30'::time, 'D', '101'),
      (3, 'SET 413', 'SA-G2', 'tutorial_lab', '12:30'::time, '14:30'::time, 'A', '311'),
      (3, 'SET 472', 'SA-G1', 'tutorial', '12:30'::time, '14:30'::time, 'D', '101'),
      (3, 'SET 472', 'DMC-G1', 'tutorial', '14:30'::time, '16:30'::time, 'D', '101'),
      (4, 'SET 413', 'DMC-G1', 'lecture', '08:30'::time, '10:30'::time, 'D', '103'),
      (4, 'SET 472', 'SA-G1+G2', 'lecture', '08:30'::time, '10:30'::time, 'A', '202'),
      (4, 'SET 413', 'SA-G1+G2', 'lecture', '10:30'::time, '12:30'::time, 'A', '208'),
      (4, 'SET 472', 'DMC-G1', 'lecture', '12:30'::time, '14:30'::time, 'D', '208')
  ),
  targets as (
    select sm.id, r.id as expected_room_id
    from approved a
    join public.terms t on t.code = '2026-2027-FALL'
    join public.course_offerings co on co.term_id = t.id
    join public.courses c on c.id = co.course_id and c.code = a.course_code
    join public.sections s on s.offering_id = co.id and s.group_code = a.group_code
    join public.section_meetings sm on sm.section_id = s.id and sm.offering_id = co.id
     and sm.day_of_week = a.day_of_week and sm.meeting_type = a.meeting_type
     and sm.starts_at = a.starts_at and sm.ends_at = a.ends_at
    left join public.buildings b on b.tenant_id = s.tenant_id and b.code = a.building_code
    left join public.rooms r on r.tenant_id = s.tenant_id and r.building_id = b.id and r.code = a.room_code
  ),
  updated as (
    update public.section_meetings sm
       set room_id = targets.expected_room_id
      from targets
     where sm.id = targets.id
    returning sm.id
  )
  select count(*) into v_updated_count from updated;

  if v_updated_count <> 27 then
    raise exception 'Expected to apply 27 approved room assignments, applied %', v_updated_count;
  end if;
end $$;
