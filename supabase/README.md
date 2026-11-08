# Cohort database

PostgreSQL schema for the unified university platform described in *A Unified AI-Powered SaaS
Platform for Universities* (sections 6.5 Core data model, 6.6 Multi-tenancy and authorisation,
7 AI layer, 8 Security and privacy). It runs on Supabase: project **GradProj**
(`gejismdqvjuygtxibdhs`, eu-west-1, Postgres 17).

100 tables, 216 row-level security policies, 12 functions clients call, and 30 tables whose
changes are written to an immutable audit log.

## Status

| Migration | In GradProj |
| --- | --- |
| `20261022134334_foundation` to `20261022140102_hardening` (11 files) | Applied |
| `20261022150000_builtin_time_ranges` | **Pending**: apply with `supabase db push` (below) |
| `20261025120000_prisma_compat` | **Pending**: apply with `supabase db push` (below) |
| `20261025120100_api_role` | **Pending**: apply with `supabase db push` (below) |

`builtin_time_ranges` replaces a custom `timerange` type with built-in ranges. On Supabase the
constructor functions of a custom range type are created as `supabase_admin`, so the earlier
migrations could not take `EXECUTE` on them away from `anon`. It contains `DROP` statements, which
the Supabase connector used to build this could not run without an interactive confirmation.
`prisma_compat` also drops an index, to replace it with an equivalent exclusion constraint.
`api_role` creates `cohort_api` without a password; set one in GradProj with
`alter role cohort_api with password '...'`.

## Apply and test

```bash
npx supabase link --project-ref gejismdqvjuygtxibdhs
npx supabase db push            # applies only migrations GradProj has not recorded yet

npx supabase start              # local stack (Docker)
npx supabase test db            # runs supabase/tests/rls_smoke_test.sql through pg_prove
```

`tests/rls_smoke_test.sql` seeds two universities and eight users, then signs in as each of them
and checks what they can and cannot see or change. It runs in one transaction and rolls back.
It also runs with plain `psql -f` against any database built from these migrations.

## Migrations

| File | Contents |
| --- | --- |
| `foundation` | Extensions (`pgcrypto`, `vector`, `btree_gist`), the `private` helper schema, default privileges |
| `identity` | Tenants, users, roles and permissions, profiles, privacy settings, consent; sign-up trigger; `directory_search` |
| `governance` | Audit log, data access log, break-glass access grants, retention policies, legal holds |
| `academic_structure` | Faculties, departments, programmes, buildings, rooms, terms, calendar, courses, offerings, sections, timetable |
| `enrollment_and_records` | Enrolments and waiting lists, advisors, grade scales, grading weights, append-only grades, GPA, standing; registration rules |
| `learning_and_assessment` | Materials, topics, question bank and answer keys, rubrics, assessments, attempts, answers, scores, appeals |
| `attendance_and_exams` | Attendance sessions with rotating QR codes, check-ins, exam sessions, seat plans |
| `communication` | Course chat and direct messages, moderation, announcements, events, surveys, office hours, appointments, notifications |
| `support_and_campus` | Tickets and comments, workflow automation, IT incidents, lost and found, campus map, emergency alerts |
| `ai_and_analytics` | Model registry, prompt templates, AI switches and budgets, documents and embeddings, hybrid search, AI logs, grading suggestions, risk scores |
| `hardening` | Final privilege sweep; fails if any table lacks row-level security |
| `builtin_time_ranges` | Room-clash rule on built-in ranges; drops the custom range type |
| `prisma_compat` | Unique keys on `(foreign key, tenant_id)` and an exclusion constraint for one active prompt version, which the API's Prisma schema needs |
| `api_role` | The `cohort_api` login role the backend API connects as; it has no privileges of its own and switches to `authenticated` for each request |

## Design rules

**Tenancy.** Each university is a tenant and every table carries `tenant_id`. References between
tenant-scoped rows are composite foreign keys on `(id, tenant_id)`, so a row cannot point at another
university's data even when row-level security is bypassed.

**Identity.** A user is a Supabase Auth account. The backend provisions accounts (invite or bulk
import) with `app_metadata = {"tenant_id", "user_type", "institutional_id"}`. A trigger then creates
the `users` row, the profile and the default role. `app_metadata` is only writable with the service
role; the user-editable `user_metadata` supplies the display name only.

