-- Allow an academic calendar to be configured before official dates are announced.
ALTER TABLE public.academic_years
  ALTER COLUMN starts_on DROP NOT NULL,
  ALTER COLUMN ends_on DROP NOT NULL;

ALTER TABLE public.terms
  ALTER COLUMN starts_on DROP NOT NULL,
  ALTER COLUMN ends_on DROP NOT NULL;

-- Seed ECU's 2026/2027 calendar skeleton without inventing academic dates.
DO $$
DECLARE
  v_tenant_id uuid := '97325228-75cb-4a36-b103-9da28968c660';
  v_calendar_id uuid;
  v_academic_year_id uuid;
BEGIN
  SELECT id INTO v_calendar_id
  FROM public.academic_calendars
  WHERE tenant_id = v_tenant_id AND code = 'ECU_MAIN';

  IF v_calendar_id IS NULL THEN
    INSERT INTO public.academic_calendars
      (tenant_id, faculty_id, code, name, timezone, is_default, is_active)
    VALUES
      (v_tenant_id, NULL, 'ECU_MAIN', 'ECU Academic Calendar', 'Africa/Cairo', true, true)
    RETURNING id INTO v_calendar_id;
  END IF;

  SELECT id INTO v_academic_year_id
  FROM public.academic_years
  WHERE tenant_id = v_tenant_id
    AND calendar_id = v_calendar_id
    AND code = '2026-2027';

  IF v_academic_year_id IS NULL THEN
    INSERT INTO public.academic_years
      (tenant_id, calendar_id, code, name, starts_on, ends_on, status)
    VALUES
      (v_tenant_id, v_calendar_id, '2026-2027',
       'Academic Year 2026/2027', NULL, NULL, 'planned')
    RETURNING id INTO v_academic_year_id;
  END IF;

  INSERT INTO public.terms
    (tenant_id, code, name, starts_on, ends_on, status,
     academic_year_id, term_kind, sequence_number,
     instructional_starts_on, instructional_ends_on,
     registration_opens_at, registration_closes_at, add_drop_ends_at)
  SELECT v_tenant_id, v.code, v.name, NULL, NULL, 'planned',
         v_academic_year_id, v.term_kind, v.sequence_number,
         NULL, NULL, NULL, NULL, NULL
  FROM (VALUES
    ('2026-2027-FALL',   'Fall 2026/2027',   'fall'::public.academic_term_kind,   1),
    ('2026-2027-SPRING', 'Spring 2026/2027', 'spring'::public.academic_term_kind, 2),
    ('2026-2027-SUMMER', 'Summer 2026/2027', 'summer'::public.academic_term_kind, 3)
  ) AS v(code, name, term_kind, sequence_number)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.terms existing
    WHERE existing.tenant_id = v_tenant_id
      AND existing.code = v.code
  );
END $$;