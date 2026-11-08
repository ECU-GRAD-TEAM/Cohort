-- ECU academic levels are General, First, Second, Third, Fourth.
alter table public.academic_year_levels add column if not exists display_name text;
update public.academic_year_levels
set name=case sequence_number when 1 then 'General Level' when 2 then 'First Level' when 3 then 'Second Level' when 4 then 'Third Level' when 5 then 'Fourth Level' else name end,
display_name=case sequence_number when 1 then 'General Level' when 2 then 'First Level' when 3 then 'Second Level' when 4 then 'Third Level' when 5 then 'Fourth Level' else display_name end
where tenant_id='97325228-75cb-4a36-b103-9da28968c660' and sequence_number between 1 and 5;

alter table public.sections add column if not exists group_code text;

create table if not exists public.section_meetings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 section_id uuid not null, offering_id uuid not null, room_id uuid,
 day_of_week smallint not null check(day_of_week between 0 and 6),
 starts_at time not null, ends_at time not null,
 meeting_type text not null, notes text,
 created_at timestamptz not null default now(),
 constraint section_meetings_time_check check(starts_at<ends_at),
 constraint section_meetings_section_fk foreign key(section_id,tenant_id,offering_id)
  references public.sections(id,tenant_id,offering_id) on delete cascade,
 constraint section_meetings_room_fk foreign key(room_id,tenant_id)
  references public.rooms(id,tenant_id)
);
create index if not exists section_meetings_section_idx on public.section_meetings(section_id);
create index if not exists section_meetings_room_time_idx on public.section_meetings(tenant_id,room_id,day_of_week,starts_at,ends_at);
alter table public.section_meetings enable row level security;
create policy "members read section meetings" on public.section_meetings for select using(tenant_id=(select private.tenant_id()));
create policy "academic managers manage section meetings" on public.section_meetings for all
 using(tenant_id=(select private.tenant_id()) and (select private.has_permission_for_section('academic.manage',section_id)))
 with check(tenant_id=(select private.tenant_id()) and (select private.has_permission_for_section('academic.manage',section_id)));
grant select,insert,update,delete on public.section_meetings to authenticated;

do $$
declare v_tenant uuid:='97325228-75cb-4a36-b103-9da28968c660'; v_term uuid;
begin
 select id into v_term from public.terms where tenant_id=v_tenant and code='2026-2027-FALL';
 if v_term is null then raise exception 'Fall 2026 term not found'; end if;
 insert into public.course_offerings(tenant_id,course_id,term_id,status)
 select v_tenant,c.id,v_term,'draft'::public.offering_status from public.courses c
 where c.tenant_id=v_tenant and regexp_replace(upper(c.code),'[^A-Z0-9]','','g') in ('SET392','SET472','SET473')
 on conflict(course_id,term_id) do nothing;
 insert into public.buildings(tenant_id,code,name) values(v_tenant,'A','Building A'),(v_tenant,'D','Building D')
 on conflict(tenant_id,code) do update set name=excluded.name;
 insert into public.rooms(tenant_id,building_id,code,name,room_type)
 select v_tenant,b.id,r.room_code,r.room_code,'classroom'::public.room_type
 from (values ('A','202'),('A','206'),('A','207'),('A','208'),('A','308'),('A','311'),('A','312'),('A','313'),('D','101'),('D','103'),('D','104'),('D','110'),('D','208')) r(building_code,room_code)
 join public.buildings b on b.tenant_id=v_tenant and b.code=r.building_code
 on conflict(building_id,code) do update set name=excluded.name;
end $$;