**Authorisation (paper 6.6).** Roles grant permissions such as `academic.manage` or
`ai.settings.manage`. Teaching, enrolment and advising access is attribute-based instead: a lecturer
sees grades only for sections they teach, an advisor sees their advisees, a student sees their own
record. Policies call helpers in the `private` schema (`private.teaches_offering(...)`,
`private.can_view_student(...)`, ...). That schema is not exposed through the API.

**Administrators see aggregates by default.** To open one student's record they call
`open_record_access(student, reason, minutes)`. It writes the reason to `data_access_log`, which
the student can read, and grants time-limited access.

**Records stay exact.**
- Published grades never change; a correction is a new entry that supersedes the old one, with a reason.
- Consent records, risk scores, GPA snapshots, the audit log and the access log are append-only.
- Room double-booking, overlapping appointments, exam-room capacity and grading weights over 100% are rejected by the database.

**Exams and attendance.** Students start and submit attempts only through functions.
- The timer runs on the server, and answers stop saving at the deadline.
- Answer keys and scores live in separate tables that students cannot read until release.
- QR check-in codes rotate every 30 seconds and are checked against a secret no client can read.

**AI (paper 7).**
- Every interaction, grading suggestion and risk score records the model version and its inputs.
- `match_chunks` runs with the caller's rights, so the permission filter applies before retrieval.
- AI grade suggestions are visible only to teachers.
- Students see their own risk prediction only after opting in.
- Question clusters smaller than the tenant's `min_group_size` are hidden.

**Service role.** Backend workers (AI gateway, ingestion, prediction, notifications) use the
service role, which bypasses row-level security. Signed-in clients use the `authenticated` role.
`anon` has no access.

## Functions clients call

| Function | Who | What |
| --- | --- | --- |
| `enroll_in_section`, `drop_section` | Students | Registration with prerequisite, credit-limit, clash and capacity checks; waiting list |
| `start_attempt`, `submit_attempt` | Students | Server-timed attempts; deterministic questions scored on submission |
| `check_in` | Students | Attendance by QR code, or name entry for the teacher to confirm |
| `attendance_qr_token` | Teachers | The current QR code for a session |
| `open_record_access` | Administrators | Audited, time-limited access to one student's record |
| `directory_search` | Everyone | People search with each field masked by its owner's privacy settings |
| `start_direct_channel` | Everyone | Direct messages, if the other person's privacy settings allow it |
| `register_for_event`, `submit_survey_response` | Everyone | Capacity and waiting list; one (optionally anonymous) answer per person |
| `match_chunks` | Assistants | Hybrid vector and keyword search over documents the caller may see |

## Mapping to the paper's data model (6.5)

Every entity in section 6.5 has a table. Where the schema differs:

- **Complaint** and **Request** are `tickets` kinds, so they share one workflow, SLA and queue.
- **QuestionTag** links questions to course `topics`, which also hold learning outcomes for the heatmap.
- **Submission** is split into `submissions` (attempts), `submission_answers`, `submission_files` and
  `answer_scores`, so students can autosave answers without seeing scores.
- Added where a feature needed one:
  - Teaching structure: `programs`, `student_programs`, `section_instructors`, `advisor_assignments`, `grade_components`.
  - Materials: `material_folders`, `materials`, `material_versions`.
  - Communication: `office_hours`, `surveys`, `channel_members`, `message_reports`.
  - IT and safety: `incidents`, `emergency_alert_deliveries`.
  - AI: `ai_feature_settings`, `ai_budgets`, `prompt_templates`, `ai_grade_suggestions`, `grading_calibrations`, `risk_alerts`.
  - Governance: `record_access_grants`, `legal_holds`.

## Not covered yet

- **Retention enforcement.** Schedules and legal holds are stored; the deletion job (for example with `pg_cron`) is not written.
- **File storage.** Tables hold object paths; Supabase Storage buckets and their policies are not set up.
- **Term-end processing.** Computing final grades, GPA snapshots and academic standing is left to a backend job.
- **P3 analytics.** The governed metrics layer and forecasts behind the administrator assistant are not modelled yet.
- **Data residency.** GradProj is in eu-west-1. Section 8.1 notes that Egypt's Law 151 restricts moving personal data abroad, so real student data may need an in-country region.
