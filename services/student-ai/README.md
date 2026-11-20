# Cohort Student AI service

Python/FastAPI orchestration service using Google's official `google-genai` SDK and the
Gemini Interactions API. The service and local playground use **Gemini 3.5 Flash-Lite only**.

## Setup

```bash
cd services/student-ai
python -m venv .venv
.venv/Scripts/activate  # Windows
# or: source .venv/bin/activate  # macOS/Linux and GitHub Codespaces
pip install -e .
cp .env.example .env
```

Set `GEMINI_API_KEY`, `COHORT_AI_INTERNAL_KEY`, `SUPABASE_URL`, and
`SUPABASE_PUBLISHABLE_KEY` in `.env`. The Supabase key must be a publishable key
(or legacy anon key), never a secret/service-role key.

Run the service with `python -m app.main`.

## Local Gemini playground

The optional Streamlit developer interface calls Gemini directly; it does not call the
student-facing FastAPI endpoint and does not require Fastify or Supabase.

```bash
pip install -e ".[playground]"
streamlit run playground/ui.py
```

Open `http://localhost:8501`. The playground binds to localhost only. Do not expose it
publicly: it has no user authentication and can incur API charges.

Features include Gemini chat, editable system prompt/model ID, thinking and output-token
controls, conversation history/reset, and best-effort token/cost estimates. The playground
uses synchronous SDK calls; production FastAPI uses asynchronous calls. The Interactions
API is documented as preview for this model, so verify availability in your Google AI
project. Temperature is not configurable for this model.

## Environment configuration

See `.env.example` for the complete template.

- `COHORT_AI_INTERNAL_KEY`: private service-to-service secret shared with Fastify.
- `STUDENT_AI_TITLE`, `STUDENT_AI_VERSION`: FastAPI metadata.
- `STUDENT_AI_HOST`, `STUDENT_AI_PORT`, `STUDENT_AI_RELOAD`: server settings.
- `STUDENT_AI_MAX_MESSAGE_CHARS`, `STUDENT_AI_MAX_HISTORY_MESSAGES`,
  `STUDENT_AI_MAX_CONTEXT_ITEMS`: request limits.
- `SUPABASE_URL`: Supabase project URL.
- `SUPABASE_PUBLISHABLE_KEY`: publishable key (legacy `SUPABASE_ANON_KEY` fallback accepted).
- `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_API_VERSION`: Gemini configuration.
- `GEMINI_THINKING_LEVEL`, `GEMINI_MAX_OUTPUT_TOKENS`: generation configuration.
- `PLAYGROUND_SYSTEM_PROMPT`, `PLAYGROUND_GEMINI_MODEL`: playground configuration.
- `PLAYGROUND_GEMINI_INPUT_USD_PER_MILLION`,
  `PLAYGROUND_GEMINI_OUTPUT_USD_PER_MILLION`: optional local cost estimates.

## Student-record retrieval and authorization

The production FastAPI service **does connect to the Supabase Data API**. It holds the
project URL and a publishable/legacy anon key, but never a Supabase secret or service-role
key. For each authenticated chat request:

1. Fastify authenticates the student and verifies the Supabase access token.
2. Fastify sends the verified student's access token and user ID to FastAPI over the
   private service-to-service channel, protected by `COHORT_AI_INTERNAL_KEY`.
3. FastAPI uses the publishable key plus that student's JWT to query the Supabase Data API.
   PostgreSQL grants and RLS policies remain the row-level authorization boundary.
4. Python uses fixed, allow-listed table and column selections. Gemini classifies the
   message into zero or more supported record intents; it never generates SQL, table names,
   IDs, or filters.
5. Python retrieves each selected record category and passes the resulting context to
   Gemini to compose the answer.

Supported personal record intents include profile (including the official institutional ID/student number), GPA/CGPA, attendance, published grades, course enrollments, the student's assigned timetable, degree progress, academic standing, exam schedule, course resources, assessment results, academic calendar, support requests, appointments, notifications, emergency alerts, events, announcements, lost-and-found listings, surveys, graduation audits, the student's officially assigned specialization with related curriculum and own elective-selection records, and the student's official course history across terms including repeated attempts, and the student's official financial summary and transaction history by academic term, and the student's assignment assessments, own submission status and released marks/feedback. Multiple categories can be retrieved
for one message. Classification is performed by Gemini only; there is no local keyword
or regex intent shortcut. Invalid or malformed classifier output fails closed to no
record lookup.

## Course catalogue and published offerings

