create index person_profile_phones_user_tenant_fk_idx
  on public.person_profile_phones (user_id, tenant_id);
