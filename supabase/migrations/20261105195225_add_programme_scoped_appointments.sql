-- Programme-scoped appointments and authorization.
ALTER TABLE public.personnel_appointments
  DROP CONSTRAINT IF EXISTS personnel_appointments_scope_type_check,
  ADD CONSTRAINT personnel_appointments_scope_type_check
  CHECK (scope_type IN ('university', 'faculty', 'department', 'program'));

ALTER TABLE public.user_roles
  DROP CONSTRAINT IF EXISTS user_roles_scope_check,
  ADD CONSTRAINT user_roles_scope_check CHECK (
    scope_type IN ('university', 'faculty', 'department', 'program', 'course')
    AND ((scope_type = 'university' AND scope_id IS NULL)
      OR (scope_type <> 'university' AND scope_id IS NOT NULL))
  );

CREATE OR REPLACE FUNCTION private.validate_personnel_appointment_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_exists boolean := false;
BEGIN
  IF NEW.scope_type = 'university' THEN RETURN NEW;
  ELSIF NEW.scope_type = 'faculty' THEN
    SELECT EXISTS (SELECT 1 FROM public.faculties f WHERE f.id=NEW.scope_id AND f.tenant_id=NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'department' THEN
    SELECT EXISTS (SELECT 1 FROM public.departments d WHERE d.id=NEW.scope_id AND d.tenant_id=NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'program' THEN
    SELECT EXISTS (SELECT 1 FROM public.programs p WHERE p.id=NEW.scope_id AND p.tenant_id=NEW.tenant_id) INTO v_exists;
  END IF;
  IF NOT v_exists THEN RAISE EXCEPTION 'Appointment scope does not exist in this tenant' USING ERRCODE='foreign_key_violation'; END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.validate_user_role_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_exists boolean := false;
BEGIN
  IF NEW.scope_type = 'university' THEN
    IF NEW.scope_id IS NOT NULL THEN RAISE EXCEPTION 'University-wide role assignments must not have a scope_id'; END IF;
    RETURN NEW;
  ELSIF NEW.scope_type = 'faculty' THEN
    SELECT EXISTS (SELECT 1 FROM public.faculties f WHERE f.id=NEW.scope_id AND f.tenant_id=NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'department' THEN
    SELECT EXISTS (SELECT 1 FROM public.departments d WHERE d.id=NEW.scope_id AND d.tenant_id=NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'program' THEN
    SELECT EXISTS (SELECT 1 FROM public.programs p WHERE p.id=NEW.scope_id AND p.tenant_id=NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'course' THEN
    SELECT EXISTS (SELECT 1 FROM public.course_offerings co WHERE co.id=NEW.scope_id AND co.tenant_id=NEW.tenant_id) INTO v_exists;
  END IF;
  IF NOT v_exists THEN RAISE EXCEPTION 'Role assignment scope does not exist in this tenant' USING ERRCODE='foreign_key_violation'; END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.has_permission(p_permission text,p_scope_type text,p_scope_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id=ur.role_id AND rp.tenant_id=ur.tenant_id
    WHERE ur.user_id=(SELECT auth.uid()) AND ur.tenant_id=private.tenant_id()
      AND rp.permission_key=p_permission AND ur.assignment_status='active'
      AND ur.starts_at<=now() AND (ur.expires_at IS NULL OR ur.expires_at>now())
      AND ur.revoked_at IS NULL
      AND (
        ur.scope_type='university'
        OR (ur.scope_type=p_scope_type AND ur.scope_id=p_scope_id)
        OR (p_scope_type='department' AND ur.scope_type='faculty' AND EXISTS (
          SELECT 1 FROM public.departments d WHERE d.id=p_scope_id AND d.faculty_id=ur.scope_id AND d.tenant_id=ur.tenant_id
        ))
        OR (p_scope_type='program' AND ur.scope_type IN ('faculty','department') AND EXISTS (
          SELECT 1 FROM public.programs p JOIN public.departments d ON d.id=p.department_id AND d.tenant_id=p.tenant_id
          WHERE p.id=p_scope_id AND p.tenant_id=ur.tenant_id
            AND ((ur.scope_type='department' AND d.id=ur.scope_id)
              OR (ur.scope_type='faculty' AND d.faculty_id=ur.scope_id))
        ))
      )
  );
$$;

CREATE OR REPLACE FUNCTION private.has_permission_for_program(p_permission text,p_program_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.programs p
    WHERE p.id=p_program_id AND p.tenant_id=private.tenant_id()
      AND private.has_permission(p_permission,'program',p.id)
  );
$$;

REVOKE EXECUTE ON FUNCTION private.has_permission(text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_permission(text,text,uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION private.has_permission_for_program(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_permission_for_program(text,uuid) TO authenticated;

INSERT INTO public.staff_positions (key,name,category,description,is_academic_rank,is_active)
VALUES
 ('programme_director','Programme Director','academic','Leads the academic planning, delivery, and quality of a specific academic programme.',false,true),
 ('programme_coordinator','Programme Coordinator','academic','Coordinates the day-to-day academic and administrative activities of a specific programme.',false,true)
ON CONFLICT (key) DO UPDATE SET
 name=EXCLUDED.name, category=EXCLUDED.category, description=EXCLUDED.description,
 is_academic_rank=EXCLUDED.is_academic_rank, is_active=EXCLUDED.is_active;
