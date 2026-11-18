CREATE OR REPLACE VIEW public.student_academic_calendar
WITH (security_invoker = true)
AS
SELECT
  e.id AS event_id,
  e.tenant_id,
  sp.student_id,
  e.term_id,
  t.code AS term_code,
  t.name AS term_name,
  ay.id AS academic_year_id,
  ay.code AS academic_year_code,
  ay.name AS academic_year_name,
  ay.status::text AS academic_year_status,
  cal.id AS calendar_id,
  cal.code AS calendar_code,
  cal.name AS calendar_name,
  cal.timezone AS calendar_timezone,
  e.kind::text AS event_kind,
  e.title AS event_title,
  e.description,
  e.location,
  e.starts_on,
  e.ends_on,
  CASE
    WHEN current_date < e.starts_on THEN 'upcoming'
    WHEN current_date > e.ends_on THEN 'past'
    ELSE 'ongoing'
  END AS event_state,
  e.created_at,
  e.updated_at
FROM public.student_profile AS sp
JOIN public.academic_calendar_events AS e
  ON e.tenant_id = sp.tenant_id
LEFT JOIN public.terms AS t
  ON t.id = e.term_id
 AND t.tenant_id = e.tenant_id
LEFT JOIN public.academic_years AS ay
  ON ay.id = t.academic_year_id
 AND ay.tenant_id = t.tenant_id
LEFT JOIN public.academic_calendars AS cal
  ON cal.id = ay.calendar_id
 AND cal.tenant_id = ay.tenant_id
WHERE sp.student_id = (SELECT auth.uid())
  AND (
    e.term_id IS NULL
    OR cal.faculty_id IS NULL
    OR cal.faculty_id = sp.faculty_id
  );

REVOKE ALL ON public.student_academic_calendar FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.student_academic_calendar FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.student_academic_calendar TO authenticated;
