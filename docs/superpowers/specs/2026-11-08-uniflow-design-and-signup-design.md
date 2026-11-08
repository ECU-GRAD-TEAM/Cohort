# UniFlow design, sign-up and sign-in: design

## Intent

Students should be able to create their own account, sign in, and register for courses, in an
app that looks like the team's UniFlow design rather than unstyled HTML. This is for the
end-of-sprint preview on Vercel, which the team and supervisors open.

The team supplied the UniFlow page skeleton (`index.html` of a static demo: sidebar, header, main
area, footer, mobile nav). Its stylesheets and scripts (`style.css`, `workspace.css`, `app.js`,
`workspace.js`) were not supplied, so the look is rebuilt from that skeleton and its brand colour.

## Decisions made with the team

- **What to build:** the UniFlow look for the existing app, plus sign-up and sign-in. Not the
  demo's other screens or features.
- **Who signs up:** students, who then register for courses.
- **No university email check for now.** Anyone can sign up with any email address.
- **Every new self-signed-up account joins one university, Rivermere University, as a student**
  (option A). The alternative, accounts staying unlinked until someone links them by hand
  (option B), was rejected: it leaves every new user unable to register.
- **The account is linked by a database rule**, not by an API endpoint (see Approaches).

## Goals

1. A visitor can create an account with full name, email and password, confirm the email if
   Supabase asks for that, sign in, and land on the dashboard as a Rivermere student.
2. From there they can open Registration and register as the app already allows. With no terms
   in GradProj yet, the page says "No terms are available."
3. Sign-in, sign-up, the dashboard and the registration page all use the UniFlow layout and
   brand, on desktop and on a phone.
4. Accounts created by the university (with university details in `app_metadata`) behave exactly
   as today.

## Non-goals

- A university email-domain check (deferred by the team).
- Terms, courses and other demo data in GradProj. Only the Rivermere University row is added.
- The demo's other features: search, the Arabic language switch, notifications, the profile
  page, the workspace (role) switcher, "Explore your campus", toasts and dialogs.
- Password reset, social sign-in, editing the profile after sign-up.
- Sign-up for staff, administrators or IT staff.
- Internationalisation and right-to-left layout.

## Anti-goals

- Any way for a sign-up to grant more than a student account at the one open university.
- Controls that look like they work but do nothing (a search box that searches nothing, a
  notifications bell with no notifications).
- Supabase's service-role key anywhere in the API or the web app.
- Regressions in the existing flows: account linking for university-created accounts, the
  401 sign-out, the "not linked" message, registration and the dashboard.

## Constraints

- The browser signs up and in with Supabase Auth directly (`@supabase/supabase-js`), as sign-in
  does today. Clients can only set `user_metadata`; `app_metadata` is writable only with the
  service role. The database trigger `private.handle_new_auth_user()` (identity migration) runs
  on every new `auth.users` row and already creates the `users` row, the profile (via
  `private.on_user_created()`) and the role matching the user type.
- `private.tenant_id()` resolves the caller's university from `public.users`, not from the token,
  so a `users` row is all row-level security needs.
- Schema changes are new, append-only files in `supabase/migrations/`. The Supabase connector can
  apply them to GradProj when they contain no `DROP`.
- Supabase's email confirmation links back to the project's **Site URL**. It is `localhost`
  until someone changes it in the Supabase Dashboard; the session cannot change it.
- Existing stack only: React 19, React Router 8, TanStack Query, Vite 8, plain CSS. No new
  dependencies.

## Approaches

**What a new account gets**
- **A. Join one university as a student (chosen).** Needs a database rule and one university row.
- **B. Login only, linked by hand later.** No database change, but nobody who signs up can do
  anything.

**How the account is linked**
- **Database rule (chosen).** Extend the existing new-account trigger: an account with no
  university details joins the university marked open for sign-up, as a student. No secrets, and
  it uses the mechanism every account already goes through.
- **API sign-up endpoint (rejected).** It would need the service-role key on Vercel, the key that
  bypasses every access rule, to set two fields the database can set itself.
- **Supabase Auth hooks (rejected).** A "before user created" hook can accept or reject an
  account but cannot link it to a university, so the database rule would still be needed.

**How the look is built**
- **Plain CSS with design tokens (chosen).** One global stylesheet imported by `main.tsx`, with
  the brand values as CSS custom properties. It matches the original's plain-CSS approach and
  adds no dependency.
