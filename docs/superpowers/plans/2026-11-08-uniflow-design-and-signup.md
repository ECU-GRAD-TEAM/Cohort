# Cohort's new look, sign-up and preview tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Students can sign up and sign in to Cohort, restyled after the team's UniFlow mock-up, land at Rivermere
University as students, register for courses, and see the rest of the workspace as labelled
preview tabs.

**Architecture:** A migration marks one university as open for sign-up and extends the existing
`auth.users` trigger so an account without university details joins it as a student. The web app
signs up through Supabase Auth directly, like sign-in. A plain-CSS stylesheet with brand tokens
restyles the shell and the auth pages. Seven preview pages render static sample data inside the
same shell.

**Tech Stack:** Postgres (Supabase), Vitest against the local test database, React 19,
React Router 8, TanStack Query 5, Vite 8, plain CSS, MSW 3 in web tests.

**Spec:** `docs/superpowers/specs/2026-11-08-uniflow-design-and-signup-design.md`

## Global Constraints

- **No new dependencies.** Existing pins only, including react 19.3.1, react-router 8.5.0,
  @tanstack/react-query 5.104.5, vite 8.3.5 and msw 3.0.3. Styling is plain CSS in one global
  stylesheet, `apps/web/src/styles.css`, imported only by `apps/web/src/main.tsx`.
- **Brand:**
  - name "Cohort" (never "UniFlow" anywhere in the app), tagline "Your university, in sync.", brand red `#B81104`;
  - the lettermark is a red rounded square with a white "c", then the word "Cohort".
- **`apps/web/index.html`:**
  - title "Cohort — Your university, in sync";
  - `<meta name="theme-color" content="#B81104">`;
  - `<meta name="description" content="Cohort connects courses, schedules, student support and
    campus operations in one responsive university workspace.">`.
- **Copy, exactly:**
  - **Sign-in page:** "Sign in to Cohort" (unchanged); "Email", "Password", "Sign in"; "New to Cohort?" with
    the link "Create an account".
  - **Sign-up page:**
    - "Create your student account";
    - fields "Full name", "Email" and "Password", with the hint "At least 6 characters";
    - the button "Create account";
    - "Already have an account?" with the link "Sign in";
    - after success, "Check your inbox. We sent a confirmation link to <email>." with the link
      "Back to sign in".
  - **Sidebar:**
    - "ONE CONNECTED CAMPUS", "WORKSPACE";
    - role labels "Student", "Teaching staff", "Administrator", "IT staff";
    - "A little more connected.", "A whole world of possibilities.", "Explore your campus ↗".
  - **Header:** the "☰" button labelled "Toggle navigation", and "Sign out".
  - **Footer:** "Cohort" and "Your university, in sync."
  - **Phone bar:** "More".
  - **Preview tag and banner:** "Preview", and "Preview: sample data. This part of Cohort isn't
    connected yet."
  - **Disabled-action note:** "Not available in the preview."
- **Unchanged copy:** "Your account is not linked to a university yet. Contact your
  administrator." and "Loading…" (U+2026) stay exactly as they are.
- **Sign-up is a student account only.** It never grants anything but a student account at the
  one open university. No service-role key anywhere.
- **Preview pages:**
  - no API calls;
  - sample names are clearly made up ("Sample course A"), never real-looking course codes;
  - controls that would act are `disabled` and carry the note above.
- **Responsive and accessible:**
  - phone layout below 900 px;
  - landmarks `aside`, `header`, `nav` (labelled "Main" and "Mobile"), `main`, `footer`;
  - visible focus outlines, labelled controls, text contrast that meets WCAG AA.
- **Tests:**
  - web tests stay strict: MSW `onUnhandledFrame: "error"`, `afterEach(cleanup)`, output with no
    warnings;
  - API and database tests need `TEST_DB_ADMIN_URL`, `TEST_DATABASE_URL` and
    `TEST_API_DATABASE_URL`, with port 54329 in this container (see `README.md`).
- **Schema changes:** only in new files under `supabase/migrations/`. Never run `prisma migrate`.
  Regenerate `apps/api/prisma/schema.prisma` with `npm run db:pull -w @cohort/api`.

## Review Focus

1. **Spoofed university details.** A sign-up that puts `tenant_id`/`user_type` in
   `user_metadata` must still join the open university as a student. Test in Task 1.
