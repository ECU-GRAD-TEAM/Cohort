-- Harden identity, authorization, account provisioning, appointment synchronization,
-- and add indexes for currently unindexed public foreign keys.

CREATE OR REPLACE FUNCTION private.has_role(p_role_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id AND r.tenant_id = ur.tenant_id
    WHERE ur.user_id = (SELECT auth.uid())
      AND ur.tenant_id = private.tenant_id()
      AND r.key = p_role_key
      AND ur.assignment_status = 'active'
      AND ur.starts_at <= now()
      AND (ur.expires_at IS NULL OR ur.expires_at > now())
      AND ur.revoked_at IS NULL
  );
$function$;

CREATE OR REPLACE FUNCTION private.tenant_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT u.tenant_id
  FROM public.users u
  JOIN public.tenants t ON t.id = u.tenant_id
  WHERE u.id = (SELECT auth.uid())
    AND u.status IN ('active', 'graduated')
    AND t.status = 'active';
$function$;

CREATE OR REPLACE FUNCTION private.handle_new_auth_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_tenant uuid;
  v_type public.user_type;
  v_status public.account_status;
BEGIN
  v_tenant := nullif(NEW.raw_app_meta_data ->> 'tenant_id', '')::uuid;
  v_type := CASE NEW.raw_app_meta_data ->> 'user_type'
    WHEN 'staff' THEN 'staff'::public.user_type
    WHEN 'non_staff' THEN 'non_staff'::public.user_type
    ELSE NULL
  END;

  IF NEW.id IS NULL OR NEW.email IS NULL THEN
    RAISE EXCEPTION 'Auth account requires an id and email' USING ERRCODE = 'check_violation';
  END IF;
  IF v_tenant IS NULL OR v_type IS NULL THEN
    RAISE EXCEPTION 'Auth account requires valid app_metadata tenant_id and user_type (staff or non_staff)'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tenants t WHERE t.id = v_tenant AND t.status = 'active') THEN
    RAISE EXCEPTION 'The requested tenant does not exist or is not active'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_status := CASE
    WHEN NEW.invited_at IS NOT NULL AND NEW.email_confirmed_at IS NULL
      THEN 'invited'::public.account_status
    ELSE 'active'::public.account_status
  END;

  INSERT INTO public.users (id, tenant_id, user_type, status, email, institutional_id)
  VALUES (
    NEW.id, v_tenant, v_type, v_status, lower(NEW.email),
    nullif(NEW.raw_app_meta_data ->> 'institutional_id', '')
  );

  UPDATE public.person_profiles
  SET display_name = coalesce(
    nullif(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''),
    display_name
  )
  WHERE user_id = NEW.id;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.sync_auth_user_account()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  UPDATE public.users
  SET email = lower(NEW.email),
      status = CASE
        WHEN status = 'invited'::public.account_status AND NEW.email_confirmed_at IS NOT NULL
          THEN 'active'::public.account_status
        ELSE status
      END
  WHERE id = NEW.id;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_auth_user_account_updated ON auth.users;
CREATE TRIGGER on_auth_user_account_updated
AFTER UPDATE OF email, email_confirmed_at ON auth.users
FOR EACH ROW
WHEN (OLD.email IS DISTINCT FROM NEW.email
   OR OLD.email_confirmed_at IS DISTINCT FROM NEW.email_confirmed_at)
EXECUTE FUNCTION private.sync_auth_user_account();

