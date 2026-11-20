# Cohort Student Assistant — agreed initial requirements

## Product scope
An all-in-one student assistant for university learning and student life. Intended users are all
active enrolled students, personalized by their own Cohort data and permissions.

## Capabilities
Personalized learning; learning-focused assignment guidance; quick quizzes and full practice exams;
course assistance; timetable/study planning; attendance explanations; academic performance analysis;
registration guidance; approved-document understanding; recommendations; student-requested reminders
and notifications information; university information; career/skills guidance; Arabic/English
multilingual interaction; support across university life.

## Initial interaction and permissions
Chat with suggested actions. Reactive only: no autonomous monitoring or unsolicited alerts. Read-only
access to official student records. The assistant cannot create tasks/reminders, send messages, submit
requests, book appointments, or change university records. It can generate plans, quizzes and
recommendations inside a conversation.

## Evidence and integrity
Use Cohort records and approved official university/course documents; no external internet and no
student-uploaded document corpus in the initial scope. Retrieve only relevant data after server-side
authorization. Use source-aware citations when appropriate; identify record/document sources for
personal and policy claims. Never guess missing information. Explain uncertainty and recommend the
relevant lecturer/department when human confirmation is required. Assignment help is learning-focused
and must not complete graded work. AI-generated practice questions are not official exam questions.

## Language and experience
Auto-detect Arabic or English with manual override. Support Modern Standard Arabic, Egyptian Arabic,
mixed Arabic/English questions and technical explanations. Fixed personality: friendly, patient,
professional, respectful, encouraging and clear. Chat history plus separate selective persistent
memory; students can review, correct, delete or opt out of memory. Memory is not an authoritative
academic record.

## Model and privacy
Only Gemini (gemini-3.5-flash-lite) is supported. 
Still minimize context and never send credentials, tokens or unrelated records. Provider keys stay server-side.
Revisit stronger anonymization, sensitive-data filtering, provider restrictions and residency before
production use.

## Governance
Flexible admin-configurable daily/monthly request/token/cost budgets. When exhausted, block AI access,
explain reset time, preserve chat history and leave normal Cohort functions available. Admin analytics:
request counts, active users, usage/cost, feature/faculty/department/provider breakdown, latency,
failures and tokens. No default admin access to private chat content. Separate retention policies for
conversation history, student-controlled memory, usage/security and technical logs.

## Reliability and safety
When uncertain, search authorized Cohort records and official documents; if still unresolved, say so
and refer the student to a relevant human contact without inventing contact details. Sensitive academic
situations receive factual information, empathy, practical suggestions and referral to verified human
support; no diagnosis or guaranteed outcomes. Assistant actions are information and suggestions only.


## Student assignments record lookup

The assistant can list official assignment-kind assessments visible to the authenticated student,
including instructions, deadlines, late policy, the student's own submission status and submission
date, and marks/feedback only after the university releases them. The feature is read-only and does
not submit or change assignments.


## Instructor and office-hour lookup

Students can view instructor role assignments for sections in their own assigned timetable
and associated official office-hour schedules. The lookup uses the student's JWT and existing
RLS policies. Instructor names and direct contact details are not exposed because current
profile/contact policies permit students to read only their own records. The feature is read-only.

## Student support tickets and requests

Students can review only their own submitted support tickets and requests, including
category, subject, description, recorded status and priority, assigned department,
SLA/response/resolution timestamps, and publicly visible comment history. Internal
staff comments and AI triage metadata are excluded. The assistant is read-only and
cannot create, edit, or close tickets.


## Student complaints and incident reports

Students can review their own complaint-kind tickets and public replies through
the existing security-invoker support view and their authenticated JWT. Internal
notes, AI triage metadata, and internal identifiers are excluded. Operational
incident records remain restricted to operations staff by existing RLS; the
assistant must explicitly disclose that limitation and must not treat an empty
complaint result as evidence that no incident report exists. The feature is
read-only.



## Student enrollment and registration status

Students can review their own official enrollment rows, including course code/title,
credit hours, academic term, recorded enrollment status, waitlist position when
present, and enrollment/status-change timestamps. Term-level counts and registered
credit hours come from the existing student_enrollment_summary security-invoker view.
The lookup uses the authenticated student's JWT and existing RLS; linked course and
term details are limited to records referenced by that student's enrollments.
Registration opening/closing and add/drop deadlines are included only when recorded
on the linked term. The database has no pending enrollment status. The assistant
cannot register, add, drop, withdraw, or otherwise modify enrollment records.


## Student course materials and learning resources

Students can search the catalogue of published/released learning resources for
their own currently enrolled course offerings. Retrieval uses the authenticated
student JWT and the existing `student_course_resources` security-invoker view.
The view joins only the student's `enrolled` offerings and enforces material
publication/release, offering-scoped document visibility, and published document
versions. Results include course/term labels and resource metadata such as title,
description, kind, origin, availability, document version/language, and effective
dates where available. Storage paths and internal identifiers are not exposed.

The view does not return file contents and the implementation does not download
Storage objects because student read access to Storage objects has not been
verified. It can locate catalogue entries, but cannot claim to summarize, quote,
explain, or generate study material grounded in file contents unless actual
authorized text is supplied separately. The feature is read-only and makes no
database changes.


## Student academic advising and degree progress

Students can review the official aggregate degree-progress summary, completed and in-progress
credits, remaining credits where calculable, required curriculum courses, active curriculum
requirement groups and their course options, and the study-plan level/semester assigned to each
requirement. They can also ask about official prerequisite and corequisite rules for courses in
their assigned programme. The summary comes from the existing security-invoker
`student_degree_progress` view; detail is retrieved using the authenticated student's JWT and
existing RLS from the student's own profile and enrollment records plus the assigned programme's
published catalogue structures.

Choice-group alternatives must not be described as individually mandatory. Course completion
requires a recorded `completed` enrollment and satisfaction of any curriculum minimum grade
points. The existing aggregate progress view excludes graduation_project-category groups from its
totals; these may be described separately but must not be included in the aggregate credit or
course counts. An unmet prerequisite is only a potential registration issue, not a guaranteed
block, because waivers, transfer credit, equivalencies, or registrar overrides may not be represented.
Missing or incomplete official data must be disclosed rather than estimated. The assistant is
strictly read-only and cannot register, add/drop courses, or change academic records.

## Course catalogue and available offerings

Use the student_available_courses security-invoker view with the authenticated student's JWT.
Distinguish active catalogue courses from published term offerings. Only published offerings
are presented as offered in a term. A null registration-window result means dates are insufficient
to determine whether registration is open. Do not infer remaining seats from section capacity
without authoritative enrolled and waitlisted counts. Do not infer programme eligibility or
registration approval. The capability is read-only, bilingual, and cannot register, add/drop,
or reserve seats.

## Graduation audit and eligibility

Use only the student's official student_graduation_audit security-invoker view with the
authenticated student's JWT. The view must remain scoped to the authenticated student and tenant.
Report the recorded audit status as authoritative: only eligible is an eligibility decision;
pending and requires_manual_review are not approvals. Do not calculate or promise eligibility
from GPA, credits, attendance, or unmet requirements. Distinguish historical credits/CGPA at the
audit timestamp from current values. Linked policy thresholds are not guaranteed historical
snapshots and must never override the recorded audit status. Do not expose internal audit UUIDs
or claim a degree has been awarded. This capability is read-only and available in English and Arabic.
