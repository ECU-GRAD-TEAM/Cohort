
drop policy "registrars manage faculty academic pathways" on public.faculty_academic_pathways;
create policy "registrars insert faculty academic pathways"
on public.faculty_academic_pathways for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));
create policy "registrars update faculty academic pathways"
on public.faculty_academic_pathways for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));

drop policy "registrars manage academic progression" on public.student_academic_progressions;
create policy "registrars insert academic progression"
on public.student_academic_progressions for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));
create policy "registrars update academic progression"
on public.student_academic_progressions for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage'));
