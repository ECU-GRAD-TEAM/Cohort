-- GradProj's database had this foreign key renamed by hand before the migration drops it by that
-- name. A fresh build names it with PostgreSQL's default, so mirror the rename first.
alter table public.graduation_audits
  rename constraint graduation_audits_policy_id_fkey to graduation_audits_policy_fk;
