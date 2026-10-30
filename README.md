# Cohort

Cohort is a multi-tenant platform for universities. This repository holds the database, a
Fastify API and a React web app. A student signs in with Supabase Auth and registers for courses.
The API checks the Supabase access token and runs every query as that user, so the database's
row-level security decides what each person can see and change.

| Path | Contents |
| --- | --- |
| `apps/api` | The Fastify API, which reads and writes the database through Prisma |
| `apps/web` | The React web app (Vite) |
| `packages/contracts` | The request and response schemas the API and the web app share |
| `supabase` | Migrations and database tests; see [supabase/README.md](supabase/README.md) |
| `scripts/db` | `reset-test-db.sh`, which builds the test database |
| `docs/superpowers/specs` | Design documents |

## Running Cohort locally

You need Node 22.22.2 or later and npm. The steps run in order; steps 2 and 8 are only for the
tests.

### Before you start: check that GradProj signs tokens with asymmetric keys

The API checks each access token against the project's public key set, so the project has to sign
its tokens with an asymmetric key. Fetch the key set:

```bash
curl -s https://gejismdqvjuygtxibdhs.supabase.co/auth/v1/.well-known/jwks.json
```

The response must list at least one key with `"alg": "ES256"` or `"alg": "RS256"`. If the list is
empty, the project still signs tokens with the legacy shared secret, and every API request gets 401
until you enable asymmetric JWT signing keys in the project's JWT settings in the Supabase
Dashboard.

### 1. Install

```bash
npm install
```

### 2. Build the test database

The API's tests run against a local Postgres 15 or later with pgvector, a superuser named
`postgres` and trust authentication for local connections. The web app's tests need no database.

| Variable | Default |
| --- | --- |
| `TEST_DB_ADMIN_URL` (creates and drops the test database) | `postgresql://postgres@127.0.0.1:5432/postgres` |
| `TEST_DATABASE_URL` (the owner, which applies migrations and seeds data) | `postgresql://postgres@127.0.0.1:5432/cohort_test` |
| `TEST_API_DATABASE_URL` (the connection the API under test uses) | `postgresql://cohort_api@127.0.0.1:5432/cohort_test` |

Export the variables whose defaults do not fit your Postgres, then run:

```bash
npm run db:test:reset
```

This drops and recreates the database named in `TEST_DATABASE_URL` (its name must end in `_test`)
and applies every migration in `supabase/migrations`.

### 3. Apply the pending migrations to GradProj

The Supabase project GradProj (`gejismdqvjuygtxibdhs`) does not have the last three migrations
yet. `db push` applies exactly these:

- `20261022150000_builtin_time_ranges`
- `20261025120000_prisma_compat`
- `20261025120100_api_role`

```bash
npx supabase link --project-ref gejismdqvjuygtxibdhs
npx supabase db push
```

The CLI needs you to be logged in (`npx supabase login`) and asks for the project's database
password. `db push` lists the migrations it is about to apply and waits for your confirmation; this
changes the live project, so read the list first. [supabase/README.md](supabase/README.md) explains
why these three are applied this way.

### 4. Set the API role's password

Migration `api_role` creates the `cohort_api` login role without a password, so the API cannot
connect until you set one. In the Supabase Dashboard, open the SQL Editor for GradProj and run:

```sql
alter role cohort_api with password '<cohort_api password>';
```

Use a long random password and keep it out of git.

### 5. Configure the API

Copy `apps/api/.env.example` to `apps/api/.env` (git-ignored) and replace the placeholders:

```bash
DATABASE_URL=postgresql://cohort_api.gejismdqvjuygtxibdhs:<cohort_api password>@<session pooler host>:5432/postgres
SUPABASE_URL=https://gejismdqvjuygtxibdhs.supabase.co
```

`DATABASE_URL` uses the Session pooler. Its user is `cohort_api.gejismdqvjuygtxibdhs` (the role,
a dot, then the project ref). Copy the host from Dashboard > Connect. If the password contains
`@`, `:`, `/`, `?`, `#` or `%`, percent-encode those characters in the URL.

**The API must never connect as `postgres`.** It connects as `cohort_api`, which holds no
privileges of its own and switches to the `authenticated` role for each request, so row-level
security applies to every query. A superuser connection would skip that protection.

### 6. Configure the web app

Copy `apps/web/.env.example` to `apps/web/.env` (git-ignored) and replace `<publishable key>` with
the project's publishable key (Dashboard > Project Settings > API Keys):

```bash
VITE_SUPABASE_URL=https://gejismdqvjuygtxibdhs.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key>
VITE_API_URL=http://localhost:3000
```

Never put a secret or service-role key in the web app.

### 7. Start the API and the web app

Run each in its own terminal:

```bash
npm run dev -w @cohort/api    # http://127.0.0.1:3000
npm run dev -w @cohort/web    # http://localhost:5173
```

Open http://localhost:5173 and sign in with a Supabase Auth account that belongs to a university.
An account gets its university when the backend creates it with `app_metadata` (see Identity in
[supabase/README.md](supabase/README.md)). An account without one signs in but sees "Your account
is not linked to a university yet."

### 8. Run the tests

```bash
npm test                      # every workspace; the API's tests need the database from step 2
npm test -w @cohort/web       # the web app alone, no database
npm run typecheck
```

The database's own tests are described in [supabase/README.md](supabase/README.md).
