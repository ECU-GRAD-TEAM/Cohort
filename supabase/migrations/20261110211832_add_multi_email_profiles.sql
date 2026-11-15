-- Support multiple profile email addresses; retain personal_email for compatibility.
CREATE TABLE public.person_profile_emails (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  user_id uuid NOT NULL,
  email_address text NOT NULL,
  label text NOT NULL DEFAULT 'personal',
  is_primary boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT person_profile_emails_label_check CHECK (label = ANY (ARRAY['personal'::text, 'work'::text, 'academic'::text, 'other'::text])),
  CONSTRAINT person_profile_emails_format_check CHECK (email_address = lower(btrim(email_address)) AND email_address ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
  CONSTRAINT person_profile_emails_profile_fk FOREIGN KEY (user_id, tenant_id) REFERENCES public.person_profiles(user_id, tenant_id) ON DELETE CASCADE,
  CONSTRAINT person_profile_emails_user_email_unique UNIQUE (user_id, email_address)
);
CREATE INDEX person_profile_emails_tenant_user_idx ON public.person_profile_emails (tenant_id, user_id);
CREATE INDEX person_profile_emails_user_tenant_fk_idx ON public.person_profile_emails (user_id, tenant_id);
CREATE UNIQUE INDEX person_profile_emails_one_primary_per_user ON public.person_profile_emails (user_id) WHERE is_primary;
ALTER TABLE public.person_profile_emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read own email addresses or manage accounts" ON public.person_profile_emails FOR SELECT TO authenticated USING (tenant_id = (SELECT private.tenant_id()) AND (user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage'::text))));
CREATE POLICY "create own email addresses or manage accounts" ON public.person_profile_emails FOR INSERT TO authenticated WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND (user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage'::text))));
CREATE POLICY "edit own email addresses or manage accounts" ON public.person_profile_emails FOR UPDATE TO authenticated USING (tenant_id = (SELECT private.tenant_id()) AND (user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage'::text)))) WITH CHECK (tenant_id = (SELECT private.tenant_id()) AND (user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage'::text))));
CREATE POLICY "delete own email addresses or manage accounts" ON public.person_profile_emails FOR DELETE TO authenticated USING (tenant_id = (SELECT private.tenant_id()) AND (user_id = (SELECT auth.uid()) OR (SELECT private.has_permission('users.manage'::text))));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.person_profile_emails TO authenticated, service_role;
CREATE TRIGGER person_profile_emails_touch BEFORE UPDATE ON public.person_profile_emails FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
INSERT INTO public.person_profile_emails (tenant_id, user_id, email_address, label, is_primary, is_verified)
SELECT tenant_id, user_id, lower(btrim(personal_email)), 'personal', true, false FROM public.person_profiles
WHERE personal_email IS NOT NULL AND btrim(personal_email) <> ''
ON CONFLICT (user_id, email_address) DO NOTHING;
