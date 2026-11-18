CREATE VIEW public.lost_and_found
WITH (security_invoker = true)
AS
SELECT
    li.id AS item_id,
    li.kind::text AS item_kind,
    li.title,
    li.description,
    li.category,
    li.building_id,
    b.code AS building_code,
    b.name AS building_name,
    li.location_text,
    li.occurred_at,
    li.status::text AS status,
    li.created_at
FROM public.lost_items AS li
LEFT JOIN public.buildings AS b
    ON b.id = li.building_id
   AND b.tenant_id = li.tenant_id;

REVOKE ALL ON public.lost_and_found FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON public.lost_and_found FROM authenticated, PUBLIC, anon;
GRANT SELECT ON public.lost_and_found TO authenticated;
