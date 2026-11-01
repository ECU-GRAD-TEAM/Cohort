# Cohort Student AI service

Python/FastAPI orchestration service using the asynchronous provider APIs:

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
python -m app.main
```

On Windows Command Prompt, activate with `.venv\\Scripts\\activate.bat`; in Git Bash use
`source .venv/Scripts/activate`.

The service loads its local `.env` automatically. Variables already injected by the deployment
environment take precedence over values in `.env`.

## Environment configuration

All runtime and provider tuning is read from environment variables. See `.env.example` for the
complete template.

### Service

- `COHORT_AI_INTERNAL_KEY`: required private service-to-service secret.
- `STUDENT_AI_TITLE`, `STUDENT_AI_VERSION`: FastAPI metadata.
- `STUDENT_AI_HOST`, `STUDENT_AI_PORT`: bind address and port.
- `STUDENT_AI_RELOAD`: enable Uvicorn reload for local development only.
- `STUDENT_AI_PROVIDER`: `auto`, `openai`, or `google`. In `auto`, OpenAI is preferred.
- `STUDENT_AI_MAX_MESSAGE_CHARS`, `STUDENT_AI_MAX_HISTORY_MESSAGES`, `STUDENT_AI_MAX_CONTEXT_ITEMS`: request-size limits.

### OpenAI

- `OPENAI_API_KEY`, `OPENAI_MODEL`
- `OPENAI_TIMEOUT_SECONDS`, `OPENAI_MAX_RETRIES`
- `OPENAI_REASONING_EFFORT`, `OPENAI_TEXT_VERBOSITY`, `OPENAI_TEMPERATURE`

### Gemini

- `GEMINI_API_KEY`, `GEMINI_MODEL`
- `GEMINI_API_VERSION`
- `GEMINI_THINKING_LEVEL`, `GEMINI_TEMPERATURE`, `GEMINI_MAX_OUTPUT_TOKENS`

Temperature and reasoning options are model-dependent. Confirm that the selected model supports
the configured options; unsupported combinations are returned as a generic provider error. The
model names in the example are placeholders and must be replaced with model IDs available to your
provider account if they are not valid for that account.

In `auto` mode, OpenAI is selected when its key is set; Gemini is selected when only its key is
set. This is deterministic configuration-based selection, not automatic failover if a provider
request fails. Set `STUDENT_AI_PROVIDER` explicitly to force a provider.

## Data handling

The OpenAI Responses and Gemini Interactions requests use `store=False`. Cohort sends its own
recent conversation history with each request rather than depending on provider-side conversation
storage. This does not replace a review of each provider's data handling and retention terms.

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

## Run with Uvicorn CLI

You can alternatively start it with:

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8001
```

When using the CLI, pass host and port explicitly (or use `python -m app.main` to apply
`STUDENT_AI_HOST` and `STUDENT_AI_PORT` from the environment).
