-- Associate GPA snapshots with the tenant's configured default grading scale.
-- Existing GPA totals are retained; this only fills the scale reference.
-- The append-only guard is temporarily removed and restored in one transaction.

begin;

drop trigger if exists gpa_snapshots_append_only on public.gpa_snapshots;

update public.gpa_snapshots gs
set scale_id = (
  select s.id
  from public.grade_scales s
  where s.tenant_id = gs.tenant_id
    and s.is_default = true
)
where gs.scale_id is null
  and exists (
    select 1
    from public.grade_scales s
    where s.tenant_id = gs.tenant_id
      and s.is_default = true
  );

create trigger gpa_snapshots_append_only
before update or delete on public.gpa_snapshots
for each row execute function private.reject_change();

commit;
