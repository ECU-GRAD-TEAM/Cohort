# Cohort Student AI service

Python/FastAPI orchestration service. Run from this directory:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
cp .env.example .env  # set a private internal key and at least one provider key
uvicorn app.main:app --host 127.0.0.1 --port 8001
```

The service has no Supabase/database credentials. The Fastify API must authenticate the student,
apply tenant/course/document permissions, retrieve only relevant records, and pass minimized context.
The internal key is a service-to-service secret. OpenAI is preferred if configured; Gemini is used
when OpenAI is not configured. This is deterministic selection, not random routing.

Current scope: conversational tutoring and orchestration only. Personal record retrieval, official
RAG citations, conversation persistence, selective memory, budgets, audit persistence, and provider
privacy controls are subsequent integration work. Until retrieval is connected, the assistant must
not claim it checked a student's university records or official documents.
