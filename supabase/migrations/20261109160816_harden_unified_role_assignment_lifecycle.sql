-- Keep the unified user_roles lifecycle consistent and preserve assignment history.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE OR REPLACE FUNCTION private.sync_user_role_lifecycle()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.ends_at IS NULL THEN NEW.ends_at := NEW.expires_at;
    ELSIF NEW.expires_at IS NULL THEN NEW.expires_at := NEW.ends_at;
    ELSIF NEW.ends_at IS DISTINCT FROM NEW.expires_at THEN
      RAISE EXCEPTION 'ends_at and expires_at must match' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status = 'active' AND NEW.assignment_status = 'revoked' THEN
      NEW.status := 'revoked';
    ELSIF NEW.assignment_status = 'active' THEN
      NEW.status := 'active';
    END IF;
  ELSE
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
  END IF;
  IF NEW.status = 'active' THEN
    NEW.assignment_status := 'active'; NEW.revoked_at := NULL;
  ELSE
    NEW.assignment_status := 'revoked';
    IF NEW.status = 'revoked' THEN NEW.revoked_at := COALESCE(NEW.revoked_at, now()); END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS user_roles_sync_lifecycle ON public.user_roles;
CREATE TRIGGER user_roles_sync_lifecycle BEFORE INSERT OR UPDATE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION private.sync_user_role_lifecycle();

DO $patch_student_role_checks$
DECLARE v_definition text; v_original text;
BEGIN
  SELECT pg_get_functiondef('private.validate_student_academic_progression()'::regprocedure) INTO v_definition;
  v_original := v_definition;
  v_definition := replace(v_definition, 'AND ur.assignment_status = ''active''',
    'AND ur.assignment_status = ''active'' AND ur.status = ''active''');
  v_definition := replace(v_definition,
    'AND (ur.expires_at IS NULL OR ur.expires_at > now())',
    'AND (ur.expires_at IS NULL OR ur.expires_at > now()) AND (ur.ends_at IS NULL OR ur.ends_at > now())');
  IF v_definition = v_original THEN RAISE EXCEPTION 'Could not update student progression role checks'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.enroll_in_section(uuid)'::regprocedure) INTO v_definition;
  v_original := v_definition;
  v_definition := replace(v_definition, 'AND ur.assignment_status = ''active''',
    'AND ur.assignment_status = ''active'' AND ur.status = ''active''');
  v_definition := replace(v_definition,
    'AND (ur.expires_at IS NULL OR ur.expires_at > now())',
    'AND (ur.expires_at IS NULL OR ur.expires_at > now()) AND (ur.ends_at IS NULL OR ur.ends_at > now())');
  IF v_definition = v_original THEN RAISE EXCEPTION 'Could not update student enrollment role checks'; END IF;
  EXECUTE v_definition;
END;
$patch_student_role_checks$;

DROP POLICY IF EXISTS "account managers remove roles" ON public.user_roles;
REVOKE DELETE ON public.user_roles FROM authenticated;
COMMIT;
