-- Rename the profile table and retire the legacy single-email column.
ALTER TABLE public.person_profiles RENAME TO user_profiles;
ALTER TABLE public.user_profiles DROP COLUMN personal_email;

-- Keep the identity-field guard active after the table rename.
CREATE OR REPLACE FUNCTION private.guard_identity_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'users' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
      RAISE EXCEPTION 'University account identity and tenant are immutable' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF TG_TABLE_NAME IN ('person_profiles', 'user_profiles') THEN
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
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.role_id IS DISTINCT FROM OLD.role_id
       OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.scope_type IS DISTINCT FROM OLD.scope_type
       OR NEW.scope_id IS DISTINCT FROM OLD.scope_id
       OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
       OR NEW.granted_by IS DISTINCT FROM OLD.granted_by
       OR NEW.granted_at IS DISTINCT FROM OLD.granted_at
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Assignment identity, scope, start date, and grant attribution are immutable' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.assignment_status IS NOT DISTINCT FROM OLD.assignment_status THEN
      NEW.assignment_status := CASE WHEN NEW.status = 'active' THEN 'active' ELSE 'revoked' END;
    ELSIF NEW.assignment_status IS DISTINCT FROM OLD.assignment_status AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
      NEW.status := CASE WHEN NEW.assignment_status = 'active' THEN 'active' ELSE 'revoked' END;
    END IF;
    IF NEW.status = 'active' THEN
      NEW.assignment_status := 'active';
      NEW.revoked_at := NULL;
    ELSE
      NEW.assignment_status := 'revoked';
      IF NEW.status = 'revoked' THEN NEW.revoked_at := COALESCE(NEW.revoked_at, now()); END IF;
    END IF;
    IF NEW.status IN ('ended','revoked') AND NEW.status IS DISTINCT FROM OLD.status
       AND (SELECT auth.uid()) IS NOT NULL AND NEW.revoked_by IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'revoked_by must be the authenticated actor' USING ERRCODE = 'insufficient_privilege';
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
