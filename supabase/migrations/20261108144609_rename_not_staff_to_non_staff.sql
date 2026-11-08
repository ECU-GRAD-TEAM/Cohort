-- Rename the broad non-employee classification without changing authorization semantics.
ALTER TYPE public.user_type RENAME VALUE 'not_staff' TO 'non_staff';

-- Update stored function source that compares or parses the old enum label.
DO $migration$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prokind IN ('f', 'p')
      AND n.nspname IN ('public', 'private')
      AND p.prosrc ILIKE '%not_staff%'
  LOOP
    EXECUTE replace(
      pg_get_functiondef(fn.oid),
      '''not_staff''',
      '''non_staff'''
    );
  END LOOP;
END
$migration$;
