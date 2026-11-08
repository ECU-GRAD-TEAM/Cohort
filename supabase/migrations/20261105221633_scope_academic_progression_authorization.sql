
drop policy "members read their faculty academic pathway" on public.faculty_academic_pathways;
create policy "members read their faculty academic pathway"
on public.faculty_academic_pathways for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (private.has_permission('enrollment.manage', 'faculty', faculty_id)
    or exists (
      select 1 from public.student_academic_progressions p
      where p.tenant_id = faculty_academic_pathways.tenant_id
        and p.faculty_id = faculty_academic_pathways.faculty_id
        and p.student_id = (select auth.uid())
    )));

drop policy "registrars insert faculty academic pathways" on public.faculty_academic_pathways;
create policy "registrars insert faculty academic pathways"
on public.faculty_academic_pathways for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage', 'faculty', faculty_id));
drop policy "registrars update faculty academic pathways" on public.faculty_academic_pathways;
create policy "registrars update faculty academic pathways"
on public.faculty_academic_pathways for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage', 'faculty', faculty_id))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission('enrollment.manage', 'faculty', faculty_id));

drop policy "students and authorized staff read academic progression" on public.student_academic_progressions;
create policy "students and authorized staff read academic progression"
on public.student_academic_progressions for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (student_id = (select auth.uid()) or private.can_view_student(student_id)
       or private.has_permission_for_student('enrollment.manage', student_id)));

drop policy "registrars insert academic progression" on public.student_academic_progressions;
create policy "registrars insert academic progression"
on public.student_academic_progressions for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and private.has_permission_for_student('enrollment.manage', student_id));
drop policy "registrars update academic progression" on public.student_academic_progressions;
create policy "registrars update academic progression"
on public.student_academic_progressions for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission_for_student('enrollment.manage', student_id))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission_for_student('enrollment.manage', student_id));

drop policy "students and authorized staff read department assignment history" on public.student_department_assignments;
create policy "students and authorized staff read department assignment history"
on public.student_department_assignments for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (student_id = (select auth.uid()) or private.can_view_student(student_id)
       or private.has_permission_for_department('enrollment.manage', department_id)));

drop policy "registrars manage department assignment decisions" on public.student_department_assignments;
create policy "registrars insert department assignment decisions"
on public.student_department_assignments for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and private.has_permission_for_department('enrollment.manage', department_id));
create policy "registrars manage department assignment decisions"
on public.student_department_assignments for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission_for_department('enrollment.manage', department_id))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission_for_department('enrollment.manage', department_id));

drop policy "students and authorized staff read programme selection history" on public.student_programme_selections;
create policy "students and authorized staff read programme selection history"
on public.student_programme_selections for select to authenticated
using (tenant_id = (select private.tenant_id())
  and (student_id = (select auth.uid()) or private.can_view_student(student_id)
       or private.has_permission_for_program('enrollment.manage', program_id)));

drop policy "registrars manage programme selection decisions" on public.student_programme_selections;
create policy "registrars insert programme selection decisions"
on public.student_programme_selections for insert to authenticated
with check (tenant_id = (select private.tenant_id())
  and private.has_permission_for_program('enrollment.manage', program_id));
create policy "registrars manage programme selection decisions"
on public.student_programme_selections for update to authenticated
using (tenant_id = (select private.tenant_id())
  and private.has_permission_for_program('enrollment.manage', program_id))
with check (tenant_id = (select private.tenant_id())
  and private.has_permission_for_program('enrollment.manage', program_id));
