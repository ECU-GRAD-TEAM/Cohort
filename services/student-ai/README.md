# Cohort Student AI service

Python/FastAPI orchestration service. It uses the official asynchronous SDKs for both supported
providers:

- OpenAI: the `openai` Python package (`AsyncOpenAI`)
- Gemini: Google's `google-genai` package (`genai.Client` async API)

Run from this directory:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env  # set a private internal key and at least one provider key
uvicorn app.main:app --host 127.0.0.1 --port 8001
```

On Windows Command Prompt, activate with `.venv\\Scripts\\activate.bat`; in Git Bash use
`source .venv/Scripts/activate`.

Configure at least one provider in `.env`. OpenAI is preferred when both keys are configured;
Gemini is selected when only its key is configured. This is deterministic configuration-based
selection, not automatic fallback if the selected provider fails.

The service has no Supabase/database credentials. The Fastify API must authenticate the student,
apply tenant/course/document permissions, retrieve only relevant records, and pass minimized context.
The internal key is a service-to-service secret and must never be exposed to the browser.

Current scope: conversational tutoring and orchestration only. Personal record retrieval, official
RAG citations, conversation persistence, selective memory, budgets, audit persistence, and provider
privacy controls are subsequent integration work. Until retrieval is connected, the assistant must
not claim it checked a student's university records or official documents.
