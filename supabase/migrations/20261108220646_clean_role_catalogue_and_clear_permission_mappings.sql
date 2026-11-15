-- Remove the approved role definitions and clear every role-permission mapping.
-- The live migration version was applied before its file was committed; this file
-- restores that migration to version control and includes the subsequent President
-- display-name correction so fresh database replays reach the same catalogue state.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- The user explicitly requested clearing every mapping, not only mappings for
-- the roles being removed.
DELETE FROM public.role_permissions;

-- The live catalogue stores "Laboratory Technician" under lab_technician.
ALTER TABLE public.roles DISABLE TRIGGER roles_guard_identity_fields;

DELETE FROM public.roles
WHERE key IN (
  'administrator',
  'admission_officer',
  'hr_manager',
  'hr_officer',
  'lab_technician',
  'laboratory_technician',
  'quality_assurance_director',
  'registrar',
  'support_technician',
  'system_administrator',
  'data_protection_officer'
);

UPDATE public.roles
SET key = 'academic_advisor',
    name = 'Academic Advisor'
WHERE key = 'advisor';

UPDATE public.roles
SET key = 'it_officer',
    name = 'IT Officer'
WHERE key = 'it_staff';

UPDATE public.roles
SET key = 'president',
    name = 'President'
WHERE key = 'university_president';

UPDATE public.roles
SET name = 'Teaching Assistant'
WHERE key = 'teaching_assistant';

-- Ensure the intended President display name if the key was already renamed
-- in an earlier direct database operation.
UPDATE public.roles
SET name = 'President'
WHERE key = 'president'
  AND name IS DISTINCT FROM 'President';

ALTER TABLE public.roles ENABLE TRIGGER roles_guard_identity_fields;

COMMIT;
