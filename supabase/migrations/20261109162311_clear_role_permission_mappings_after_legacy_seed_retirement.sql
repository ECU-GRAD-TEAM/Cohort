-- Keep the previously approved role catalogue free of permission mappings.
BEGIN;
SET LOCAL lock_timeout = '5s';
DELETE FROM public.role_permissions;
COMMIT;
