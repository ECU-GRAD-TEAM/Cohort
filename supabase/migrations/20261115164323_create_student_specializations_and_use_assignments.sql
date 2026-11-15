-- Separate specialization requests from confirmed student specialization assignments.
-- Pending selection requests remain in student_specialization_selections; this table stores assignments only.

CREATE TABLE public.student_specializations (
  student_id uuid NOT NULL,
  program_id uuid NOT NULL,
  tenant_id uuid NOT NULL,
  specialization_id uuid NOT NULL,
  status public.program_membership_status NOT NULL DEFAULT 'active',
  starts_on date,
  ends_on date,
  CONSTRAINT student_specializations_pkey PRIMARY KEY (student_id, program_id),
  CONSTRAINT student_specializations_dates_check
    CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
  CONSTRAINT student_specializations_student_program_fkey
    FOREIGN KEY (student_id, program_id)
    REFERENCES public.student_programs(student_id, program_id)
    ON DELETE CASCADE,
  CONSTRAINT student_specializations_student_tenant_fkey
    FOREIGN KEY (student_id, tenant_id)
    REFERENCES public.users(id, tenant_id)
    ON DELETE CASCADE,
  CONSTRAINT student_specializations_specialization_fkey
    FOREIGN KEY (specialization_id, program_id, tenant_id)
    REFERENCES public.specializations(id, program_id, tenant_id)
    ON DELETE RESTRICT
);

CREATE INDEX idx_student_specializations_student_tenant_fk
  ON public.student_specializations(student_id, tenant_id);
CREATE INDEX idx_student_specializations_specialization_program_tenant_fk
  ON public.student_specializations(specialization_id, program_id, tenant_id);

ALTER TABLE public.student_specializations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students and authorized staff read specialization assignments"
ON public.student_specializations
FOR SELECT
TO authenticated
USING (
  tenant_id = (SELECT private.tenant_id())
  AND (
    private.can_view_student(student_id)
    OR (
      SELECT private.has_permission_for_department(
        'academic.manage'::text,
        (SELECT p.department_id
         FROM public.programs p
         WHERE p.id = student_specializations.program_id
           AND p.tenant_id = student_specializations.tenant_id)
      )
    )
  )
);

CREATE POLICY "academic managers manage specialization assignments"
ON public.student_specializations
FOR ALL
TO authenticated
USING (
  tenant_id = (SELECT private.tenant_id())
  AND (
    SELECT private.has_permission_for_department(
      'academic.manage'::text,
      (SELECT p.department_id
       FROM public.programs p
       WHERE p.id = student_specializations.program_id
         AND p.tenant_id = student_specializations.tenant_id)
    )
  )
)
WITH CHECK (
  tenant_id = (SELECT private.tenant_id())
  AND (
    SELECT private.has_permission_for_department(
      'academic.manage'::text,
      (SELECT p.department_id
       FROM public.programs p
       WHERE p.id = student_specializations.program_id
         AND p.tenant_id = student_specializations.tenant_id)
    )
  )
);

REVOKE ALL ON public.student_specializations FROM anon, PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.student_specializations TO authenticated;
GRANT ALL ON public.student_specializations TO service_role;

-- Remove the pending specialization request identified during the schema review.
DELETE FROM public.student_specialization_selections
WHERE id = '0636d1a7-240b-4cfb-8704-dd25972558ec'::uuid
  AND status = 'pending';

-- Expose only active, effective specialization assignments in the student profile.
CREATE OR REPLACE VIEW public.student_profile
WITH (security_invoker = true)
AS
SELECT
  u.tenant_id,
  u.id AS student_id,
  COALESCE(
    NULLIF(btrim(up.display_name), ''),
    NULLIF(btrim(concat_ws(' ', up.first_name, up.last_name)), '')
  ) AS full_name,
  u.email,
  prog.id AS program_id,
  prog.name AS program_name,
  confirmed_spec.specialization_id,
  confirmed_spec.specialization_name,
  dept.id AS department_id,
  dept.name AS department_name,
  fac.id AS faculty_id,
  fac.name AS faculty_name,
  COALESCE(
    NULLIF(btrim(year_level.display_name), ''),
    NULLIF(btrim(year_level.name), '')
  ) AS academic_level,
  u.status::text AS enrollment_status
FROM public.users u
LEFT JOIN public.user_profiles up
  ON up.user_id = u.id AND up.tenant_id = u.tenant_id
LEFT JOIN public.departments dept
  ON dept.id = up.department_id AND dept.tenant_id = up.tenant_id
LEFT JOIN public.faculties fac
  ON fac.id = up.faculty_id AND fac.tenant_id = up.tenant_id
LEFT JOIN public.student_academic_progressions progression
  ON progression.student_id = u.id AND progression.tenant_id = u.tenant_id
LEFT JOIN public.academic_year_levels year_level
  ON year_level.id = progression.current_year_level_id
 AND year_level.tenant_id = progression.tenant_id
LEFT JOIN LATERAL (
  SELECT p.id, p.name
  FROM public.student_programs membership
  JOIN public.programs p
    ON p.id = membership.program_id AND p.tenant_id = membership.tenant_id
  WHERE membership.student_id = u.id
    AND membership.tenant_id = u.tenant_id
    AND membership.status = 'active'::public.program_membership_status
  ORDER BY membership.admitted_on DESC NULLS LAST, membership.program_id
  LIMIT 1
) prog ON true
LEFT JOIN LATERAL (
  SELECT assignment.specialization_id, s.name AS specialization_name
  FROM public.student_specializations assignment
  JOIN public.specializations s
    ON s.id = assignment.specialization_id
   AND s.program_id = assignment.program_id
   AND s.tenant_id = assignment.tenant_id
  WHERE assignment.student_id = u.id
    AND assignment.tenant_id = u.tenant_id
    AND assignment.status = 'active'::public.program_membership_status
    AND (assignment.starts_on IS NULL OR assignment.starts_on <= CURRENT_DATE)
    AND (assignment.ends_on IS NULL OR assignment.ends_on >= CURRENT_DATE)
    AND prog.id IS NOT NULL
    AND assignment.program_id = prog.id
  ORDER BY assignment.starts_on DESC NULLS LAST, assignment.specialization_id
  LIMIT 1
) confirmed_spec ON true
WHERE u.id = (SELECT auth.uid())
  AND u.user_type = 'non_staff'::public.user_type;

REVOKE ALL ON public.student_profile FROM anon, PUBLIC;
GRANT SELECT ON public.student_profile TO authenticated;
