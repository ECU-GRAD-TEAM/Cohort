-- Create the approved SET staff position and leadership appointments.
-- System-provisioned records deliberately have appointed_by NULL rather than
-- attributing them to a fabricated authenticated person.
-- The existing leadership trigger grants Rania the scoped department_head role.

DO $validation$
DECLARE
  v_staff_count integer;
  v_professor_count integer;
  v_ta_count integer;
  v_bad_profiles integer;
  v_existing_appointments integer;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE p.title = 'Professor'),
         count(*) FILTER (WHERE p.title = 'Teaching Assistant'),
         count(*) FILTER (
           WHERE u.tenant_id <> '97325228-75cb-4a36-b103-9da28968c660'::uuid
              OR u.user_type <> 'staff'
              OR u.status <> 'invited'
              OR p.department_id <> 'e80f3b65-e85c-4c84-9c69-003a4494e6d7'::uuid
              OR p.faculty_id <> 'b3964b2a-bdbe-478e-9bbb-d858966a9d93'::uuid
         )
  INTO v_staff_count, v_professor_count, v_ta_count, v_bad_profiles
  FROM public.users u
  JOIN public.person_profiles p ON p.user_id = u.id
  WHERE lower(u.email) IN (
    'rswief@ecu.edu.eg','mayar.ali@ecu.edu.eg','islam.mohammed@ecu.edu.eg',
    'doaa.amin@ecu.edu.eg','hmhussen@ecu.edu.eg','norhan.mamdoh@ecu.edu.eg',
    'mohamed.mohamed@ecu.edu.eg','maiada.alaaeldin@ecu.edu.eg','ramobark@ecu.edu.eg',
    'asmaa.elwihady@ecu.edu.eg','reem.waleed@ecu.edu.eg','fady.romany@ecu.edu.eg',
    'mohamed.taha@ecu.edu.eg','rahma.ali@ecu.edu.eg','amira.ali@ecu.edu.eg'
  );

  IF v_staff_count <> 15 OR v_professor_count <> 3 OR v_ta_count <> 12 OR v_bad_profiles <> 0 THEN
    RAISE EXCEPTION
      'SET appointment preflight failed: staff %, professors %, teaching assistants %, invalid profiles %',
      v_staff_count, v_professor_count, v_ta_count, v_bad_profiles;
  END IF;

  SELECT count(*) INTO v_existing_appointments
  FROM public.personnel_appointments pa
  JOIN public.users u ON u.id = pa.user_id
  WHERE lower(u.email) IN (
    'rswief@ecu.edu.eg','mayar.ali@ecu.edu.eg','islam.mohammed@ecu.edu.eg',
    'doaa.amin@ecu.edu.eg','hmhussen@ecu.edu.eg','norhan.mamdoh@ecu.edu.eg',
    'mohamed.mohamed@ecu.edu.eg','maiada.alaaeldin@ecu.edu.eg','ramobark@ecu.edu.eg',
    'asmaa.elwihady@ecu.edu.eg','reem.waleed@ecu.edu.eg','fady.romany@ecu.edu.eg',
    'mohamed.taha@ecu.edu.eg','rahma.ali@ecu.edu.eg','amira.ali@ecu.edu.eg'
  );

  IF v_existing_appointments <> 0 THEN
    RAISE EXCEPTION 'SET appointment preflight found % existing appointments; refusing duplicates',
      v_existing_appointments;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.staff_positions WHERE key='professor' AND is_active)
     OR NOT EXISTS (SELECT 1 FROM public.staff_positions WHERE key='teaching_assistant' AND is_active)
     OR NOT EXISTS (SELECT 1 FROM public.staff_positions WHERE key='department_head' AND is_active) THEN
    RAISE EXCEPTION 'Required active SET staff positions are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.roles
    WHERE tenant_id='97325228-75cb-4a36-b103-9da28968c660'::uuid AND key='department_head'
  ) THEN
    RAISE EXCEPTION 'The ECU department_head system role is missing';
  END IF;
END
$validation$;

WITH approved_staff(email) AS (
  VALUES
    ('rswief@ecu.edu.eg'),('mayar.ali@ecu.edu.eg'),('islam.mohammed@ecu.edu.eg'),
    ('doaa.amin@ecu.edu.eg'),('hmhussen@ecu.edu.eg'),('norhan.mamdoh@ecu.edu.eg'),
    ('mohamed.mohamed@ecu.edu.eg'),('maiada.alaaeldin@ecu.edu.eg'),('ramobark@ecu.edu.eg'),
    ('asmaa.elwihady@ecu.edu.eg'),('reem.waleed@ecu.edu.eg'),('fady.romany@ecu.edu.eg'),
    ('mohamed.taha@ecu.edu.eg'),('rahma.ali@ecu.edu.eg'),('amira.ali@ecu.edu.eg')
)
INSERT INTO public.personnel_appointments (
  tenant_id,user_id,position_id,appointment_type,scope_type,scope_id,status,appointed_by,notes
)
SELECT u.tenant_id,u.id,sp.id,'position','department',
       'e80f3b65-e85c-4c84-9c69-003a4494e6d7'::uuid,'active',NULL,
       'Initial SET staff directory appointment; created by approved system provisioning.'
