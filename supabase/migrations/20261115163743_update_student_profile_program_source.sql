CREATE OR REPLACE VIEW public.student_profile
WITH (security_invoker = true)
AS
SELECT
  u.tenant_id,
  u.id AS student_id,
  COALESCE(
    NULLIF(BTRIM(up.display_name), ''),
    NULLIF(BTRIM(CONCAT_WS(' ', up.first_name, up.last_name)), '')
  ) AS full_name,
  u.email,
  prog.id AS program_id,
  prog.name AS program_name,
  confirmed_spec.specialization_id,
  confirmed_spec.specialization_name,
  dept.id AS department_id,
  dept.name AS department_name,
  fac.id AS faculty_id,
  fac.name AS faculty_name,
  COALESCE(NULLIF(BTRIM(year_level.display_name), ''),
           NULLIF(BTRIM(year_level.name), '')) AS academic_level,
  u.status::text AS enrollment_status
FROM public.users AS u
LEFT JOIN public.user_profiles AS up
  ON up.user_id = u.id
 AND up.tenant_id = u.tenant_id
LEFT JOIN public.departments AS dept
  ON dept.id = up.department_id
 AND dept.tenant_id = up.tenant_id
LEFT JOIN public.faculties AS fac
  ON fac.id = up.faculty_id
 AND fac.tenant_id = up.tenant_id
LEFT JOIN public.student_academic_progressions AS progression
  ON progression.student_id = u.id
 AND progression.tenant_id = u.tenant_id
LEFT JOIN public.academic_year_levels AS year_level
  ON year_level.id = progression.current_year_level_id
 AND year_level.tenant_id = progression.tenant_id
LEFT JOIN LATERAL (
  SELECT p.id, p.name
  FROM public.student_programs AS membership
  JOIN public.programs AS p
    ON p.id = membership.program_id
   AND p.tenant_id = membership.tenant_id
  WHERE membership.student_id = u.id
    AND membership.tenant_id = u.tenant_id
    AND membership.status::text = 'active'
  ORDER BY membership.admitted_on DESC NULLS LAST,
           membership.program_id
  LIMIT 1
) AS prog ON TRUE
LEFT JOIN LATERAL (
  SELECT ss.specialization_id, s.name AS specialization_name
  FROM public.student_specialization_selections AS ss
  JOIN public.specializations AS s
    ON s.id = ss.specialization_id
   AND s.program_id = ss.program_id
   AND s.tenant_id = ss.tenant_id
  WHERE ss.student_id = u.id
    AND ss.tenant_id = u.tenant_id
    AND ss.status = 'approved'
    AND (ss.starts_on IS NULL OR ss.starts_on <= CURRENT_DATE)
    AND (ss.ends_on IS NULL OR ss.ends_on >= CURRENT_DATE)
    AND prog.id IS NOT NULL
    AND ss.program_id = prog.id
  ORDER BY ss.starts_on DESC NULLS LAST,
           ss.reviewed_at DESC NULLS LAST,
           ss.requested_at DESC
  LIMIT 1
) AS confirmed_spec ON TRUE
WHERE u.id = (SELECT auth.uid())
  AND u.user_type = 'non_staff'::public.user_type;

GRANT SELECT ON public.student_profile TO authenticated;
REVOKE ALL ON public.student_profile FROM anon, PUBLIC;
