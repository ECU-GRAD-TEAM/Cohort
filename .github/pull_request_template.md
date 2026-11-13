## What and why

<!-- What this pull request changes, and why. Link the issue it closes. -->

## Database (GradProj)

- [ ] This pull request changes nothing in the database, **or**:
- [ ] Every migration it needs is in `supabase/migrations`, under the version GradProj records
      (`select version, name from supabase_migrations.schema_migrations order by version desc`).
- [ ] A renamed or removed table or column is also changed in every function, trigger, view and
      policy that uses it (search `pg_get_functiondef` and `pg_policies` for the old name).
- [ ] `npm run db:test:reset` still builds the test database. If a migration only reworks GradProj's
      real records, its name is in `scripts/db/data-only-migrations.txt` or
      `scripts/db/data-check-migrations.txt`.
- [ ] `supabase/README.md` lists any migration that is not applied to GradProj yet.

## Checks

- [ ] `npm run typecheck && npm test` passes.
- [ ] `psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_smoke_test.sql` ends with
      "All smoke tests passed".
