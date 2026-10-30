# Web foundation and course registration: design

## Intent

Give Cohort its first runnable application on top of the GradProj database
(`supabase/README.md`):
- a React web app, a Fastify API and a shared contracts package;
- one end-to-end feature: a student signs in, sees their courses and published grades, and
  registers for or drops course sections.

Later features (teaching staff, administrators, AI) each get their own plan on this foundation.

The point of the slice is to prove the architecture the paper commits to (sections 6.1, 6.6):
- one identity;
- one permission model, enforced in the data layer;
- records that stay exact;
- typed contracts shared by both clients.

## Decisions made with the team

- **Scope:** foundation plus student registration.
- **Data access:** the API reuses the database's row-level security. Prisma connects as a login
  role that has no privileges of its own. Every request runs inside a transaction that sets the
  caller's JWT claims and switches to the `authenticated` role, so the existing policies decide
  what each query sees. A query run outside that wrapper fails with `permission denied` instead
  of returning data.

## Decisions made by the planner (with reasons)

| Decision | Reason |
| --- | --- |
| npm workspaces: `apps/api`, `apps/web`, `packages/contracts` | Built into npm; no extra tool to install |
| Zod schemas for every request and response live in `packages/contracts`, used by both apps | One definition of the API; the web app parses responses with the same schemas the API serialises with |
| Packages export TypeScript source; no build step. The API runs with `tsx`, the web app with Vite | Fewer moving parts; type-checking is `tsc --noEmit` everywhere |
| TypeScript 7.0.2, no ESLint | TS 7 is current; typescript-eslint 8.72 supports only TS < 6.1. Type-checking and tests are the gates |
| Prisma 7.10.1, schema introspected with `prisma db pull`; never `prisma migrate` | The SQL files in `supabase/migrations` own the schema; Prisma is the typed query layer |
| Prisma introspects `public` and `auth` | `public.users.id` references `auth.users`; Prisma refuses cross-schema references otherwise |
| Prisma models: `users` is the app's user table, `auth_users` is Supabase's | A fresh introspection (Prisma 7.10.1) names Supabase's table `auth_users` and the app's `public_users`; `public_users` is renamed once to `users`, and `db pull` keeps the names |
| A migration adds composite unique keys that Prisma needs, and turns the one-active-prompt-version index into an exclusion constraint | Prisma 7 rejects the introspected schema otherwise (six one-to-one relations; one misread partial index) |
| Login role `cohort_api`: `LOGIN NOINHERIT`, member of `authenticated` | Fails closed. Its password is set per environment, never committed |
| Tokens verified with `jose` against Supabase's published key set (`/auth/v1/.well-known/jwks.json`), issuer `https://gejismdqvjuygtxibdhs.supabase.co/auth/v1`, audience `authenticated` | Supabase signs access tokens with asymmetric keys; no shared secret on the API |
| Sign-in in the browser with `@supabase/supabase-js` (`signInWithPassword`) | Supabase Auth already owns identities (accounts are provisioned through it) |
| Data fetching with TanStack Query; routing with React Router's declarative `<Routes>` | Standard, small; cache invalidation after register/drop |
| Weekday 1 = Monday … 7 = Sunday (ISO 8601) | The schema stores 1–7 without naming day 1 |
| API tests run against a plain Postgres (15+, with pgvector) built by `scripts/db/reset-test-db.sh`: a stub of Supabase's `auth` schema and API roles, then every migration | Works without Docker; CI can use the `pgvector/pgvector:pg17` image. `supabase start` also works for local development |

## Goals

1. Students sign in with email and password and stay signed in across reloads.
2. The dashboard lists the student's courses (enrolled, waitlisted, completed …) and their current
   published grades.
3. The registration page lists the open sections of a term and lets the student register or drop.
   - The database's rules (prerequisites, credit limit, timetable clash, capacity, waiting list,
     registration window) decide the outcome.
   - The page shows the database's message when a rule says no.
4. A signed-in account that is not linked to a university sees an explanation, not an empty page.

## Non-goals

- Features for teaching staff and administrators, beyond signing in.
- Instructor names and remaining seats in the catalogue. Both need new database functions,
  because students cannot read staff profiles or other students' enrolments.
- Internationalisation and right-to-left layout.
- A full WCAG audit. This slice uses semantic HTML and labelled controls only.
- A CI pipeline, a production build and deployment.
- Supabase Storage.

## Anti-goals

- The API connecting at runtime as `postgres`, `service_role`, or any role that bypasses RLS.
- Re-implementing in TypeScript an access rule the database already enforces.
- Error responses that leak table, constraint or policy names.

## API

All routes except `/health` require `Authorization: Bearer <Supabase access token>`.

