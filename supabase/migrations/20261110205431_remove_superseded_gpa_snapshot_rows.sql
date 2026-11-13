-- Remove the five superseded historical GPA snapshot rows for the ECU
-- transcript import. Three unaffected original term snapshots are retained.
-- The append-only guard is restored in the same transaction.
begin;

drop trigger if exists gpa_snapshots_append_only on public.gpa_snapshots;

delete from public.gpa_snapshots
where id in (
  '41262f9f-745a-49be-9b91-83c56e3f10ca', -- Fall 2022/2023: 64.22 replaced by 64.20
  '0886585f-9d5e-4d8d-8141-c04cc4c5e779', -- Spring 2024/2025: 60.84 replaced by 60.90
  'e5a7dfbe-bffe-447a-b192-4f966b7315bd', -- Fall 2024/2025: 68.04 replaced by 68.10
  '80a74908-a561-4026-b329-7f4ad51c83da', -- Fall 2025/2026: 68.94 replaced by 69.00
  '808ef42c-3883-4ee1-9e30-7e94eda9573a'  -- Spring 2025/2026: 68.04 replaced by 68.10
);

create trigger gpa_snapshots_append_only
before update or delete on public.gpa_snapshots
for each row execute function private.reject_change();

commit;
