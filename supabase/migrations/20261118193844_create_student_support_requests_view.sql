CREATE OR REPLACE VIEW public.student_support_requests
WITH (security_invoker = true)
AS
SELECT
  t.id AS request_id,
  t.tenant_id,
  t.kind::text AS request_kind,
  t.category,
  t.subject,
  t.description,
  t.status::text AS status,
  t.priority::text AS priority,
  d.id AS department_id,
  d.code AS department_code,
  d.name AS department_name,
  t.sla_due_at,
  t.first_response_at,
  t.resolved_at,
  t.created_at,
  t.updated_at,
  COALESCE(comments.public_comments, '[]'::jsonb) AS public_comments
FROM public.tickets AS t
LEFT JOIN public.departments AS d
  ON d.id = t.department_id
 AND d.tenant_id = t.tenant_id
LEFT JOIN LATERAL (
  SELECT jsonb_agg(
    jsonb_build_object(
      'comment_id', tc.id,
      'body', tc.body,
      'created_at', tc.created_at
    ) ORDER BY tc.created_at ASC
  ) AS public_comments
  FROM public.ticket_comments AS tc
  WHERE tc.ticket_id = t.id
    AND tc.tenant_id = t.tenant_id
    AND tc.is_internal = false
) AS comments ON true
WHERE t.requester_id = (SELECT auth.uid());

REVOKE ALL ON public.student_support_requests FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.student_support_requests FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_support_requests TO authenticated;
