# Web Foundation and Course Registration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a React web app, a Fastify API and a shared Zod contracts package, delivering
one feature: a student signs in, sees their courses and grades, and registers for or drops
sections on the GradProj database.

**Architecture:**
- npm workspaces: `packages/contracts` holds the Zod schemas for every request and response,
  and both apps import them.
- The API uses Prisma 7, with a schema introspected from the SQL migrations, through
  `@prisma/adapter-pg`. It connects as the `NOINHERIT` role `cohort_api`.
- Each request runs in a transaction that sets the caller's JWT claims and switches to the
  `authenticated` role, so the database's row-level security decides what every query sees.
  Registration goes through the database's own `enroll_in_section` and `drop_section`.
- The web app signs in with Supabase Auth and calls the API with the access token.

**Tech Stack:**
- Node 22.12+, npm workspaces, TypeScript 7.0.2.
- API: Fastify 5.12.7, fastify-type-provider-zod 7.0.0, Zod 4.6.7, Prisma 7.10.1, pg 8.23.1, jose 6.2.13.
- Web: React 19.3.1, Vite 8.3.5, React Router 8.5.0, TanStack Query 5.104.5, supabase-js 2.118.0.
- Tests: Vitest 5.0.5, Testing Library, MSW 3.0.3.

**Spec:** `docs/superpowers/specs/2026-10-25-web-foundation-registration-design.md`. The
database it builds on is described in `supabase/README.md` and the files in
`supabase/migrations/`.

## Global Constraints

- Root `package.json`: `"private": true`, `"type": "module"`, `"engines": { "node": ">=22.12" }`,
  `"workspaces": ["packages/*", "apps/*"]`. Every package is `"type": "module"`.
- Exact version pins (no `^`):
  - **Compiler and runtime:** typescript 7.0.2, @types/node 22.20.5, tsx 4.23.15.
  - **API:** fastify 5.12.7, @fastify/cors 11.3.1, fastify-type-provider-zod 7.0.0, zod 4.6.7,
    prisma 7.10.1, @prisma/client 7.10.1, @prisma/adapter-pg 7.10.1, pg 8.23.1,
    @types/pg 8.23.1, jose 6.2.13.
  - **Web:** react 19.3.1, react-dom 19.3.1, @types/react 19.3.0, @types/react-dom 19.3.0,
    vite 8.3.5, @vitejs/plugin-react 6.1.2, react-router 8.5.0, @tanstack/react-query 5.104.5,
    @supabase/supabase-js 2.118.0.
  - **Tests:** vitest 5.0.5, jsdom 30.1.3, @testing-library/react 16.3.3,
    @testing-library/user-event 14.6.8, @testing-library/jest-dom 7.0.1, msw 3.0.3.
- Do not install `prisma@latest`: its `latest` tag points at 8.0.0-rc.25.
- TypeScript runs with `"noEmit": true`, `"allowImportingTsExtensions": true` and `"strict": true`.
  Relative imports end in `.ts`/`.tsx`. Packages export their `src/*.ts` files directly; there is
  no build step. The API runs under `tsx`.
- No ESLint: typescript-eslint 8.72 supports only TypeScript < 6.1.
- Never run `prisma init`, which writes AI-agent folders into the repo, or `prisma migrate`.
  - Schema changes are new SQL files in `supabase/migrations/` named `YYYYMMDDHHMMSS_name.sql`.
  - `apps/api/prisma/schema.prisma` is regenerated with `npm run db:pull -w @cohort/api`.
- At runtime the API connects only as `cohort_api`. Every database call in a route goes through
  `request.withDb`.
- Error bodies are `{ "error": { "code", "message" } }` with the codes, statuses and messages in
  the spec's error table.
- Token verification:
  - Key set at `${SUPABASE_URL}/auth/v1/.well-known/jwks.json`.
  - Issuer `${SUPABASE_URL}/auth/v1`; audience `authenticated`; algorithms `ES256` and `RS256`.
  - GradProj: `SUPABASE_URL=https://gejismdqvjuygtxibdhs.supabase.co`.
- API on `127.0.0.1:3000`; web dev server on port 5173; CORS origin defaults to
  `http://localhost:5173`.
- Test database (variable, then default):
  - `TEST_DB_ADMIN_URL`: `postgresql://postgres@127.0.0.1:5432/postgres`
  - `TEST_DATABASE_URL` (owner): `postgresql://postgres@127.0.0.1:5432/cohort_test`
  - `TEST_API_DATABASE_URL`: `postgresql://cohort_api@127.0.0.1:5432/cohort_test`
  - Requirements: Postgres 15 or later with pgvector, superuser `postgres`, trust auth for local
    connections.
- **This container:**
  - Postgres 16 with pgvector and pgTAP listens on `127.0.0.1:54329`. Start it with
    `su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/cohort-test -o '-p 54329 -k /var/lib/postgresql -c listen_addresses=127.0.0.1' -l /var/lib/postgresql/cohort-test.log start"`.
  - Export all three variables with port `54329` before running database or API tests.
- UI copy, weekday names (1 = Mon … 7 = Sun) and number formats exactly as in the spec's
  "Web pages and copy" section.
- Work on branch `claude/serene-gates-0fvivv`; one commit per task.

## Review Focus

1. **Signed in, but no university.** A valid account with no `public.users` row gets 403
   `forbidden` from `/me`, and the shell shows the "not linked to a university" copy rather than
   an empty dashboard. Tests: Task 5 (`me.test.ts`), Task 10 (`AppShell.test.tsx`).
2. **Expired or forged token.** Any route returns 401 `unauthorized`. The web client calls
   `onUnauthorized` (wired to sign-out), and the user lands on the sign-in page. Tests: Task 4
   (`auth.test.ts`), Task 5 (`me.test.ts`), Task 9 (`api.test.ts`), Task 10 (`App.test.tsx`).
3. **The database says no.** A closed term, a full section, a duplicate, a missing prerequisite
   or the wrong role gets the exact status and the database's own message, and the page shows it
   in an alert without changing anything. Tests: Task 7 (`enrollments.test.ts`), Task 12
   (`RegistrationPage.test.tsx`).
4. **Ids from another university, or not ids at all.** These get 404 or 400 and never another
   university's data. Tests: Task 6 (`catalogue.test.ts`), Task 7 (`enrollments.test.ts`).
5. **Exact formatting.** Decimal credits (3.5), clock times with minutes (09:05) and weekday 7
   come through and render exactly. Tests: Task 6 (`format.test.ts`, `catalogue.test.ts`),
   Task 12 (`format.test.ts`).

---

### Task 1: Workspace and shared contracts

**Files:**
- Create: `package.json`, `tsconfig.base.json`, `.gitignore`
- Create: `packages/contracts/package.json`, `packages/contracts/tsconfig.json`, `packages/contracts/vitest.config.ts`
- Create: `packages/contracts/src/index.ts`, `src/errors.ts`, `src/me.ts`, `src/catalogue.ts`, `src/enrollments.ts`, `src/grades.ts`
- Test: `packages/contracts/test/contracts.test.ts`

**Interfaces:**
- Produces: package `@cohort/contracts`, with `"exports": { ".": "./src/index.ts" }` and
  dependency `zod`. Each schema is exported as a value, with a type of the same name
  (`export type X = z.infer<typeof X>`):
  - `ApiErrorCode`: `z.enum(['invalid_request','unauthorized','forbidden','not_found','rule_violation','conflict','internal'])`
  - `ApiErrorBody`: `{ error: { code: ApiErrorCode, message: string } }`
  - `UserType`: `z.enum(['student','teaching_staff','administrator','it_staff'])`
  - `MeResponse`: `{ id: uuid, email: string, userType: UserType, displayName: string, tenant: { id: uuid, name: string }, roles: string[] }`
  - `Term`: `{ id: uuid, code, name, startsOn: z.iso.date(), endsOn: z.iso.date(), registrationOpensAt: z.iso.datetime().nullable(), registrationClosesAt: …nullable(), addDropEndsAt: …nullable() }`
  - `TermsResponse`: `{ terms: Term[] }`
  - `TermParams`: `{ termId: z.uuid() }`
  - `Meeting`: `{ weekday: int 1–7, startsAt: /^\d{2}:\d{2}$/, endsAt: /^\d{2}:\d{2}$/, room: string | null }`
  - `CatalogueSection`: `{ id: uuid, code: string, kind: z.enum(['lecture','lab','tutorial']), capacity: int | null, course: { id: uuid, code, title, creditHours: number }, meetings: Meeting[] }`
  - `SectionsResponse`: `{ sections: CatalogueSection[] }`
  - `EnrollmentStatus`: `z.enum(['enrolled','waitlisted','dropped','withdrawn','completed','failed','incomplete'])`
  - `Enrollment`: `{ id: uuid, sectionId: uuid, sectionCode: string, termId: uuid, status: EnrollmentStatus, waitlistPosition: int | null, course: { code, title, creditHours: number } }`
  - `EnrollmentsResponse`: `{ enrollments: Enrollment[] }`
  - `EnrollRequest`: `{ sectionId: z.uuid() }`
  - `SectionParams`: `{ sectionId: z.uuid() }`
  - `EnrollmentChange`: `{ enrollment: { id: uuid, sectionId: uuid, status: EnrollmentStatus, waitlistPosition: int | null } }`
  - `Grade`: `{ id: uuid, offeringId: uuid, course: { code, title }, item: string | null, score: number, maxScore: number, publishedAt: z.iso.datetime() }`
  - `GradesResponse`: `{ grades: Grade[] }`
