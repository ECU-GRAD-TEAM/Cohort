-- Simplify unified role assignments and expand student role categories.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

UPDATE public.user_roles
SET granted_by = COALESCE(granted_by, appointed_by)
WHERE appointed_by IS NOT NULL;

CREATE OR REPLACE FUNCTION private.sync_user_role_lifecycle()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $function$
BEGIN
  IF NEW.status = 'active' THEN
    NEW.assignment_status := 'active';
    NEW.revoked_at := NULL;
  ELSE
    NEW.assignment_status := 'revoked';
    IF NEW.status = 'revoked' THEN NEW.revoked_at := COALESCE(NEW.revoked_at, now()); END IF;
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
       OR NEW.starts_at IS DISTINCT FROM OLD.starts_at OR NEW.granted_by IS DISTINCT FROM OLD.granted_by
       OR NEW.granted_at IS DISTINCT FROM OLD.granted_at OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Assignment identity, scope, start date, and grant attribution are immutable'
        USING ERRCODE = 'check_violation';
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
    IF (SELECT auth.uid()) IS NOT NULL THEN
      NEW.granted_by := COALESCE(NEW.granted_by, (SELECT auth.uid()));
      IF NEW.granted_by IS DISTINCT FROM (SELECT auth.uid()) THEN
        RAISE EXCEPTION 'granted_by must be the authenticated actor' USING ERRCODE = 'insufficient_privilege';
      END IF;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.granted_by IS DISTINCT FROM OLD.granted_by THEN
      RAISE EXCEPTION 'granted_by is immutable' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status IN ('ended','revoked') AND NEW.status IS DISTINCT FROM OLD.status
       AND (SELECT auth.uid()) IS NOT NULL THEN
      NEW.ended_by := COALESCE(NEW.ended_by, (SELECT auth.uid()));
      IF NEW.ended_by IS DISTINCT FROM (SELECT auth.uid()) THEN
        RAISE EXCEPTION 'ended_by must be the authenticated actor' USING ERRCODE = 'insufficient_privilege';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

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
  IF v_role_type NOT IN ('system','position','both') THEN
    RAISE EXCEPTION 'Unsupported role definition type' USING ERRCODE = 'check_violation';
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
  IF (v_role_key IN ('dean','vice_dean') AND NEW.scope_type <> 'faculty')
     OR (v_role_key = 'department_head' AND NEW.scope_type <> 'department') THEN
    RAISE EXCEPTION 'Leadership role % has an invalid organizational scope', v_role_key USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.has_role(p_role_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id AND r.tenant_id = ur.tenant_id
    WHERE ur.user_id = (SELECT auth.uid()) AND ur.tenant_id = private.tenant_id()
      AND r.key = p_role_key AND ur.assignment_status = 'active' AND ur.status = 'active'
      AND ur.starts_at <= now() AND (ur.ends_at IS NULL OR ur.ends_at > now())
      AND ur.revoked_at IS NULL
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
      AND ur.starts_at <= now() AND (ur.ends_at IS NULL OR ur.ends_at > now())
      AND ur.revoked_at IS NULL
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
      AND ur.starts_at <= now() AND (ur.ends_at IS NULL OR ur.ends_at > now()) AND ur.revoked_at IS NULL
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

DO $replace_undergraduate_role_checks$
DECLARE v_definition text; v_original text;
BEGIN
  SELECT pg_get_functiondef('private.validate_student_academic_progression()'::regprocedure) INTO v_definition;
  v_original := v_definition;
  v_definition := replace(v_definition, 'r.key = ''student''', 'r.key = ''undergraduate''');
  v_definition := replace(v_definition, 'AND (ur.expires_at IS NULL OR ur.expires_at > now())', '');
  IF v_definition = v_original THEN RAISE EXCEPTION 'Could not update student academic progression role check'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.enroll_in_section(uuid)'::regprocedure) INTO v_definition;
  v_original := v_definition;
  v_definition := replace(v_definition, 'r.key = ''student''', 'r.key = ''undergraduate''');
  v_definition := replace(v_definition, 'AND (ur.expires_at IS NULL OR ur.expires_at > now())', '');
  IF v_definition = v_original THEN RAISE EXCEPTION 'Could not update course registration role check'; END IF;
  EXECUTE v_definition;
END;
$replace_undergraduate_role_checks$;

CREATE OR REPLACE FUNCTION private.seed_tenant_roles()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.roles
    (tenant_id,key,name,description,is_system,role_type,category,is_academic_rank,is_active)
  VALUES
    (NEW.id,'academic_advisor','Academic Advisor',NULL,true,'system',NULL,false,true),
    (NEW.id,'assistant_professor','Assistant Professor','Academic rank.',true,'position','academic',true,true),
    (NEW.id,'associate_professor','Associate Professor','Academic rank.',true,'position','academic',true,true),
    (NEW.id,'dean','Dean','Faculty-scoped academic leadership position.',true,'both','academic',false,true),
    (NEW.id,'department_head','Department Head','Department-scoped academic leadership position.',true,'both','academic',false,true),
    (NEW.id,'finance_manager','Finance Manager','Finance management position.',true,'position','administrative',false,true),
    (NEW.id,'finance_officer','Finance Officer','Finance operations position.',true,'position','administrative',false,true),
    (NEW.id,'graduate','Graduate','Graduate student role.',true,'system','academic',false,true),
    (NEW.id,'instructor','Instructor','Teaching role without an academic professorial rank.',true,'both','academic',false,true),
    (NEW.id,'it_administrator','IT Administrator','University technology administration position.',true,'position','technical',false,true),
    (NEW.id,'it_director','IT Director','University technology leadership position.',true,'position','technical',false,true),
    (NEW.id,'it_officer','IT Officer',NULL,true,'system',NULL,false,true),
    (NEW.id,'lecturer','Lecturer','Academic teaching position.',true,'position','academic',true,true),
    (NEW.id,'librarian','Librarian','Library services position.',true,'position','support',false,true),
    (NEW.id,'postgraduate','PostGraduate','Postgraduate student role.',true,'system','academic',false,true),
    (NEW.id,'president','President','University-wide leadership position.',true,'position','academic',false,true),
    (NEW.id,'professor','Professor','Senior academic rank.',true,'position','academic',true,true),
    (NEW.id,'programme_coordinator','Programme Coordinator','Academic programme coordination position.',true,'position','academic',false,true),
    (NEW.id,'programme_director','Programme Director','Academic programme leadership position.',true,'position','academic',false,true),
    (NEW.id,'student_affairs_officer','Student Affairs Officer','Student affairs administration position.',true,'position','administrative',false,true),
    (NEW.id,'teaching_assistant','Teaching Assistant','Academic teaching support position.',true,'both','academic',false,true),
    (NEW.id,'undergraduate','Undergraduate',NULL,true,'system','academic',false,true),
    (NEW.id,'vice_dean','Vice Dean','Faculty-scoped deputy academic leadership position.',true,'both','academic',false,true),
    (NEW.id,'vice_president','Vice President','University-wide deputy leadership position.',true,'position','academic',false,true)
  ON CONFLICT (tenant_id,key) DO NOTHING;
  RETURN NEW;
END;
$function$;

ALTER TABLE public.roles DISABLE TRIGGER roles_guard_identity_fields;
UPDATE public.roles SET key='undergraduate',name='Undergraduate',category='academic',role_type='system'
WHERE key='student';
INSERT INTO public.roles
  (tenant_id,key,name,description,is_system,role_type,category,is_academic_rank,is_active)
SELECT DISTINCT r.tenant_id, seed.key, seed.name, seed.description, true, 'system','academic',false,true
FROM public.roles r
CROSS JOIN (VALUES
  ('graduate','Graduate','Graduate student role.'),
  ('postgraduate','PostGraduate','Postgraduate student role.')
) seed(key,name,description)
ON CONFLICT (tenant_id,key) DO NOTHING;
ALTER TABLE public.roles ENABLE TRIGGER roles_guard_identity_fields;

ALTER TABLE public.user_roles
  DROP CONSTRAINT IF EXISTS user_roles_appointed_by_tenant_id_fkey,
  DROP CONSTRAINT IF EXISTS user_roles_appointment_type_check,
  DROP CONSTRAINT IF EXISTS user_roles_assignment_dates_check;
DROP INDEX IF EXISTS public.user_roles_source_appointment_id_uidx;
DROP INDEX IF EXISTS public.user_roles_appointed_by_tenant_id_idx;
ALTER TABLE public.user_roles
  DROP COLUMN appointed_by,
  DROP COLUMN expires_at,
  DROP COLUMN source_appointment_id,
  DROP COLUMN appointment_type;

COMMIT;
