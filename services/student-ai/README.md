# Cohort Student AI service

Python/FastAPI orchestration service using Google's official `google-genai` SDK and the Gemini Interactions API. Production chat uses Gemini 3.5 Flash-Lite.

## Setup

```bash
cd services/student-ai
python -m venv .venv
.venv/Scripts/activate  # Windows
# or: source .venv/bin/activate  # macOS/Linux
pip install -e .
cp .env.example .env
```

Set `GEMINI_API_KEY`, `COHORT_AI_INTERNAL_KEY`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY` in the private service environment. Use the same internal key as Fastify's `STUDENT_AI_INTERNAL_KEY`.

Run:

```bash
python -m app.main
```

## Student data security

- Fastify authenticates the incoming Supabase access token and forwards the same bearer token to the private Python service over the internal connection.
- Python validates it with Supabase Auth's `/auth/v1/user` endpoint and confirms the account has an active `undergraduate` or `postgraduate` role. No student ID is accepted from the browser or model.
- Every database read uses the student's bearer token plus the Supabase anon/publishable key. PostgreSQL RLS applies as that student for every request.
- **Never configure a service-role/secret key** for this retrieval service. Never log the access token or include it in Gemini prompts.
- Personal records are read-only and queried from fixed, allowlisted table names and columns. Gemini cannot generate SQL or mutate official records.
- GPA, published grades, attendance, enrollment, and timetable are retrieved only when the request indicates that category. Draft grades are excluded.
- Official university knowledge uses the existing `documents`, `document_versions`, and `chunks` tables. Their RLS policies enforce tenant, publication, audience role, department, and course enrollment visibility. Retrieval uses existing full-text search; no duplicate RAG tables or unverified vector RPC are introduced.
- No database schema or RLS policy changes are required for this integration.

## Local playground

The separate Streamlit playground is for developer prompt experiments. It calls Gemini directly and does not access student records.

```bash
pip install -e ".[playground]"
streamlit run playground/ui.py
```

Keep the playground private; it has no student authentication and can incur Gemini API charges.

## Configuration

See `.env.example`.

- Service: `COHORT_AI_INTERNAL_KEY`, `STUDENT_AI_TITLE`, `STUDENT_AI_VERSION`, `STUDENT_AI_HOST`, `STUDENT_AI_PORT`
- Supabase: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (server-side only)
- Gemini: `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_API_VERSION`, `GEMINI_THINKING_LEVEL`, `GEMINI_MAX_OUTPUT_TOKENS`
- Playground: `PLAYGROUND_SYSTEM_PROMPT`, `PLAYGROUND_GEMINI_MODEL`, and optional pricing estimates

Gemini requests use `store=False`; Cohort supplies recent conversation history. The FastAPI endpoint returns one complete JSON response (streaming is not yet implemented).
