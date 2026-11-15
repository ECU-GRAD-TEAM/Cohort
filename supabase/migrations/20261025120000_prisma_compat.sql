-- Keys the API's Prisma schema needs. Prisma 7 introspects a one-to-one relation only when the
-- foreign key is unique together with tenant_id, so tables whose foreign-key column is already
-- unique also get a unique key on (that column, tenant_id). Prisma also reads a partial unique
-- index as a full one, so "one active version per prompt template" becomes an exclusion
-- constraint, which it leaves alone and the database enforces just the same.

alter table public.person_profiles add unique (user_id, tenant_id);
alter table public.notification_preferences add unique (user_id, tenant_id);
alter table public.answer_scores add unique (submission_answer_id, tenant_id);
alter table public.question_answer_keys add unique (question_id, tenant_id);
alter table public.channels add unique (offering_id, tenant_id);

drop index public.prompt_template_versions_one_active;
alter table public.prompt_template_versions add constraint prompt_template_versions_one_active
  exclude using btree (template_id with =) where (is_active);
