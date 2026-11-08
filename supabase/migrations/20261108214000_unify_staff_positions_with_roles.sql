-- Unify university positions and application roles in public.roles.
-- Keep user_roles (system authorization) and personnel_appointments (organizational
-- appointments) as separate assignment histories.

ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS role_type text NOT NULL DEFAULT 'system',
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS is_academic_rank boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

ALTER TABLE public.roles
  DROP CONSTRAINT IF EXISTS roles_role_type_check,
  ADD CONSTRAINT roles_role_type_check
    CHECK (role_type IN ('system', 'position', 'both'));

-- Copy the global position catalogue into each tenant's role catalogue.
-- Matching system roles are upgraded to "both", preserving their IDs and
-- therefore all existing user_roles and role_permissions references.
INSERT INTO public.roles
  (tenant_id, key, name, description, is_system, role_type, category, is_academic_rank, is_active)
SELECT
  t.id,
  sp.key,
  sp.name,
  sp.description,
  true,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM public.roles existing
      WHERE existing.tenant_id = t.id AND existing.key = sp.key AND existing.is_system
    ) THEN 'both'
    ELSE 'position'
  END,
  sp.category,
  sp.is_academic_rank,
  sp.is_active
FROM public.tenants t
CROSS JOIN public.staff_positions sp
ON CONFLICT (tenant_id, key) DO UPDATE
SET role_type = 'both',
    category = EXCLUDED.category,
    is_academic_rank = EXCLUDED.is_academic_rank,
    is_active = EXCLUDED.is_active;

-- Prevent the old trigger implementation from interpreting the new role IDs
-- as staff_positions IDs while appointment references are being migrated.
ALTER TABLE public.personnel_appointments
  DISABLE TRIGGER personnel_appointments_sync_leadership_role;

-- Ensure the appointment catalogue references the tenant-scoped role row.
ALTER TABLE public.personnel_appointments
  DROP CONSTRAINT IF EXISTS personnel_appointments_position_id_fkey;

UPDATE public.personnel_appointments pa
SET position_id = r.id
FROM public.staff_positions sp, public.roles r
WHERE sp.id = pa.position_id
  AND r.tenant_id = pa.tenant_id
  AND r.key = sp.key;

DO $verify_mapping$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.personnel_appointments pa
    LEFT JOIN public.roles r
      ON r.id = pa.position_id AND r.tenant_id = pa.tenant_id
    WHERE r.id IS NULL OR r.role_type NOT IN ('position', 'both')
  ) THEN
    RAISE EXCEPTION 'Cannot migrate personnel appointments: one or more position definitions have no matching tenant role';
  END IF;
END
$verify_mapping$;

ALTER TABLE public.personnel_appointments
  RENAME COLUMN position_id TO role_id;

DROP INDEX IF EXISTS public.idx_personnel_appointments_position_id_fk;
CREATE INDEX IF NOT EXISTS idx_personnel_appointments_role_id_tenant_id_fk
  ON public.personnel_appointments (role_id, tenant_id);

ALTER TABLE public.personnel_appointments
  ADD CONSTRAINT personnel_appointments_role_id_tenant_id_fkey
  FOREIGN KEY (role_id, tenant_id)
  REFERENCES public.roles (id, tenant_id)
  ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS roles_tenant_role_type_category_idx
  ON public.roles (tenant_id, role_type, category)
  WHERE is_active;

-- Appointments may reference only active position-capable definitions.
CREATE OR REPLACE FUNCTION private.validate_personnel_appointment_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_exists boolean := false;
  v_role_type text;
  v_role_active boolean;
BEGIN
  SELECT r.role_type, r.is_active
  INTO v_role_type, v_role_active
  FROM public.roles r
  WHERE r.id = NEW.role_id
    AND r.tenant_id = NEW.tenant_id;

  IF v_role_type NOT IN ('position', 'both') OR v_role_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Personnel appointments require an active position or combined role definition'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.scope_type = 'university' THEN
    RETURN NEW;
  ELSIF NEW.scope_type = 'faculty' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.faculties f
      WHERE f.id = NEW.scope_id AND f.tenant_id = NEW.tenant_id
    ) INTO v_exists;
  ELSIF NEW.scope_type = 'department' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.departments d
      WHERE d.id = NEW.scope_id AND d.tenant_id = NEW.tenant_id
    ) INTO v_exists;
  ELSIF NEW.scope_type = 'program' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.programs p
      WHERE p.id = NEW.scope_id AND p.tenant_id = NEW.tenant_id
    ) INTO v_exists;
  END IF;

  IF NOT v_exists THEN
    RAISE EXCEPTION 'Appointment scope does not exist in this tenant'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN NEW;
END;
$function$;

-- System authorization assignments may use only active system-capable roles.
CREATE OR REPLACE FUNCTION private.validate_user_role_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_exists boolean := false;
  v_role_type text;
  v_role_active boolean;
BEGIN
  SELECT r.role_type, r.is_active
  INTO v_role_type, v_role_active
  FROM public.roles r
  WHERE r.id = NEW.role_id
    AND r.tenant_id = NEW.tenant_id;

  IF v_role_type NOT IN ('system', 'both') OR v_role_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'System role assignments require an active system or combined role definition'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.scope_type = 'university' THEN
    IF NEW.scope_id IS NOT NULL THEN
      RAISE EXCEPTION 'University-wide role assignments must not have a scope_id';
    END IF;
    RETURN NEW;
  ELSIF NEW.scope_type = 'faculty' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.faculties f
      WHERE f.id = NEW.scope_id AND f.tenant_id = NEW.tenant_id
    ) INTO v_exists;
  ELSIF NEW.scope_type = 'department' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.departments d
      WHERE d.id = NEW.scope_id AND d.tenant_id = NEW.tenant_id
    ) INTO v_exists;
  ELSIF NEW.scope_type = 'program' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.programs p
      WHERE p.id = NEW.scope_id AND p.tenant_id = NEW.tenant_id
    ) INTO v_exists;
  ELSIF NEW.scope_type = 'course' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.course_offerings co
      WHERE co.id = NEW.scope_id AND co.tenant_id = NEW.tenant_id
    ) INTO v_exists;
  END IF;

  IF NOT v_exists THEN
    RAISE EXCEPTION 'Role assignment scope does not exist in this tenant'
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  RETURN NEW;
END;
$function$;