2. **Signed-in visitor on `/signup`.** They are sent to the dashboard and never shown the form.
   Test in Task 3.
3. **Phone menu.** After the visitor picks a link, the opened sidebar closes. Test in Task 2.
4. **Preview pages.** They fetch nothing beyond the shell's `/me`. Test in Task 4.
5. **Suspended open university.** With the open university suspended, a sign-up stays unlinked
   and nothing errors. Test in Task 1.

---

### Task 1: Open sign-up in the database

**Files:**
- Create: `supabase/migrations/20261108120000_open_signup.sql`
- Modify: `apps/api/test/support/db.ts` (add `withOwnerTransaction`; reword `createAuthOnlyUser`'s
  doc comment, which says no row is ever created, to say "when no university is open for sign-up")
- Modify: `apps/api/prisma/schema.prisma` (regenerated)
- Modify: `supabase/README.md` (status and migrations tables, plus a short "Open sign-up"
  paragraph)
- Test: `apps/api/test/open-signup.test.ts`

**Interfaces:**
- Produces:
  - column `public.tenants.open_signup boolean not null default false`;
  - unique index `tenants_one_open_signup on public.tenants ((true)) where open_signup`;
  - a new version of `private.handle_new_auth_user()`.
- Produces (test support): `withOwnerTransaction<T>(fn: (query: <R>(sql: string, params?:
  unknown[]) => Promise<R[]>) => Promise<T>): Promise<T>`. It runs `fn` on one owner connection
  inside `begin` … `rollback`, always rolling back.

- [ ] **Step 1: Write the failing tests** in `apps/api/test/open-signup.test.ts`

  Every test runs inside `withOwnerTransaction`, so the open university never becomes visible to
  other test files. `me.test.ts` relies on unlinked accounts.

  Helpers inside the transaction:
  - `university(open: boolean, status = "active")` inserts a tenant with a random slug and returns
    its id.
  - `signUp(appMeta, userMeta)` inserts into `auth.users (id, email, raw_app_meta_data,
    raw_user_meta_data)`. The email is `Nadia-<k>@Example.TEST`, mixed case on purpose. It returns
    the id.
  - `linked(id)` selects the user's `users.tenant_id` and `user_type`, `person_profiles.display_name`,
    and the `roles.key` values from `user_roles`.

  The tests:
  - **"joins the open university as a student":**
    - setup: an open university;
    - action: `signUp({}, { full_name: "Nadia New" })`;
    - expected: `tenant_id` is the open university, `user_type` is `student`, `email` is the
      lowercased address, `display_name` is `Nadia New`, and the role keys are `["student"]`.
  - **"ignores university details sent as user metadata":**
    - setup: an open university and another university B;
    - action: `signUp({}, { tenant_id: B, user_type: "administrator", full_name: "Mal" })`;
    - expected: the account is at the open university with `student`.
  - **"leaves the account unlinked when no university is open":**
    - action: `signUp({}, {})`;
    - expected: no `users` row.
  - **"leaves the account unlinked when the open university is suspended":**
    - setup: `university(true, "suspended")`;
    - action: `signUp({}, {})`;
    - expected: no `users` row.
  - **"keeps university-created accounts as they are":**
    - setup: an open university and university B;
    - action: `signUp({ tenant_id: B, user_type: "teaching_staff" }, {})`;
    - expected: the account is at B as `teaching_staff`.
  - **"keeps partial university details unlinked":**
    - setup: an open university;
    - action: `signUp({ tenant_id: <open> }, {})`;
    - expected: no `users` row.
  - **"allows only one open university":**
    - action: a second `university(true)`;
    - expected: it rejects with `code: "23505"`.

- [ ] **Step 2: Run them to verify they fail**

  Run: `npm test -w @cohort/api -- open-signup.test.ts`
  Expected: FAIL. Column `open_signup` does not exist, and `withOwnerTransaction` is not exported.

