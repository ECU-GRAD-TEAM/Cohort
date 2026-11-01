# Cohort Student AI service

Python/FastAPI orchestration service using the current asynchronous provider APIs:

- OpenAI: Responses API through the official `openai` SDK (`AsyncOpenAI`).
- Gemini: Interactions API through Google's official `google-genai` SDK.

## Setup

Run from this directory:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
# Edit .env and set COHORT_AI_INTERNAL_KEY and at least one provider API key.
uvicorn app.main:app --host 127.0.0.1 --port 8001
```

On Windows Command Prompt, activate with `.venv\\Scripts\\activate.bat`; in Git Bash use
`source .venv/Scripts/activate`.

## Provider configuration

- `OPENAI_API_KEY`: OpenAI API key.
- `OPENAI_MODEL`: defaults to `gpt-6-luna`.
- `OPENAI_REASONING_EFFORT`: defaults to `medium`.
- `GEMINI_API_KEY`: Google AI Studio API key.
- `GEMINI_MODEL`: defaults to `gemini-3.8-flash`.
- `GEMINI_THINKING_LEVEL`: defaults to `medium`.
- `GEMINI_MAX_OUTPUT_TOKENS`: defaults to `8192`.

OpenAI is preferred when both keys are configured; Gemini is selected when only its key is
configured. This is deterministic configuration-based selection, not automatic fallback if the
selected provider fails. Set the unused provider key to an empty value when testing the other one.

The OpenAI Responses request uses `store=False`. The Gemini Interactions request also uses
`store=False`. Cohort sends its own recent conversation history with each request rather than
depending on provider-side conversation storage. This does not replace a review of each provider's
data handling and retention terms.

## Architecture and security

The service has no Supabase/database credentials. The Fastify API must authenticate the student,
apply tenant/course/document permissions, retrieve only relevant records, and pass minimized context.
The internal key is a service-to-service secret and must never be exposed to the browser.

The FastAPI `/v1/chat` endpoint currently returns one complete JSON response. Provider requests are
asynchronous, but token-by-token streaming is not yet exposed to Fastify or the React frontend.
Adding streaming requires changing the API response path end-to-end.

Current scope: conversational tutoring and orchestration only. Personal record retrieval, official
RAG citations, conversation persistence, selective memory, budgets, audit persistence, and provider
privacy controls are subsequent integration work. Until retrieval is connected, the assistant must
not claim it checked a student's university records or official documents.