CREATE OR REPLACE FUNCTION private.guard_identity_fields()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'users' THEN
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
      RAISE EXCEPTION 'University account identity and tenant are immutable'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF TG_TABLE_NAME = 'person_profiles' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
      RAISE EXCEPTION 'Profile ownership and tenant are immutable'
        USING ERRCODE = 'check_violation';
    END IF;
    IF (SELECT auth.uid()) = OLD.user_id
       AND NOT private.has_permission('users.manage')
       AND (
         NEW.department_id IS DISTINCT FROM OLD.department_id
         OR NEW.faculty_id IS DISTINCT FROM OLD.faculty_id
         OR NEW.title IS DISTINCT FROM OLD.title
       ) THEN
      RAISE EXCEPTION 'Only authorized account managers can change organizational profile fields'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF TG_TABLE_NAME = 'user_roles' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.role_id IS DISTINCT FROM OLD.role_id
       OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.granted_by IS DISTINCT FROM OLD.granted_by
       OR NEW.granted_at IS DISTINCT FROM OLD.granted_at THEN
      RAISE EXCEPTION 'Role assignment ownership, role, tenant, and grant attribution are immutable; revoke and create a new assignment'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF TG_TABLE_NAME = 'roles' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.key IS DISTINCT FROM OLD.key
       OR NEW.is_system IS DISTINCT FROM OLD.is_system THEN
      RAISE EXCEPTION 'Role identity, tenant, key, and system status are immutable'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS users_guard_identity_fields ON public.users;
CREATE TRIGGER users_guard_identity_fields BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION private.guard_identity_fields();
DROP TRIGGER IF EXISTS person_profiles_guard_identity_fields ON public.person_profiles;
CREATE TRIGGER person_profiles_guard_identity_fields BEFORE UPDATE ON public.person_profiles
FOR EACH ROW EXECUTE FUNCTION private.guard_identity_fields();
DROP TRIGGER IF EXISTS user_roles_guard_identity_fields ON public.user_roles;
CREATE TRIGGER user_roles_guard_identity_fields BEFORE UPDATE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION private.guard_identity_fields();
DROP TRIGGER IF EXISTS roles_guard_identity_fields ON public.roles;
CREATE TRIGGER roles_guard_identity_fields BEFORE UPDATE ON public.roles
FOR EACH ROW EXECUTE FUNCTION private.guard_identity_fields();