FROM approved_staff s
JOIN public.users u ON lower(u.email)=s.email
JOIN public.person_profiles p ON p.user_id=u.id
JOIN public.staff_positions sp ON sp.key=CASE p.title
  WHEN 'Professor' THEN 'professor'
  WHEN 'Teaching Assistant' THEN 'teaching_assistant'
END
WHERE NOT EXISTS (
  SELECT 1 FROM public.personnel_appointments existing
  WHERE existing.user_id=u.id AND existing.tenant_id=u.tenant_id
    AND existing.position_id=sp.id AND existing.appointment_type='position'
    AND existing.scope_type='department'
    AND existing.scope_id='e80f3b65-e85c-4c84-9c69-003a4494e6d7'::uuid
    AND existing.status='active'
);

-- Rania's Head of SET Department appointment is separate from her Professor
-- position. The existing trigger creates the scoped department_head role.
INSERT INTO public.personnel_appointments (
  tenant_id,user_id,position_id,appointment_type,scope_type,scope_id,status,appointed_by,notes
)
SELECT u.tenant_id,u.id,sp.id,'leadership','department',
       'e80f3b65-e85c-4c84-9c69-003a4494e6d7'::uuid,'active',NULL,
       'Head of SET Department leadership appointment; created by approved system provisioning.'
FROM public.users u
JOIN public.staff_positions sp ON sp.key='department_head' AND sp.is_active
WHERE lower(u.email)='rswief@ecu.edu.eg'
  AND u.tenant_id='97325228-75cb-4a36-b103-9da28968c660'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM public.personnel_appointments existing
    WHERE existing.user_id=u.id AND existing.tenant_id=u.tenant_id
      AND existing.position_id=sp.id AND existing.appointment_type='leadership'
      AND existing.scope_type='department'
      AND existing.scope_id='e80f3b65-e85c-4c84-9c69-003a4494e6d7'::uuid
      AND existing.status='active'
  );

DO $verify$
DECLARE
  v_position_count integer;
  v_leadership_count integer;
  v_head_role_count integer;
BEGIN
  SELECT count(*) FILTER (WHERE pa.appointment_type='position'),
         count(*) FILTER (WHERE pa.appointment_type='leadership')
  INTO v_position_count,v_leadership_count
  FROM public.personnel_appointments pa
  JOIN public.users u ON u.id=pa.user_id
  WHERE u.tenant_id='97325228-75cb-4a36-b103-9da28968c660'::uuid
    AND pa.scope_type='department'
    AND pa.scope_id='e80f3b65-e85c-4c84-9c69-003a4494e6d7'::uuid
    AND pa.status='active'
    AND lower(u.email) IN (
      'rswief@ecu.edu.eg','mayar.ali@ecu.edu.eg','islam.mohammed@ecu.edu.eg',
      'doaa.amin@ecu.edu.eg','hmhussen@ecu.edu.eg','norhan.mamdoh@ecu.edu.eg',
      'mohamed.mohamed@ecu.edu.eg','maiada.alaaeldin@ecu.edu.eg','ramobark@ecu.edu.eg',
      'asmaa.elwihady@ecu.edu.eg','reem.waleed@ecu.edu.eg','fady.romany@ecu.edu.eg',
      'mohamed.taha@ecu.edu.eg','rahma.ali@ecu.edu.eg','amira.ali@ecu.edu.eg'
    );

  SELECT count(*) INTO v_head_role_count
  FROM public.user_roles ur
  JOIN public.users u ON u.id=ur.user_id
  JOIN public.roles r ON r.id=ur.role_id
  WHERE lower(u.email)='rswief@ecu.edu.eg'
    AND ur.tenant_id='97325228-75cb-4a36-b103-9da28968c660'::uuid
    AND r.key='department_head'
    AND ur.scope_type='department'
    AND ur.scope_id='e80f3b65-e85c-4c84-9c69-003a4494e6d7'::uuid
    AND ur.assignment_status='active'
    AND ur.revoked_at IS NULL;

  IF v_position_count<>15 OR v_leadership_count<>1 OR v_head_role_count<>1 THEN
    RAISE EXCEPTION 'SET appointment verification failed: position %, leadership %, Rania department_head roles %',
      v_position_count,v_leadership_count,v_head_role_count;
  END IF;
END
$verify$;
