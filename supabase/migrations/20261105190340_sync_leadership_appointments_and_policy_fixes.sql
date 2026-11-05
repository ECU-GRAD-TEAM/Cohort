-- Link leadership appointments to scoped authorization assignments.
-- Also make INSERT policies evaluate the parent scope rather than the new row id.

CREATE OR REPLACE FUNCTION private.sync_leadership_appointment_role()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_role_key text; v_scope_type text;
BEGIN
  SELECT sp.key INTO v_role_key FROM public.staff_positions sp WHERE sp.id=NEW.position_id;
  IF v_role_key NOT IN ('dean','vice_dean','department_head') THEN RETURN NEW; END IF;
  v_scope_type := CASE WHEN v_role_key IN ('dean','vice_dean') THEN 'faculty' ELSE 'department' END;
  IF NEW.scope_type <> v_scope_type THEN
    RAISE EXCEPTION 'The % appointment must have % scope',v_role_key,v_scope_type;
  END IF;

  IF TG_OP='UPDATE' THEN
    UPDATE public.user_roles ur
    SET assignment_status='revoked',revoked_at=COALESCE(ur.revoked_at,now())
    WHERE ur.user_id=OLD.user_id AND ur.tenant_id=OLD.tenant_id
      AND ur.scope_type=OLD.scope_type AND ur.scope_id IS NOT DISTINCT FROM OLD.scope_id
      AND ur.role_id IN (SELECT r.id FROM public.roles r WHERE r.tenant_id=OLD.tenant_id AND r.key=v_role_key)
      AND ur.assignment_status='active'
      AND (OLD.status<>NEW.status OR OLD.scope_id IS DISTINCT FROM NEW.scope_id
        OR OLD.user_id<>NEW.user_id OR OLD.starts_at IS DISTINCT FROM NEW.starts_at
        OR OLD.ends_at IS DISTINCT FROM NEW.ends_at);
  END IF;

  IF NEW.status='active' AND (NEW.ends_at IS NULL OR NEW.ends_at>now()) THEN
    UPDATE public.user_roles ur
    SET starts_at=NEW.starts_at,expires_at=NEW.ends_at,assignment_status='active',
        revoked_at=NULL,granted_by=NEW.appointed_by
    WHERE ur.user_id=NEW.user_id AND ur.tenant_id=NEW.tenant_id
      AND ur.scope_type=NEW.scope_type AND ur.scope_id=NEW.scope_id
      AND ur.role_id IN (SELECT r.id FROM public.roles r WHERE r.tenant_id=NEW.tenant_id AND r.key=v_role_key);
    IF NOT FOUND THEN
      INSERT INTO public.user_roles(user_id,role_id,tenant_id,granted_by,starts_at,expires_at,scope_type,scope_id,assignment_status)
      SELECT NEW.user_id,r.id,NEW.tenant_id,NEW.appointed_by,NEW.starts_at,NEW.ends_at,NEW.scope_type,NEW.scope_id,'active'
      FROM public.roles r WHERE r.tenant_id=NEW.tenant_id AND r.key=v_role_key;
    END IF;
  ELSE
    UPDATE public.user_roles ur SET assignment_status='revoked',revoked_at=COALESCE(ur.revoked_at,now())
    WHERE ur.user_id=NEW.user_id AND ur.tenant_id=NEW.tenant_id
      AND ur.scope_type=NEW.scope_type AND ur.scope_id=NEW.scope_id
      AND ur.role_id IN (SELECT r.id FROM public.roles r WHERE r.tenant_id=NEW.tenant_id AND r.key=v_role_key)
      AND ur.assignment_status='active';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION private.sync_leadership_appointment_role() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS personnel_appointments_sync_leadership_role ON public.personnel_appointments;
CREATE TRIGGER personnel_appointments_sync_leadership_role AFTER INSERT OR UPDATE ON public.personnel_appointments
FOR EACH ROW EXECUTE FUNCTION private.sync_leadership_appointment_role();

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.departments;
CREATE POLICY "academic managers write the catalogue" ON public.departments FOR ALL TO authenticated
USING (tenant_id=(SELECT private.tenant_id()) AND
  (private.has_permission('academic.manage','department',id) OR private.has_permission('academic.manage','faculty',faculty_id)))
WITH CHECK (tenant_id=(SELECT private.tenant_id()) AND
  (private.has_permission('academic.manage','department',id) OR private.has_permission('academic.manage','faculty',faculty_id)));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.course_offerings;
CREATE POLICY "academic managers write the catalogue" ON public.course_offerings FOR ALL TO authenticated
USING (tenant_id=(SELECT private.tenant_id()) AND private.has_permission_for_offering('academic.manage',id))
WITH CHECK (tenant_id=(SELECT private.tenant_id()) AND EXISTS (
  SELECT 1 FROM public.courses c WHERE c.id=course_id AND c.tenant_id=course_offerings.tenant_id
    AND (private.has_permission('academic.manage','department',c.department_id)
      OR private.has_permission('academic.manage','course',id))));

DROP POLICY IF EXISTS "academic managers write the catalogue" ON public.sections;
CREATE POLICY "academic managers write the catalogue" ON public.sections FOR ALL TO authenticated
USING (tenant_id=(SELECT private.tenant_id()) AND private.has_permission_for_offering('academic.manage',offering_id))
WITH CHECK (tenant_id=(SELECT private.tenant_id()) AND private.has_permission_for_offering('academic.manage',offering_id));

-- Preserve grade-scale management as a university-wide capability because
-- grade scales do not carry a faculty or department foreign key.
DROP POLICY IF EXISTS "grade managers write grade scales" ON public.grade_scales;
CREATE POLICY "grade managers write grade scales" ON public.grade_scales
FOR ALL TO authenticated
USING (tenant_id=(SELECT private.tenant_id()) AND private.has_permission('grades.manage'))
WITH CHECK (tenant_id=(SELECT private.tenant_id()) AND private.has_permission('grades.manage'));