The course_catalog intent reads the student_available_courses security-invoker view using
the student's JWT. It includes active catalogue courses and only published offerings, with
department, term, registration-window, section capacity and prerequisite/corequisite details.
Catalogue-only courses must not be described as offered in a term. A null registration-window
value means the official dates are insufficient to determine whether registration is open.
Section capacity is not remaining seat availability; no open-seat count is inferred without
authoritative enrollment and waitlist counts. The assistant does not infer programme eligibility
or registration approval and cannot register, add/drop, or reserve a seat. The capability is
read-only and supports English and Arabic.

## Student graduation audits

The graduation-audit intent reads only the student_graduation_audit security-invoker view
using the student's JWT. The view scopes each row to auth.uid() and the active tenant;
the underlying graduation_audits table also has an explicit student-ownership SELECT policy.
The assistant reports the official audit_status verbatim: only eligible means eligible,
while pending and requires_manual_review are not approval. It never independently calculates
or promises eligibility from CGPA, credits, attendance, or unmet requirements, and it never
claims that a degree has been awarded. Credits and CGPA are historical values recorded at the
audit timestamp. Linked policy thresholds are not guaranteed to be historical snapshots and
must not override the recorded status. Internal audit UUIDs are excluded from the AI context.
The feature is read-only and supports English and Arabic.

The Fastify-to-FastAPI identity forwarding contract and the database RLS policies must
be verified in the deployed environment. The internal key must never be exposed to the
browser. Do not treat a forwarded user ID alone as authorization.

## Student assignments

The assignments intent reads published assignment-kind assessments visible to the authenticated
student through the existing assessments RLS policy. It joins the student's own submission attempts
and published grade entries using the student's JWT. Assignment instructions, due/closing timestamps,
and the recorded late policy are returned where present. Marks and feedback are included only after
the assessment's grades_released_at timestamp has passed and only when the student's grade entry
is published. Draft assessments, other students' submissions, and unreleased grades are not exposed.
This feature is read-only; it cannot submit or modify assignments.

## Student financial transactions

The dedicated transaction-history intent reads only `student_financial_transaction_history`
with the authenticated student's JWT. It returns the student's recorded ledger entries,
newest first, with academic term, transaction type, status, amount, currency, reference,
and description where available. The assistant may filter returned rows by requested term,
type, or status, but must keep currencies separate and distinguish posted, pending, and
void transactions. This remains read-only; payments and ledger changes are not supported.

## Data handling and API behavior

Gemini Interactions requests use `store=False`. Cohort sends its recent conversation
history with each request rather than relying on provider-side conversation storage.
This does not replace a review of Google's data handling and retention terms.

The FastAPI `/v1/chat` endpoint returns one complete JSON response. Provider requests
are asynchronous, but token-by-token streaming is not exposed to Fastify or React.

Current scope includes conversational tutoring and read-only retrieval of the supported personal record categories above. Official-document RAG citations, conversation
persistence, selective memory, budgets, audit persistence, and provider privacy controls
remain outside this service's current implementation.


## Student financial summary

The financial assistant intent reads only `student_financial_summary` and
`student_financial_transaction_history` using the authenticated student's JWT.
The underlying `student_financial_transactions` ledger is tenant-scoped and protected
by RLS; authenticated students have SELECT only and cannot insert, update, or delete
financial records. Finance-system ingestion and authorized staff posting must be
performed through a separately secured university workflow.

Only posted transactions contribute to the outstanding balance:
charges and refunds increase the balance; payments, scholarships, and discounts
reduce it. Pending transactions are displayed separately and are not treated as
posted or paid. Totals remain separated by currency. If no official transactions
exist, the assistant must say the balance is unavailable—not report a zero balance.


## Student support tickets and requests

The `support_requests` intent reads the existing `student_support_requests`
security-invoker view with the authenticated student's JWT. It returns only tickets
submitted by that student, including category, subject, description, recorded status
and priority, assigned department, SLA/response/resolution timestamps, and public
comment history. The view filters comments to `is_internal = false`; internal staff
notes and AI triage metadata are not exposed. Ticket statuses are the database values
`open`, `in_progress`, `waiting_on_requester`, `escalated`, `resolved`, and
`closed`. There is no separate human-readable ticket reference field, so the assistant
must not present the internal UUID as a reference. This feature is read-only and cannot
create, edit, or close tickets.

## Instructor assignments and office hours

The instructor_office_hours intent resolves section assignments only from the authenticated
student's own student_timetable rows, then reads section_instructors and office_hours with
the same student JWT. It returns instructor role labels and official office-hour schedule
fields without exposing staff UUIDs. Current user_profiles and person_profile_emails RLS
policies restrict students to their own profile/contact records, so instructor names,
email addresses, and phone numbers are not queried or disclosed. The office_hours source
does not contain meeting-link or contact columns. The assistant must state these limitations
rather than infer instructor identities or contact details. This feature is read-only.


## Student complaints and incident-report limitation

