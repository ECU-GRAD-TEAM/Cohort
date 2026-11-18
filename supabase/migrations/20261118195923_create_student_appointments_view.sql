CREATE OR REPLACE VIEW public.student_appointments
WITH (security_invoker = true)
AS
SELECT
  a.id AS appointment_id,
  a.starts_at,
  a.ends_at,
  a.status::text AS status,
  a.mode::text AS meeting_mode,
  a.topic,
  a.location,
  a.cancel_reason,
  a.created_at
FROM public.appointments AS a
WHERE a.requester_id = (SELECT auth.uid());

REVOKE ALL ON public.student_appointments FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.student_appointments FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_appointments TO authenticated;