- [ ] **Step 3: Write the migration**

  The file contains:
  - `alter table public.tenants add column open_signup boolean not null default false;`
  - the unique partial index above, with a comment saying at most one university is open for
    sign-up;
  - `create or replace function private.handle_new_auth_user()`, keeping the same signature,
    `security definer` and `set search_path = ''`.

  The new rule, as a declare/begin block. It changes only what happens when both values are
  missing:

  ```sql
  if v_tenant is null and v_type is null then
    -- Self sign-up: join the university open for sign-up, as a student. Clients can only set
    -- user_metadata, so nothing they send can choose the university or the user type.
    select t.id into v_tenant from public.tenants t where t.open_signup and t.status = 'active';
    v_type := 'student';
  end if;
  if v_tenant is null or v_type is null then
    return new;
  end if;
  ```

  The insert into `public.users` and the `full_name` profile update stay as they are.

- [ ] **Step 4: Add `withOwnerTransaction` to `apps/api/test/support/db.ts`**

  It uses `ownerPool.connect()` and always runs `rollback` and `release()` in `finally`.

- [ ] **Step 5: Rebuild the test database, regenerate the Prisma schema, and run the tests**

  Run: `npm run db:test:reset && npm run db:pull -w @cohort/api && npm test -w @cohort/api && npm run typecheck -w @cohort/api`
  Expected:
  - `cohort_test ready`;
  - `schema.prisma` gains `open_signup Boolean @default(false)` on `tenants`, and nothing else
    changes except the index;
  - every API test passes, including the 7 new ones;
  - no type errors.

- [ ] **Step 6: Update `supabase/README.md`**

  - Add the migration to the Status table as pending in GradProj.
  - Add it to the Migrations table: "Open sign-up: one university can accept self sign-ups as
    students".
  - Add a short "Open sign-up" paragraph under Design rules: how it works, how to choose the
    university (`update public.tenants set open_signup = true where slug = '…'`), and that the
    domain check is still to come.

- [ ] **Step 7: Commit**

  `git add` the files above, then `git commit -m "feat: let one university accept self sign-ups as students"`.

---

### Task 2: The new look for the shell and the sign-in page

**Files:**
- Create: `apps/web/src/styles.css`
- Create: `apps/web/src/navigation.ts`
- Create: `apps/web/src/components/BrandMark.tsx`
- Create: `apps/web/src/components/AuthLayout.tsx`
- Modify: `apps/web/src/AppShell.tsx`, `apps/web/src/pages/LoginPage.tsx`,
  `apps/web/src/main.tsx` (import `./styles.css`), `apps/web/index.html`
- Modify: `apps/web/src/lib/format.ts`
- Test: `apps/web/src/lib/format.test.ts`, `apps/web/src/AppShell.test.tsx`,
  `apps/web/src/App.test.tsx`

**Interfaces:**
- Produces:
  - `type NavItem = { to: string; label: string; preview: boolean }`.
  - In `navigation.ts`, `navItems: NavItem[]` starts as Dashboard `/` and Registration
    `/register`, both with `preview: false`. Task 4 appends to it.
  - `mobileNavPaths: string[]` starts as `["/", "/register"]`; Task 4 adds two more.
  - `BrandMark()` is the lettermark. `AuthLayout({ children })` is the centred auth card with
    `BrandMark` and the tagline above `children`. Task 3 uses both.
  - In `format.ts`:
    - `formatUserType(type: UserType): string`, giving "Student", "Teaching staff",
      "Administrator" or "IT staff";
    - `initials(displayName: string): string`, built from the first letters of the first and
      last words, upper-cased, with "?" when the name is empty.

- [ ] **Step 1: Write the failing tests**

  **`format.test.ts`:**
  - `formatUserType`: all four values give their labels.
  - `initials`: "Sara Student" gives "SS", "nadia" gives "N", "Ana María de la Cruz" gives "AC",
    and "  " gives "?".

  **`AppShell.test.tsx`:**
  - Replace each assertion on the combined "<name> · <university>" string. Assert
    `within(screen.getByRole("banner")).getByText("Sara Student")`, and do the same for "Omar
    Other".
  - **"shows the student's university and role in the sidebar":** inside
    `getByRole("complementary")`, expect "Smoke University A", "ONE CONNECTED CAMPUS",
    "WORKSPACE" and "Student".
  - **"shows the student's initials":** the banner contains "SS".
  - **"links to both pages":** query inside `getByRole("navigation", { name: "Main" })`, then
    check the "Dashboard" link's href is "/" and the "Registration" link's is "/register".
  - **"opens and closes the menu on a phone":**
    - the "Toggle navigation" button has `aria-expanded="false"`;
    - after a click it is `"true"`;
    - after clicking the Main nav's "Registration" link it is `"false"` again.
  - **"keeps the not-linked message":** existing test, unchanged copy. Also assert there is no
    navigation named "Main".

  **`App.test.tsx` and `AppShell.test.tsx`:** the sign-in heading stays "Sign in to Cohort", so
  those assertions don't change.

