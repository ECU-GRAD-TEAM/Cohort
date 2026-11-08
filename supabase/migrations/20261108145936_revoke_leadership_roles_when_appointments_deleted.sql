-- Revoke leadership roles when an appointment is deleted, as well as when it changes.
CREATE OR REPLACE FUNCTION private.sync_leadership_appointment_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
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
       AND OLD.position_id IS NOT DISTINCT FROM NEW.position_id
       AND OLD.scope_type IS NOT DISTINCT FROM NEW.scope_type
       AND OLD.scope_id IS NOT DISTINCT FROM NEW.scope_id
       AND OLD.starts_at IS NOT DISTINCT FROM NEW.starts_at
       AND OLD.ends_at IS NOT DISTINCT FROM NEW.ends_at
       AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
      RETURN NEW;
    END IF;

    SELECT sp.key INTO v_old_key
    FROM public.staff_positions sp
    WHERE sp.id = OLD.position_id;

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
          SELECT r.id
          FROM public.roles r
          WHERE r.tenant_id = OLD.tenant_id
            AND r.key = v_old_role_key
        )
        AND ur.assignment_status = 'active';
    END IF;

    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
  END IF;

  SELECT sp.key INTO v_new_key
  FROM public.staff_positions sp
  WHERE sp.id = NEW.position_id;

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
        SELECT r.id
        FROM public.roles r
        WHERE r.tenant_id = NEW.tenant_id
          AND r.key = v_new_role_key
      );

    IF NOT FOUND THEN
      INSERT INTO public.user_roles (
        user_id, role_id, tenant_id, granted_by, starts_at, expires_at,
        scope_type, scope_id, assignment_status
      )
      SELECT NEW.user_id, r.id, NEW.tenant_id, NEW.appointed_by,
             NEW.starts_at, NEW.ends_at, NEW.scope_type, NEW.scope_id, 'active'
      FROM public.roles r
      WHERE r.tenant_id = NEW.tenant_id
        AND r.key = v_new_role_key;

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
        SELECT r.id
        FROM public.roles r
        WHERE r.tenant_id = NEW.tenant_id
          AND r.key = v_new_role_key
      )
      AND ur.assignment_status = 'active';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS personnel_appointments_sync_leadership_role
ON public.personnel_appointments;

CREATE TRIGGER personnel_appointments_sync_leadership_role
AFTER INSERT OR UPDATE OR DELETE
ON public.personnel_appointments
FOR EACH ROW
EXECUTE FUNCTION private.sync_leadership_appointment_role();