| Method and path | Response (`packages/contracts`) | Notes |
| --- | --- | --- |
| `GET /health` | `{ status: "ok" }` | Public |
| `GET /me` | `MeResponse` | 403 when the account has no `public.users` row |
| `GET /terms` | `TermsResponse` | Newest first |
| `GET /terms/:termId/sections` | `SectionsResponse` | Sections of published offerings, by course code then section code; 404 for an unknown or other-tenant term |
| `GET /me/enrollments` | `EnrollmentsResponse` | The caller's enrolments in every status, by course code |
| `POST /enrollments` `{ sectionId }` | `EnrollmentChange`, 201 | Calls `public.enroll_in_section` |
| `DELETE /enrollments/:sectionId` | `EnrollmentChange`, 200 | Calls `public.drop_section` |
| `GET /me/grades` | `GradesResponse` | The caller's rows from `public.published_grades` (published and not superseded) |

Errors always have the body `{ "error": { "code", "message" } }`:

| Cause | Status | `code` | `message` |
| --- | --- | --- | --- |
| Request fails schema validation | 400 | `invalid_request` | Validation summary |
| Missing, expired or invalid token | 401 | `unauthorized` | `Sign in to continue.` |
| SQLSTATE `42501` (insufficient privilege) | 403 | `forbidden` | `You are not allowed to do that.` |
| SQLSTATE `P0002` (no data found) | 404 | `not_found` | The database's message |
| SQLSTATE `23514` (check violation) | 422 | `rule_violation` | The database's message |
| SQLSTATE `23503` (foreign key violation) | 422 | `rule_violation` | `That refers to something that does not exist.` |
| SQLSTATE `23505`, `23P01` (unique or exclusion violation) | 409 | `conflict` | The database's message |
| Supabase's signing keys cannot be fetched or read (timeout, network error, malformed key set) | 500 | `internal` | `Something went wrong. Please try again.` |
| Anything else | 500 | `internal` | `Something went wrong. Please try again.` |

The database's messages come from the registration functions, which are written for users (for
example `Prerequisites for CS201 are not met`).

- Postgres's own constraint messages are never passed through. A `23505` or `23P01` message that
  names a constraint becomes `That conflicts with something that already exists.` (409
  `conflict`), and a `23514` one becomes `That value is not allowed.` (422 `rule_violation`).
  Messages raised by the registration functions pass through.
- If the key set cannot be fetched, the API answers 500 `internal`, not 401, and logs the cause.
  A 401 makes the web app sign the user out, and an outage on Supabase's side is not a rejected
  session. A token whose `kid` the key set does not list is still 401.

## Web pages and copy

- **`/login`**
  - Heading "Sign in to Cohort"; fields "Email" and "Password"; button "Sign in".
  - Supabase's error message appears in an alert.
- **Shell (every signed-in page)**
  - Shows "<display name> · <university name>", links "Dashboard" and "Registration", and a
    button "Sign out".
  - An unlinked account sees "Your account is not linked to a university yet. Contact your
    administrator." instead of the page.
  - An automatic sign-out after a 401 signs out this device only; the "Sign out" button keeps
    Supabase's default and signs out every device.
- **`/` Dashboard**
  - "My courses": one line per enrolment that is not dropped, e.g. "CS101 Programming I ·
    Section L1 · Enrolled" or "… · Waitlisted (position 2)". Empty state: "You are not
    registered in any courses yet."
  - "Published grades": course code, item, "75 / 100". The item is the grade component's name,
    "Course grade" for a grade with no component, or "Graded item" when the component is not
    visible yet. Empty state: "No published grades yet."
- **`/register` Course registration**
  - A "Term" select. It defaults to the term whose registration window contains now, otherwise
    the first (newest) term. No terms: "No terms are available."
  - Each section shows "CS101 Programming I · Section L1 · 3.5 credits", then one line per
    meeting: "Mon 09:00–10:30 · Room 101" (no room: "Mon 09:00–10:30").
  - Buttons: "Register for CS101 L1", or "Drop CS101 L1" when the student is enrolled or
    waitlisted in that section. No sections: "No sections are open for registration in this
    term."
  - After an action, a status message: "Registered for CS101 L1.", "Added to the waiting list
    for CS101 L1 (position 1)." or "Dropped CS101 L1." A refusal shows the API's message in an
    alert.
- **Status labels:** Enrolled, Waitlisted (position N), Dropped, Withdrawn, Completed, Failed,
  Incomplete.
- **Credits:** "1 credit", "3 credits", "3.5 credits".

## Constraints

- Node 22.22.2 or later.
- Supabase project ref `gejismdqvjuygtxibdhs`.
- The database's migration history is append-only. This slice adds two migrations. The team
  applies them to GradProj with `npx supabase db push`, together with the pending
  `20261022150000_builtin_time_ranges`, because the connector used so far cannot run `DROP`
  statements.
- `cohort_api`'s password must be set in GradProj (`alter role cohort_api with password …`)
  before the API can connect.

## Left to the builder

- Styling and the component structure inside each page.
- Query-key names.
- How each route maps Prisma rows to contract objects, as long as the contract parses.