create temporary table tmp_fall26_meetings(course_code text,group_code text,section_kind public.section_kind,day_of_week smallint,starts_at time,ends_at time,room_code text,meeting_type text) on commit drop;
insert into tmp_fall26_meetings values
('SET 412','SA-G1+G2','lecture',0,'08:30','09:30','A308','lecture'),
('SET 497','SA-G1+G2','lecture',0,'09:30','13:30',null,'graduation_project'),
('SET 392','SA-G1+G2','lecture',0,'14:30','16:30','A207','lecture'),
('SET 412','DMC-G1','lecture',0,'10:30','11:30','D104','lecture'),
('SET 473','DMC-G1','lecture',0,'11:30','13:30','D110','lecture'),
('SET 497','DMC-G1','lecture',0,'13:30','17:30',null,'graduation_project'),
('SET 392','SA-G1','tutorial',1,'08:30','09:30','A311','tutorial'),
('SET 411','SA-G1','lab',1,'10:30','12:30','A311','tutorial_lab'),
('SET 412','SA-G1','lab',1,'14:30','16:30','A311','tutorial_lab'),
('SET 412','SA-G2','lab',1,'08:30','10:30','A313','tutorial_lab'),
('SET 392','SA-G2','tutorial',1,'10:30','11:30','A313','tutorial'),
('SET 411','SA-G2','lab',1,'14:30','16:30','A313','tutorial_lab'),
('SET 411','DMC-G1','lab',1,'08:30','10:30','A206','tutorial_lab'),
('SET 412','DMC-G1','lab',1,'10:30','12:30','A206','tutorial_lab'),
('SET 473','DMC-G1','tutorial',1,'14:30','15:30','A206','tutorial'),
('SET 411','SA-G1+G2','lecture',3,'08:30','09:30','A312','lecture'),
('SET 413','SA-G1','lab',3,'10:30','11:30','A311','tutorial_lab'),
('SET 472','SA-G1','tutorial',3,'13:30','14:30','D101','tutorial'),
('SET 472','SA-G2','tutorial',3,'10:30','11:30','D101','tutorial'),
('SET 413','SA-G2','lab',3,'12:30','13:30','A311','tutorial_lab'),
('SET 413','DMC-G1','lab',3,'08:30','09:30','A311','tutorial_lab'),
('SET 411','DMC-G1','lecture',3,'09:30','11:30','D110','lecture'),
('SET 472','DMC-G1','tutorial',3,'14:30','15:30','D101','tutorial'),
('SET 472','SA-G1+G2','lecture',4,'08:30','09:30','A202','lecture'),
('SET 413','SA-G1+G2','lecture',4,'09:30','11:30','A208','lecture'),
('SET 413','DMC-G1','lecture',4,'08:30','09:30','D103','lecture'),
('SET 472','DMC-G1','lecture',4,'13:30','14:30','D208','lecture');

insert into public.sections(tenant_id,offering_id,code,kind,group_code)
select distinct o.tenant_id,o.id,replace(m.group_code,'+','-')||'-'||regexp_replace(upper(c.code),'[^A-Z0-9]','','g')||'-'||upper(m.section_kind::text),m.section_kind,m.group_code
from tmp_fall26_meetings m join public.courses c on regexp_replace(upper(c.code),'[^A-Z0-9]','','g')=regexp_replace(upper(m.course_code),'[^A-Z0-9]','','g') and c.tenant_id='97325228-75cb-4a36-b103-9da28968c660
join public.course_offerings o on o.course_id=c.id join public.terms t on t.id=o.term_id and t.code='2026-2027-FALL'
on conflict(offering_id,code) do update set group_code=excluded.group_code,kind=excluded.kind;

insert into public.section_meetings(tenant_id,section_id,offering_id,day_of_week,starts_at,ends_at,meeting_type)
select o.tenant_id,s.id,o.id,m.day_of_week,m.starts_at,m.ends_at,m.meeting_type
from tmp_fall26_meetings m join public.courses c on regexp_replace(upper(c.code),'[^A-Z0-9]','','g')=regexp_replace(upper(m.course_code),'[^A-Z0-9]','','g') and c.tenant_id='97325228-75cb-4a36-b103-9da28968c660
join public.course_offerings o on o.course_id=c.id join public.terms t on t.id=o.term_id and t.code='2026-2027-FALL'
join public.sections s on s.offering_id=o.id and s.group_code=m.group_code and s.kind=m.section_kind
 and s.code=replace(m.group_code,'+','-')||'-'||regexp_replace(upper(c.code),'[^A-Z0-9]','','g')||'-'||upper(m.section_kind::text)
left join public.section_meetings x on x.section_id=s.id and x.day_of_week=m.day_of_week and x.starts_at=m.starts_at and x.ends_at=m.ends_at and x.meeting_type=m.meeting_type
where x.id is null;
