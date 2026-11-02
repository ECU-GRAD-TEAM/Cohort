# Cohort Student AI service

Python/FastAPI orchestration service using the asynchronous provider APIs:

- OpenAI: Responses API through the official `openai` SDK (`AsyncOpenAI`).
- Gemini: Interactions API through Google's official `google-genai` SDK.

## Setup

Move first to this directory:
cd services/student-ai

Run from this directory:

```bash
python -m venv .venv
source .venv/bin/activate

# Without LLM Playground
pip install -e .

cp .env.example .env
# Edit .env and set the provider API key(s).
python -m app.main
```

On Windows Command Prompt, activate with `.venv\\Scripts\\activate.bat`; in Git Bash use
`source .venv/Scripts/activate`.

The service loads its local `.env` automatically. Variables injected by the deployment environment
take precedence over values in `.env`.

## Local LLM playground

A separate Streamlit developer interface lets you experiment without waiting for the Cohort React
frontend. It calls the providers directly through their official SDKs; it does not call the
student-facing FastAPI endpoint and does not require the Fastify API or Supabase to be running.

Install the optional dependency and start the UI from this directory:

```bash
pip install -e ".[playground]"
streamlit run playground/ui.py
```

Open `http://localhost:8501`. The Streamlit server is configured to bind to `127.0.0.1` only.
Do not expose this developer playground publicly: it has no user authentication and can incur
provider charges using the configured API keys.

The playground includes:
- Single-provider chat and side-by-side comparison of configured providers.
- Editable system prompt and model IDs.
- Temperature, OpenAI reasoning/verbosity, Gemini thinking level and output-token controls.
- Conversation history and reset.
- Best-effort token usage and latency display.
- Optional estimated-cost calculation when you configure per-million-token rates.

The playground uses synchronous SDK calls because Streamlit runs a synchronous rerun-based UI.
The production FastAPI service continues to use asynchronous SDK calls. Provider options vary by
model; unsupported parameter combinations will produce a provider error. Token usage fields are
best-effort and may not be returned by every provider/model. Cost is only an estimate and remains
zero unless you enter current provider pricing in the local `.env`.

### Playground environment variables

- `PLAYGROUND_SYSTEM_PROMPT`
- `PLAYGROUND_OPENAI_MODEL`, `PLAYGROUND_GEMINI_MODEL`
- `PLAYGROUND_TEMPERATURE`
- `PLAYGROUND_OPENAI_INPUT_USD_PER_MILLION`, `PLAYGROUND_OPENAI_OUTPUT_USD_PER_MILLION`
- `PLAYGROUND_GEMINI_INPUT_USD_PER_MILLION`, `PLAYGROUND_GEMINI_OUTPUT_USD_PER_MILLION`

The playground also reads the standard `OPENAI_API_KEY`, `GEMINI_API_KEY`, model and provider
settings as defaults. Model and generation settings can be changed in the sidebar for each run.

## Environment configuration

See `.env.example` for the complete template.

### Service

- `COHORT_AI_INTERNAL_KEY`: private service-to-service secret used by Fastify.
- `STUDENT_AI_TITLE`, `STUDENT_AI_VERSION`: FastAPI metadata.
- `STUDENT_AI_HOST`, `STUDENT_AI_PORT`: bind address and port.
- `STUDENT_AI_RELOAD`: enable Uvicorn reload for local development only.
- `STUDENT_AI_PROVIDER`: `auto`, `openai`, or `google`.
- `STUDENT_AI_MAX_MESSAGE_CHARS`, `STUDENT_AI_MAX_HISTORY_MESSAGES`, `STUDENT_AI_MAX_CONTEXT_ITEMS`: request-size limits.

### OpenAI

- `OPENAI_API_KEY`, `OPENAI_MODEL`
- `OPENAI_TIMEOUT_SECONDS`, `OPENAI_MAX_RETRIES`
- `OPENAI_REASONING_EFFORT`, `OPENAI_TEXT_VERBOSITY`, `OPENAI_TEMPERATURE`

### Gemini

- `GEMINI_API_KEY`, `GEMINI_MODEL`, `GEMINI_API_VERSION`
- `GEMINI_THINKING_LEVEL`, `GEMINI_TEMPERATURE`, `GEMINI_MAX_OUTPUT_TOKENS`

Temperature and reasoning options are model-dependent. Confirm that the selected model supports
the configured options. Replace example model IDs with IDs available to your provider accounts.

In `auto` mode, OpenAI is selected when its key is set; Gemini is selected when only its key is
set. This is deterministic configuration-based selection, not automatic failover if a request fails.

## Data handling

The OpenAI Responses and Gemini Interactions requests use `store=False`. Cohort sends its own
recent conversation history with each request rather than depending on provider-side conversation
storage. This does not replace a review of each provider's data handling and retention terms.

## Architecture and security

The production AI service has no Supabase/database credentials. The Fastify API must authenticate
the student, apply tenant/course/document permissions, retrieve only relevant records, and pass
minimized context. The internal key must never be exposed to the browser.

The FastAPI `/v1/chat` endpoint currently returns one complete JSON response. Provider requests are
asynchronous, but token-by-token streaming is not yet exposed to Fastify or React.

Current scope: conversational tutoring and orchestration only. Personal record retrieval, official
RAG citations, conversation persistence, selective memory, budgets, audit persistence, and provider
privacy controls are subsequent integration work.
