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

Supported personal record intents: GPA/CGPA, attendance, published grades, course
enrollments, and the student's assigned timetable. Multiple categories can be retrieved
for one message. Classification is performed by Gemini only; there is no local keyword
or regex intent shortcut. Invalid or malformed classifier output fails closed to no
record lookup.

The Fastify-to-FastAPI identity forwarding contract and the database RLS policies must
be verified in the deployed environment. The internal key must never be exposed to the
browser. Do not treat a forwarded user ID alone as authorization.

## Data handling and API behavior

Gemini Interactions requests use `store=False`. Cohort sends its recent conversation
history with each request rather than relying on provider-side conversation storage.
This does not replace a review of Google's data handling and retention terms.

The FastAPI `/v1/chat` endpoint returns one complete JSON response. Provider requests
are asynchronous, but token-by-token streaming is not exposed to Fastify or React.

Current scope includes conversational tutoring and read-only retrieval of the five
personal record categories above. Official-document RAG citations, conversation
persistence, selective memory, budgets, audit persistence, and provider privacy controls
remain outside this service's current implementation.