DROP POLICY IF EXISTS "edit own profile or manage accounts" ON public.person_profiles;
CREATE POLICY "edit own profile or manage accounts" ON public.person_profiles
FOR UPDATE TO authenticated
USING (
  tenant_id = (SELECT private.tenant_id())
  AND (user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage')))
)
WITH CHECK (
  tenant_id = (SELECT private.tenant_id())
  AND (user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage')))
);

DROP POLICY IF EXISTS "account managers change role assignments" ON public.user_roles;
CREATE POLICY "account managers change role assignments" ON public.user_roles
FOR UPDATE TO authenticated
USING (
  tenant_id = (SELECT private.tenant_id())
  AND (SELECT private.has_permission('users.manage'))
)
WITH CHECK (
  tenant_id = (SELECT private.tenant_id())
  AND (SELECT private.has_permission('users.manage'))
);

DROP POLICY IF EXISTS "account managers update" ON public.users;
CREATE POLICY "account managers update" ON public.users
FOR UPDATE TO authenticated
USING (
  tenant_id = (SELECT private.tenant_id())
  AND (SELECT private.has_permission('users.manage'))
)
WITH CHECK (
  tenant_id = (SELECT private.tenant_id())
  AND (SELECT private.has_permission('users.manage'))
);

DROP POLICY IF EXISTS "account managers edit custom roles" ON public.roles;
CREATE POLICY "account managers edit custom roles" ON public.roles
FOR UPDATE TO authenticated
USING (
  tenant_id = (SELECT private.tenant_id())
  AND (SELECT private.has_permission('users.manage'))
  AND NOT is_system
)
WITH CHECK (
  tenant_id = (SELECT private.tenant_id())
  AND (SELECT private.has_permission('users.manage'))
  AND NOT is_system
);

CREATE OR REPLACE FUNCTION private.sync_leadership_appointment_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_old_key text;
  v_new_key text;
  v_old_role_key text;
  v_new_role_key text;
  v_new_scope_type text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.user_id IS NOT DISTINCT FROM NEW.user_id
       AND OLD.tenant_id IS NOT DISTINCT FROM NEW.tenant_id
       AND OLD.position_id IS NOT DISTINCT FROM NEW.position_id
       AND OLD.scope_type IS NOT DISTINCT FROM NEW.scope_type
       AND OLD.scope_id IS NOT DISTINCT FROM NEW.scope_id
       AND OLD.starts_at IS NOT DISTINCT FROM NEW.starts_at
       AND OLD.ends_at IS NOT DISTINCT FROM NEW.ends_at
       AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
      RETURN NEW;
    END IF;

    SELECT sp.key INTO v_old_key FROM public.staff_positions sp WHERE sp.id = OLD.position_id;
    v_old_role_key := CASE
      WHEN v_old_key IN ('dean', 'vice_dean', 'department_head') THEN v_old_key
      ELSE NULL
    END;

    IF v_old_role_key IS NOT NULL THEN
      UPDATE public.user_roles ur
      SET assignment_status = 'revoked', revoked_at = COALESCE(ur.revoked_at, now())
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
  END IF;

  SELECT sp.key INTO v_new_key FROM public.staff_positions sp WHERE sp.id = NEW.position_id;
  v_new_role_key := CASE
    WHEN v_new_key IN ('dean', 'vice_dean', 'department_head') THEN v_new_key
    ELSE NULL
  END;
  IF v_new_role_key IS NULL THEN RETURN NEW; END IF;

  v_new_scope_type := CASE
    WHEN v_new_role_key IN ('dean', 'vice_dean') THEN 'faculty'
    WHEN v_new_role_key = 'department_head' THEN 'department'
  END;
  IF NEW.scope_type <> v_new_scope_type THEN
    RAISE EXCEPTION 'The % appointment must have % scope', v_new_role_key, v_new_scope_type
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.status = 'active' AND (NEW.ends_at IS NULL OR NEW.ends_at > now()) THEN
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
        RAISE EXCEPTION 'The system role % is not configured for this tenant', v_new_role_key
          USING ERRCODE = 'foreign_key_violation';
      END IF;
    END IF;
  ELSE
    UPDATE public.user_roles ur
    SET assignment_status = 'revoked', revoked_at = COALESCE(ur.revoked_at, now())
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

REVOKE EXECUTE ON FUNCTION public.attendance_qr_token(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attendance_qr_token(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.check_in(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_in(uuid, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.directory_search(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.directory_search(text, integer) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.drop_section(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.drop_section(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.enroll_in_section(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enroll_in_section(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.open_record_access(uuid, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_record_access(uuid, text, integer) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.register_for_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_for_event(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.start_attempt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_attempt(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.start_direct_channel(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_direct_channel(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.submit_attempt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_attempt(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.submit_survey_response(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_survey_response(uuid, jsonb) TO authenticated, service_role;

DO $block$
DECLARE
  v_fk record;
  v_columns text;
  v_index_name text;
BEGIN
  FOR v_fk IN
    SELECT c.conrelid, c.conkey, ns.nspname, tbl.relname
    FROM pg_constraint c
    JOIN pg_class tbl ON tbl.oid = c.conrelid
    JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
    WHERE c.contype = 'f'
      AND ns.nspname = 'public'
      AND NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = c.conrelid
          AND i.indisvalid
          AND i.indpred IS NULL
          AND i.indnkeyatts >= cardinality(c.conkey)
          AND (
            SELECT array_agg(i.indkey[g] ORDER BY g)
            FROM generate_series(0, cardinality(c.conkey) - 1) AS g
          ) = c.conkey
      )
  LOOP
    SELECT string_agg(format('%I', a.attname), ', ' ORDER BY k.ord),
           string_agg(a.attname, '_' ORDER BY k.ord)
    INTO v_columns, v_index_name
    FROM unnest(v_fk.conkey) WITH ORDINALITY AS k(attnum, ord)
    JOIN pg_attribute a ON a.attrelid = v_fk.conrelid AND a.attnum = k.attnum;

    v_index_name := left('idx_' || v_fk.relname || '_' || v_index_name || '_fk', 63);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.%I (%s)',
      v_index_name, v_fk.nspname, v_fk.relname, v_columns);
  END LOOP;
END;
$block$;
