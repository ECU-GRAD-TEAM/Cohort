-- Assign the confirmed Fall 2026 SET teaching assistants and instructor.
-- Uses tenant-scoped natural keys so this migration can be replayed on another ECU environment.
-- Unconfirmed staff identities and SET 497 supervisors are intentionally omitted.

BEGIN;

WITH assignments(section_code, staff_email, assignment_role) AS (
  VALUES
    ('SA-G1-SET411-LAB', 'mohamed.mohamed@ecu.edu.eg', 'teaching_assistant'),
    ('SA-G2-SET411-LAB', 'mohamed.mohamed@ecu.edu.eg', 'teaching_assistant'),
    ('DMC-G1-SET411-LAB', 'mohamed.mohamed@ecu.edu.eg', 'teaching_assistant'),
    ('SA-G1-SET412-LAB', 'rahma.ali@ecu.edu.eg', 'teaching_assistant'),
    ('SA-G2-SET412-LAB', 'rahma.ali@ecu.edu.eg', 'teaching_assistant'),
    ('DMC-G1-SET412-LAB', 'rahma.ali@ecu.edu.eg', 'teaching_assistant'),
    ('SA-G1-SET472-TUTORIAL', 'amira.ali@ecu.edu.eg', 'teaching_assistant'),
    ('SA-G2-SET472-TUTORIAL', 'amira.ali@ecu.edu.eg', 'teaching_assistant'),
    ('DMC-G1-SET472-TUTORIAL', 'amira.ali@ecu.edu.eg', 'teaching_assistant'),
    ('DMC-G1-SET473-LECTURE', 'islam.mohammed@ecu.edu.eg', 'instructor')
)
INSERT INTO public.section_instructors (section_id, user_id, tenant_id, role)
SELECT s.id, u.id, t.id, a.assignment_role::public.teaching_role
FROM assignments a
JOIN public.tenants t ON t.slug = 'ecu'
JOIN public.sections s ON s.tenant_id = t.id AND s.code = a.section_code
JOIN public.users u ON u.tenant_id = t.id AND u.email = a.staff_email
ON CONFLICT (section_id, user_id) DO NOTHING;

DO $verify$
DECLARE
  v_count integer;
BEGIN
  WITH assignments(section_code, staff_email, assignment_role) AS (
    VALUES
      ('SA-G1-SET411-LAB', 'mohamed.mohamed@ecu.edu.eg', 'teaching_assistant'),
      ('SA-G2-SET411-LAB', 'mohamed.mohamed@ecu.edu.eg', 'teaching_assistant'),
      ('DMC-G1-SET411-LAB', 'mohamed.mohamed@ecu.edu.eg', 'teaching_assistant'),
      ('SA-G1-SET412-LAB', 'rahma.ali@ecu.edu.eg', 'teaching_assistant'),
      ('SA-G2-SET412-LAB', 'rahma.ali@ecu.edu.eg', 'teaching_assistant'),
      ('DMC-G1-SET412-LAB', 'rahma.ali@ecu.edu.eg', 'teaching_assistant'),
      ('SA-G1-SET472-TUTORIAL', 'amira.ali@ecu.edu.eg', 'teaching_assistant'),
      ('SA-G2-SET472-TUTORIAL', 'amira.ali@ecu.edu.eg', 'teaching_assistant'),
      ('DMC-G1-SET472-TUTORIAL', 'amira.ali@ecu.edu.eg', 'teaching_assistant'),
      ('DMC-G1-SET473-LECTURE', 'islam.mohammed@ecu.edu.eg', 'instructor')
  )
  SELECT count(*) INTO v_count
  FROM assignments a
  JOIN public.tenants t ON t.slug = 'ecu'
  JOIN public.sections s ON s.tenant_id = t.id AND s.code = a.section_code
  JOIN public.users u ON u.tenant_id = t.id AND u.email = a.staff_email
  JOIN public.section_instructors si
    ON si.section_id = s.id AND si.user_id = u.id AND si.tenant_id = t.id
   AND si.role = a.assignment_role::public.teaching_role;

  IF v_count <> 10 THEN
    RAISE EXCEPTION 'Expected 10 verified section instructor assignments; found %', v_count;
  END IF;
END;
$verify$;

COMMIT;