- [ ] **Step 2: Run them to verify they fail**

  Run: `npm test -w @cohort/web`
  Expected: FAIL. The new helpers are missing, and the old copy and markup don't match.

- [ ] **Step 3: Implement**

  - The two `format.ts` helpers.
  - `navigation.ts`.
  - `BrandMark` and `AuthLayout`.
  - **The new `AppShell` markup:**
    - an `aside` holding the lettermark link to "/", the university card, WORKSPACE and the role,
      the "Main" nav built from `navItems` (with a "Preview" tag where `preview` is true), and the
      sidebar foot;
    - a `header` holding the menu button, avatar initials, name, university, and Sign out;
    - `main` with the `<Outlet/>`, then the `footer`;
    - a "Mobile" nav built from `mobileNavPaths`, plus a "More" button that opens the sidebar.
  - **Menu state:** the open/closed state lives in `AppShell` and closes on any nav click.
  - **The not-linked and error screens:** they keep the header (with Sign out) and the footer,
    but show no navs.
  - **`LoginPage`:** keeps its behaviour, now inside `AuthLayout` with the new heading.
  - **`index.html`:** the meta values from Global Constraints.
  - **`styles.css`:**
    - tokens on `:root`, at least `--brand: #B81104`, a darker hover shade, surface and text
      colours, radius and shadow;
    - the layout grid (sidebar, header, main, footer);
    - the auth card;
    - a phone layout under 900 px: the sidebar becomes an off-canvas panel toggled by a class,
      and the mobile nav is a fixed bottom bar;
    - focus-visible outlines;
    - `.preview-tag` and `.preview-banner` for Task 4.

- [ ] **Step 4: Run the tests and the type-check**

  Run: `npm test -w @cohort/web && npm run typecheck -w @cohort/web`
  Expected: all web tests pass with no warnings, and there are no type errors.

- [ ] **Step 5: Check it visually**

  This check is a throwaway, and nothing from it is committed.
  1. Run `npm run build -w @cohort/web` and `npx vite preview` in `apps/web`.
  2. Use Playwright to screenshot `/login` at 1280×800 and at 390×844. Use your scratchpad, not
     the repo.
  3. Look at the screenshots: brand red, the lettermark, a centred card, no overflow at phone
     width.

  The shell needs a session, so the final review checks it on the deployed preview.

- [ ] **Step 6: Commit**

  `git add` the files above, then `git commit -m "feat: restyle the shell and sign-in page"`.

---

### Task 3: Sign-up

**Files:**
- Modify: `apps/web/src/auth/AuthProvider.tsx`
- Modify: `apps/web/test/render.tsx`
- Create: `apps/web/src/pages/SignUpPage.tsx`
- Modify: `apps/web/src/App.tsx`, `apps/web/src/pages/LoginPage.tsx`
- Modify: `README.md`
- Test: `apps/web/src/pages/SignUpPage.test.tsx`, `apps/web/src/auth/AuthProvider.test.tsx`

**Interfaces:**
- Consumes: `AuthLayout` (Task 2).
- Produces:
  - `AuthClientLike` now includes `"signUp"`.
  - `useAuth().signUp(fullName: string, email: string, password: string): Promise<{
    needsConfirmation: boolean }>`. It calls `auth.signUp({ email, password, options: { data: {
    full_name: fullName }, emailRedirectTo: \`${window.location.origin}/\` } })`. It throws
    `Error(error.message)` on error. `needsConfirmation` is `data.session === null`.
  - `createFakeAuth(options)` gains `signUpError?: string` and `signUpSession?: boolean`.
    - The fake `signUp` is a `vi.fn`.
    - With `signUpSession`, it sets the session to `fakeSession`, notifies `SIGNED_IN`, and returns
      it.
    - Otherwise it returns `{ data: { user: fakeSession.user, session: null }, error: null }`.

