-- Normalize the Postgraduate display name and rename the assignment revocation actor.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

UPDATE public.roles
SET name = 'Postgraduate'
WHERE key = 'postgraduate' AND name IS DISTINCT FROM 'Postgraduate';

DO $rename_seed_display_name$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef('private.seed_tenant_roles()'::regprocedure) INTO v_definition;
  IF position('PostGraduate' in v_definition) > 0 THEN
    EXECUTE replace(v_definition, 'PostGraduate', 'Postgraduate');
  END IF;
END;
$rename_seed_display_name$;

ALTER TABLE public.user_roles RENAME COLUMN ended_by TO revoked_by;
ALTER TABLE public.user_roles
  RENAME CONSTRAINT user_roles_ended_by_tenant_id_fkey TO user_roles_revoked_by_tenant_id_fkey;
ALTER INDEX public.user_roles_ended_by_tenant_id_idx RENAME TO user_roles_revoked_by_tenant_id_idx;

DO $rename_actor_column_references$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef('private.guard_user_role_actor()'::regprocedure) INTO v_definition;
  IF position('ended_by' in v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected ended_by reference in private.guard_user_role_actor';
  END IF;
  EXECUTE replace(v_definition, 'ended_by', 'revoked_by');

  SELECT pg_get_functiondef('private.guard_identity_fields()'::regprocedure) INTO v_definition;
  IF position('ended_by' in v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected ended_by reference in private.guard_identity_fields';
  END IF;
  EXECUTE replace(v_definition, 'ended_by', 'revoked_by');
END;
$rename_actor_column_references$;
COMMIT;
