-- Support faculty-owned and department-owned course catalogue records.
-- Exactly one academic owner is required for every course.

ALTER TABLE public.courses
  ADD COLUMN faculty_id uuid,
  ADD COLUMN lecture_hours numeric,
  ADD COLUMN tutorial_hours numeric,
  ADD COLUMN lab_hours numeric;

ALTER TABLE public.courses
  ALTER COLUMN department_id DROP NOT NULL;

ALTER TABLE public.courses
  ADD CONSTRAINT courses_faculty_id_tenant_id_fkey
    FOREIGN KEY (faculty_id, tenant_id)
    REFERENCES public.faculties (id, tenant_id),
  ADD CONSTRAINT courses_exactly_one_owner_check
    CHECK (
      (faculty_id IS NOT NULL AND department_id IS NULL)
      OR
      (faculty_id IS NULL AND department_id IS NOT NULL)
    ),
  ADD CONSTRAINT courses_lecture_hours_nonnegative_check
    CHECK (lecture_hours IS NULL OR lecture_hours >= 0),
  ADD CONSTRAINT courses_tutorial_hours_nonnegative_check
    CHECK (tutorial_hours IS NULL OR tutorial_hours >= 0),
  ADD CONSTRAINT courses_lab_hours_nonnegative_check
    CHECK (lab_hours IS NULL OR lab_hours >= 0);

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.courses;

CREATE POLICY "academic managers write the catalogue"
ON public.courses
FOR ALL
USING (
  tenant_id = (SELECT private.tenant_id())
  AND (
    (department_id IS NOT NULL
      AND private.has_permission_for_department('academic.manage', department_id))
    OR
    (faculty_id IS NOT NULL
      AND private.has_permission('academic.manage', 'faculty', faculty_id))
  )
)
WITH CHECK (
  tenant_id = (SELECT private.tenant_id())
  AND (
    (department_id IS NOT NULL
      AND private.has_permission_for_department('academic.manage', department_id))
    OR
    (faculty_id IS NOT NULL
      AND private.has_permission('academic.manage', 'faculty', faculty_id))
  )
);
