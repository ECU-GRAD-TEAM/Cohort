-- Seed the Egyptian Chinese University tenant for local development.
-- Idempotent: existing tenant, faculty, and department records are left unchanged.

INSERT INTO public.tenants (
  name,
  slug,
  country_code,
  data_region
)
VALUES (
  'Egyptian Chinese University',
  'ecu',
  'EG',
  'egypt'
)
ON CONFLICT (slug) DO NOTHING;

-- Seed ECU's Engineering and Technology faculty.
-- Resolve tenant_id by slug so this works with locally generated tenant UUIDs.
INSERT INTO public.faculties (
  tenant_id,
  code,
  name
)
SELECT
  id,
  'ENG',
  'Engineering and Technology'
FROM public.tenants
WHERE slug = 'ecu'
ON CONFLICT (tenant_id, code) DO NOTHING;

-- Seed departments belonging to ECU's Engineering and Technology faculty.
-- Resolve both tenant_id and faculty_id by stable natural keys rather than UUIDs.
INSERT INTO public.departments (
  tenant_id,
  faculty_id,
  code,
  name
)
SELECT
  t.id,
  f.id,
  department.code,
  department.name
FROM public.tenants AS t
JOIN public.faculties AS f
  ON f.tenant_id = t.id
 AND f.code = 'ENG'
CROSS JOIN (
  VALUES
    ('SET', 'Software Engineering & Information Technology'),
    ('MCT', 'Mechatronics Engineering'),
    ('ERG', 'Energy and Renewable Energy Engineering'),
    ('CBE', 'Construction and Building Engineering')
) AS department(code, name)
WHERE t.slug = 'ecu'
ON CONFLICT (tenant_id, code) DO NOTHING;
