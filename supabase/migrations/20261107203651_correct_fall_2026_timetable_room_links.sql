-- Room codes are three digits; the building is stored separately.
-- This migration is retained as a corrective migration after the first room-link pass.
update public.section_meetings set notes='Room assignment is recorded in the linked room_id.' where room_id is not null and notes is null;