- **A CSS framework such as Tailwind (rejected).** A new dependency and build step, for a design
  that was written in plain CSS.

## Design

### Database: open sign-up

A new migration, `supabase/migrations/<timestamp>_open_signup.sql`:

- `public.tenants` gains `open_signup boolean not null default false`. At most one university can
  have it set: a unique partial index on a constant expression `where open_signup`.
- `private.handle_new_auth_user()` is replaced (`create or replace`) so that:

| New account's `app_metadata` | Result |
| --- | --- |
| Has both `tenant_id` and `user_type` | As today: `users` row with those values |
| Has neither | If an active university has `open_signup`: `users` row at that university, `user_type` `student`. Otherwise no `users` row (as today) |
| Has only one of them | As today: no `users` row |

  The display name still comes from `user_metadata.full_name`, which the sign-up page sends. The
  student role and the profile still come from `private.on_user_created()`.
- Nothing a client can send changes the university or the user type: those come only from
  `app_metadata` or the open-sign-up flag.

Accepted behaviour: the `users` row is created when the account is created, before the email is
confirmed. The account cannot sign in until it is confirmed (while confirmation is on), so the
row is harmless.

The sign-up leaves `institutional_id` (the student number) null. Nothing in this slice reads it:
`/me` does not return it, and `enroll_in_section` and `drop_section` never use it.

### Accepted consequences and known limitations

- **Anyone can become a Rivermere student.** With no email check, anyone on the internet can
  create a full student account. Row-level security and `enroll_in_section` treat it as a real
  student, so it can take seats, join waiting lists and appear in the university's directory.
  This is accepted because the team deferred the email check and GradProj holds preview data
  only. The domain check is the planned fix.
- **A later import can collide with a sign-up.** If the university later creates an account
  with an email someone already signed up with, Supabase refuses the duplicate, and the
  existing account stays a Rivermere student. No import tool exists yet. The fix belongs with
  that tool: update the existing account's `app_metadata` and `users` row instead of creating
  one. *(Builder's call: documented, not handled.)*
- **No open university means "not linked".** If no active university has `open_signup`, sign-up
  still succeeds, and the account sees the existing "not linked to a university" message. Failing
  the sign-up instead would need a mechanism other than the trigger. *(Builder's call: accepted
  for the preview.)*

### GradProj data

After the migration is applied, one row is inserted in GradProj through the Supabase connector
(not in a migration, because migrations also build the test database):

- `tenants`: slug `rivermere`, name `Rivermere University`, `data_region` `eu-west-1`,
  `open_signup` true. The existing `tenants_seed_roles` trigger creates its roles.

The README records how this row was made and how to point open sign-up at another university.

### Web: sign-up and sign-in

- **Routes:** `/signup` is added next to `/login`, outside the signed-in shell. A signed-in
  visitor who opens either is sent to `/`.
- **Auth:** `AuthClientLike` gains `signUp`. `useAuth()` gains
  `signUp(fullName, email, password): Promise<{ needsConfirmation: boolean }>`, which calls
  `auth.signUp({ email, password, options: { data: { full_name }, emailRedirectTo: <origin>/ } })`
  and throws `Error(error.message)` on failure, like `signIn`. `needsConfirmation` is true when
  Supabase returns no session.
- **Sign-up page** (`/signup`):
  - Heading "Create your student account".
  - Fields "Full name", "Email" and "Password", with the hint "At least 6 characters".
  - Button "Create account". Link "Already have an account? Sign in" to `/login`.
  - On success with confirmation needed, the form is replaced by a `role="status"` message:
    "Check your inbox. We sent a confirmation link to <email>." It has a link back to sign-in.
  - On success with a session, the visitor goes to `/`.
  - On failure, Supabase's message is shown in a `role="alert"`, for example "User already
    registered".
- **Sign-in page** (`/login`):
  - Heading "Sign in to UniFlow", fields "Email" and "Password", button "Sign in".
  - Link "New to UniFlow? Create an account" to `/signup`.
  - Errors as today.
- **Confirmation link:** Supabase redirects to the app with the session in the URL. supabase-js
  reads it on load (its default `detectSessionInUrl`), and the existing `onAuthStateChange`
  listener signs the visitor in.

### Web: the UniFlow look

**Brand:**
- Name "UniFlow", tagline "Your university, in sync.", brand red `#B81104`.
- `index.html`:
  - title "UniFlow — Your university, in sync"
  - `theme-color` `#B81104`
  - the description from the original page, word for word: "UniFlow connects courses, schedules,
    student support and campus operations in one responsive university workspace."
- Lettermark: a red rounded square with a white "u", then "Uni" and "Flow" with "Flow" in red.

**Signed-in shell (desktop):**

```
┌──────────────┬──────────────────────────────────────────────────────┐
│ [u] UniFlow  │                         (SS) Sara Student  [Sign out] │
│              │                              Rivermere University     │
│ ▥ Rivermere  ├──────────────────────────────────────────────────────┤
│   University │                                                      │
│ ONE CONNECTED│   page content (Dashboard / Course registration)     │
│ CAMPUS       │                                                      │
│              │                                                      │
│ WORKSPACE    │                                                      │
│ Student      │                                                      │
│              │                                                      │
│ ▸ Dashboard  │                                                      │
│   Registration│                                                     │
│              ├──────────────────────────────────────────────────────┤
│ A little more│ UniFlow  Your university, in sync.                   │
│ connected.   │                                                      │
└──────────────┴──────────────────────────────────────────────────────┘
```

- **Sidebar:**
  - the lettermark;
  - a university card with the caller's university name (from `/me`) and "ONE CONNECTED CAMPUS";
  - "WORKSPACE" with the caller's role as text ("Student", "Teaching staff", "Administrator" or
    "IT staff", from `/me` `userType`), not a switcher;
  - nav links "Dashboard" and "Registration", with the current one highlighted in brand red;
  - at the foot, "A little more connected." and "A whole world of possibilities."
