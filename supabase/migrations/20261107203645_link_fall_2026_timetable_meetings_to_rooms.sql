-- Backfill room references for timetable sessions using the room code
-- and building letter supplied by the official timetable.
with room_map(group_code,course_code,day_of_week,starts_at,ends_at,building_code,room_code) as (values
('SA-G1+G2','SET 412',0,'08:30'::time,'09:30'::time,'A','308'),
('SA-G1+G2','SET 392',0,'14:30'::time,'16:30'::time,'A','207'),
('DMC-G1','SET 412',0,'10:30'::time,'11:30'::time,'D','104'),
('DMC-G1','SET 473',0,'11:30'::time,'13:30'::time,'D','110'),
('SA-G1','SET 392',1,'08:30'::time,'09:30'::time,'A','311'),
('SA-G1','SET 411',1,'10:30'::time,'12:30'::time,'A','311'),
('SA-G1','SET 412',1,'14:30'::time,'16:30'::time,'A','311'),
('SA-G2','SET 412',1,'08:30'::time,'10:30'::time,'A','313'),
('SA-G2','SET 392',1,'10:30'::time,'11:30'::time,'A','313'),
('SA-G2','SET 411',1,'14:30'::time,'16:30'::time,'A','313'),
('DMC-G1','SET 411',1,'08:30'::time,'10:30'::time,'A','206'),
('DMC-G1','SET 412',1,'10:30'::time,'12:30'::time,'A','206'),
('DMC-G1','SET 473',1,'14:30'::time,'15:30'::time,'A','206'),
('SA-G1+G2','SET 411',3,'08:30'::time,'09:30'::time,'A','312'),
('SA-G1','SET 413',3,'10:30'::time,'11:30'::time,'A','311'),
('SA-G2','SET 413',3,'12:30'::time,'13:30'::time,'A','311'),
('DMC-G1','SET 413',3,'08:30'::time,'09:30'::time,'A','311'),
('DMC-G1','SET 411',3,'09:30'::time,'11:30'::time,'D','110'),
('DMC-G1','SET 472',3,'14:30'::time,'15:30'::time,'D','101'),
('SA-G1+G2','SET 472',4,'08:30'::time,'09:30'::time,'A','202'),
('SA-G1+G2','SET 413',4,'09:30'::time,'11:30'::time,'A','208'),
('DMC-G1','SET 413',4,'08:30'::time,'09:30'::time,'D','103'),
('DMC-G1','SET 472',4,'13:30'::time,'14:30'::time,'D','208')
)
update public.section_meetings sm set room_id=r.id
from public.sections s join public.course_offerings o on o.id=s.offering_id join public.courses c on c.id=o.course_id
join public.terms t on t.id=o.term_id join room_map m on m.group_code=s.group_code
and regexp_replace(upper(m.course_code),'[^A-Z0-9]','','g')=regexp_replace(upper(c.code),'[^A-Z0-9]','','g')
join public.buildings b on b.tenant_id=s.tenant_id and b.code=m.building_code
join public.rooms r on r.tenant_id=s.tenant_id and r.building_id=b.id and r.code=m.room_code
where sm.section_id=s.id and sm.offering_id=o.id and sm.day_of_week=m.day_of_week
and sm.starts_at=m.starts_at and sm.ends_at=m.ends_at and t.code='2026-2027-FALL';