- [ ] **Step 1: Write the failing tests**

  **`SignUpPage.test.tsx`:**
  - **"creates an account and asks the student to confirm their email":**
    - action: `renderApp({ route: "/signup", auth })`; type "Nadia New", "nadia@x.test" and
      "secret-pass"; click "Create account";
    - expected: `auth.signUp` was called with `{ email: "nadia@x.test", password: "secret-pass",
      options: { data: { full_name: "Nadia New" }, emailRedirectTo:
      expect.stringMatching(/\/$/) } }`;
    - expected: a `status` role with "Check your inbox. We sent a confirmation link to
      nadia@x.test.";
    - expected: a link "Back to sign in" to `/login`.
  - **"signs the student straight in when no confirmation is needed":** with `signUpSession: true`
    → the "Dashboard" heading.
  - **"shows why sign-up failed":** with `signUpError: "User already registered"` → an `alert`
    with that text; the "Create account" button is enabled again.
  - **"sends a signed-in visitor to the dashboard":** route `/signup` with `fakeSession` → the
    "Dashboard" heading; no "Create your student account" heading.
  - **"links sign-in and sign-up":**
    - `/login` has the link "Create an account" with href `/signup`;
    - `/signup` has the link "Sign in" with href `/login`;
    - the hint "At least 6 characters" is shown.

  **`AuthProvider.test.tsx`:** **"signUp reports when confirmation is needed":** `signUp` resolves
  `{ needsConfirmation: true }` with the default fake, and `false` with `signUpSession: true`.

- [ ] **Step 2: Run them to verify they fail**

  Run: `npm test -w @cohort/web -- SignUpPage.test.tsx AuthProvider.test.tsx`
  Expected: FAIL. The `/signup` route does not exist, and `signUp` is not a function.

- [ ] **Step 3: Implement**

  - `AuthProvider.signUp` and the fake auth's `signUp`.
  - **`SignUpPage`:**
    - it has the same form pattern as `LoginPage`;
    - `autoComplete` is `name`, `email` and `new-password`;
    - the button is disabled while submitting;
    - on success it shows the confirmation `status` or navigates to `/`;
    - a signed-in visitor gets `<Navigate to="/" replace />`.
  - **Routing:** add `/signup` next to `/login` in `App.tsx`.
  - **Sign-in page:** add the "New to Cohort? Create an account" link to `LoginPage`.

- [ ] **Step 4: Run all web tests and the type-check**

  Run: `npm test -w @cohort/web && npm run typecheck -w @cohort/web`
  Expected: all web tests pass with no warnings, and there are no type errors.

- [ ] **Step 5: Update `README.md`**

  Add a "Sign-up" subsection under "Running Cohort locally":
  - Self sign-ups join the university open for sign-up as students (see `supabase/README.md`).
  - In the Supabase Dashboard, under Authentication > URL Configuration, set the Site URL to the
    production address `https://cohort-nine-mu.vercel.app`.
  - Also there, add `http://localhost:5173/**` to Redirect URLs.
  - With "Confirm email" on, students confirm by email before they can sign in.

- [ ] **Step 6: Commit**

  `git add` the files above, then `git commit -m "feat: let students create an account"`.

---

### Task 4: Preview tabs

**Files:**
- Create: `apps/web/src/previews/sampleData.ts`
- Create: `apps/web/src/previews/PreviewPage.tsx`
- Create: `apps/web/src/previews/CoursesPreview.tsx`, `SchedulePreview.tsx`,
  `AssignmentsPreview.tsx`, `MessagesPreview.tsx`, `SupportPreview.tsx`, `CampusPreview.tsx`,
  `AssistantPreview.tsx` (all in `apps/web/src/previews/`)
- Modify: `apps/web/src/navigation.ts`, `apps/web/src/App.tsx`, `apps/web/src/AppShell.tsx`
- Modify: `apps/web/src/styles.css`
- Test: `apps/web/src/previews/previews.test.tsx`

**Interfaces:**
- Consumes: `navItems` and `mobileNavPaths` (Task 2); the `.preview-tag` and `.preview-banner`
  styles.
