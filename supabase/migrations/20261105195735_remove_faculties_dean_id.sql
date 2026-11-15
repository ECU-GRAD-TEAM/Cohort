-- Remove the denormalized dean reference from faculties.
-- Faculty leadership is managed through personnel_appointments.

ALTER TABLE public.faculties
  DROP CONSTRAINT IF EXISTS faculties_dean_id_tenant_id_fkey;

DROP INDEX IF EXISTS public.faculties_dean_id_tenant_id_idx;

ALTER TABLE public.faculties
  DROP COLUMN IF EXISTS dean_id;
