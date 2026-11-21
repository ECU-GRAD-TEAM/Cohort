"""Index published PDF/DOCX versions from the private university-documents bucket.

Run with: python -m app.ingest_documents
Only the service worker uses SUPABASE_SERVICE_ROLE_KEY. Student chat never does.
"""
from __future__ import annotations

import asyncio
import hashlib
import io
import math
import os
import re
import uuid
from typing import Any
from urllib.parse import quote

import httpx
from docx import Document as DocxDocument
from google import genai
from google.genai import types
from pypdf import PdfReader
from dotenv import load_dotenv

load_dotenv()

EMBEDDING_MODEL = "gemini-embedding-001"
EMBEDDING_DIMENSIONS = 1024
BUCKET = os.getenv("AI_DOCUMENTS_BUCKET", "university-documents")
MAX_CHARS = 2400
OVERLAP_CHARS = 300


def extract_pages(filename: str, payload: bytes) -> list[tuple[int | None, str]]:
    suffix = filename.lower().rsplit(".", 1)[-1] if "." in filename else ""
    if suffix == "pdf":
        reader = PdfReader(io.BytesIO(payload))
        return [(index + 1, page.extract_text() or "") for index, page in enumerate(reader.pages)]
    if suffix == "docx":
        document = DocxDocument(io.BytesIO(payload))
        blocks = [paragraph.text for paragraph in document.paragraphs if paragraph.text.strip()]
        for table in document.tables:
            for row in table.rows:
                blocks.append(" | ".join(cell.text.strip() for cell in row.cells))
        return [(None, "\n".join(blocks))]
    raise ValueError("Only PDF and DOCX documents can be indexed.")


