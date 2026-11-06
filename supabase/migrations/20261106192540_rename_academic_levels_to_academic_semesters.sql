ALTER TABLE public.academic_levels RENAME TO academic_semesters;

DO $$
DECLARE
  fn record;
  definition text;
BEGIN
  FOR fn IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ILIKE '%academic_levels%'
  LOOP
    definition := pg_get_functiondef(fn.oid);
    definition := replace(definition, 'public.academic_levels', 'public.academic_semesters');
    definition := replace(definition, 'academic_levels', 'academic_semesters');
    EXECUTE definition;
  END LOOP;
END $$;

COMMENT ON TABLE public.academic_semesters IS
  'The ten curriculum semesters in the academic programme; distinct from the five annual academic progression levels in academic_year_levels.';
