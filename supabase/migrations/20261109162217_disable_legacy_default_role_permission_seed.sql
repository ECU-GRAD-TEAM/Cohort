-- Retire the legacy default role/permission seed. The unified role catalogue
-- is now populated exclusively by private.seed_tenant_roles().
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE OR REPLACE FUNCTION private.seed_default_roles_for_tenant(p_tenant_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RETURN;
END;
$function$;
COMMIT;