-- Keep leadership authorization synchronized with the appointment's role row.
CREATE OR REPLACE FUNCTION private.sync_leadership_appointment_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_old_key text;
  v_new_key text;
  v_old_role_key text;
  v_new_role_key text;
  v_new_scope_type text;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    IF TG_OP = 'UPDATE'
       AND OLD.user_id IS NOT DISTINCT FROM NEW.user_id
       AND OLD.tenant_id IS NOT DISTINCT FROM NEW.tenant_id
       AND OLD.role_id IS NOT DISTINCT FROM NEW.role_id
       AND OLD.scope_type IS NOT DISTINCT FROM NEW.scope_type
       AND OLD.scope_id IS NOT DISTINCT FROM NEW.scope_id
       AND OLD.starts_at IS NOT DISTINCT FROM NEW.starts_at
       AND OLD.ends_at IS NOT DISTINCT FROM NEW.ends_at
       AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
      RETURN NEW;
    END IF;

    SELECT r.key INTO v_old_key
    FROM public.roles r
    WHERE r.id = OLD.role_id AND r.tenant_id = OLD.tenant_id;

    v_old_role_key := CASE
      WHEN v_old_key IN ('dean', 'vice_dean', 'department_head') THEN v_old_key
      ELSE NULL
    END;

    IF v_old_role_key IS NOT NULL THEN
      UPDATE public.user_roles ur
      SET assignment_status = 'revoked',
          revoked_at = COALESCE(ur.revoked_at, now())
      WHERE ur.user_id = OLD.user_id
        AND ur.tenant_id = OLD.tenant_id
        AND ur.scope_type = OLD.scope_type
        AND ur.scope_id IS NOT DISTINCT FROM OLD.scope_id
        AND ur.role_id IN (
          SELECT r.id FROM public.roles r
          WHERE r.tenant_id = OLD.tenant_id AND r.key = v_old_role_key
        )
        AND ur.assignment_status = 'active';
    END IF;

    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
  END IF;

  SELECT r.key INTO v_new_key
  FROM public.roles r
  WHERE r.id = NEW.role_id AND r.tenant_id = NEW.tenant_id;

  v_new_role_key := CASE
    WHEN v_new_key IN ('dean', 'vice_dean', 'department_head') THEN v_new_key
    ELSE NULL
  END;

  IF v_new_role_key IS NULL THEN
    RETURN NEW;
  END IF;

  v_new_scope_type := CASE
    WHEN v_new_role_key IN ('dean', 'vice_dean') THEN 'faculty'
    WHEN v_new_role_key = 'department_head' THEN 'department'
  END;

  IF NEW.scope_type <> v_new_scope_type THEN
    RAISE EXCEPTION 'The % appointment must have % scope',
      v_new_role_key, v_new_scope_type
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.status = 'active'
     AND (NEW.ends_at IS NULL OR NEW.ends_at > now()) THEN
    UPDATE public.user_roles ur
    SET starts_at = NEW.starts_at,
        expires_at = NEW.ends_at,
        assignment_status = 'active',
        revoked_at = NULL
    WHERE ur.user_id = NEW.user_id
      AND ur.tenant_id = NEW.tenant_id
      AND ur.scope_type = NEW.scope_type
      AND ur.scope_id = NEW.scope_id
      AND ur.role_id IN (
        SELECT r.id FROM public.roles r
        WHERE r.tenant_id = NEW.tenant_id AND r.key = v_new_role_key
      );

    IF NOT FOUND THEN
      INSERT INTO public.user_roles (
        user_id, role_id, tenant_id, granted_by, starts_at, expires_at,
        scope_type, scope_id, assignment_status
      )
      SELECT NEW.user_id, r.id, NEW.tenant_id, NEW.appointed_by,
             NEW.starts_at, NEW.ends_at, NEW.scope_type, NEW.scope_id, 'active'
      FROM public.roles r
      WHERE r.tenant_id = NEW.tenant_id AND r.key = v_new_role_key;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'The system role % is not configured for this tenant',
          v_new_role_key
          USING ERRCODE = 'foreign_key_violation';
      END IF;
    END IF;
  ELSE
    UPDATE public.user_roles ur
    SET assignment_status = 'revoked',
        revoked_at = COALESCE(ur.revoked_at, now())
    WHERE ur.user_id = NEW.user_id
      AND ur.tenant_id = NEW.tenant_id
      AND ur.scope_type = NEW.scope_type
      AND ur.scope_id = NEW.scope_id
      AND ur.role_id IN (
        SELECT r.id FROM public.roles r
        WHERE r.tenant_id = NEW.tenant_id AND r.key = v_new_role_key
      )
      AND ur.assignment_status = 'active';
  END IF;

  RETURN NEW;
END;
$function$;

-- Re-enable leadership synchronization after its function now reads public.roles.
ALTER TABLE public.personnel_appointments
  ENABLE TRIGGER personnel_appointments_sync_leadership_role;

-- No function, trigger, or foreign key should retain a dependency on this table.
DROP TABLE public.staff_positions;
