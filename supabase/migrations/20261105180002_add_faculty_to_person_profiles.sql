-- Add a direct faculty relationship to each person profile.
-- Keep it nullable to support institution-wide accounts that are not assigned
-- to a faculty. Department remains optional.

ALTER TABLE public.person_profiles
  ADD COLUMN IF NOT EXISTS faculty_id uuid;

-- Backfill faculty from the existing department relationship.
UPDATE public.person_profiles AS pp
SET faculty_id = d.faculty_id
FROM public.departments AS d
WHERE pp.department_id = d.id
  AND pp.tenant_id = d.tenant_id
  AND pp.faculty_id IS NULL;

-- Required target key for enforcing that a profile's department belongs
-- to the same faculty and tenant as the profile.
CREATE UNIQUE INDEX IF NOT EXISTS departments_id_faculty_id_tenant_id_uidx
  ON public.departments (id, faculty_id, tenant_id);

-- Faculty must belong to the same tenant as the profile.
ALTER TABLE public.person_profiles
  DROP CONSTRAINT IF EXISTS person_profiles_faculty_id_tenant_id_fkey;

ALTER TABLE public.person_profiles
  ADD CONSTRAINT person_profiles_faculty_id_tenant_id_fkey
  FOREIGN KEY (faculty_id, tenant_id)
  REFERENCES public.faculties (id, tenant_id)
  ON DELETE SET NULL (faculty_id);

-- If a department is assigned, it must belong to the selected faculty.
-- A NULL department is valid (e.g. a dean or faculty-level staff member).
ALTER TABLE public.person_profiles
  DROP CONSTRAINT IF EXISTS person_profiles_department_faculty_tenant_fkey;

ALTER TABLE public.person_profiles
  ADD CONSTRAINT person_profiles_department_faculty_tenant_fkey
  FOREIGN KEY (department_id, faculty_id, tenant_id)
  REFERENCES public.departments (id, faculty_id, tenant_id)
  ON DELETE SET NULL (department_id);
