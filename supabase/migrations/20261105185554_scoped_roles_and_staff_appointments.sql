-- Dynamic staff positions, leadership appointments, and scoped role assignments.
-- Keep users.user_type as a broad account category; rank/title and temporary
-- leadership appointments are modeled separately from authorization.

ALTER TABLE public.user_roles
  ADD COLUMN IF NOT EXISTS scope_type text NOT NULL DEFAULT 'university',
  ADD COLUMN IF NOT EXISTS scope_id uuid,
  ADD COLUMN IF NOT EXISTS starts_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS revoked_at timestamptz,
  ADD COLUMN IF NOT EXISTS assignment_status text NOT NULL DEFAULT 'active';

ALTER TABLE public.user_roles
  DROP CONSTRAINT IF EXISTS user_roles_scope_check,
  DROP CONSTRAINT IF EXISTS user_roles_assignment_status_check,
  DROP CONSTRAINT IF EXISTS user_roles_assignment_dates_check;

ALTER TABLE public.user_roles
  ADD CONSTRAINT user_roles_scope_check
    CHECK (scope_type IN ('university', 'faculty', 'department', 'course')
      AND ((scope_type = 'university' AND scope_id IS NULL)
        OR (scope_type <> 'university' AND scope_id IS NOT NULL))),
  ADD CONSTRAINT user_roles_assignment_status_check
    CHECK (assignment_status IN ('active', 'revoked')),
  ADD CONSTRAINT user_roles_assignment_dates_check
    CHECK (expires_at IS NULL OR expires_at > starts_at);

ALTER TABLE public.user_roles DROP CONSTRAINT user_roles_pkey;
ALTER TABLE public.user_roles ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);
CREATE UNIQUE INDEX IF NOT EXISTS user_roles_assignment_scope_uidx
  ON public.user_roles (user_id, role_id, scope_type, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX IF NOT EXISTS user_roles_active_lookup_idx
  ON public.user_roles (user_id, tenant_id, role_id, scope_type, scope_id)
  WHERE assignment_status = 'active';

CREATE OR REPLACE FUNCTION private.validate_user_role_scope()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_exists boolean := false;
BEGIN
  IF NEW.scope_type = 'university' THEN
    IF NEW.scope_id IS NOT NULL THEN RAISE EXCEPTION 'University-wide role assignments must not have a scope_id'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.scope_type = 'faculty' THEN
    SELECT EXISTS (SELECT 1 FROM public.faculties f WHERE f.id = NEW.scope_id AND f.tenant_id = NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'department' THEN
    SELECT EXISTS (SELECT 1 FROM public.departments d WHERE d.id = NEW.scope_id AND d.tenant_id = NEW.tenant_id) INTO v_exists;
  ELSIF NEW.scope_type = 'course' THEN
    SELECT EXISTS (SELECT 1 FROM public.course_offerings co WHERE co.id = NEW.scope_id AND co.tenant_id = NEW.tenant_id) INTO v_exists;
  END IF;
  IF NOT v_exists THEN RAISE EXCEPTION 'Role assignment scope does not exist in this tenant' USING ERRCODE = 'foreign_key_violation'; END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS user_roles_validate_scope ON public.user_roles;
CREATE TRIGGER user_roles_validate_scope BEFORE INSERT OR UPDATE OF tenant_id, scope_type, scope_id
  ON public.user_roles FOR EACH ROW EXECUTE FUNCTION private.validate_user_role_scope();

CREATE TABLE IF NOT EXISTS public.staff_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL UNIQUE,
  name text NOT NULL,
  category text NOT NULL CHECK (category IN ('academic', 'administrative', 'technical', 'support')),
  description text,
  is_academic_rank boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.staff_positions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "members read staff position catalogue" ON public.staff_positions;
CREATE POLICY "members read staff position catalogue" ON public.staff_positions FOR SELECT TO authenticated USING (true);

INSERT INTO public.staff_positions (key, name, category, description, is_academic_rank) VALUES
  ('instructor', 'Instructor', 'academic', 'Teaching role without an academic professorial rank.', false),
  ('lecturer', 'Lecturer', 'academic', 'Academic teaching position.', true),
  ('assistant_professor', 'Assistant Professor', 'academic', 'Academic rank.', true),
  ('associate_professor', 'Associate Professor', 'academic', 'Academic rank.', true),
  ('professor', 'Professor', 'academic', 'Senior academic rank.', true),
  ('admission_officer', 'Admission Officer', 'administrative', 'Admissions operations position.', false),
  ('registrar', 'Registrar', 'administrative', 'Academic records and registration position.', false),
  ('finance_officer', 'Finance Officer', 'administrative', 'Finance operations position.', false),
  ('hr_officer', 'HR Officer', 'administrative', 'Human resources position.', false),
  ('it_administrator', 'IT Administrator', 'technical', 'University technology administration position.', false),
  ('support_technician', 'Support Technician', 'technical', 'Technical support position.', false),
  ('librarian', 'Librarian', 'support', 'Library services position.', false),
  ('lab_technician', 'Laboratory Technician', 'support', 'Laboratory operations position.', false)
ON CONFLICT (key) DO UPDATE SET name=EXCLUDED.name, category=EXCLUDED.category,
  description=EXCLUDED.description, is_academic_rank=EXCLUDED.is_academic_rank;

CREATE TABLE IF NOT EXISTS public.personnel_appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  position_id uuid NOT NULL REFERENCES public.staff_positions(id),
  appointment_type text NOT NULL DEFAULT 'position' CHECK (appointment_type IN ('position', 'leadership')),
  scope_type text NOT NULL CHECK (scope_type IN ('university', 'faculty', 'department')),
  scope_id uuid,
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended', 'revoked')),
  appointed_by uuid,
  ended_by uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((scope_type = 'university' AND scope_id IS NULL) OR (scope_type <> 'university' AND scope_id IS NOT NULL)),
  CHECK (ends_at IS NULL OR ends_at > starts_at),
  FOREIGN KEY (user_id, tenant_id) REFERENCES public.users(id, tenant_id) ON DELETE CASCADE,
  FOREIGN KEY (appointed_by, tenant_id) REFERENCES public.users(id, tenant_id),
  FOREIGN KEY (ended_by, tenant_id) REFERENCES public.users(id, tenant_id)
);
CREATE INDEX IF NOT EXISTS personnel_appointments_user_active_idx ON public.personnel_appointments (user_id, tenant_id, starts_at, ends_at) WHERE status='active';
CREATE INDEX IF NOT EXISTS personnel_appointments_scope_idx ON public.personnel_appointments (tenant_id, scope_type, scope_id) WHERE status='active';
ALTER TABLE public.personnel_appointments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "members read own appointments or account managers read all" ON public.personnel_appointments;
CREATE POLICY "members read own appointments or account managers read all" ON public.personnel_appointments FOR SELECT TO authenticated
  USING (tenant_id=(SELECT private.tenant_id()) AND (user_id=(SELECT auth.uid()) OR (SELECT private.has_permission('users.manage'))));
DROP POLICY IF EXISTS "account managers create appointments" ON public.personnel_appointments;
CREATE POLICY "account managers create appointments" ON public.personnel_appointments FOR INSERT TO authenticated
  WITH CHECK (tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission('users.manage')) AND appointed_by=(SELECT auth.uid()));