def split_text(text: str, page: int | None, *, max_chars: int = MAX_CHARS, overlap: int = OVERLAP_CHARS) -> list[dict[str, Any]]:
    normalized = re.sub(r"\s+", " ", text).strip()
    if not normalized:
        return []
    chunks: list[dict[str, Any]] = []
    start = 0
    while start < len(normalized):
        end = min(start + max_chars, len(normalized))
        if end < len(normalized):
            boundary = normalized.rfind(" ", start + max_chars // 2, end)
            if boundary > start:
                end = boundary
        content = normalized[start:end].strip()
        if content:
            chunks.append({
                "id": str(uuid.uuid4()),
                "chunk_index": len(chunks),
                "content": content,
                "token_count": max(1, math.ceil(len(content) / 4)),
                "metadata": {"page": page} if page is not None else {},
            })
        if end >= len(normalized):
            break
        start = max(start + 1, end - overlap)
    return chunks


def _embed(client: genai.Client, text: str) -> list[float]:
    result = client.models.embed_content(
        model=os.getenv("GEMINI_EMBEDDING_MODEL", EMBEDDING_MODEL),
        contents=text,
        config=types.EmbedContentConfig(
            task_type="RETRIEVAL_DOCUMENT",
            output_dimensionality=EMBEDDING_DIMENSIONS,
        ),
    )
    if not result.embeddings or not result.embeddings[0].values:
        raise RuntimeError("Gemini returned no document embedding.")
    values = [float(value) for value in result.embeddings[0].values]
    if len(values) != EMBEDDING_DIMENSIONS or not all(math.isfinite(value) for value in values):
        raise RuntimeError("Gemini returned an invalid document embedding.")
    return values


async def _request(client: httpx.AsyncClient, method: str, path: str, *, params=None, json=None, headers=None):
    base = os.environ["SUPABASE_URL"].rstrip("/")
    response = await client.request(
        method, f"{base}{path}", params=params, json=json,
        headers=headers or {},
    )
    if response.is_error:
        raise RuntimeError(f"Supabase ingestion request failed (HTTP {response.status_code}): {response.text[:300]}")
    return response


async def ingest_published_documents() -> int:
    base_headers = {
        "apikey": os.environ["SUPABASE_SERVICE_ROLE_KEY"],
        "Authorization": f"Bearer {os.environ['SUPABASE_SERVICE_ROLE_KEY']}",
        "Content-Type": "application/json",
    }
    timeout = httpx.Timeout(60.0, connect=10.0)
    indexed = 0
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    try:
        async with httpx.AsyncClient(timeout=timeout) as http:
            versions_response = await _request(
                http, "GET", "/rest/v1/document_versions",
                params={
                    "select": "id,tenant_id,document_id,version,language,storage_path,content_hash,documents!inner(id,title,kind,status,scope,offering_id)",
                    "published_at": "not.is.null",
                    "storage_path": "not.is.null",
                    "documents.status": "eq.published",
                    "order": "created_at.asc",
                },
                headers=base_headers,
            )
            for version in versions_response.json():
                storage_path = version.get("storage_path")
                if not storage_path:
                    continue
                model_response = await _request(
                    http, "GET", "/rest/v1/model_versions",
                    params={
                        "select": "id",
                        "tenant_id": f"eq.{version['tenant_id']}",
                        "provider": "eq.google",
                        "model_name": f"eq.{EMBEDDING_MODEL}",
                        "purpose": "eq.embedding",
                        "status": "eq.active",
                        "order": "created_at.desc",
                        "limit": "1",
                    },
                    headers=base_headers,
                )
                models = model_response.json()
                if not models:
                    raise RuntimeError(f"No active embedding model exists for tenant {version['tenant_id']}.")

                encoded_path = quote(storage_path, safe="/")
                file_response = await _request(
                    http, "GET",
                    f"/storage/v1/object/{BUCKET}/{encoded_path}",
                    headers=base_headers,
                )
                payload = file_response.content
                digest = hashlib.sha256(payload).hexdigest()
                if version.get("content_hash") == digest:
                    existing = await _request(
                        http, "GET", "/rest/v1/chunks",
                        params={"select": "id", "document_version_id": f"eq.{version['id']}", "limit": "1"},
                        headers=base_headers,
                    )
                    if existing.json():
                        continue

                pages = extract_pages(storage_path, payload)
                chunks: list[dict[str, Any]] = []
                for page, text in pages:
                    chunks.extend(split_text(text, page))
                if not chunks:
                    raise RuntimeError(f"No extractable text found in published document {version['document_id']}.")

                embeddings: list[dict[str, Any]] = []
                for chunk in chunks:
                    vector = await asyncio.to_thread(_embed, client, chunk["content"])
                    embeddings.append({
                        "chunk_id": chunk["id"],
                        "model_version_id": models[0]["id"],
                        "tenant_id": version["tenant_id"],
                        "embedding": vector,
                    })

                await _request(
                    http, "DELETE", "/rest/v1/chunks",
                    params={"document_version_id": f"eq.{version['id']}"},
                    headers={**base_headers, "Prefer": "return=minimal"},
                )
                chunk_rows = [{
                    "id": chunk["id"],
                    "tenant_id": version["tenant_id"],
                    "document_version_id": version["id"],
                    "chunk_index": chunk["chunk_index"],
                    "content": chunk["content"],
                    "token_count": chunk["token_count"],
                    "metadata": chunk["metadata"],
                } for chunk in chunks]
                for offset in range(0, len(chunk_rows), 100):
                    await _request(
                        http, "POST", "/rest/v1/chunks",
                        json=chunk_rows[offset:offset + 100],
                        headers={**base_headers, "Prefer": "return=minimal"},
                    )
                for offset in range(0, len(embeddings), 100):
                    await _request(
                        http, "POST", "/rest/v1/chunk_embeddings",
                        json=embeddings[offset:offset + 100],
                        headers={**base_headers, "Prefer": "return=minimal"},
                    )
                await _request(
                    http, "PATCH", "/rest/v1/document_versions",
                    params={"id": f"eq.{version['id']}"},
                    json={"content_hash": digest},
                    headers={**base_headers, "Prefer": "return=minimal"},
                )
                indexed += 1
    finally:
        client.close()
    return indexed


if __name__ == "__main__":
    count = asyncio.run(ingest_published_documents())
    print(f"Indexed {count} published document version(s).")
