-- Restore ECU's explicitly designated university-wide IT Officer permissions.
-- This matches the existing grant policy from
-- 20261113142259_grant_ecu_it_officer_every_permission.sql.
INSERT INTO public.role_permissions (role_id, tenant_id, permission_key)
SELECT r.id, r.tenant_id, p.key
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
  AND r.key = 'it_officer'
  AND NOT EXISTS (
    SELECT 1
    FROM public.role_permissions rp
    WHERE rp.role_id = r.id
      AND rp.tenant_id = r.tenant_id
      AND rp.permission_key = p.key
  );
