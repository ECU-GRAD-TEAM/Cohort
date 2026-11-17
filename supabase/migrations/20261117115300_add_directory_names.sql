-- Everyone at a university can see each other's display name and title: public.directory_search
-- returns both without a privacy check. directory_search finds people by name, though, and stops
-- at 200, so it cannot reliably name given people. directory_names returns those same two fields
-- for a list of user ids, so a timetable can name its lecturers. It shows nothing else, and only
-- active people at the caller's own university.

CREATE OR REPLACE FUNCTION public.directory_names(p_user_ids uuid[])
 RETURNS TABLE(user_id uuid, display_name text, title text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select u.id, p.display_name, p.title
  from public.users u
  join public.user_profiles p on p.user_id = u.id and p.tenant_id = u.tenant_id
  where u.tenant_id = private.tenant_id()
    and u.status = 'active'
    and u.id = any(p_user_ids)
$function$;

REVOKE ALL ON FUNCTION public.directory_names(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.directory_names(uuid[]) TO authenticated, service_role;
