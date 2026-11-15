-- Rename ECU's Mechatronics Engineering department code from MCT to MCE.
-- Keep the department UUID and all dependent course/relationship references unchanged.
UPDATE public.departments AS d
SET code = 'MCE'
FROM public.tenants AS t
JOIN public.faculties AS f
  ON f.tenant_id = t.id
 AND f.code = 'ENG'
WHERE d.tenant_id = t.id
  AND t.slug = 'ecu'
  AND d.faculty_id = f.id
  AND d.code = 'MCT'
  AND d.name = 'Mechatronics Engineering';
