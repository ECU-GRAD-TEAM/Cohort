DROP VIEW public.student_events;

CREATE VIEW public.student_events
WITH (security_invoker = true)
AS
SELECT
    e.id AS event_id,
    e.kind::text AS event_kind,
    e.title,
    e.description,
    e.starts_at,
    e.ends_at,
    e.location_text,
    b.code AS building_code,
    b.name AS building_name,
    r.code AS room_code,
    COALESCE(r.name, r.code) AS room_name,
    e.capacity,
    e.waitlist_enabled,
    e.registration_opens_at,
    e.registration_closes_at,
    (er.event_id IS NOT NULL) AS has_registration_record,
    er.status::text AS registration_status,
    er.registered_at
FROM public.events AS e
LEFT JOIN public.rooms AS r
    ON r.id = e.room_id
   AND r.tenant_id = e.tenant_id
LEFT JOIN public.buildings AS b
    ON b.id = r.building_id
   AND b.tenant_id = r.tenant_id
LEFT JOIN public.event_registrations AS er
    ON er.event_id = e.id
   AND er.tenant_id = e.tenant_id
   AND er.user_id = (SELECT auth.uid());

REVOKE ALL ON public.student_events FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON public.student_events FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_events TO authenticated;
