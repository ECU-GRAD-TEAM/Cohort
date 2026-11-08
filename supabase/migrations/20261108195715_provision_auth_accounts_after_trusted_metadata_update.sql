-- Allow Auth Admin to create an unconfirmed Auth identity first, then provision
-- the university account only after trusted app_metadata is assigned by Admin API.

CREATE OR REPLACE FUNCTION private.provision_auth_user_account(
  p_user_id uuid,
  p_email text,
  p_email_confirmed_at timestamptz,
  p_raw_app_meta_data jsonb,
  p_raw_user_meta_data jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_tenant_text text;
  v_tenant uuid;
  v_type public.user_type;
  v_existing_tenant uuid;
  v_existing_type public.user_type;
  v_status public.account_status;
BEGIN
  IF p_user_id IS NULL OR p_email IS NULL THEN
    RAISE EXCEPTION 'Auth account requires an id and email'
      USING ERRCODE = 'check_violation';
  END IF;

  v_tenant_text := nullif(btrim(coalesce(p_raw_app_meta_data ->> 'tenant_id', '')), '');
  IF v_tenant_text IS NULL
     AND nullif(btrim(coalesce(p_raw_app_meta_data ->> 'user_type', '')), '') IS NULL THEN
    -- Normal Auth creation may precede trusted server-side tenant provisioning.
    RETURN;
  END IF;

  IF v_tenant_text IS NULL THEN
    RAISE EXCEPTION 'Trusted app_metadata requires tenant_id'
      USING ERRCODE = 'check_violation';
  END IF;

  BEGIN
    v_tenant := v_tenant_text::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Auth account requires a valid app_metadata tenant_id'
      USING ERRCODE = 'check_violation';
  END;

  v_type := CASE p_raw_app_meta_data ->> 'user_type'
    WHEN 'staff' THEN 'staff'::public.user_type
    WHEN 'non_staff' THEN 'non_staff'::public.user_type
    ELSE NULL
  END;

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'Auth account requires app_metadata user_type staff or non_staff'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.tenants t
    WHERE t.id = v_tenant AND t.status = 'active'
  ) THEN
    RAISE EXCEPTION 'The requested tenant does not exist or is not active'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_status := CASE
    WHEN p_email_confirmed_at IS NULL
      THEN 'invited'::public.account_status
    ELSE 'active'::public.account_status
  END;

  INSERT INTO public.users (id, tenant_id, user_type, status, email, institutional_id)
  VALUES (
    p_user_id,
    v_tenant,
    v_type,
    v_status,
    lower(p_email),
    nullif(p_raw_app_meta_data ->> 'institutional_id', '')
  )
  ON CONFLICT (id) DO NOTHING;

  SELECT u.tenant_id, u.user_type
  INTO v_existing_tenant, v_existing_type
  FROM public.users u
  WHERE u.id = p_user_id;

  IF NOT FOUND
     OR v_existing_tenant IS DISTINCT FROM v_tenant
     OR v_existing_type IS DISTINCT FROM v_type THEN
    RAISE EXCEPTION 'Existing university account does not match trusted Auth tenant and user_type metadata'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.person_profiles
  SET display_name = coalesce(
    nullif(btrim(p_raw_user_meta_data ->> 'full_name'), ''),
    display_name
  )
  WHERE user_id = p_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  PERFORM private.provision_auth_user_account(
    NEW.id,
    NEW.email,
    NEW.email_confirmed_at,
    NEW.raw_app_meta_data,
    NEW.raw_user_meta_data
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.handle_auth_app_metadata_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF OLD.raw_app_meta_data IS DISTINCT FROM NEW.raw_app_meta_data THEN
    PERFORM private.provision_auth_user_account(
      NEW.id,
      NEW.email,
      NEW.email_confirmed_at,
      NEW.raw_app_meta_data,
      NEW.raw_user_meta_data
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_auth_user_app_metadata_updated ON auth.users;
CREATE TRIGGER on_auth_user_app_metadata_updated
AFTER UPDATE OF raw_app_meta_data ON auth.users
FOR EACH ROW
WHEN (OLD.raw_app_meta_data IS DISTINCT FROM NEW.raw_app_meta_data)
EXECUTE FUNCTION private.handle_auth_app_metadata_updated();

REVOKE ALL ON FUNCTION private.provision_auth_user_account(uuid, text, timestamptz, jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.handle_auth_app_metadata_updated()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.handle_new_auth_user()
  FROM PUBLIC, anon, authenticated;