The `complaints_incidents` intent reads only complaint-kind rows
(`request_kind=complaint`) from the existing `student_support_requests`
security-invoker view using the authenticated student's JWT. It includes only
that student's complaint tickets and public replies; internal comments, AI triage
metadata, and internal ticket UUIDs are excluded. The `incidents` and
`incident_tickets` tables are restricted by current RLS to operations staff,
so incident-report records cannot be retrieved or confirmed by the student
assistant. An empty complaint result must not be described as proof that no
incident report exists. This feature is read-only and does not create or modify
complaints or incident reports.



## Student enrollment and registration status

The `enrollments` intent reads the student's own rows directly from `enrollments`
using the authenticated student JWT and existing row-level security. It joins only
course and term records referenced by those enrollment rows or their linked course
offerings. The `student_enrollment_summary` security-invoker view supplies term-level
counts and registered credit hours.

The direct enrollment rows are necessary because the `student_courses` course-history
view excludes waitlisted enrollments. The assistant reports the database's recorded
statuses (enrolled, waitlisted, dropped, withdrawn, completed, failed, or incomplete)
and a waitlist position only when present. Course code, title, credit hours, enrollment
timestamps, and term registration/add-drop dates are shown only when returned by the
official linked records. The database has no pending enrollment status. No registration,
add/drop, withdrawal, or other record changes are supported.


## Student course materials and learning resources

The `course_resources` intent reads the existing `student_course_resources`
security-invoker view with the authenticated student's JWT. The view joins only
the student's own `enrolled` course offerings and returns published/released
materials plus published offering-scoped course-material documents with their
latest published document-version metadata. It supplies course and term labels,
resource title/description/kind, origin, availability, language, and effective
dates where available. The view enforces the student's own enrollment, material
publication/release time, document scope/status, and published-version rules.

This is a **resource-catalogue lookup**, not document-content retrieval. The view
deliberately omits Storage paths and file/page text; student Storage-object read
access has not been verified. The assistant can locate catalogue entries by
course, title, kind, description, and term, but must not claim to summarize or
explain file contents or generate source-grounded notes, flashcards, or questions
unless actual document text is separately supplied in authorized context. No
database schema change or migration is required. The feature is read-only.


## Student academic advising and degree progress

The `degree_progress` intent uses the existing `student_degree_progress` security-invoker view
for the official credit/course aggregate, then reads the authenticated student's own
`student_profile`, active programme curriculum, requirement groups, study-plan level labels,
course prerequisite/corequisite catalogue, and own enrollment attempts. It reports required
curriculum courses separately from selectable requirement-group options, including group course
counts and credit-hour constraints. A course is treated as completed only when an official
enrollment status is `completed` and any curriculum minimum grade-points threshold is met;
currently enrolled courses remain in progress. Prerequisite satisfaction uses the recorded
completed attempt and any prerequisite minimum grade-points threshold; a corequisite may also
be met by a currently enrolled attempt.

The existing aggregate progress view excludes graduation_project-category groups from its
totals; any such detailed group is shown separately and is not included in aggregate credits or
course counts. An unsatisfied prerequisite is described only as a potential planning/registration
issue, not a guaranteed registration block, because waivers, transfer credit, equivalencies and
registrar overrides may exist outside the returned records. Missing programme/curriculum/credit data is
reported as unavailable rather than estimated. This feature is read-only and does not register,
add/drop courses, or modify academic records. Retrieval uses the student's JWT and existing RLS;
no service-role key is used.


## Official document retrieval (Phase 2)

The assistant supports permission-aware retrieval from published PDF and DOCX documents. The student chat service embeds the question with `gemini-embedding-001` (1024 dimensions) and calls the existing `match_chunks` hybrid vector/keyword RPC with the student's verified access token. Database RLS applies tenant, department, role, published-version, and enrolled-offering scope before passages are returned. Answers cite source title, version, and PDF page when available.

### Ingestion worker

Configure `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `GEMINI_API_KEY`, and `AI_DOCUMENTS_BUCKET` only in a separately protected ingestion-worker environment. Never add the service-role key to the FastAPI chat service or browser. Upload source files to the private `university-documents` bucket, create the corresponding `documents` and `document_versions` rows through the university's authorized document workflow, and set `storage_path`, `published_at`, `effective_from`, and the document's published status. Then run `python -m app.ingest_documents`. The worker extracts page-aware PDF text and DOCX paragraphs/tables, chunks content with overlap, generates 1024-dimensional retrieval-document embeddings, and writes chunk/embedding rows. It is idempotent for unchanged content hashes. Scanned PDFs without an embedded text layer require OCR before ingestion; OCR is not included.

The bucket is private and student reads are restricted to published, effective document versions visible under the linked document's RLS policy. The ingestion worker is a privileged server-side process; isolate it from the student-facing API and do not expose its credentials.
