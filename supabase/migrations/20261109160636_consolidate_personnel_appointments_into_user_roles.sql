-- Consolidate organizational appointments and system-role assignments into user_roles.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE public.user_roles
  ADD COLUMN IF NOT EXISTS appointment_type text NOT NULL DEFAULT 'system_access',
  ADD COLUMN IF NOT EXISTS ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS appointed_by uuid,
  ADD COLUMN IF NOT EXISTS ended_by uuid,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS source_appointment_id uuid;

ALTER TABLE public.user_roles DISABLE TRIGGER user_roles_guard_identity_fields;
ALTER TABLE public.user_roles DISABLE TRIGGER user_roles_validate_scope;

-- Merge the existing leadership assignment with its matching appointment.
UPDATE public.user_roles ur
SET appointment_type = pa.appointment_type,
    ends_at = pa.ends_at,
    expires_at = pa.ends_at,
    status = pa.status,
    assignment_status = CASE WHEN pa.status = 'active' THEN 'active' ELSE 'revoked' END,
    revoked_at = CASE WHEN pa.status = 'revoked' THEN COALESCE(ur.revoked_at, pa.ends_at) ELSE NULL END,
    appointed_by = pa.appointed_by,
    ended_by = pa.ended_by,
    notes = pa.notes,
    created_at = pa.created_at,
    granted_at = COALESCE(pa.created_at, ur.granted_at),
    granted_by = COALESCE(pa.appointed_by, ur.granted_by),
    source_appointment_id = pa.id
FROM public.personnel_appointments pa
WHERE ur.user_id = pa.user_id
  AND ur.tenant_id = pa.tenant_id
  AND ur.role_id = pa.role_id
  AND ur.scope_type = pa.scope_type
  AND ur.scope_id IS NOT DISTINCT FROM pa.scope_id;

-- Copy all other appointments with their original appointment UUID as assignment UUID.
INSERT INTO public.user_roles (
  id, tenant_id, user_id, role_id, appointment_type,
  scope_type, scope_id, starts_at, ends_at, status,
  appointed_by, ended_by, notes, created_at, source_appointment_id,
  granted_by, granted_at, expires_at, revoked_at, assignment_status
)
SELECT
  pa.id, pa.tenant_id, pa.user_id, pa.role_id, pa.appointment_type,
  pa.scope_type, pa.scope_id, pa.starts_at, pa.ends_at, pa.status,
  pa.appointed_by, pa.ended_by, pa.notes, pa.created_at, pa.id,
  pa.appointed_by, pa.created_at, pa.ends_at,
  CASE WHEN pa.status = 'revoked' THEN pa.ends_at ELSE NULL END,
  CASE WHEN pa.status = 'active' THEN 'active' ELSE 'revoked' END
FROM public.personnel_appointments pa
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_roles ur
  WHERE ur.user_id = pa.user_id AND ur.tenant_id = pa.tenant_id
    AND ur.role_id = pa.role_id AND ur.scope_type = pa.scope_type
    AND ur.scope_id IS NOT DISTINCT FROM pa.scope_id
);

ALTER TABLE public.user_roles
  ADD CONSTRAINT user_roles_appointment_type_check
    CHECK (appointment_type IN ('system_access','position','leadership')),
  ADD CONSTRAINT user_roles_status_check
    CHECK (status IN ('active','ended','revoked')),
  ADD CONSTRAINT user_roles_ends_at_check
    CHECK (ends_at IS NULL OR ends_at > starts_at),
  ADD CONSTRAINT user_roles_granted_by_tenant_id_fkey
    FOREIGN KEY (granted_by, tenant_id) REFERENCES public.users(id, tenant_id),
  ADD CONSTRAINT user_roles_appointed_by_tenant_id_fkey
    FOREIGN KEY (appointed_by, tenant_id) REFERENCES public.users(id, tenant_id),
  ADD CONSTRAINT user_roles_ended_by_tenant_id_fkey
    FOREIGN KEY (ended_by, tenant_id) REFERENCES public.users(id, tenant_id);

CREATE UNIQUE INDEX IF NOT EXISTS user_roles_source_appointment_id_uidx
  ON public.user_roles(source_appointment_id) WHERE source_appointment_id IS NOT NULL;

