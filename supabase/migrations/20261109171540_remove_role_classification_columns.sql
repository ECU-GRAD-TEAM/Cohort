-- Remove role classification metadata; role definitions remain simple catalogue entries.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '90s';

ALTER TABLE public.roles
  DROP CONSTRAINT IF EXISTS roles_role_type_check,
  DROP COLUMN IF EXISTS is_academic_rank,
  DROP COLUMN IF EXISTS role_type,
  DROP COLUMN IF EXISTS category;

CREATE OR REPLACE FUNCTION private.validate_user_role_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_exists boolean := false;
  v_role_active boolean;
  v_role_key text;
BEGIN
  SELECT r.is_active, r.key INTO v_role_active, v_role_key
  FROM public.roles r
  WHERE r.id = NEW.role_id AND r.tenant_id = NEW.tenant_id;

  IF v_role_active IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Role assignments require an active role definition' USING ERRCODE = 'check_violation';
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

CREATE OR REPLACE FUNCTION private.seed_tenant_roles()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.roles (tenant_id,key,name,description,is_system,is_active)
  VALUES
    (NEW.id,'academic_advisor','Academic Advisor',NULL,true,true),
    (NEW.id,'assistant_professor','Assistant Professor','Academic rank.',true,true),
    (NEW.id,'associate_professor','Associate Professor','Academic rank.',true,true),
    (NEW.id,'dean','Dean','Faculty-scoped academic leadership position.',true,true),
    (NEW.id,'department_head','Department Head','Department-scoped academic leadership position.',true,true),
    (NEW.id,'finance_manager','Finance Manager','Finance management position.',true,true),
    (NEW.id,'finance_officer','Finance Officer','Finance operations position.',true,true),
    (NEW.id,'graduate','Graduate','Graduate student role.',true,true),
    (NEW.id,'instructor','Instructor','Teaching role without an academic professorial rank.',true,true),
    (NEW.id,'it_administrator','IT Administrator','University technology administration position.',true,true),
    (NEW.id,'it_director','IT Director','University technology leadership position.',true,true),
    (NEW.id,'it_officer','IT Officer',NULL,true,true),
    (NEW.id,'lecturer','Lecturer','Academic teaching position.',true,true),
    (NEW.id,'librarian','Librarian','Library services position.',true,true),
    (NEW.id,'postgraduate','Postgraduate','Postgraduate student role.',true,true),
    (NEW.id,'president','President','University-wide leadership position.',true,true),
    (NEW.id,'professor','Professor','Senior academic rank.',true,true),
    (NEW.id,'programme_coordinator','Programme Coordinator','Academic programme coordination position.',true,true),
    (NEW.id,'programme_director','Programme Director','Academic programme leadership position.',true,true),
    (NEW.id,'student_affairs_officer','Student Affairs Officer','Student affairs administration position.',true,true),
    (NEW.id,'teaching_assistant','Teaching Assistant','Academic teaching support position.',true,true),
    (NEW.id,'undergraduate','Undergraduate',NULL,true,true),
    (NEW.id,'vice_dean','Vice Dean','Faculty-scoped deputy academic leadership position.',true,true),
    (NEW.id,'vice_president','Vice President','University-wide deputy leadership position.',true,true)
  ON CONFLICT (tenant_id,key) DO NOTHING;

  RETURN NEW;
END;
$function$;

COMMIT;
