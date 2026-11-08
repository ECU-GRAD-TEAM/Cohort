-- GradProj's ECU tenant was created by hand, not by a migration, yet later migrations seed data
-- for it by this id and slug. Create it first so a fresh build can follow them.
insert into public.tenants (id, slug, name, country_code, data_region, timezone)
values ('97325228-75cb-4a36-b103-9da28968c660', 'ecu', 'Egyptian Chinese University', 'EG',
        'eu-central-1', 'Africa/Cairo')
on conflict do nothing;