- Produces:
  - `PreviewPage({ title, children })`: the heading `<h1>{title}</h1>`, then the banner with the
    exact preview copy in a `role="note"`, then the content.
  - `navItems` gains, in this order, with `preview: true`:
    - Courses `/courses`
    - Schedule `/schedule`
    - Assignments `/assignments`
    - Messages `/messages`
    - Support `/support`
    - Campus `/campus`
    - AI assistant `/assistant`
  - `mobileNavPaths` becomes `["/", "/register", "/courses", "/schedule"]`.
  - The sidebar foot gets "Explore your campus ↗" linking to `/campus`.

- [ ] **Step 1: Write the failing tests** in `previews.test.tsx`

  - **`it.each` over the seven preview items** (from `navItems.filter((i) => i.preview)`):
    "<label> is a labelled preview".
    - Render the route with `fakeSession`.
    - Expect the heading "<label>".
    - Expect a `note` with "Preview: sample data. This part of Cohort isn't connected yet."
    - Inside the Main nav, the link whose name starts with "<label>" (`name: new RegExp(\`^${label}\`)`)
      contains the text "Preview". The tag is visible text, so it is part of the link's name.
  - **"previews fetch nothing but the signed-in user":**
    - Record every request with `server.events.on("request:start", …)`.
    - Visit each preview route in turn (`/courses` through `/assistant`).
    - Expect every recorded pathname to be `/me`.
  - **`it.each`** over:
    - `["/messages", "Send"]`
    - `["/support", "Submit request"]`
    - `["/assistant", "Ask"]`

    "<path>'s <button> is disabled": the button is `disabled`, and "Not available in the
    preview." is shown.
  - **"links the campus preview from the sidebar":** "Explore your campus ↗" has href `/campus`.

- [ ] **Step 2: Run them to verify they fail**

  Run: `npm test -w @cohort/web -- previews.test.tsx`
  Expected: FAIL. The routes and nav items don't exist.

- [ ] **Step 3: Implement the sample data, the seven pages, the routes and the nav items**

  The content follows the spec's table:

  | Page | Sample content |
  | --- | --- |
  | Courses | course cards with materials and a progress bar |
  | Schedule | a Monday-to-Sunday grid |
  | Assignments | items with due dates and status |
  | Messages | a conversation list and a thread, with a disabled message box and "Send" |
  | Support | tickets with status, and a "New request" form with a disabled "Submit request" |
  | Campus | a map placeholder and a list of buildings and services |
  | AI assistant | a sample question and answer, with a disabled input and "Ask" |

  Every name in `sampleData.ts` is clearly made up: "Sample course A", "Sample course B",
  "Sample Hall".

- [ ] **Step 4: Run all web tests and the type-check**

  Run: `npm test -w @cohort/web && npm run typecheck -w @cohort/web`
  Expected: all pass with no warnings, and there are no type errors.

- [ ] **Step 5: Check the whole workspace and the Vercel build**

  Run, with the database variables exported: `npm run typecheck && npm test && npm run build:vercel`
  Expected:
  - every workspace passes;
  - `.vercel/output/static/index.html` contains the title "Cohort — Your university, in sync".

- [ ] **Step 6: Commit**

  `git add` the files above, then `git commit -m "feat: add preview tabs for the rest of the workspace"`.

---

### Task 5: Release (controller, after the final review)

This task changes GradProj and opens the pull request, so the controller runs it with the
Supabase and GitHub connectors. It is not a subagent task.

- [ ] **Step 1: Apply the migration to GradProj**

  1. Run `20261108120000_open_signup.sql` through the Supabase connector.
  2. Record it in `supabase_migrations.schema_migrations` with version `20261108120000` and name
     `open_signup`.
  3. Check that `list_migrations` shows it, and that `tenants.open_signup` exists.

- [ ] **Step 2: Add Rivermere University**

  1. Insert the tenant: slug `rivermere`, name `Rivermere University`, `data_region` `eu-west-1`,
     `open_signup` true.
  2. Check that its roles were seeded and that it is the only open university.
  3. Mark the migration as applied in `supabase/README.md`, and commit.

- [ ] **Step 3: Push and check the preview deployment**

  1. Push the branch. Vercel builds a preview.
  2. Check the preview as the earlier deployment was checked, from a Vercel Sandbox:
     - `/login` and `/signup` serve the app;
     - `/api/health` is 200.

