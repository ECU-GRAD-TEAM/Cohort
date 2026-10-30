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
Backend chooses provider deterministically; student does not choose provider. Initial provider policy
is the user's temporary choice to send relevant student context to OpenAI/Gemini when needed. Still
minimize context and never send credentials, tokens or unrelated records. Provider keys stay server-side.
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
