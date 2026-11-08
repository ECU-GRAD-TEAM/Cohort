-- Open sign-up: one university can accept self sign-ups, as students.

alter table public.tenants add column open_signup boolean not null default false;

-- At most one university is open for sign-up at a time.
create unique index tenants_one_open_signup on public.tenants ((true)) where open_signup;

-- Same as the identity version, except that an account with neither a tenant_id nor a user_type
-- in app_metadata joins the university open for sign-up, as a student. Clients can only set
-- user_metadata, so nothing they send can choose the university or the user type.
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := nullif(new.raw_app_meta_data ->> 'tenant_id', '')::uuid;
  v_type public.user_type := nullif(new.raw_app_meta_data ->> 'user_type', '')::public.user_type;
begin
  if v_tenant is null and v_type is null then
    -- Self sign-up: join the university open for sign-up, as a student.
    select t.id into v_tenant from public.tenants t where t.open_signup and t.status = 'active';
    v_type := 'student';
  end if;
  if v_tenant is null or v_type is null then
    return new;
  end if;

  insert into public.users (id, tenant_id, user_type, email, institutional_id)
  values (new.id, v_tenant, v_type, lower(new.email), nullif(new.raw_app_meta_data ->> 'institutional_id', ''));

  update public.person_profiles
  set display_name = coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), display_name)
  where user_id = new.id;

  return new;
end;
$$;

-- Choosing the open university is the platform operator's decision. University administrators can
-- update their tenant row, so a signed-in change to the flag is refused whatever their permissions.
-- The database owner and the service role have no signed-in user, so they can still change it.
create function private.guard_tenant_open_signup()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.open_signup is distinct from old.open_signup and auth.uid() is not null then
    raise exception 'Only the platform operator can open a university for sign-up'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger tenants_guard_open_signup before update of open_signup on public.tenants
  for each row execute function private.guard_tenant_open_signup();
