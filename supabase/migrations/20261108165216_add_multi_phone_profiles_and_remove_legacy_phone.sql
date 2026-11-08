-- Replace the single profile phone field with a dedicated multi-number contact table.
-- person_profiles currently has no rows, so dropping its legacy phone column loses no data.

create table public.person_profile_phones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid not null,
  phone_number text not null,
  label text not null default 'mobile'
    check (label in ('mobile', 'office', 'whatsapp', 'other')),
  is_primary boolean not null default false,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint person_profile_phones_phone_number_format
    check (phone_number ~ '^\+[1-9][0-9]{6,14}$'),
  constraint person_profile_phones_user_phone_unique
    unique (user_id, phone_number),
  constraint person_profile_phones_profile_fk
    foreign key (user_id, tenant_id)
    references public.person_profiles (user_id, tenant_id)
    on delete cascade
);

create index person_profile_phones_tenant_user_idx
  on public.person_profile_phones (tenant_id, user_id);

create unique index person_profile_phones_one_primary_per_user
  on public.person_profile_phones (user_id)
  where is_primary;

create trigger person_profile_phones_touch
  before update on public.person_profile_phones
  for each row execute function private.touch_updated_at();

create function private.guard_person_profile_phone_verification()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null
     and not (select private.has_permission('users.manage')) then
    if tg_op = 'INSERT' then
      new.is_verified := false;
    elsif new.is_verified is distinct from old.is_verified then
      raise exception 'Only account managers can change phone verification status';
    end if;
  end if;
  return new;
end;
$$;

create trigger person_profile_phones_guard_verification
  before insert or update on public.person_profile_phones
  for each row execute function private.guard_person_profile_phone_verification();

alter table public.person_profile_phones enable row level security;

grant select, insert, update, delete on public.person_profile_phones to authenticated, service_role;

create policy "read own phone numbers or manage accounts"
  on public.person_profile_phones
  for select to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      user_id = (select auth.uid())
      or (select private.has_permission('users.manage'))
    )
  );

create policy "create own phone numbers or manage accounts"
  on public.person_profile_phones
  for insert to authenticated
  with check (
    tenant_id = (select private.tenant_id())
    and (
      user_id = (select auth.uid())
      or (select private.has_permission('users.manage'))
    )
  );

create policy "edit own phone numbers or manage accounts"
  on public.person_profile_phones
  for update to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      user_id = (select auth.uid())
      or (select private.has_permission('users.manage'))
    )
  )
  with check (
    tenant_id = (select private.tenant_id())
    and (
      user_id = (select auth.uid())
      or (select private.has_permission('users.manage'))
    )
  );

create policy "delete own phone numbers or manage accounts"
  on public.person_profile_phones
  for delete to authenticated
  using (
    tenant_id = (select private.tenant_id())
    and (
      user_id = (select auth.uid())
      or (select private.has_permission('users.manage'))
    )
  );

-- Keep directory search's existing privacy behavior, returning only the primary number.
create or replace function public.directory_search(p_query text default null, p_limit integer default 50)
returns table (
  user_id uuid,
  user_type public.user_type,
  display_name text,
  title text,
  email text,
  phone text,
  avatar_path text,
  bio text,
  office_location text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    u.id,
    u.user_type,
    p.display_name,
    p.title,
    case when private.field_visible_to_me(u.id, u.user_type, 'email') then u.email end,
    case when private.field_visible_to_me(u.id, u.user_type, 'phone') then primary_phone.phone_number end,
    case when private.field_visible_to_me(u.id, u.user_type, 'avatar') then p.avatar_path end,
    case when private.field_visible_to_me(u.id, u.user_type, 'bio') then p.bio end,
    case when private.field_visible_to_me(u.id, u.user_type, 'office_location') then p.office_location end
  from public.users u
  join public.person_profiles p on p.user_id = u.id
  left join lateral (
    select ppn.phone_number
    from public.person_profile_phones ppn
    where ppn.user_id = u.id
      and ppn.tenant_id = u.tenant_id
      and ppn.is_primary
    order by ppn.created_at desc
    limit 1
  ) primary_phone on true
  where u.tenant_id = private.tenant_id()
    and u.status = 'active'
    and (p_query is null or p.display_name ilike '%' || p_query || '%')
  order by p.display_name
  limit least(greatest(p_limit, 1), 200)
$$;

alter table public.person_profiles drop column phone;
