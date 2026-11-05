-- Seed the Egyptian Chinese University tenant for local development.
-- Idempotent: if the tenant slug already exists, this seed leaves it unchanged.

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
