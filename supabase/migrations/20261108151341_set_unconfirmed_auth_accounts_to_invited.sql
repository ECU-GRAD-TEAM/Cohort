-- Keep unconfirmed Auth accounts in the invited state until email confirmation.
-- This supports silent Auth Admin provisioning without granting application access.

CREATE OR REPLACE FUNCTION private.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
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
    RAISE EXCEPTION 'Auth account requires an id and email'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_tenant IS NULL OR v_type IS NULL THEN
    RAISE EXCEPTION 'Auth account requires valid app_metadata tenant_id and user_type (staff or non_staff)'
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
    WHEN NEW.email_confirmed_at IS NULL
      THEN 'invited'::public.account_status
    ELSE 'active'::public.account_status
  END;

  INSERT INTO public.users (
    id, tenant_id, user_type, status, email, institutional_id
  )
  VALUES (
    NEW.id,
    v_tenant,
    v_type,
    v_status,
    lower(NEW.email),
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
