create index grading_policy_component_rules_policy_tenant_fk_idx
  on public.grading_policy_component_rules (grading_policy_id, tenant_id);

drop policy "university leadership manages grading policies" on public.grading_policies;
create policy "university leadership inserts grading policies"
  on public.grading_policies for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));
create policy "university leadership updates grading policies"
  on public.grading_policies for update to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()))
  with check (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));
create policy "university leadership deletes grading policies"
  on public.grading_policies for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));

drop policy "university leadership manages grading policy component rules" on public.grading_policy_component_rules;
create policy "university leadership inserts grading policy component rules"
  on public.grading_policy_component_rules for insert to authenticated
  with check (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));
create policy "university leadership updates grading policy component rules"
  on public.grading_policy_component_rules for update to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()))
  with check (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));
create policy "university leadership deletes grading policy component rules"
  on public.grading_policy_component_rules for delete to authenticated
  using (tenant_id = (select private.tenant_id()) and (select private.can_manage_grading_policies()));