- [ ] **Step 4: Open the pull request into `main`, and give the user the Site URL step**

  The Site URL step is the one in Task 3's README text.

---

## Revision 1: plug sign-up into the team's provisioning flow

GradProj's identity model changed while this plan ran (see the spec's "Revision" section). Task 1
is withdrawn and Task 5 is replaced, as the list below sets out. Tasks 2–4 stand. Tasks 6–8
follow, in order.

**Global Constraints, amended:**
- Role labels are "Student" (the caller has the `student` role), "Staff" (`staff`) and
  "Non-staff" (`non_staff` without the `student` role).
- Nothing in this branch writes to GradProj or adds a migration of its own. The repository's
  migrations mirror GradProj's, including `20261108195715`.

**Changes to earlier tasks:**
- **Task 1:** withdrawn, and its commits are reverted in Task 6.
- **Task 5:** replaced. There is no GradProj step. The release is a pull request into `main`,
  after a final review.

### Task 6: Withdraw open sign-up and merge `main`

**Files:**
- Revert: commits `d95eb3b` and `f2899d5`, in one revert commit. Afterwards
  `20261108120000_open_signup.sql`, `apps/api/test/open-signup.test.ts` and `withOwnerTransaction`
  are gone, and `schema.prisma` and `supabase/README.md` are back to their state before Task 1.
- Merge: `origin/main`. Expect conflicts in `apps/web/src/App.tsx`, `apps/web/src/AppShell.tsx`
  and `README.md`.
- Modify: `apps/web/src/navigation.ts`. Add
  `{ to: "/student-assistant", label: "Student assistant", preview: false }` after Registration.

**Interfaces:**
- Consumes: `main`'s `StudentAiPage` at route `student-assistant`.
- Produces: a branch that contains `main`. The shell keeps this branch's layout, with Student
  assistant as a real nav item.

- [ ] **Step 1: Revert Task 1**
  - Run `git revert --no-commit d95eb3b f2899d5`.
  - Commit as `revert: withdraw open sign-up; the team provisions accounts`.
- [ ] **Step 2: Merge `origin/main`**
  - **App.tsx:** keep this branch's routes and add main's `student-assistant` route inside the
    shell.
  - **AppShell.tsx:** keep this branch's version. The nav comes from `navigation.ts`, so drop
    main's hand-written `NavLink`s.
  - **README.md:** keep both sides' additions.
- [ ] **Step 3: Update the nav-order test**
  In `apps/web/src/previews/previews.test.tsx`, the test that pins the nav order now expects
  Student assistant after Registration.
- [ ] **Step 4: Verify the web app**
  - Run `npm test -w @cohort/web && npm run typecheck -w @cohort/web`. Every web test should pass.
  - Run `npm run typecheck -w @cohort/api`. It should be clean.
  - The API's database tests are expected to fail until Task 7: `main`'s migrations need columns
    the test stub lacks. Record the failure, don't fix it here.
- [ ] **Step 5: Commit the merge**
  Message: `merge: bring main (staff/non_staff model, Student assistant) into the sign-up branch`.

### Task 7: Bring the code in line with GradProj's account model