- Root scripts:
  - `typecheck`: `npm run typecheck --workspaces --if-present`
  - `test`: `npm run test --workspaces --if-present`
  - `db:test:reset`: `bash scripts/db/reset-test-db.sh`
- Root devDependencies: typescript, @types/node, vitest.
- `tsconfig.base.json` compiler options: target `es2023`, lib `["es2023"]`, module and
  moduleResolution `nodenext`, `strict`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax`,
  `allowImportingTsExtensions`, `noEmit`, `skipLibCheck`, types `["node"]`.
- Package scripts: `typecheck` (`tsc -p tsconfig.json`) and `test` (`vitest run`).
- `.gitignore`: `node_modules/`, `.env`, `apps/api/src/generated/`, `*.log`.

- [ ] **Step 1: Write the failing test** `packages/contracts/test/contracts.test.ts`

```ts
import { describe, expect, it } from "vitest";
import { ApiErrorBody, CatalogueSection, Meeting, Term } from "../src/index.ts";

const uuid = "0a000000-0000-4000-8000-00000000000a";

describe("contracts", () => {
  it("accepts clock times with minutes and rejects unpadded ones", () => {
    expect(Meeting.parse({ weekday: 7, startsAt: "09:05", endsAt: "10:30", room: "101" }).startsAt).toBe("09:05");
    expect(Meeting.safeParse({ weekday: 1, startsAt: "9:5", endsAt: "10:30", room: null }).success).toBe(false);
    expect(Meeting.safeParse({ weekday: 8, startsAt: "09:00", endsAt: "10:30", room: null }).success).toBe(false);
  });
  it("keeps fractional credit hours", () => {
    const s = CatalogueSection.parse({ id: uuid, code: "L1", kind: "lecture", capacity: null,
      course: { id: uuid, code: "CS101", title: "Programming I", creditHours: 3.5 }, meetings: [] });
    expect(s.course.creditHours).toBe(3.5);
  });
  it("allows terms without a registration window", () => {
    expect(Term.safeParse({ id: uuid, code: "F26", name: "Fall 2026", startsOn: "2026-09-01", endsOn: "2026-12-20",
      registrationOpensAt: null, registrationClosesAt: null, addDropEndsAt: null }).success).toBe(true);
  });
  it("rejects unknown error codes", () => {
    expect(ApiErrorBody.safeParse({ error: { code: "teapot", message: "x" } }).success).toBe(false);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm install && npm test -w @cohort/contracts`
Expected: FAIL. Vitest cannot resolve `../src/index.ts`.

- [ ] **Step 3: Implement the schemas listed under Interfaces**, using Zod 4 helpers (`z.uuid()`, `z.iso.date()`, `z.iso.datetime()`)

- [ ] **Step 4: Run the tests and the type-check**

Run: `npm test -w @cohort/contracts && npm run typecheck`
Expected: 4 tests pass; `tsc` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json tsconfig.base.json .gitignore packages/contracts
git commit -m "feat: add npm workspace and shared Zod contracts"
```

---

### Task 2: Test database and database prerequisites

**Files:**
- Create: `scripts/db/supabase-stub.sql`, `scripts/db/reset-test-db.sh`
- Create: `supabase/migrations/20261025120000_prisma_compat.sql`, `supabase/migrations/20261025120100_api_role.sql`
- Modify: `supabase/tests/rls_smoke_test.sql` (add a check after the "AI grading suggestions and risk predictions" block)
- Modify: `supabase/README.md` (add both migrations to the Status and Migrations tables, both pending in GradProj)

**Interfaces:**
- Produces:
  - `npm run db:test:reset` rebuilds `cohort_test` from the stub and every migration.
  - Role `cohort_api` (`LOGIN NOINHERIT`, member of `authenticated`).
  - Unique keys Prisma needs: `(user_id, tenant_id)` on `person_profiles` and
    `notification_preferences`; `(submission_answer_id, tenant_id)` on `answer_scores`;
    `(question_id, tenant_id)` on `question_answer_keys`; `(offering_id, tenant_id)` on
    `channels`.
  - Exclusion constraint `prompt_template_versions_one_active`.

- [ ] **Step 1: Write the failing check.** In `supabase/tests/rls_smoke_test.sql`, add as the owner:

```sql
insert into public.prompt_templates (id, tenant_id, key) values
  ('50000000-0000-4000-8000-000000000021', '0a000000-0000-4000-8000-00000000000a', 'smoke.prompt');
insert into public.prompt_template_versions (tenant_id, template_id, version, body, is_active) values
  ('0a000000-0000-4000-8000-00000000000a', '50000000-0000-4000-8000-000000000021', 1, 'v1', true),
  ('0a000000-0000-4000-8000-00000000000a', '50000000-0000-4000-8000-000000000021', 2, 'v2', false);
do $$
declare
  failed boolean := false;
begin
  begin
    update public.prompt_template_versions set is_active = true where version = 2
      and template_id = '50000000-0000-4000-8000-000000000021';
  exception when exclusion_violation then
    failed := true;
  end;
  assert failed, 'only one version of a prompt template can be active';
end;
$$;
```

- [ ] **Step 2: Write `scripts/db/supabase-stub.sql` and `scripts/db/reset-test-db.sh`**

The stub creates, idempotently:
- Roles `anon`, `authenticated` (both `nologin noinherit`), `service_role`
  (`nologin noinherit bypassrls`) and `supabase_auth_admin` (`nologin`), plus
  `grant anon, authenticated, service_role to postgres`.
- Schemas `extensions` and `auth`, with usage granted to anon, authenticated and service_role.
- `auth.users (id uuid primary key default gen_random_uuid(), email text, raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}', created_at timestamptz default now())`.
- `auth.uid()` and `auth.jwt()`, defined exactly as Supabase defines them:

```sql
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
```

- `grant usage on schema public` to the three API roles.
- `alter default privileges for role postgres in schema public grant all on tables, sequences and functions to anon, authenticated, service_role`, mirroring Supabase.

The reset script does the following; `TEST_DATABASE_URL` names the target database:
- `set -euo pipefail`.
- On `TEST_DB_ADMIN_URL`, run `drop database if exists <name> with (force)` and `create database <name>`.
- Apply the stub.
- Apply every `supabase/migrations/*.sql` in name order with `psql -v ON_ERROR_STOP=1 -1 -f`.
- Print `cohort_test ready`.

- [ ] **Step 3: Run the smoke test to verify the new check fails**

Run: `npm run db:test:reset && pg_prove -d "$TEST_DATABASE_URL" supabase/tests/rls_smoke_test.sql`
Expected: FAIL with `duplicate key value violates unique constraint "prompt_template_versions_one_active"`.
The partial unique index raises `unique_violation`, which the check does not catch.

- [ ] **Step 4: Write the two migrations**

`20261025120000_prisma_compat.sql`. The comment explains that Prisma 7 needs
`(fk, tenant_id)` to be unique on tables whose foreign-key column is unique, and that it reads
partial unique indexes as full ones:

```sql
alter table public.person_profiles add unique (user_id, tenant_id);
alter table public.notification_preferences add unique (user_id, tenant_id);
alter table public.answer_scores add unique (submission_answer_id, tenant_id);
alter table public.question_answer_keys add unique (question_id, tenant_id);
alter table public.channels add unique (offering_id, tenant_id);
drop index public.prompt_template_versions_one_active;
alter table public.prompt_template_versions add constraint prompt_template_versions_one_active
  exclude using btree (template_id with =) where (is_active);
```

`20261025120100_api_role.sql`. The comment explains `NOINHERIT` (no privileges of its own; each
request switches to `authenticated`; fails closed) and that the password is set per environment
with `alter role cohort_api with password '…'`:

```sql
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'cohort_api') then
    create role cohort_api login noinherit;
  end if;
end;
$$;
grant authenticated to cohort_api;
```

- [ ] **Step 5: Verify**

Run: `npm run db:test:reset && pg_prove -d "$TEST_DATABASE_URL" supabase/tests/rls_smoke_test.sql && psql "$TEST_API_DATABASE_URL" -c 'select count(*) from public.courses'`
Expected:
- `cohort_test ready`.
- `Result: PASS`.
- psql fails with `ERROR:  permission denied for table courses`.

- [ ] **Step 6: Commit**

```bash
git add scripts/db supabase/migrations/20261025120000_prisma_compat.sql supabase/migrations/20261025120100_api_role.sql supabase/tests/rls_smoke_test.sql supabase/README.md
git commit -m "feat: add test database script, API login role and Prisma compatibility keys"
```

---

### Task 3: Prisma schema and per-request database context

**Files:**
- Create: `apps/api/package.json`, `apps/api/tsconfig.json`, `apps/api/vitest.config.ts`, `apps/api/prisma.config.ts`, `apps/api/prisma/schema.prisma`
- Create: `apps/api/src/db.ts`, `apps/api/test/support/db.ts`
- Test: `apps/api/test/db.test.ts`

**Interfaces:**
- Consumes: Task 2's test database and `cohort_api` role.
- Produces:
  - `createPrisma(databaseUrl: string): PrismaClient`, using `new PrismaPg({ connectionString })`.
  - `type Tx = Prisma.TransactionClient`.
  - `withUserContext<T>(prisma: PrismaClient, claims: AuthClaims, fn: (tx: Tx) => Promise<T>): Promise<T>`.
    It runs `prisma.$transaction` with ``select set_config('request.jwt.claims', ${JSON.stringify(claims)}, true)``,
    then `set local role authenticated`, then `fn`.
  - `type AuthClaims = { sub: string; role: "authenticated"; email?: string; [claim: string]: unknown }`.
    Defined in `src/auth.ts` in this task, as a type only; Task 4 adds the verifier.
  - Generated client: `src/generated/prisma/client.ts` (import `PrismaClient` and `Prisma`
    from it). Model names are table names, except `users` (the app's) and `auth_users`
    (Supabase's). Relation field names are as generated in `prisma/schema.prisma`.
  - Test support (`test/support/db.ts`):
    - `ownerQuery<T>(sql: string, params?: unknown[]): Promise<T[]>` (a `pg` Pool on `TEST_DATABASE_URL`)
    - `closeOwnerPool(): Promise<void>`
    - `apiDatabaseUrl: string` (`TEST_API_DATABASE_URL`)
    - `createAuthOnlyUser(): Promise<string>` (an `auth.users` row with no app metadata, so no `public.users` row)
    - `seedUniversity(options?: { cs101Capacity?: number; cs101Waitlist?: number; registrationOpen?: boolean }): Promise<University>`, where:

```ts
type University = {
  tenantId: string; tenantName: string; termId: string;
  users: { student: string; classmate: string; latecomer: string; teacher: string; admin: string };
  courses: { cs101: string; cs201: string; ma101: string };
  offerings: { cs101: string; cs201: string; ma101: string };
  sections: { cs101: string; cs201: string; ma101: string };
};
```

`seedUniversity` inserts as the owner, with random UUIDs. Let `<k>` be the first eight hex
characters of a random UUID.
- **Tenant:** slug `t-<k>`, name `University <k>`, data region `eu-west-1`.
- **Users:** created through `auth.users` with `app_metadata { tenant_id, user_type }`, emails
  `<role>-<k>@cohort.test`, and `user_metadata.full_name`:

| Key | Display name | User type |
| --- | --- | --- |
| student | Sara Student | student |
| classmate | Samir Student | student |
| latecomer | Laila Late | student |
| teacher | Tariq Teacher | teaching_staff |
| admin | Ada Admin | administrator |

- **Term:** code `T-<k>`, name `Fall 2026`, from current_date − 7 to + 90 days. Registration
  opens now − 1 day and closes now + 7 days. With `registrationOpen: false`, it opens + 1 day
  and closes + 8 days.
- **Courses** (one department):
  - `CS101` "Programming I", 3.5 credits.
  - `CS201` "Programming II", 3 credits; prerequisite CS101.
  - `MA101` "Calculus I", 3 credits.
- **Offerings:** CS101 and CS201 are `published`; MA101 is `draft`.
- **Sections:** code `L1` for each course.
  - CS101: capacity `cs101Capacity ?? 30`, waiting list `cs101Waitlist ?? 0`.
  - Others: capacity 30.
- **Teaching and timetable:**
  - The teacher teaches CS101 L1.
  - CS101 L1 meets weekday 7, 09:05–10:30, in room `101` of building `B1`.

- [ ] **Step 1: Write the package files**
  - **`package.json`:** name `@cohort/api`. Dependencies: `@cohort/contracts` (`*`), plus the
    API pins from Global Constraints. devDependencies: `prisma`, `tsx`, `@types/pg`.
    Scripts:
    - `pretest`: `prisma generate` (no `postinstall`: the schema has no models until Step 2)
    - `db:pull`: `prisma db pull`
    - `db:generate`: `prisma generate`
    - `typecheck`: `prisma generate && tsc -p tsconfig.json`
    - `test`: `vitest run`
    - `dev`: `tsx watch --env-file=.env src/server.ts`
  - **`prisma.config.ts`:**
    `defineConfig({ schema: "prisma/schema.prisma", datasource: { url: process.env.TEST_DATABASE_URL ?? "postgresql://postgres@127.0.0.1:5432/cohort_test" } })`.
  - **`prisma/schema.prisma`:** generator
    `client { provider = "prisma-client", output = "../src/generated/prisma" }`, datasource
    `db { provider = "postgresql", schemas = ["public", "auth"] }`.
  - **`vitest.config.ts`:** `include: ["test/**/*.test.ts"]`, `testTimeout: 20000`,
    `hookTimeout: 30000`.

- [ ] **Step 2: Introspect, and rename the two user models once**

Run: `npm install && npm run db:pull -w @cohort/api`
Expected: `Introspected 101 models`, plus warnings about check and exclusion constraints, which
Prisma does not model.

Then run this script once with `node rename.mjs apps/api/prisma/schema.prisma`, from a scratch
location outside the repo:

```js
import { readFileSync, writeFileSync } from "node:fs";
const path = process.argv[2];
let s = readFileSync(path, "utf8");
s = s.replace(/^model users \{/m, "model auth_users {");                    // Supabase's auth.users
s = s.replace(/\bpublic_users\b/g, "__APP_USERS__");
s = s.replace(/^([ \t]+\w+[ \t]+)users(\??[ \t\n])/gm, "$1auth_users$2");   // fields typed as auth.users
s = s.replaceAll("__APP_USERS__", "users");
writeFileSync(path, s);
```

Run: `(cd apps/api && npx prisma validate) && cp apps/api/prisma/schema.prisma /tmp/s.prisma && npm run db:pull -w @cohort/api && diff -w /tmp/s.prisma apps/api/prisma/schema.prisma && echo stable`
Expected: `The schema at prisma/schema.prisma is valid`, then `stable`. A re-pull keeps the names.

- [ ] **Step 3: Write the failing test** `apps/api/test/db.test.ts`

```ts
it("refuses a query made outside a user context", async () => {
  await expect(prisma.courses.findMany()).rejects.toMatchObject({
    meta: { driverAdapterError: { cause: { originalCode: "42501" } } },
  });
});
it("shows a student only their own university's courses", async () => {
  const ids = await withUserContext(prisma, claimsFor(a.users.student), (tx) =>
    tx.courses.findMany({ select: { id: true } }));
  expect(ids.map((c) => c.id).sort()).toEqual([a.courses.cs101, a.courses.cs201, a.courses.ma101].sort());
});
it("runs database functions as the student", async () => {
  const rows = await withUserContext(prisma, claimsFor(a.users.student), (tx) =>
    tx.$queryRaw<{ status: string }[]>`select status::text from public.enroll_in_section(${a.sections.cs101}::uuid)`);
  expect(rows).toEqual([{ status: "enrolled" }]);
});
```

Setup:
- `beforeAll` seeds two universities `a` and `b`, and creates `prisma = createPrisma(apiDatabaseUrl)`.
- `claimsFor(sub)` returns `{ sub, role: "authenticated" }`.
- `afterAll` disconnects Prisma and closes the owner pool.

- [ ] **Step 4: Run the test to verify it fails**

Run: `npm test -w @cohort/api -- db.test.ts`
Expected: FAIL. `../src/db.ts` does not exist.

- [ ] **Step 5: Implement `src/db.ts` and the `AuthClaims` type in `src/auth.ts`**

- [ ] **Step 6: Run the tests and the type-check**

Run: `npm test -w @cohort/api -- db.test.ts && npm run typecheck -w @cohort/api`
Expected: 3 tests pass; no type errors.

- [ ] **Step 7: Commit**

```bash
git add apps/api package-lock.json
git commit -m "feat: add Prisma schema and per-request database user context"
```

---

### Task 4: Token verification and configuration

**Files:**
- Modify: `apps/api/src/auth.ts`
- Create: `apps/api/src/config.ts`, `apps/api/test/support/tokens.ts`
- Test: `apps/api/test/auth.test.ts`, `apps/api/test/config.test.ts`

**Interfaces:**
- Produces:
  - `class UnauthorizedError extends Error`
  - `type TokenVerifier = (token: string) => Promise<AuthClaims>`
  - `createTokenVerifier(options: { getKey: JWTVerifyGetKey; issuer: string; audience: string }): TokenVerifier`.
    Uses `jwtVerify` with algorithms `["ES256", "RS256"]`. It requires `sub` to be a UUID and
    `role === "authenticated"`, and wraps any failure in `UnauthorizedError`.
  - `loadConfig(env: Record<string, string | undefined>): Config`, where
    `Config = { databaseUrl: string; supabaseUrl: string; jwksUrl: URL; issuer: string; audience: "authenticated"; corsOrigin: string; port: number; host: string }`.
    - Reads `DATABASE_URL` (required), `SUPABASE_URL` (required, URL), `CORS_ORIGIN`
      (default `http://localhost:5173`), `PORT` (default 3000) and `HOST` (default `127.0.0.1`).
    - Validates with Zod and throws if a required value is missing.
  - Test support (`test/support/tokens.ts`):
    - `TEST_ISSUER = "https://test.supabase.co/auth/v1"`
    - `createTestAuth(): Promise<{ verifyToken: TokenVerifier; tokenFor(sub: string, overrides?: JWTPayload): Promise<string>; foreignTokenFor(sub: string): Promise<string> }>`
    - An ES256 key pair with `createLocalJWKSet`. Tokens carry `role: "authenticated"`,
      `aud: "authenticated"` and `exp` one hour ahead. `foreignTokenFor` signs with a second,
      unknown key.

- [ ] **Step 1: Write the failing tests**

`auth.test.ts`. Each failing case expects `rejects.toBeInstanceOf(UnauthorizedError)`:

```ts
it("returns the claims of a valid token", async () => {
  await expect(auth.verifyToken(await auth.tokenFor(sub))).resolves.toMatchObject({ sub, role: "authenticated" });
});
it.each([
  ["expired", { exp: Math.floor(Date.now() / 1000) - 60 }],
  ["wrong audience", { aud: "anon" }],
  ["wrong issuer", { iss: "https://evil.example/auth/v1" }],
  ["anonymous role", { role: "anon" }],
  ["non-uuid subject", { sub: "not-a-uuid" }],
])("rejects a token with %s", async (_label, overrides) => {
  await expect(auth.verifyToken(await auth.tokenFor(sub, overrides))).rejects.toBeInstanceOf(UnauthorizedError);
});
it("rejects a token signed by an unknown key", async () => {
  await expect(auth.verifyToken(await auth.foreignTokenFor(sub))).rejects.toBeInstanceOf(UnauthorizedError);
});
it("rejects garbage", async () => {
  await expect(auth.verifyToken("abc")).rejects.toBeInstanceOf(UnauthorizedError);
});
```

`config.test.ts`:

```ts
it("derives the Supabase key set and issuer", () => {
  const c = loadConfig({ DATABASE_URL: "postgresql://cohort_api@db/x", SUPABASE_URL: "https://gejismdqvjuygtxibdhs.supabase.co" });
  expect(c.jwksUrl.href).toBe("https://gejismdqvjuygtxibdhs.supabase.co/auth/v1/.well-known/jwks.json");
  expect(c.issuer).toBe("https://gejismdqvjuygtxibdhs.supabase.co/auth/v1");
  expect([c.port, c.host, c.corsOrigin]).toEqual([3000, "127.0.0.1", "http://localhost:5173"]);
});
it("refuses to start without a database URL", () => {
  expect(() => loadConfig({ SUPABASE_URL: "https://x.supabase.co" })).toThrow();
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -w @cohort/api -- auth.test.ts config.test.ts`
Expected: FAIL. `createTokenVerifier` and `loadConfig` are not exported.

- [ ] **Step 3: Implement `createTokenVerifier`, `UnauthorizedError`, `loadConfig` and `test/support/tokens.ts`**

- [ ] **Step 4: Run the tests**

Run: `npm test -w @cohort/api -- auth.test.ts config.test.ts && npm run typecheck -w @cohort/api`
Expected: 10 tests pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api
git commit -m "feat: verify Supabase access tokens and load API configuration"
```

---

### Task 5: Fastify app, error handling, `/health` and `/me`

**Files:**
- Create: `apps/api/src/errors.ts`, `apps/api/src/app.ts`, `apps/api/src/routes/me.ts`, `apps/api/src/server.ts`, `apps/api/.env.example`, `apps/api/test/support/app.ts`
- Test: `apps/api/test/errors.test.ts`, `apps/api/test/me.test.ts`

**Interfaces:**
- Consumes: `createPrisma`, `withUserContext`, `Tx` (Task 3); `TokenVerifier`, `UnauthorizedError`, `loadConfig` (Task 4); `ApiErrorCode` and `MeResponse` (Task 1).
- Produces:
  - `class ApiError extends Error { constructor(readonly statusCode: number, readonly code: ApiErrorCode, message: string) }`
  - `databaseErrorToApiError(error: unknown): ApiError | null`. Reads
    `error.meta.driverAdapterError.cause.originalCode` and `originalMessage` from a
    `Prisma.PrismaClientKnownRequestError`, and maps them with the spec's error table.
  - `buildApp(deps: { prisma: PrismaClient; verifyToken: TokenVerifier; corsOrigin: string; logger?: boolean }): Promise<FastifyInstance>`. It:
    - Installs `validatorCompiler`/`serializerCompiler`.
    - Registers `@fastify/cors` (the origin, methods GET, POST and DELETE).
    - Adds a not-found handler (`not_found`, `Not found.`).
    - Adds an error handler, applied in this order:
      1. Zod validation errors (`hasZodFastifySchemaValidationErrors`) → 400 `invalid_request`.
      2. `ApiError` → its own status, code and message.
      3. `databaseErrorToApiError` → the mapped error.
      4. Other Fastify 4xx errors → that status, `invalid_request`.
      5. Anything else → logged; 500 `internal`.
    - Serves `GET /health` → `{ status: "ok" }`.
    - Registers an authenticated scope. Its `onRequest` hook parses `Bearer <token>`, sets
      `request.user`, and replies 401 `unauthorized`, `Sign in to continue.` on any failure.
      Task 5 registers `meRoutes` in it; Tasks 6–8 add their own route plugins to the same scope.
  - Fastify module augmentation:
    `FastifyRequest { user: AuthClaims; withDb<T>(fn: (tx: Tx) => Promise<T>): Promise<T> }`.
    `withDb` calls `withUserContext(deps.prisma, request.user, fn)`.
  - `meRoutes: FastifyPluginAsync` serves `GET /me`. It reads the caller's `users` row with its
    tenant, profile and role keys. With no row, it throws
    `ApiError(403, "forbidden", "Your account is not linked to a university yet.")`.
  - `src/server.ts` wires `loadConfig(process.env)`, `createPrisma`, and
    `createTokenVerifier({ getKey: createRemoteJWKSet(config.jwksUrl), … })`, then calls
    `listen({ port, host })` and disconnects Prisma on close.
  - `.env.example` lists `DATABASE_URL`, `SUPABASE_URL`, `CORS_ORIGIN`, `PORT` and `HOST`.
  - Test support (`test/support/app.ts`):
    `createTestApp(): Promise<{ app: FastifyInstance; tokenFor(sub: string): Promise<string>; foreignTokenFor(sub: string): Promise<string>; close(): Promise<void> }>`.
    Builds the app on `apiDatabaseUrl` with `createTestAuth().verifyToken`.

- [ ] **Step 1: Write the failing tests**

`errors.test.ts`. A helper `dbError(code, message)` builds
`new Prisma.PrismaClientKnownRequestError("Raw query failed", { code: "P2010", clientVersion: "7.10.1", meta: { driverAdapterError: { cause: { originalCode: code, originalMessage: message } } } })`:

```ts
it.each([
  ["42501", "permission denied for table x", 403, "forbidden", "You are not allowed to do that."],
  ["P0002", "Section not found", 404, "not_found", "Section not found"],
  ["23514", "Prerequisites for CS201 are not met", 422, "rule_violation", "Prerequisites for CS201 are not met"],
  ["23503", "insert violates foreign key constraint", 422, "rule_violation", "That refers to something that does not exist."],
  ["23505", "Already registered in a lecture section of this course", 409, "conflict", "Already registered in a lecture section of this course"],
  ["23P01", "conflicting key value violates exclusion constraint", 409, "conflict", "conflicting key value violates exclusion constraint"],
  ["XX000", "boom", 500, "internal", "Something went wrong. Please try again."],
])("maps SQLSTATE %s", (code, message, status, apiCode, apiMessage) => {
  expect(databaseErrorToApiError(dbError(code, message))).toMatchObject({ statusCode: status, code: apiCode, message: apiMessage });
});
it("ignores errors that are not database errors", () => {
  expect(databaseErrorToApiError(new Error("x"))).toBeNull();
});
```

`me.test.ts`. Seeds one university; `get(url, token?)` wraps `app.inject`:

```ts
it("is healthy without a token", async () => {
  expect((await get("/health")).json()).toEqual({ status: "ok" });
});
it("asks for a token", async () => {
  const r = await get("/me");
  expect(r.statusCode).toBe(401);
  expect(r.json()).toEqual({ error: { code: "unauthorized", message: "Sign in to continue." } });
});
it("rejects a token signed by another key", async () => {
  expect((await get("/me", await t.foreignTokenFor(u.users.student))).statusCode).toBe(401);
});
it("describes the signed-in student", async () => {
  const r = await get("/me", await t.tokenFor(u.users.student));
  expect(r.statusCode).toBe(200);
  expect(r.json()).toMatchObject({ id: u.users.student, userType: "student", displayName: "Sara Student",
    tenant: { id: u.tenantId, name: u.tenantName }, roles: ["student"] });
});
it("explains an account that is not linked to a university", async () => {
  const r = await get("/me", await t.tokenFor(await createAuthOnlyUser()));
  expect(r.statusCode).toBe(403);
  expect(r.json()).toEqual({ error: { code: "forbidden", message: "Your account is not linked to a university yet." } });
});
it("allows the web origin", async () => {
  const r = await t.app.inject({ method: "OPTIONS", url: "/me", headers: { origin: "http://localhost:5173", "access-control-request-method": "GET" } });
  expect(r.headers["access-control-allow-origin"]).toBe("http://localhost:5173");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -w @cohort/api -- errors.test.ts me.test.ts`
Expected: FAIL. `../src/errors.ts` and `test/support/app.ts` imports cannot be resolved.

- [ ] **Step 3: Implement `errors.ts`, `app.ts`, `routes/me.ts`, `server.ts`, `.env.example` and `test/support/app.ts`**

- [ ] **Step 4: Run all API tests and the type-check**

Run: `npm test -w @cohort/api && npm run typecheck -w @cohort/api`
Expected: all 27 API tests so far pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api
git commit -m "feat: add Fastify app with auth scope, error mapping and /me"
```

---

### Task 6: Catalogue routes

**Files:**
- Create: `apps/api/src/format.ts`, `apps/api/src/routes/catalogue.ts`
- Modify: `apps/api/src/app.ts` (register `catalogueRoutes` in the authenticated scope)
- Test: `apps/api/test/format.test.ts`, `apps/api/test/catalogue.test.ts`

**Interfaces:**
- Consumes: `request.withDb`, `ApiError` (Task 5); `TermsResponse`, `TermParams`, `SectionsResponse` (Task 1).
- Produces:
  - `toIsoDate(d: Date): string` (`YYYY-MM-DD` from the UTC date).
  - `toClockTime(d: Date): string` (`HH:MM` from the UTC time; Prisma returns `time` columns as
    1970-01-01 UTC).
  - `toNumber(n: Prisma.Decimal | number): number`.
  - `catalogueRoutes: FastifyPluginAsync`, serving:
    - `GET /terms`: newest `starts_on` first.
    - `GET /terms/:termId/sections`: sections whose offering is in that term and `published`,
      ordered by course code then section code. Meetings are ordered by weekday then start
      time, and `room` is the room code. An unknown term (including another university's)
      gets `ApiError(404, "not_found", "Term not found.")`.

- [ ] **Step 1: Write the failing tests**

`format.test.ts`:

```ts
expect(toClockTime(new Date("1970-01-01T09:05:00Z"))).toBe("09:05");
expect(toIsoDate(new Date("2026-10-25T00:00:00Z"))).toBe("2026-10-25");
expect(toNumber(new Prisma.Decimal("3.5"))).toBe(3.5);
```

`catalogue.test.ts`. Seeds universities `u` and `other`:

```ts
it("lists only the caller's terms, newest first", async () => {
  await ownerQuery(`insert into public.terms (tenant_id, code, name, starts_on, ends_on) values ($1, 'OLD', 'Spring 2026', '2026-01-10', '2026-05-30')`, [u.tenantId]);
  const r = await get("/terms", student);
  expect(r.json().terms.map((t: { name: string }) => t.name)).toEqual(["Fall 2026", "Spring 2026"]);
});
it("lists published sections with exact credits and meeting times", async () => {
  const r = await get(`/terms/${u.termId}/sections`, student);
  expect(r.statusCode).toBe(200);
  expect(r.json().sections.map((s: { course: { code: string } }) => s.course.code)).toEqual(["CS101", "CS201"]); // MA101 is a draft
  expect(r.json().sections[0]).toMatchObject({ id: u.sections.cs101, code: "L1", kind: "lecture",
    course: { code: "CS101", title: "Programming I", creditHours: 3.5 },
    meetings: [{ weekday: 7, startsAt: "09:05", endsAt: "10:30", room: "101" }] });
});
it("does not reveal another university's term", async () => {
  const r = await get(`/terms/${other.termId}/sections`, student);
  expect(r.statusCode).toBe(404);
  expect(r.json().error.code).toBe("not_found");
});
it("rejects a malformed term id", async () => {
  expect((await get("/terms/abc/sections", student)).json().error.code).toBe("invalid_request");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -w @cohort/api -- format.test.ts catalogue.test.ts`
Expected: FAIL. `../src/format.ts` is missing, and `/terms` returns 404 `Not found.`.

- [ ] **Step 3: Implement `format.ts`, `routes/catalogue.ts` and register the routes**

- [ ] **Step 4: Run the tests**

Run: `npm test -w @cohort/api && npm run typecheck -w @cohort/api`
Expected: all API tests pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api
git commit -m "feat: add term and section catalogue routes"
```

---

### Task 7: Enrolment routes

**Files:**
- Create: `apps/api/src/routes/enrollments.ts`
- Modify: `apps/api/src/app.ts` (register `enrollmentRoutes`)
- Test: `apps/api/test/enrollments.test.ts`

**Interfaces:**
- Consumes: `request.withDb` (Task 5); `toNumber` (Task 6); `EnrollmentsResponse`, `EnrollRequest`, `SectionParams`, `EnrollmentChange` (Task 1).
- Produces: `enrollmentRoutes: FastifyPluginAsync`, serving:
  - `GET /me/enrollments`: the caller's rows (`student_id = request.user.sub`), every status,
    ordered by course code.
  - `POST /enrollments`: returns 201 with
    ``select id, section_id, status::text as status, waitlist_position from public.enroll_in_section(${sectionId}::uuid)``.
  - `DELETE /enrollments/:sectionId`: returns 200 with the same columns from
    `public.drop_section`.
  - Refusals reach the client through Task 5's error handler. This route does no rule checks of
    its own.

- [ ] **Step 1: Write the failing tests** `enrollments.test.ts`

Helpers:
- `post(sectionId, sub)`, `del(sectionId, sub)` and `mine(sub)` call the API with a token.
- Each test seeds its own university so capacities stay independent.

```ts
it("registers a student and lists the enrolment", async () => {
  const u = await seedUniversity();
  const r = await post(u.sections.cs101, u.users.student);
  expect(r.statusCode).toBe(201);
  expect(r.json()).toMatchObject({ enrollment: { sectionId: u.sections.cs101, status: "enrolled", waitlistPosition: null } });
  expect((await mine(u.users.student)).json().enrollments).toEqual([expect.objectContaining({
    sectionId: u.sections.cs101, sectionCode: "L1", termId: u.termId, status: "enrolled",
    course: { code: "CS101", title: "Programming I", creditHours: 3.5 } })]);
});
it("waitlists, then refuses, when the section fills", async () => {
  const u = await seedUniversity({ cs101Capacity: 1, cs101Waitlist: 1 });
  await post(u.sections.cs101, u.users.student);
  expect((await post(u.sections.cs101, u.users.classmate)).json().enrollment).toMatchObject({ status: "waitlisted", waitlistPosition: 1 });
  const full = await post(u.sections.cs101, u.users.latecomer);
  expect([full.statusCode, full.json()]).toEqual([422, { error: { code: "rule_violation", message: "This section is full" } }]);
});
it.each([
  ["missing prerequisite", (u: University) => post(u.sections.cs201, u.users.student), 422, "rule_violation", "Prerequisites for CS201 are not met"],
  ["teacher registering", (u: University) => post(u.sections.cs101, u.users.teacher), 403, "forbidden", "You are not allowed to do that."],
])("refuses a %s", async (_label, act, status, code, message) => {
  const r = await act(await seedUniversity());
  expect([r.statusCode, r.json()]).toEqual([status, { error: { code, message } }]);
});
it("refuses a duplicate registration", async () => {
  const u = await seedUniversity();
  await post(u.sections.cs101, u.users.student);
  const r = await post(u.sections.cs101, u.users.student);
  expect([r.statusCode, r.json().error]).toEqual([409, { code: "conflict", message: "Already registered in a lecture section of this course" }]);
});
it("refuses when registration is closed", async () => {
  const u = await seedUniversity({ registrationOpen: false });
  expect((await post(u.sections.cs101, u.users.student)).json().error).toEqual({ code: "rule_violation", message: "Registration is closed for this term" });
});
it("does not reveal another university's section", async () => {
  const [u, other] = [await seedUniversity(), await seedUniversity()];
  expect((await post(other.sections.cs101, u.users.student)).json().error).toEqual({ code: "not_found", message: "Section not found" });
});
it("rejects a malformed section id", async () => {
  const u = await seedUniversity();
  expect((await post("x", u.users.student)).statusCode).toBe(400);
});
it("drops, and promotes the head of the waiting list", async () => {
  const u = await seedUniversity({ cs101Capacity: 1, cs101Waitlist: 1 });
  await post(u.sections.cs101, u.users.student);
  await post(u.sections.cs101, u.users.classmate);
  const r = await del(u.sections.cs101, u.users.student);
  expect([r.statusCode, r.json().enrollment.status]).toEqual([200, "dropped"]);
  expect((await mine(u.users.classmate)).json().enrollments[0]).toMatchObject({ status: "enrolled", waitlistPosition: null });
});
it("refuses to drop a section the student is not in", async () => {
  const u = await seedUniversity();
  expect((await del(u.sections.cs101, u.users.student)).json().error).toEqual({ code: "not_found", message: "You are not registered in this section" });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -w @cohort/api -- enrollments.test.ts`
Expected: FAIL. `/enrollments` returns 404 `Not found.`.

- [ ] **Step 3: Implement `routes/enrollments.ts` and register it**

- [ ] **Step 4: Run the tests**

Run: `npm test -w @cohort/api && npm run typecheck -w @cohort/api`
Expected: all API tests pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api
git commit -m "feat: add registration, drop and my-enrolments routes"
```

---

### Task 8: Grades route

**Files:**
- Create: `apps/api/src/routes/grades.ts`
- Modify: `apps/api/src/app.ts` (register `gradeRoutes`)
- Test: `apps/api/test/grades.test.ts`

**Interfaces:**
- Consumes: `request.withDb` (Task 5); `toNumber` (Task 6); `GradesResponse` (Task 1).
- Produces: `gradeRoutes: FastifyPluginAsync`, serving `GET /me/grades`.
  - The query reads `public.published_grades` with `student_id = request.user.sub`, joined to
    its offering and course, and left-joined to `grade_components` for the item name.
  - Results are ordered by course code, then `published_at`.

- [ ] **Step 1: Write the failing test** `grades.test.ts`

`beforeAll`, as the owner (`ownerQuery`), for the student in CS101:
- Insert an enrolment with status `enrolled`.
- Insert a grade component `Midterm`: weight 30, `published_at = now()`.
- Insert grade entries: a draft of 50; a published 70; and a published 75 that supersedes the
  70, with `change_reason 'Re-marked question 3'`. All have `max_score` 100 and reference the
  component.

```ts
it("shows the student their current published grades only", async () => {
  const r = await get("/me/grades", await t.tokenFor(u.users.student));
  expect(r.json().grades).toEqual([expect.objectContaining({ offeringId: u.offerings.cs101,
    course: { code: "CS101", title: "Programming I" }, item: "Midterm", score: 75, maxScore: 100 })]);
});
it("shows a classmate nothing", async () => {
  expect((await get("/me/grades", await t.tokenFor(u.users.classmate))).json().grades).toEqual([]);
});
it("shows the teacher none of their students' grades", async () => {
  expect((await get("/me/grades", await t.tokenFor(u.users.teacher))).json().grades).toEqual([]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm test -w @cohort/api -- grades.test.ts`
Expected: FAIL. `/me/grades` returns 404 `Not found.`.

- [ ] **Step 3: Implement `routes/grades.ts` and register it**

- [ ] **Step 4: Run all API tests**

Run: `npm test -w @cohort/api && npm run typecheck -w @cohort/api`
Expected: all API tests pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api
git commit -m "feat: add my-grades route over published_grades"
```

---

### Task 9: Web app scaffold and API client

**Files:**
- Create: `apps/web/package.json`, `apps/web/tsconfig.json`, `apps/web/vite.config.ts`, `apps/web/index.html`, `apps/web/src/config.ts`
- Create: `apps/web/src/lib/api.ts`, `apps/web/src/lib/ApiContext.tsx`, `apps/web/src/lib/queryKeys.ts`
- Create: `apps/web/test/setup.ts`, `apps/web/test/server.ts`
- Test: `apps/web/src/lib/api.test.ts`

**Interfaces:**
- Consumes: every contract schema (Task 1).
- Produces:
  - `class ApiError extends Error { constructor(readonly status: number, readonly code: ApiErrorCode, message: string) }`
  - `type ApiClient = { getMe(): Promise<MeResponse>; getTerms(): Promise<TermsResponse>; getSections(termId: string): Promise<SectionsResponse>; getMyEnrollments(): Promise<EnrollmentsResponse>; enroll(sectionId: string): Promise<EnrollmentChange>; drop(sectionId: string): Promise<EnrollmentChange>; getMyGrades(): Promise<GradesResponse> }`
  - `createApiClient(options: { baseUrl: string; getAccessToken: () => Promise<string | null>; onUnauthorized?: () => void }): ApiClient`. It:
    - Sends `Authorization: Bearer <token>` when there is a token.
    - Parses success bodies with the matching schema. A mismatch becomes
      `ApiError(status, "internal", "Unexpected response from the server.")`.
    - Turns error bodies into an `ApiError` built from `ApiErrorBody`; anything unparseable
      becomes `ApiError(status, "internal", "Something went wrong. Please try again.")`.
    - Calls `onUnauthorized` on a 401.
  - `ApiProvider({ client, children })` and `useApi(): ApiClient`.
  - `queryKeys = { me: ["me"], terms: ["terms"], sections: (termId: string) => ["sections", termId], enrollments: ["enrollments"], grades: ["grades"] } as const`.
  - `webConfig = { supabaseUrl, supabasePublishableKey, apiUrl }`, from `VITE_SUPABASE_URL`,
    `VITE_SUPABASE_PUBLISHABLE_KEY` and `VITE_API_URL` (default `http://localhost:3000`).
  - `test/server.ts`: `API = "http://api.test"` and `server = setupServer()`.
  - `test/setup.ts`: imports `@testing-library/jest-dom/vitest`; starts, resets and closes `server`.
- Package and config:
  - `package.json`: name `@cohort/web`. Scripts:
    - `dev`: `vite`
    - `test`: `vitest run`
    - `typecheck`: `tsc -p tsconfig.json`
  - `vite.config.ts`: `defineConfig` from `vitest/config`, with the React plugin, the dev
    server on port 5173, and `test: { environment: "jsdom", setupFiles: ["./test/setup.ts"] }`.
  - `tsconfig.json`: extends the base with module `esnext`, moduleResolution `bundler`,
    jsx `react-jsx`, lib `["es2023", "dom", "dom.iterable"]` and types `["vite/client"]`.

- [ ] **Step 1: Write the failing test** `src/lib/api.test.ts`

These tests use MSW handlers on `API`:

```ts
const client = (onUnauthorized = vi.fn()) =>
  createApiClient({ baseUrl: API, getAccessToken: async () => "test-token", onUnauthorized });

it("sends the access token and parses the response", async () => {
  server.use(http.get(`${API}/me`, ({ request }) =>
    request.headers.get("authorization") === "Bearer test-token" ? HttpResponse.json(me) : new HttpResponse(null, { status: 401 })));
  await expect(client().getMe()).resolves.toEqual(me);
});
it("surfaces the API's error code and message", async () => {
  server.use(http.post(`${API}/enrollments`, () => HttpResponse.json(
    { error: { code: "rule_violation", message: "Prerequisites for CS201 are not met" } }, { status: 422 })));
  await expect(client().enroll(sectionId)).rejects.toMatchObject({ status: 422, code: "rule_violation", message: "Prerequisites for CS201 are not met" });
});
it("reports unreadable failures generically", async () => {
  server.use(http.get(`${API}/terms`, () => new HttpResponse("<html>Bad gateway</html>", { status: 502 })));
  await expect(client().getTerms()).rejects.toMatchObject({ status: 502, code: "internal", message: "Something went wrong. Please try again." });
});
it("signals an expired session", async () => {
  const onUnauthorized = vi.fn();
  server.use(http.get(`${API}/me/grades`, () => HttpResponse.json({ error: { code: "unauthorized", message: "Sign in to continue." } }, { status: 401 })));
  await expect(client(onUnauthorized).getMyGrades()).rejects.toMatchObject({ code: "unauthorized" });
  expect(onUnauthorized).toHaveBeenCalledTimes(1);
});
it("refuses a response that breaks the contract", async () => {
  server.use(http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [{ id: 1 }] })));
  await expect(client().getMyEnrollments()).rejects.toMatchObject({ code: "internal", message: "Unexpected response from the server." });
});
it("drops with DELETE on the section's path", async () => {
  server.use(http.delete(`${API}/enrollments/${sectionId}`, () => HttpResponse.json({ enrollment: { id: sectionId, sectionId, status: "dropped", waitlistPosition: null } })));
  await expect(client().drop(sectionId)).resolves.toMatchObject({ enrollment: { status: "dropped" } });
});
```

`me` is a valid `MeResponse` fixture; `sectionId` is a UUID.

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm install && npm test -w @cohort/web`
Expected: FAIL. `./api.ts` does not exist.

- [ ] **Step 3: Implement the files listed above**

- [ ] **Step 4: Run the tests and the type-check**

Run: `npm test -w @cohort/web && npm run typecheck -w @cohort/web`
Expected: 6 tests pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/web package-lock.json
git commit -m "feat: scaffold web app with typed API client"
```

---

### Task 10: Sign-in, protected shell and local setup docs

**Files:**
- Create: `apps/web/src/lib/supabase.ts`, `apps/web/src/auth/AuthProvider.tsx`, `apps/web/src/auth/RequireAuth.tsx`
- Create: `apps/web/src/pages/LoginPage.tsx`, `apps/web/src/AppShell.tsx`, `apps/web/src/App.tsx`, `apps/web/src/main.tsx`
- Create: `apps/web/src/pages/DashboardPage.tsx` and `apps/web/src/pages/RegistrationPage.tsx` (each only an `<h1>`: "Dashboard" and "Course registration"; Tasks 11 and 12 fill them)
- Create: `apps/web/.env.example`, `apps/web/test/render.tsx`
- Modify: `README.md` (replace the empty file)
- Test: `apps/web/src/App.test.tsx`, `apps/web/src/AppShell.test.tsx`

**Interfaces:**
- Consumes: `createApiClient`, `ApiError`, `ApiProvider`, `useApi`, `queryKeys`, `webConfig` (Task 9).
- Produces:
  - `type AuthClientLike = Pick<SupabaseClient["auth"], "getSession" | "onAuthStateChange" | "signInWithPassword" | "signOut">`
  - `AuthProvider({ auth, children })` and
    `useAuth(): { session: Session | null; loading: boolean; signIn(email: string, password: string): Promise<void>; signOut(): Promise<void> }`.
    `signIn` throws `Error(error.message)` when Supabase returns an error.
  - `RequireAuth({ children })`: shows "Loading…" while loading; `<Navigate to="/login" replace />`
    without a session.
  - `App`: `<Routes>` with `/login` → `LoginPage`. Everything else is inside
    `RequireAuth` > `AppShell`: index → `DashboardPage`, `register` → `RegistrationPage`.
  - `main.tsx` wires:
    - `BrowserRouter`, a `QueryClientProvider`, and `AuthProvider` over `supabase.auth`.
    - `ApiProvider` with `createApiClient({ baseUrl: webConfig.apiUrl, getAccessToken: from supabase.auth.getSession, onUnauthorized: () => void supabase.auth.signOut() })`.
  - Test support (`test/render.tsx`):
    - `createFakeAuth(options?: { session?: Session | null; signInError?: string }): AuthClientLike`.
      `signInWithPassword` and `signOut` are `vi.fn`s that update the session and notify
      `onAuthStateChange` listeners.
    - `fakeSession: Session`: `{ access_token: "test-token", user: { id, email } }`, cast to `Session`.
    - `renderApp(options: { route: string; auth: AuthClientLike })`: renders `<App />` in a
      `MemoryRouter`, with `QueryClient({ defaultOptions: { queries: { retry: false } } })` and
      `createApiClient({ baseUrl: API, getAccessToken: async () => "test-token" })`.
- README "Running Cohort locally" covers:
  - `npm install`.
  - The test database (`npm run db:test:reset`, with the three variables).
  - Applying pending migrations to GradProj with `npx supabase link --project-ref gejismdqvjuygtxibdhs`
    and `npx supabase db push`.
  - Setting `cohort_api`'s password in the SQL editor.
  - `apps/api/.env`: `DATABASE_URL` on the Session pooler as user
    `cohort_api.gejismdqvjuygtxibdhs` (copy the host from Dashboard → Connect), plus `SUPABASE_URL`.
  - `apps/web/.env` with the publishable key.
  - `npm run dev -w @cohort/api` and `npm run dev -w @cohort/web`.
  - Running the tests.

- [ ] **Step 1: Write the failing tests**

`App.test.tsx`. MSW serves `/me` with display name "Sara Student" and tenant name "Smoke University A":

```ts
it("sends a visitor without a session to sign in", async () => {
  renderApp({ route: "/", auth: createFakeAuth({ session: null }) });
  expect(await screen.findByRole("heading", { name: "Sign in to Cohort" })).toBeInTheDocument();
});
it("signs in and shows who is signed in", async () => {
  const auth = createFakeAuth({ session: null });
  renderApp({ route: "/login", auth });
  await userEvent.type(await screen.findByLabelText("Email"), "sara@a.test");
  await userEvent.type(screen.getByLabelText("Password"), "secret-pass");
  await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
  expect(auth.signInWithPassword).toHaveBeenCalledWith({ email: "sara@a.test", password: "secret-pass" });
  expect(await screen.findByText("Sara Student · Smoke University A")).toBeInTheDocument();
});
it("shows why sign-in failed", async () => {
  renderApp({ route: "/login", auth: createFakeAuth({ session: null, signInError: "Invalid login credentials" }) });
  await userEvent.type(await screen.findByLabelText("Email"), "sara@a.test");
  await userEvent.type(screen.getByLabelText("Password"), "wrong");
  await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Invalid login credentials");
});
it("returns to sign-in after signing out", async () => {
  const auth = createFakeAuth({ session: fakeSession });
  renderApp({ route: "/", auth });
  await userEvent.click(await screen.findByRole("button", { name: "Sign out" }));
  expect(auth.signOut).toHaveBeenCalled();
  expect(await screen.findByRole("heading", { name: "Sign in to Cohort" })).toBeInTheDocument();
});
```

`AppShell.test.tsx`:

```ts
it("explains an account that is not linked to a university", async () => {
  server.use(http.get(`${API}/me`, () => HttpResponse.json(
    { error: { code: "forbidden", message: "Your account is not linked to a university yet." } }, { status: 403 })));
  renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
  expect(await screen.findByText("Your account is not linked to a university yet. Contact your administrator.")).toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Dashboard" })).not.toBeInTheDocument();
});
it("links to both pages", async () => {
  renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
  expect(await screen.findByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/");
  expect(screen.getByRole("link", { name: "Registration" })).toHaveAttribute("href", "/register");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -w @cohort/web`
Expected: FAIL. `./App.tsx` and `../test/render.tsx` cannot be resolved.

- [ ] **Step 3: Implement the files listed above, and write the README section**

- [ ] **Step 4: Run the tests and the type-check**

Run: `npm test -w @cohort/web && npm run typecheck -w @cohort/web`
Expected: all web tests pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/web README.md
git commit -m "feat: add sign-in, protected shell and local setup guide"
```

---

### Task 11: Dashboard

**Files:**
- Create: `apps/web/src/lib/format.ts`
- Modify: `apps/web/src/pages/DashboardPage.tsx`
- Test: `apps/web/src/lib/format.test.ts`, `apps/web/src/pages/DashboardPage.test.tsx`

**Interfaces:**
- Consumes: `useApi`, `queryKeys` (Task 9); `renderApp`, `createFakeAuth`, `fakeSession` (Task 10).
- Produces, in `format.ts`:
  - `formatEnrollmentStatus(status: EnrollmentStatus, waitlistPosition: number | null): string`
    → "Enrolled", "Waitlisted (position 2)", "Dropped", "Withdrawn", "Completed", "Failed",
    "Incomplete".
  - `formatScore(score: number, maxScore: number): string` → "75 / 100".
- Produces, in `DashboardPage`:
  - `<h1>Dashboard</h1>`.
  - Section "My courses" (`<h2>`), listing non-dropped enrolments as
    `"<code> <title> · Section <sectionCode> · <status label>"`.
  - Section "Published grades" (`<h2>`), a table with columns Course, Item and Score. A null
    item shows "Course grade".
  - The empty states from the spec.

- [ ] **Step 1: Write the failing tests**

`format.test.ts`:

```ts
expect(formatEnrollmentStatus("waitlisted", 2)).toBe("Waitlisted (position 2)");
expect(formatEnrollmentStatus("enrolled", null)).toBe("Enrolled");
expect(formatScore(75, 100)).toBe("75 / 100");
expect(formatScore(17.5, 20)).toBe("17.5 / 20");
```

`DashboardPage.test.tsx`. MSW serves three enrolments (CS101 enrolled, MA201 waitlisted at
position 2, CS201 dropped) and two grades (`item: "Midterm"`, 75/100; `item: null`, 88/100):

```ts
it("lists current courses and published grades", async () => {
  renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
  expect(await screen.findByText("CS101 Programming I · Section L1 · Enrolled")).toBeInTheDocument();
  expect(screen.getByText("MA201 Linear Algebra · Section L2 · Waitlisted (position 2)")).toBeInTheDocument();
  expect(screen.queryByText(/CS201/)).not.toBeInTheDocument();
  const rows = within(screen.getByRole("table")).getAllByRole("row");
  expect(rows[1]).toHaveTextContent("CS101Midterm75 / 100");
  expect(rows[2]).toHaveTextContent("Course grade88 / 100");
});
it("says when there is nothing yet", async () => {
  server.use(
    http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [] })),
    http.get(`${API}/me/grades`, () => HttpResponse.json({ grades: [] })));
  renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
  expect(await screen.findByText("You are not registered in any courses yet.")).toBeInTheDocument();
  expect(await screen.findByText("No published grades yet.")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -w @cohort/web -- format.test.ts DashboardPage.test.tsx`
Expected: FAIL. `./format.ts` does not exist, and the course line is not rendered.

- [ ] **Step 3: Implement `format.ts` and `DashboardPage`**

- [ ] **Step 4: Run the tests**

Run: `npm test -w @cohort/web && npm run typecheck -w @cohort/web`
Expected: all web tests pass; no type errors.

- [ ] **Step 5: Commit**

```bash
git add apps/web
git commit -m "feat: add student dashboard with courses and published grades"
```

---

### Task 12: Course registration page

**Files:**
- Create: `apps/web/src/lib/terms.ts`
- Modify: `apps/web/src/lib/format.ts`, `apps/web/src/pages/RegistrationPage.tsx`
- Test: `apps/web/src/lib/terms.test.ts`, `apps/web/src/lib/format.test.ts`, `apps/web/src/pages/RegistrationPage.test.tsx`

**Interfaces:**
- Consumes: `useApi`, `queryKeys`, `ApiError` (Task 9); `format.ts` (Task 11); `renderApp`, `createFakeAuth`, `fakeSession` (Task 10).
- Produces:
  - `pickDefaultTerm(terms: Term[], now: Date): Term | undefined`. Returns the first term with
    `registrationOpensAt <= now <= (addDropEndsAt ?? registrationClosesAt)`, else `terms[0]`.
  - `formatMeeting(m: Meeting): string` → "Mon 09:00–10:30 · Room 101", or "Sun 09:05–10:30"
    without a room. It uses an en dash.
  - `formatCredits(n: number): string` → "1 credit", "3 credits", "3.5 credits".
  - `RegistrationPage`:
    - `<h1>Course registration</h1>` and a labelled select "Term".
    - For the selected term's sections: `"<code> <title> · Section <code> · <credits>"`, then
      one line per meeting.
    - A button per section: "Register for <code> <section>", or "Drop <code> <section>" when
      `/me/enrollments` has it as enrolled or waitlisted. The button is disabled while its
      request is in flight.
    - After success: the status message from the spec (`role="status"`) and invalidation of
      `queryKeys.enrollments`.
    - After an `ApiError`: its message in `role="alert"`.
    - The empty states from the spec.

- [ ] **Step 1: Write the failing tests**

`terms.test.ts`, with `now = new Date("2026-10-25T12:00:00Z")`:

```ts
expect(pickDefaultTerm([spring, fall], now)?.name).toBe("Fall 2026");    // fall's window contains now
expect(pickDefaultTerm([later, earlier], now)?.name).toBe("Later");       // no window open → first
expect(pickDefaultTerm([], now)).toBeUndefined();
expect(pickDefaultTerm([addDropOnly], now)?.name).toBe("Add/drop");      // closes yesterday, add/drop ends tomorrow
```

Added to `format.test.ts`:

```ts
expect(formatMeeting({ weekday: 1, startsAt: "09:00", endsAt: "10:30", room: "101" })).toBe("Mon 09:00–10:30 · Room 101");
expect(formatMeeting({ weekday: 7, startsAt: "09:05", endsAt: "10:30", room: null })).toBe("Sun 09:05–10:30");
expect([formatCredits(1), formatCredits(3), formatCredits(3.5)]).toEqual(["1 credit", "3 credits", "3.5 credits"]);
```

`RegistrationPage.test.tsx`. MSW keeps an in-memory `enrolled: Set<string>`:
- `GET /terms` → one open term.
- `GET /terms/:id/sections` → CS101 L1 (3.5 credits, Sun 09:05–10:30, room 101) and CS201 L1.
- `GET /me/enrollments` reflects the set.
- `POST /enrollments` adds the id and returns `enrolled`.
- `DELETE` removes the id and returns `dropped`.

```ts
it("lists sections with credits and meetings", async () => {
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  expect(await screen.findByText("CS101 Programming I · Section L1 · 3.5 credits")).toBeInTheDocument();
  expect(screen.getByText("Sun 09:05–10:30 · Room 101")).toBeInTheDocument();
});
it("registers, then offers to drop", async () => {
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  await userEvent.click(await screen.findByRole("button", { name: "Register for CS101 L1" }));
  expect(await screen.findByRole("status")).toHaveTextContent("Registered for CS101 L1.");
  expect(await screen.findByRole("button", { name: "Drop CS101 L1" })).toBeInTheDocument();
});
it("tells the student they are on the waiting list", async () => {
  server.use(http.post(`${API}/enrollments`, () => HttpResponse.json(
    { enrollment: { id: enrollmentId, sectionId: cs101, status: "waitlisted", waitlistPosition: 1 } }, { status: 201 })));
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  await userEvent.click(await screen.findByRole("button", { name: "Register for CS101 L1" }));
  expect(await screen.findByRole("status")).toHaveTextContent("Added to the waiting list for CS101 L1 (position 1).");
});
it("shows the database's reason when registration is refused", async () => {
  server.use(http.post(`${API}/enrollments`, () => HttpResponse.json(
    { error: { code: "rule_violation", message: "Prerequisites for CS201 are not met" } }, { status: 422 })));
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  await userEvent.click(await screen.findByRole("button", { name: "Register for CS201 L1" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Prerequisites for CS201 are not met");
  expect(screen.getByRole("button", { name: "Register for CS201 L1" })).toBeEnabled();
});
it("disables the button while the request is in flight", async () => {
  server.use(http.post(`${API}/enrollments`, async () => { await delay("infinite"); return HttpResponse.json({}); }));
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  const button = await screen.findByRole("button", { name: "Register for CS101 L1" });
  await userEvent.click(button);
  expect(button).toBeDisabled();
});
it("drops a section", async () => {
  enrolled.add(cs101);
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  await userEvent.click(await screen.findByRole("button", { name: "Drop CS101 L1" }));
  expect(await screen.findByRole("status")).toHaveTextContent("Dropped CS101 L1.");
});
it("says when there are no terms", async () => {
  server.use(http.get(`${API}/terms`, () => HttpResponse.json({ terms: [] })));
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  expect(await screen.findByText("No terms are available.")).toBeInTheDocument();
});
it("says when a term has no open sections", async () => {
  server.use(http.get(`${API}/terms/:termId/sections`, () => HttpResponse.json({ sections: [] })));
  renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
  expect(await screen.findByText("No sections are open for registration in this term.")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -w @cohort/web -- terms.test.ts format.test.ts RegistrationPage.test.tsx`
Expected: FAIL. `./terms.ts` is missing, and `formatMeeting` is not exported.

- [ ] **Step 3: Implement `terms.ts`, the two formatters and `RegistrationPage`**

- [ ] **Step 4: Run the whole workspace**

Run: `npm run typecheck && npm test`
Expected: `tsc` prints nothing for every workspace; every test passes in contracts, api and web.

- [ ] **Step 5: Commit**

```bash
git add apps/web
git commit -m "feat: add course registration page"
```

---

## After the plan: steps for the team

These are not tasks for the executor; they need GradProj credentials.

1. Run `npx supabase link --project-ref gejismdqvjuygtxibdhs` and `npx supabase db push`. This
   applies `20261022150000_builtin_time_ranges`, `20261025120000_prisma_compat` and
   `20261025120100_api_role`.
2. In the SQL editor, run `alter role cohort_api with password '<new password>'`.
3. Fill in `apps/api/.env` and `apps/web/.env` as the README describes, run both dev servers,
   and sign in with a provisioned account.
