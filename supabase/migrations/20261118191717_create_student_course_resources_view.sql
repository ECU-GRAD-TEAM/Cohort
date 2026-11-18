-- Student-visible course resources. SECURITY INVOKER preserves the source tables' RLS policies.
-- Only currently enrolled offerings are considered; materials and documents must also pass
-- their own student-facing publication, release, scope, and audience policies.
CREATE OR REPLACE VIEW public.student_course_resources
WITH (security_invoker = true)
AS
WITH student_offerings AS (
  SELECT e.tenant_id, e.student_id, e.offering_id, o.course_id, o.term_id
  FROM public.enrollments AS e
  JOIN public.course_offerings AS o
    ON o.id = e.offering_id AND o.tenant_id = e.tenant_id
  WHERE e.student_id = (SELECT auth.uid())
    AND e.status = 'enrolled'::public.enrollment_status
)
SELECT
  so.tenant_id, so.student_id, so.offering_id,
  c.id AS course_id, c.code AS course_code, c.title AS course_title,
  t.id AS term_id, t.code AS term_code, t.name AS term_name,
  ay.id AS academic_year_id, ay.code AS academic_year_code, ay.name AS academic_year_name,
  m.id AS resource_id, 'material'::text AS resource_source,
  m.title AS resource_title, m.description AS resource_description,
  m.kind::text AS resource_kind, m.origin::text AS resource_origin,
  m.created_at AS resource_created_at, m.release_at AS available_at,
  NULL::integer AS document_version, NULL::text AS document_language,
  NULL::date AS effective_from, NULL::date AS effective_until,
  NULL::timestamptz AS document_published_at
FROM student_offerings AS so
JOIN public.materials AS m
  ON m.offering_id = so.offering_id AND m.tenant_id = so.tenant_id
JOIN public.courses AS c
  ON c.id = so.course_id AND c.tenant_id = so.tenant_id
JOIN public.terms AS t
  ON t.id = so.term_id AND t.tenant_id = so.tenant_id
LEFT JOIN public.academic_years AS ay
  ON ay.id = t.academic_year_id AND ay.tenant_id = t.tenant_id
WHERE m.is_published AND (m.release_at IS NULL OR m.release_at <= now())
UNION ALL
SELECT
  so.tenant_id, so.student_id, so.offering_id,
  c.id AS course_id, c.code AS course_code, c.title AS course_title,
  t.id AS term_id, t.code AS term_code, t.name AS term_name,
  ay.id AS academic_year_id, ay.code AS academic_year_code, ay.name AS academic_year_name,
  d.id AS resource_id, 'document'::text AS resource_source,
  d.title AS resource_title, NULL::text AS resource_description,
  d.kind::text AS resource_kind, NULL::text AS resource_origin,
  d.created_at AS resource_created_at, dv.published_at AS available_at,
  dv.version AS document_version, dv.language AS document_language,
  dv.effective_from, dv.effective_until, dv.published_at AS document_published_at
FROM student_offerings AS so
JOIN public.documents AS d
  ON d.offering_id = so.offering_id AND d.tenant_id = so.tenant_id
JOIN public.courses AS c
  ON c.id = so.course_id AND c.tenant_id = so.tenant_id
JOIN public.terms AS t
  ON t.id = so.term_id AND t.tenant_id = so.tenant_id
LEFT JOIN public.academic_years AS ay
  ON ay.id = t.academic_year_id AND ay.tenant_id = t.tenant_id
JOIN LATERAL (
  SELECT v.version, v.language, v.effective_from, v.effective_until, v.published_at
  FROM public.document_versions AS v
  WHERE v.document_id = d.id AND v.tenant_id = d.tenant_id
    AND v.published_at IS NOT NULL
  ORDER BY v.version DESC, v.published_at DESC
  LIMIT 1
) AS dv ON true
WHERE d.scope = 'offering'::public.document_scope
  AND d.status = 'published'::public.document_status
  AND d.kind = 'course_material'::public.document_kind;

REVOKE ALL ON public.student_course_resources FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.student_course_resources FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_course_resources TO authenticated;
