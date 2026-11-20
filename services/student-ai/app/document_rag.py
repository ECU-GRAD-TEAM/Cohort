"""Permission-aware hybrid retrieval over published university documents.

Query embeddings are generated with the same 1024-dimensional Gemini model used by
the ingestion worker. Search runs through match_chunks() with the student's JWT so
Postgres RLS filters tenant, department, role, and enrolled-offering scope.
"""
from __future__ import annotations

import asyncio
import math
import os
from typing import Any
from urllib.parse import quote

import httpx
from google import genai
from google.genai import types

from app.records import RecordRetrievalError


EMBEDDING_MODEL = "gemini-embedding-001"
EMBEDDING_DIMENSIONS = 1024
DOCUMENT_INTENTS = frozenset({"institutional_knowledge", "course_content"})


class DocumentRetriever:
    def __init__(self) -> None:
        self.base_url = os.getenv("SUPABASE_URL", "").rstrip("/")
        self.api_key = os.getenv("SUPABASE_PUBLISHABLE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")

    def configured(self) -> bool:
        return bool(self.base_url and self.api_key and os.getenv("GEMINI_API_KEY"))

    async def _request(
        self,
        client: httpx.AsyncClient,
        token: str,
        path: str,
        *,
        method: str = "GET",
        params: dict[str, str] | None = None,
        json: dict[str, Any] | None = None,
    ) -> Any:
        response = await client.request(
            method,
            f"{self.base_url}/rest/v1/{path}",
            params=params,
            json=json,
            headers={
                "apikey": self.api_key,
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        if response.status_code in (401, 403):
            raise RecordRetrievalError("The student's database session was rejected during document retrieval.")
        if response.is_error:
            raise RecordRetrievalError(f"Document retrieval failed (HTTP {response.status_code}).")
        return response.json()

    @staticmethod
    def _embed(query: str) -> list[float]:
        client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
        try:
            result = client.models.embed_content(
                model=os.getenv("GEMINI_EMBEDDING_MODEL", EMBEDDING_MODEL),
                contents=query,
                config=types.EmbedContentConfig(
                    task_type="RETRIEVAL_QUERY",
                    output_dimensionality=EMBEDDING_DIMENSIONS,
                ),
            )
            if not result.embeddings or not result.embeddings[0].values:
                raise ValueError("Gemini returned no query embedding.")
            vector = [float(value) for value in result.embeddings[0].values]
            if len(vector) != EMBEDDING_DIMENSIONS or not all(math.isfinite(v) for v in vector):
                raise ValueError("Gemini returned an invalid query embedding.")
            return vector
        finally:
            client.close()

    async def retrieve(
        self, query: str, intent: str, access_token: str
    ) -> tuple[str, list[str]]:
        if intent not in DOCUMENT_INTENTS:
            return "", []
        if not self.configured():
            raise RecordRetrievalError("Official-document retrieval is not configured.")

        try:
            embedding = await asyncio.to_thread(self._embed, query)
        except Exception as exc:
            raise RecordRetrievalError("The document query could not be embedded.") from exc

        timeout = httpx.Timeout(20.0, connect=5.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            models = await self._request(client, access_token, "model_versions", params={
                "select": "id",
                "provider": "eq.google",
                "model_name": f"eq.{EMBEDDING_MODEL}",
                "purpose": "eq.embedding",
                "status": "eq.active",
                "order": "created_at.desc",
                "limit": "1",
            })
            if not models:
                raise RecordRetrievalError("No active document embedding model is configured for this university.")

            matches = await self._request(
                client,
                access_token,
                "rpc/match_chunks",
                method="POST",
                json={
                    "p_model_version": models[0]["id"],
                    "p_query_embedding": "[" + ",".join(f"{value:.9g}" for value in embedding) + "]",
                    "p_query_text": query,
                    "p_match_count": 8,
                },
            )
            if not matches:
                return (
                    "No published university document passages matched this question. Do not claim that a policy or course document was checked.",
                    [],
                )

            document_ids = list(dict.fromkeys(row["document_id"] for row in matches))
            version_ids = list(dict.fromkeys(row["document_version_id"] for row in matches))
            chunk_ids = list(dict.fromkeys(row["chunk_id"] for row in matches))
            in_documents = "in.(" + ",".join(document_ids) + ")"
            in_versions = "in.(" + ",".join(version_ids) + ")"
            in_chunks = "in.(" + ",".join(chunk_ids) + ")"

            documents = await self._request(client, access_token, "documents", params={
                "select": "id,title,kind,scope",
                "id": in_documents,
            })
            versions = await self._request(client, access_token, "document_versions", params={
                "select": "id,document_id,version,language,effective_from,effective_until,published_at",
                "id": in_versions,
            })
            chunks = await self._request(client, access_token, "chunks", params={
                "select": "id,metadata,chunk_index",
                "id": in_chunks,
            })

        document_by_id = {row["id"]: row for row in documents}
        version_by_id = {row["id"]: row for row in versions}
        chunk_by_id = {row["id"]: row for row in chunks}
        context_parts: list[str] = []
        citations: list[str] = []
        seen_sources: dict[tuple[str, str, str], int] = {}

        for row in matches:
            document = document_by_id.get(row["document_id"])
            version = version_by_id.get(row["document_version_id"])
            chunk = chunk_by_id.get(row["chunk_id"], {})
            if not document or not version:
                continue
            metadata = chunk.get("metadata") if isinstance(chunk.get("metadata"), dict) else {}
            page = metadata.get("page")
            page_label = str(page) if isinstance(page, int) and page > 0 else ""
            key = (document["id"], str(version["version"]), page_label)
            if key not in seen_sources:
                number = len(seen_sources) + 1
                seen_sources[key] = number
                citation = f"[{number}] {document['title']} — version {version['version']}"
                if page_label:
                    citation += f", page {page_label}"
                citations.append(citation)
            number = seen_sources[key]
            context_parts.append(
                f"[SOURCE {number} | {document['title']} | version {version['version']}"
                + (f" | page {page_label}" if page_label else "")
                + f"]\n{row['content']}"
            )

        return "\n\n".join(context_parts), citations