**Files:**
- Create: `supabase/migrations/20261108195715_provision_auth_accounts_after_trusted_metadata_update.sql`,
  copied byte for byte from `.superpowers/sdd/2026-11-08-uniflow-design-and-signup/` (it was
  copied from GradProj's recorded migration).
- Modify: `scripts/db/supabase-stub.sql`. `auth.users` gains `email_confirmed_at timestamptz` and
  `invited_at timestamptz`, plus any other column the migrations read; find them by grepping the
  migrations.
- Modify: `apps/api/prisma/schema.prisma`, regenerated with `db:pull`.
- Modify: `packages/contracts/src/me.ts` and its test.
- Modify: `apps/api/src/routes/me.ts`.
- Modify: `apps/api/test/support/db.ts`, `apps/api/test/**/*.test.ts` (as needed),
  `apps/web/src/lib/format.ts` and its test, `apps/web/src/AppShell.tsx`, `apps/web/test/server.ts`,
  and every web test fixture with a `userType`.

**Interfaces:**
- Produces:
  - `UserType = z.enum(["staff", "non_staff"])`.
  - `/me.roles` lists only active assignments: `assignment_status = 'active'`,
    `starts_at <= now`, `revoked_at` null, and `expires_at` null or in the future.
  - `formatRole(me: Pick<MeResponse, "userType" | "roles">): string` gives "Student", "Staff" or
    "Non-staff". It replaces `formatUserType`.
  - `seedUniversity` still returns `University`, with the same keys:
    - every user is created through `auth.users` with `email_confirmed_at` set, so it is active;
    - students are `non_staff`, with the `student` role granted in `user_roles`
      (`assignment_status 'active'`, `starts_at now()`);
    - the teacher is `staff` with `instructor`;
    - the admin is `staff` with `administrator`.
  - `createAuthOnlyUser` still produces an account with no `users` row.

- [ ] **Step 1: Make the test database build**
  - Add the migration file and extend the stub.
  - Run `npm run db:test:reset`. Expect `cohort_test ready`.
- [ ] **Step 2: Regenerate Prisma**
  - Run `npm run db:pull -w @cohort/api`.
  - The `user_type` enum becomes `staff`/`non_staff`. Keep the model names `users` and
    `auth_users`, re-applying the plan's rename script only if `db pull` undoes them.
- [ ] **Step 3: Write the failing tests**
  - **Contracts:** `MeResponse` rejects `student` and accepts `non_staff`.
  - **me.test.ts:**
    - "describes the signed-in student" expects `userType: "non_staff"` and `roles: ["student"]`.
    - A revoked role, an inactive role and a not-yet-started role are each left out.
  - **format.test.ts:** `formatRole` covers all three labels.
  - **AppShell test:** the sidebar shows "Student" for the default `/me`, which is now `non_staff`
    with roles `["student"]`.
- [ ] **Step 4: Implement**
  - Update the contracts, the `/me` role filter, `seedUniversity` and the fixtures.
  - Fix the API tests the model change breaks. Enrolment needs the `student` role. Keep each
    test's intent.
- [ ] **Step 5: Verify the whole workspace**
  With the database variables exported, run `npm run typecheck && npm test`. Everything passes
  with no warnings.
- [ ] **Step 6: Commit**
  Message: `fix: follow GradProj's staff/non_staff account model`.

### Task 8: Sign-up in the provisioning flow, and the final review's fixes

**Files:**
- Modify: `apps/web/src/AppShell.tsx`, `apps/web/src/pages/SignUpPage.tsx`,
  `apps/web/src/previews/sampleData.ts`, `apps/web/src/styles.css`, `README.md` and
  `supabase/README.md`, with their tests.

- [ ] **Step 1: Write the failing tests**
  - **Phone menu:**
    - opening it with ☰ or "More" moves focus to the first sidebar link;
    - Escape closes it and returns focus to the button that opened it;
    - "More" has `aria-expanded` and `aria-controls="sidebar"`.
  - **Loading:** while `/me` is pending, "Loading…" renders inside `main` within the shell frame.
  - **Sign-up:**
    - the password input has `minLength` 6;
    - after success, focus moves to the confirmation message.
  - **Assignments:** the preview includes "Sample midterm exam".
- [ ] **Step 2: Implement**
  - The four behaviours above.
  - `.auth-page` uses the soft brand background (`--brand-soft`, or a light gradient from it).
  - While the menu is open, the content behind it is `inert`.
- [ ] **Step 3: Rewrite the stale release documentation**
  - **README.md:**
    - Remove "Apply the pending migrations" and the `cohort_api` step's "pending" wording. GradProj
      has every migration in the repository, and `supabase/migrations` mirrors GradProj.
    - Describe sign-up: it creates the login; the team's trusted provisioning step links the
      account to ECU and grants roles; until then the person sees "not linked".
    - Keep the Site URL step.
    - Move the "Sign-up" subsection after step 8.
  - **supabase/README.md:** the status table shows every migration as applied, and points to
    `supabase_migrations` on GradProj as the source of truth.
- [ ] **Step 4: Verify**
  - Run `npm run typecheck && npm test && npm run build:vercel`. Everything passes.
  - `grep -ri uniflow apps packages` returns nothing.
- [ ] **Step 5: Commit**
  Message: `fix: keyboard-friendly phone menu, sign-up focus, and current setup docs`.
