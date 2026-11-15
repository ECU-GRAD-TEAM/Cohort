-- Department leadership is managed through personnel_appointments.
-- Remove the redundant direct department head reference.
ALTER TABLE public.departments
  DROP COLUMN IF EXISTS head_id;