- **Header:** avatar initials from the display name, the display name with the university name
  under it, and a "Sign out" button.
- **Footer:** "UniFlow" and "Your university, in sync."

**Phone width (under about 900 px):**
- The sidebar hides behind a "☰" button in the header labelled "Toggle navigation".
- A bottom bar repeats the two nav links.

**Auth pages:** a centred card on a soft brand background, with the lettermark, the tagline and
the form. They are not inside the shell.

**Loading and messages:**
- "Loading…" sits in the content area.
- The "not linked to a university" message keeps its exact copy. It appears inside the shell
  frame without nav links, and its Sign out button stays.

**Accessibility:**
- Semantic landmarks (`aside`, `header`, `nav`, `main`, `footer`).
- Visible focus outlines.
- Labelled controls.
- Text contrast that meets WCAG AA against the brand red.

### Supabase settings the team changes once

In the Supabase Dashboard, under Authentication > URL Configuration:
- **Site URL:** `https://cohort-nine-mu.vercel.app`.
- **Redirect URLs:** add `http://localhost:5173/**` for local development.
- **Email confirmation:** stays on. The sign-up page handles both on and off.

### Release

1. Apply the migration to GradProj through the connector, recorded under the file's version.
2. Insert the Rivermere University row.
3. Merge to `main`; Vercel deploys.

## Testing

- **Database** (against the test database built by `npm run db:test:reset`). Its stub of
  Supabase's `auth` schema (`scripts/db/supabase-stub.sql`) includes `auth.users`, the migrations
  create the trigger on it, and `createAuthOnlyUser` in `apps/api/test/support/db.ts` already
  inserts into it. The cases:
  - an account with no `app_metadata` joins the open university as a student, with its
    `full_name`;
  - with no open university, it gets no `users` row;
  - university-created accounts behave as before;
  - a second open university is rejected.
- **Web:**
  - the sign-up page: confirmation-needed path, session path, error path, and the links between
    the two pages;
  - a signed-in visitor is redirected away from `/signup`;
  - the new sign-in copy;
  - the shell shows the university name and role;
  - the existing shell, dashboard and registration tests still pass, with updated copy where the
    copy changed.
- **Whole workspace:** `npm run typecheck && npm test` and `npm run build:vercel` pass.

## Left to the builder

- The stylesheet's structure, class names, spacing, type scale and other colours, within the
  brand above.
- How the migration and trigger are tested (pgTAP in `supabase/tests/rls_smoke_test.sql`, or API
  tests through the owner connection), as long as the cases above are covered.
- The migration's timestamp and the index name.
- Whether `RequireAuth`'s "Loading…" uses the shell frame.
