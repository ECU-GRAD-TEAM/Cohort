# Cohort Student AI service

Python/FastAPI orchestration service using Google's official `google-genai` SDK and the
Gemini Interactions API. The service and local playground use **Gemini 3.5 Flash-Lite only**.

## Setup

Move first to this directory:

```bash
cd services/student-ai
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env
```

Edit `.env` and set `GEMINI_API_KEY` and `COHORT_AI_INTERNAL_KEY`.

Run the Python service:

```bash
python -m app.main
```

The service loads its local `.env` automatically. Variables injected by the deployment
environment take precedence over values in `.env`.

## Local Gemini playground

A separate Streamlit developer interface lets you experiment without waiting for the Cohort React
frontend. It calls Gemini directly through the official SDK; it does not call the student-facing
FastAPI endpoint and does not require the Fastify API or Supabase to be running.

Install and start the UI from this directory:

```bash
pip install -e ".[playground]"
streamlit run playground/ui.py
```

Open `http://localhost:8501`. The Streamlit server binds to `127.0.0.1` only. Do not expose
this developer playground publicly: it has no user authentication and can incur API charges using
the configured Gemini API key.

The playground includes:
- Gemini 3.5 Flash-Lite chat.
- Editable system prompt and model ID.
- Thinking-level and maximum-output-token controls.
- Conversation history and reset.
- Best-effort token usage, latency, and optional estimated-cost display.

The playground uses synchronous SDK calls because Streamlit runs a synchronous rerun-based UI.
The production FastAPI service uses the asynchronous Gemini SDK. The Interactions API is documented
as preview for this model; verify availability and behavior for your Google AI API project.
Gemini 3.5 Flash-Lite ignores custom temperature values, so the playground does not expose a
temperature setting. Token usage fields are best-effort. Estimated cost remains unavailable or
zero until you configure the current per-million-token rates in your local `.env`.

## Environment configuration

See `.env.example` for the complete template.

### Service

- `COHORT_AI_INTERNAL_KEY`: private service-to-service secret used by Fastify.
- `STUDENT_AI_TITLE`, `STUDENT_AI_VERSION`: FastAPI metadata.
- `STUDENT_AI_HOST`, `STUDENT_AI_PORT`: bind address and port.
- `STUDENT_AI_RELOAD`: enable Uvicorn reload for local development only.
- `STUDENT_AI_MAX_MESSAGE_CHARS`, `STUDENT_AI_MAX_HISTORY_MESSAGES`,
  `STUDENT_AI_MAX_CONTEXT_ITEMS`: request-size limits.

### Gemini

- `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_API_VERSION`
- `GEMINI_THINKING_LEVEL`, `GEMINI_MAX_OUTPUT_TOKENS`

### Playground

- `PLAYGROUND_SYSTEM_PROMPT`, `PLAYGROUND_GEMINI_MODEL`
- `PLAYGROUND_GEMINI_INPUT_USD_PER_MILLION`,
  `PLAYGROUND_GEMINI_OUTPUT_USD_PER_MILLION`

The model defaults to `gemini-3.5-flash-lite`. Thinking level defaults to `minimal`, which is
the model's low-latency default; raise it to `low`, `medium`, or `high` when the task needs
more reasoning. Custom temperature values are not supported by this model and are ignored.

## Data handling

Gemini Interactions requests use `store=False`. Cohort sends its own recent conversation history
with each request rather than depending on provider-side conversation storage. This does not replace
a review of Google's data handling and retention terms.

## Architecture and security

The production AI service has no Supabase/database credentials. The Fastify API must authenticate
the student, apply tenant/course/document permissions, retrieve only relevant records, and pass
minimized context. The internal key must never be exposed to the browser.

The FastAPI `/v1/chat` endpoint returns one complete JSON response. Provider requests are
asynchronous, but token-by-token streaming is not yet exposed to Fastify or React.

Current scope: conversational tutoring and orchestration only. Personal record retrieval, official
RAG citations, conversation persistence, selective memory, budgets, audit persistence, and provider
privacy controls are subsequent integration work.