DROP POLICY IF EXISTS "account managers update appointments" ON public.personnel_appointments;
CREATE POLICY "account managers update appointments" ON public.personnel_appointments FOR UPDATE TO authenticated
  USING (tenant_id=(SELECT private.tenant_id()) AND (SELECT private.has_permission('users.manage')))
  WITH CHECK (tenant_id=(SELECT private.tenant_id()));

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
  END IF;
  IF NOT v_exists THEN RAISE EXCEPTION 'Appointment scope does not exist in this tenant' USING ERRCODE='foreign_key_violation'; END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS personnel_appointments_validate_scope ON public.personnel_appointments;
CREATE TRIGGER personnel_appointments_validate_scope BEFORE INSERT OR UPDATE OF tenant_id, scope_type, scope_id
  ON public.personnel_appointments FOR EACH ROW EXECUTE FUNCTION private.validate_personnel_appointment_scope();

-- Legacy one-argument checks now authorize university-wide assignments only.
CREATE OR REPLACE FUNCTION private.has_permission(p_permission text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id=ur.role_id AND rp.tenant_id=ur.tenant_id
    WHERE ur.user_id=(SELECT auth.uid()) AND ur.tenant_id=private.tenant_id()
      AND rp.permission_key=p_permission AND ur.scope_type='university'
      AND ur.assignment_status='active' AND ur.starts_at<=now()
      AND (ur.expires_at IS NULL OR ur.expires_at>now()) AND ur.revoked_at IS NULL
  )
$$;

CREATE OR REPLACE FUNCTION private.has_permission(p_permission text, p_scope_type text, p_scope_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id=ur.role_id AND rp.tenant_id=ur.tenant_id
    WHERE ur.user_id=(SELECT auth.uid()) AND ur.tenant_id=private.tenant_id()
      AND rp.permission_key=p_permission AND ur.assignment_status='active'
      AND ur.starts_at<=now() AND (ur.expires_at IS NULL OR ur.expires_at>now()) AND ur.revoked_at IS NULL
      AND (ur.scope_type='university'
        OR (ur.scope_type=p_scope_type AND ur.scope_id=p_scope_id)
        OR (p_scope_type='department' AND ur.scope_type='faculty' AND EXISTS (
          SELECT 1 FROM public.departments d WHERE d.id=p_scope_id AND d.faculty_id=ur.scope_id AND d.tenant_id=ur.tenant_id
        )))
  )
$$;
REVOKE EXECUTE ON FUNCTION private.has_permission(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION private.has_permission(text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.has_permission(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_permission(text, text, uuid) TO authenticated;

DROP TRIGGER IF EXISTS personnel_appointments_audit ON public.personnel_appointments;
CREATE TRIGGER personnel_appointments_audit AFTER INSERT OR UPDATE OR DELETE ON public.personnel_appointments
  FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

-- Keep users.user_type enum values unchanged; rank and appointments are separate.
