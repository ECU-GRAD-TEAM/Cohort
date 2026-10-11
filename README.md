# Markets-SaaS-Project

Retail SaaS Platform & Distributed Edge POS, the ECU graduation project. It is a multi-tenant
platform for supermarkets with these parts:

- a WebApp for business owners, regional managers and branch staff;
- a MobileApp for shoppers;
- offline-first POS tills that sync to the cloud;
- an AI assistant over the market's own data and documents.

| Part | Where |
|---|---|
| Database (Supabase Postgres): schema, row level security, tests, backend connection contract | [`supabase/README.md`](supabase/README.md) |
| Database design | [`docs/superpowers/specs/2026-10-11-supabase-database-design.md`](docs/superpowers/specs/2026-10-11-supabase-database-design.md) |
| Database implementation plan | [`docs/superpowers/plans/2026-10-11-supabase-database.md`](docs/superpowers/plans/2026-10-11-supabase-database.md) |
| Backend, WebApp, MobileApp | not in this repository yet |

The apps talk only to our own backend, and the backend is the only code that connects to the
database.

```bash
PGPASSWORD=... scripts/db-test.sh   # needs PostgreSQL 16+ with pgvector and pgTAP; see supabase/README.md
```
