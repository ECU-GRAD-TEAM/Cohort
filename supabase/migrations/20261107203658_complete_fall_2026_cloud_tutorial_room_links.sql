with room_map(group_code,day_of_week,starts_at,ends_at) as (values
('SA-G1',3,'13:30'::time,'14:30'::time),
('SA-G2',3,'10:30'::time,'11:30'::time)
)
update public.section_meetings sm set room_id=r.id
from public.sections s join public.course_offerings o on o.id=s.offering_id
join public.courses c on c.id=o.course_id join public.terms t on t.id=o.term_id
join room_map m on m.group_code=s.group_code
join public.buildings b on b.tenant_id=s.tenant_id and b.code='D'
join public.rooms r on r.tenant_id=s.tenant_id and r.building_id=b.id and r.code='101'
where sm.section_id=s.id and sm.offering_id=o.id and sm.day_of_week=m.day_of_week
and sm.starts_at=m.starts_at and sm.ends_at=m.ends_at
and regexp_replace(upper(c.code),'[^A-Z0-9]','','g')='SET472' and t.code='2026-2027-FALL';
