drop policy "teachers manage deadline extensions" on public.assessment_deadline_extensions;

create policy "teachers insert deadline extensions"
on public.assessment_deadline_extensions
for insert to authenticated
with check (
  tenant_id = (select private.tenant_id())
  and private.teaches_offering(
    (select a.offering_id from public.assessments a
     where a.id = assessment_deadline_extensions.assessment_id
       and a.tenant_id = assessment_deadline_extensions.tenant_id)
  )
);

create policy "teachers update deadline extensions"
on public.assessment_deadline_extensions
for update to authenticated
using (
  tenant_id = (select private.tenant_id())
  and private.teaches_offering(
    (select a.offering_id from public.assessments a
     where a.id = assessment_deadline_extensions.assessment_id
       and a.tenant_id = assessment_deadline_extensions.tenant_id)
  )
)
with check (
  tenant_id = (select private.tenant_id())
  and private.teaches_offering(
    (select a.offering_id from public.assessments a
     where a.id = assessment_deadline_extensions.assessment_id
       and a.tenant_id = assessment_deadline_extensions.tenant_id)
  )
);

create policy "teachers delete deadline extensions"
on public.assessment_deadline_extensions
for delete to authenticated
using (
  tenant_id = (select private.tenant_id())
  and private.teaches_offering(
    (select a.offering_id from public.assessments a
     where a.id = assessment_deadline_extensions.assessment_id
       and a.tenant_id = assessment_deadline_extensions.tenant_id)
  )
);
