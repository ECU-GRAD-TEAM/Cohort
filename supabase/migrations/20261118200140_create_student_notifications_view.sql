CREATE OR REPLACE VIEW public.student_notifications
WITH (security_invoker = true)
AS
SELECT
  n.id AS notification_id,
  n.category,
  n.severity::text AS severity,
  n.title,
  n.body,
  n.link,
  n.created_at,
  (n.read_at IS NOT NULL) AS is_read,
  n.read_at
FROM public.notifications AS n
WHERE n.user_id = (SELECT auth.uid())
  AND n.tenant_id = (SELECT private.tenant_id());

REVOKE ALL ON public.student_notifications FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.student_notifications FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_notifications TO authenticated;
