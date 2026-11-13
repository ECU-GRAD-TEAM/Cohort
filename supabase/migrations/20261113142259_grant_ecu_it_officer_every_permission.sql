-- 20261109162311 cleared every role's permissions, so no role at ECU (Egyptian Chinese University)
-- grants anything. ECU's it_officer role becomes the university's full administrator again: it
-- gets every permission in public.permissions. Other roles are left for the university to map.
-- Running it twice adds nothing, and on a database without ECU it does nothing.

INSERT INTO public.role_permissions (role_id, tenant_id, permission_key)
SELECT r.id, r.tenant_id, p.key
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.tenant_id = '97325228-75cb-4a36-b103-9da28968c660'
  AND r.key = 'it_officer'
  AND NOT EXISTS (
    SELECT 1 FROM public.role_permissions rp
    WHERE rp.role_id = r.id AND rp.tenant_id = r.tenant_id AND rp.permission_key = p.key
  );
