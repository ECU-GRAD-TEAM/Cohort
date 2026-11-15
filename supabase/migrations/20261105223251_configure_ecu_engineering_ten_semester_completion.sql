-- Configure ECU Engineering and Technology for the confirmed 10-semester (5-year) pathway.
-- Semester 8 remains the programme-selection point; semester 10 is the expected completion endpoint.
ALTER TABLE public.faculty_academic_pathways
  ADD COLUMN IF NOT EXISTS expected_completion_level_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'faculty_pathways_expected_completion_level_fkey'
      AND conrelid = 'public.faculty_academic_pathways'::regclass
  ) THEN
    ALTER TABLE public.faculty_academic_pathways
      ADD CONSTRAINT faculty_pathways_expected_completion_level_fkey
      FOREIGN KEY (expected_completion_level_id, tenant_id)
      REFERENCES public.academic_levels(id, tenant_id)
      ON DELETE RESTRICT;
  END IF;
END $$;

INSERT INTO public.academic_levels
  (tenant_id, faculty_id, code, name, sequence_number, period_unit, stage_key, is_terminal, is_active)
SELECT t.id, f.id, 'SEMESTER_' || n, 'Semester ' || n, n, 'semester',
       CASE WHEN n <= 2 THEN 'preparatory'
            WHEN n <= 7 THEN 'departmental'
            ELSE 'programme' END,
       n = 10, true
FROM public.tenants t
JOIN public.faculties f ON f.tenant_id = t.id AND f.code = 'ENG'
CROSS JOIN generate_series(9, 10) AS n
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, faculty_id, code) DO UPDATE
SET name = EXCLUDED.name,
    sequence_number = EXCLUDED.sequence_number,
    period_unit = EXCLUDED.period_unit,
    stage_key = EXCLUDED.stage_key,
    is_terminal = EXCLUDED.is_terminal,
    is_active = true;

UPDATE public.academic_levels
SET is_terminal = false, stage_key = 'programme'
WHERE tenant_id = (SELECT id FROM public.tenants WHERE slug = 'ecu')
  AND faculty_id = (SELECT id FROM public.faculties WHERE code = 'ENG' AND tenant_id = (SELECT id FROM public.tenants WHERE slug = 'ecu'))
  AND sequence_number = 8;

UPDATE public.faculty_academic_pathways p
SET expected_completion_level_id = completion.id,
    updated_at = now()
FROM public.academic_levels completion
WHERE completion.tenant_id = p.tenant_id
  AND completion.faculty_id = p.faculty_id
  AND completion.sequence_number = 10
  AND p.tenant_id = (SELECT id FROM public.tenants WHERE slug = 'ecu')
  AND p.faculty_id = (SELECT id FROM public.faculties WHERE code = 'ENG' AND tenant_id = p.tenant_id);