DROP INDEX IF EXISTS public.user_roles_assignment_scope_uidx;
CREATE UNIQUE INDEX user_roles_active_assignment_scope_uidx
  ON public.user_roles(user_id, role_id, scope_type,
    COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE assignment_status = 'active' AND status = 'active' AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS user_roles_scope_active_idx
  ON public.user_roles(tenant_id, scope_type, scope_id, starts_at, ends_at)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS user_roles_appointed_by_tenant_id_idx
  ON public.user_roles(appointed_by, tenant_id);
CREATE INDEX IF NOT EXISTS user_roles_ended_by_tenant_id_idx
  ON public.user_roles(ended_by, tenant_id);

CREATE OR REPLACE FUNCTION private.validate_user_role_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
DECLARE
  v_exists boolean := false;
  v_role_type text;
  v_role_active boolean;
  v_role_key text;
BEGIN
  SELECT r.role_type, r.is_active, r.key INTO v_role_type, v_role_active, v_role_key
  FROM public.roles r WHERE r.id = NEW.role_id AND r.tenant_id = NEW.tenant_id;
  IF v_role_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Role assignments require an active role definition' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.appointment_type = 'system_access' THEN
    IF v_role_type NOT IN ('system','both') THEN
      RAISE EXCEPTION 'System access requires a system or combined role' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.appointment_type IN ('position','leadership') THEN
    IF v_role_type NOT IN ('position','both') THEN
      RAISE EXCEPTION 'Position and leadership assignments require a position or combined role' USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unsupported assignment type' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.scope_type = 'university' THEN
    IF NEW.scope_id IS NOT NULL THEN
      RAISE EXCEPTION 'University-wide assignments must not have a scope_id' USING ERRCODE = 'check_violation';
    END IF;
    v_exists := true;
  ELSIF NEW.scope_type = 'faculty' THEN
    SELECT EXISTS (SELECT 1 FROM public.faculties f WHERE f.id = NEW.scope_id AND f.tenant_id = NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'department' THEN
    SELECT EXISTS (SELECT 1 FROM public.departments d WHERE d.id = NEW.scope_id AND d.tenant_id = NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'program' THEN
    SELECT EXISTS (SELECT 1 FROM public.programs p WHERE p.id = NEW.scope_id AND p.tenant_id = NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'course' THEN
    SELECT EXISTS (SELECT 1 FROM public.course_offerings co WHERE co.id = NEW.scope_id AND co.tenant_id = NEW.tenant_id) INTO v_exists;
  END IF;
  IF NOT v_exists THEN
    RAISE EXCEPTION 'Assignment scope does not exist in this tenant' USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NEW.appointment_type = 'leadership' THEN
    IF (v_role_key IN ('dean','vice_dean') AND NEW.scope_type <> 'faculty')
       OR (v_role_key = 'department_head' AND NEW.scope_type <> 'department') THEN
      RAISE EXCEPTION 'Leadership role % has an invalid organizational scope', v_role_key USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.guard_identity_fields()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'users' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
      RAISE EXCEPTION 'University account identity and tenant are immutable' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF TG_TABLE_NAME = 'person_profiles' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
      RAISE EXCEPTION 'Profile ownership and tenant are immutable' USING ERRCODE = 'check_violation';
    END IF;
    IF (SELECT auth.uid()) = OLD.user_id AND NOT private.has_permission('users.manage')
       AND (NEW.department_id IS DISTINCT FROM OLD.department_id
         OR NEW.faculty_id IS DISTINCT FROM OLD.faculty_id
         OR NEW.title IS DISTINCT FROM OLD.title) THEN
      RAISE EXCEPTION 'Only authorized account managers can change organizational profile fields'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF TG_TABLE_NAME = 'user_roles' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.role_id IS DISTINCT FROM OLD.role_id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.scope_type IS DISTINCT FROM OLD.scope_type OR NEW.scope_id IS DISTINCT FROM OLD.scope_id
       OR NEW.appointment_type IS DISTINCT FROM OLD.appointment_type OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
       OR NEW.granted_by IS DISTINCT FROM OLD.granted_by OR NEW.granted_at IS DISTINCT FROM OLD.granted_at
       OR NEW.appointed_by IS DISTINCT FROM OLD.appointed_by OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.source_appointment_id IS DISTINCT FROM OLD.source_appointment_id THEN
      RAISE EXCEPTION 'Assignment identity, scope, type, and grant attribution are immutable; end/revoke and create a new assignment'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.ends_at IS DISTINCT FROM OLD.ends_at AND NEW.expires_at IS NOT DISTINCT FROM OLD.expires_at THEN
      NEW.expires_at := NEW.ends_at;
    ELSIF NEW.expires_at IS DISTINCT FROM OLD.expires_at AND NEW.ends_at IS NOT DISTINCT FROM OLD.ends_at THEN
      NEW.ends_at := NEW.expires_at;
    ELSIF NEW.ends_at IS DISTINCT FROM NEW.expires_at THEN
      RAISE EXCEPTION 'ends_at and expires_at must match' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.assignment_status IS NOT DISTINCT FROM OLD.assignment_status THEN
      NEW.assignment_status := CASE WHEN NEW.status = 'active' THEN 'active' ELSE 'revoked' END;
    ELSIF NEW.assignment_status IS DISTINCT FROM OLD.assignment_status AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
      NEW.status := CASE WHEN NEW.assignment_status = 'active' THEN 'active' ELSE 'revoked' END;
    END IF;
    IF NEW.status = 'active' THEN
      NEW.assignment_status := 'active'; NEW.revoked_at := NULL;
    ELSE
      NEW.assignment_status := 'revoked';
      IF NEW.status = 'revoked' THEN NEW.revoked_at := COALESCE(NEW.revoked_at, now()); END IF;
    END IF;
    IF NEW.status IN ('ended','revoked') AND NEW.status IS DISTINCT FROM OLD.status
       AND (SELECT auth.uid()) IS NOT NULL AND NEW.ended_by IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'ended_by must be the authenticated actor' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF TG_TABLE_NAME = 'roles' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.key IS DISTINCT FROM OLD.key OR NEW.is_system IS DISTINCT FROM OLD.is_system THEN
      RAISE EXCEPTION 'Role identity, tenant, key, and system status are immutable' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.guard_user_role_actor()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.appointment_type IN ('position','leadership')
       AND NEW.appointed_by IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'appointed_by must be the authenticated actor';
    END IF;
    IF NEW.appointment_type = 'system_access' AND NEW.granted_by IS NOT NULL
       AND NEW.granted_by IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'granted_by must be the authenticated actor';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.appointed_by IS DISTINCT FROM OLD.appointed_by THEN
      RAISE EXCEPTION 'appointed_by is immutable';
    END IF;
    IF NEW.status IN ('ended','revoked') AND NEW.status IS DISTINCT FROM OLD.status
       AND (SELECT auth.uid()) IS NOT NULL AND NEW.ended_by IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'ended_by must be the authenticated actor when ending or revoking an assignment';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS user_roles_guard_actor ON public.user_roles;
CREATE TRIGGER user_roles_guard_actor BEFORE INSERT OR UPDATE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION private.guard_user_role_actor();

CREATE OR REPLACE FUNCTION private.has_role(p_role_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id AND r.tenant_id = ur.tenant_id
    WHERE ur.user_id = (SELECT auth.uid()) AND ur.tenant_id = private.tenant_id()
      AND r.key = p_role_key AND ur.assignment_status = 'active' AND ur.status = 'active'
      AND ur.starts_at <= now()
      AND (ur.expires_at IS NULL OR ur.expires_at > now())
      AND (ur.ends_at IS NULL OR ur.ends_at > now()) AND ur.revoked_at IS NULL
  );
$function$;

CREATE OR REPLACE FUNCTION private.has_any_role(p_role_keys text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id AND r.tenant_id = ur.tenant_id
    WHERE ur.user_id = (SELECT auth.uid()) AND ur.tenant_id = private.tenant_id()
      AND r.key = ANY (p_role_keys) AND ur.assignment_status = 'active' AND ur.status = 'active'
      AND ur.starts_at <= now()
      AND (ur.expires_at IS NULL OR ur.expires_at > now())
      AND (ur.ends_at IS NULL OR ur.ends_at > now()) AND ur.revoked_at IS NULL
  );
$function$;

CREATE OR REPLACE FUNCTION private.has_permission(p_permission text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id AND rp.tenant_id = ur.tenant_id
    WHERE ur.user_id = (SELECT auth.uid()) AND ur.tenant_id = private.tenant_id()
      AND rp.permission_key = p_permission AND ur.scope_type = 'university'
      AND ur.assignment_status = 'active' AND ur.status = 'active' AND ur.starts_at <= now()
      AND (ur.expires_at IS NULL OR ur.expires_at > now())
      AND (ur.ends_at IS NULL OR ur.ends_at > now()) AND ur.revoked_at IS NULL
  );
$function$;

CREATE OR REPLACE FUNCTION private.has_permission(p_permission text, p_scope_type text, p_scope_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id AND rp.tenant_id = ur.tenant_id
    WHERE ur.user_id = (SELECT auth.uid()) AND ur.tenant_id = private.tenant_id()
      AND rp.permission_key = p_permission AND ur.assignment_status = 'active' AND ur.status = 'active'
      AND ur.starts_at <= now()
      AND (ur.expires_at IS NULL OR ur.expires_at > now())
      AND (ur.ends_at IS NULL OR ur.ends_at > now()) AND ur.revoked_at IS NULL
      AND (
        ur.scope_type = 'university'
        OR (ur.scope_type = p_scope_type AND ur.scope_id = p_scope_id)
        OR (p_scope_type = 'department' AND ur.scope_type = 'faculty'
          AND EXISTS (SELECT 1 FROM public.departments d WHERE d.id = p_scope_id AND d.faculty_id = ur.scope_id AND d.tenant_id = ur.tenant_id))
        OR (p_scope_type = 'program' AND ur.scope_type IN ('faculty','department')
          AND EXISTS (
            SELECT 1 FROM public.programs p
            JOIN public.departments d ON d.id = p.department_id AND d.tenant_id = p.tenant_id
            WHERE p.id = p_scope_id AND p.tenant_id = ur.tenant_id
              AND ((ur.scope_type = 'department' AND d.id = ur.scope_id)
                OR (ur.scope_type = 'faculty' AND d.faculty_id = ur.scope_id))
          ))
      )
  );
$function$;

DROP POLICY IF EXISTS "read own roles or manage accounts" ON public.user_roles;
CREATE POLICY "read own roles or manage accounts" ON public.user_roles FOR SELECT TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND (
  user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage'))
  OR private.has_permission('appointments.manage', scope_type, scope_id)
));

DROP POLICY IF EXISTS "account managers assign roles" ON public.user_roles;
CREATE POLICY "account managers assign roles" ON public.user_roles FOR INSERT TO authenticated
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND (
  (SELECT private.has_permission('users.manage'))
  OR private.has_permission('appointments.manage', scope_type, scope_id)
));

DROP POLICY IF EXISTS "account managers change role assignments" ON public.user_roles;
CREATE POLICY "account managers change role assignments" ON public.user_roles FOR UPDATE TO authenticated
USING (tenant_id = (SELECT private.tenant_id()) AND (
  (SELECT private.has_permission('users.manage'))
  OR private.has_permission('appointments.manage', scope_type, scope_id)
))
WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND (
  (SELECT private.has_permission('users.manage'))
  OR private.has_permission('appointments.manage', scope_type, scope_id)
));

DROP TRIGGER IF EXISTS personnel_appointments_audit ON public.personnel_appointments;
DROP TRIGGER IF EXISTS personnel_appointments_guard_actor ON public.personnel_appointments;
DROP TRIGGER IF EXISTS personnel_appointments_sync_leadership_role ON public.personnel_appointments;
DROP TRIGGER IF EXISTS personnel_appointments_validate_scope ON public.personnel_appointments;

DROP TRIGGER IF EXISTS user_roles_validate_scope ON public.user_roles;
CREATE TRIGGER user_roles_validate_scope BEFORE INSERT OR UPDATE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION private.validate_user_role_scope();

DROP TABLE public.personnel_appointments;
DROP FUNCTION IF EXISTS private.guard_personnel_appointment_actor();
DROP FUNCTION IF EXISTS private.validate_personnel_appointment_scope();
DROP FUNCTION IF EXISTS private.sync_leadership_appointment_role();

ALTER TABLE public.user_roles ENABLE TRIGGER user_roles_guard_identity_fields;
COMMIT;
