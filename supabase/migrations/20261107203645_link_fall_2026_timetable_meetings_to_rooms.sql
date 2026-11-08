-- Initial room-link pass: this legacy statement only links a room when a
-- room code was previously stored in notes. The following corrective
-- migration performs the authoritative timetable-to-room mapping.
update public.section_meetings sm
set room_id = r.id
from public.sections s
join public.course_offerings o on o.id=s.offering_id
join public.courses c on c.id=o.course_id
join public.terms t on t.id=o.term_id
join public.rooms r on r.tenant_id=s.tenant_id
join public.buildings b on b.id=r.building_id and b.tenant_id=r.tenant_id
where sm.section_id=s.id
  and sm.offering_id=o.id
  and t.code='2026-2027-FALL'
  and sm.room_id is null
  and sm.notes is null
  and r.code = substring(sm.notes from 1 for 3)
  and b.code = substring(sm.notes from 4 for 1);
