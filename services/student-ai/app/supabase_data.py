"""RLS-scoped, read-only student data and university knowledge retrieval."""
from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote

import httpx

PERSONAL_TERMS = {
    "gpa": ("gpa", "cgpa", "cumulative average", "معدلي", "المعدل التراكمي", "المعدل"),
    "grades": ("grade", "grades", "mark", "marks", "score", "نتيجة", "درجاتي", "درجات"),
    "attendance": ("attendance", "absent", "absence", "present", "حضور", "غياب", "غيابي"),
    "enrollments": ("enrollment", "registered", "registration", "courses", "مواد مسجل", "تسجيل", "موادي"),
    "timetable": ("timetable", "schedule", "class time", "lecture time", "جدولي", "الجدول", "المحاضرات"),
}


def classify_intents(message: str) -> set[str]:
    text = message.casefold()
    return {name for name, terms in PERSONAL_TERMS.items() if any(term in text for term in terms)}


class SupabaseStudentData:
    """Calls Supabase Auth and PostgREST with the caller's JWT, so database RLS remains active."""

    def __init__(self, base_url: str, anon_key: str, access_token: str):
        self.base_url = base_url.rstrip("/")
        self.anon_key = anon_key
        self.access_token = access_token
        self.client = httpx.AsyncClient(
            timeout=httpx.Timeout(12.0, connect=5.0),
            headers={"apikey": anon_key, "Authorization": f"Bearer {access_token}"},
        )

    async def close(self) -> None:
        await self.client.aclose()

    async def _get(self, path: str, params: list[tuple[str, str]] | None = None, *, auth_user: bool = False) -> Any:
        url = f"{self.base_url}{path}"
        response = await self.client.get(url, params=params)
        if response.status_code == 401:
            raise PermissionError("The supplied access token is invalid or expired.")
        response.raise_for_status()
        return response.json()

    async def _rows(self, table: str, params: list[tuple[str, str]]) -> list[dict[str, Any]]:
        value = await self._get(f"/rest/v1/{table}", params)
        return value if isinstance(value, list) else []

    async def verified_student_id(self) -> str:
        # Auth's user endpoint validates signature, expiry, and revocation server-side.
        user = await self._get("/auth/v1/user")
        user_id = user.get("id") if isinstance(user, dict) else None
        if not isinstance(user_id, str) or not user_id:
            raise PermissionError("The access token has no valid user.")
        now = datetime.now(timezone.utc).isoformat()
        assignments = await self._rows("user_roles", [
            ("select", "role_id"),
            ("user_id", f"eq.{user_id}"),
            ("assignment_status", "eq.active"),
            ("revoked_at", "is.null"),
            ("starts_at", f"lte.{now}"),
            ("or", f"(ends_at.is.null,ends_at.gt.{now})"),
        ])
        role_ids = [str(item["role_id"]) for item in assignments if item.get("role_id")]
        if not role_ids:
            raise PermissionError("This assistant is available to enrolled students only.")
        roles = await self._rows("roles", [
            ("select", "key"),
            ("id", f"in.({','.join(role_ids)})"),
            ("is_active", "eq.true"),
        ])
        if not any(item.get("key") in {"undergraduate", "postgraduate"} for item in roles):
            raise PermissionError("This assistant is available to enrolled students only.")
        return user_id

    async def _personal_records(self, student_id: str, intents: set[str]) -> list[str]:
        context: list[str] = []
        if "gpa" in intents:
            rows = await self._rows("gpa_snapshots", [
                ("select", "term_gpa,cgpa,credits_attempted,credits_earned,computed_at,term_id"),
                ("student_id", f"eq.{student_id}"),
                ("order", "computed_at.desc"),
                ("limit", "8"),
            ])
            if rows:
                context.append("STUDENT GPA RECORDS (official snapshots): " + _json(rows))

        if "grades" in intents:
            rows = await self._rows("published_grades", [
                ("select", "score,max_score,status,published_at,feedback,component_id,offering_id,created_at"),
                ("student_id", f"eq.{student_id}"),
                ("status", "eq.published"),
                ("order", "published_at.desc"),
                ("limit", "60"),
            ])
            if rows:
                component_ids = sorted({str(row["component_id"]) for row in rows if row.get("component_id")})
                components = await self._rows("grade_components", [
                    ("select", "id,name,category,weight,offering_id"),
                    ("id", f"in.({','.join(component_ids)})"),
                ]) if component_ids else []
                names = {str(row["id"]): row for row in components}
                enriched = [{**row, "component": names.get(str(row.get("component_id")))} for row in rows]
                context.append("STUDENT PUBLISHED GRADES (draft grades excluded): " + _json(enriched))

        if "attendance" in intents:
            rows = await self._rows("attendance_records", [
                ("select", "status,confirmation,checked_in_at,session_id"),
                ("student_id", f"eq.{student_id}"),
                ("order", "checked_in_at.desc"),
                ("limit", "150"),
            ])
            if rows:
                counts: dict[str, int] = {}
                for row in rows:
                    key = str(row.get("status", "unknown"))
                    counts[key] = counts.get(key, 0) + 1
                session_ids = sorted({str(row["session_id"]) for row in rows if row.get("session_id")})
                sessions = await self._rows("attendance_sessions", [
                    ("select", "id,starts_at,ends_at,section_id"),
                    ("id", f"in.({','.join(session_ids)})"),
                ]) if session_ids else []
                session_map = {str(row["id"]): row for row in sessions}
                enriched = [{**row, "session": session_map.get(str(row.get("session_id")))} for row in rows]
                context.append("STUDENT ATTENDANCE RECORDS (counts are from returned records): " +
                               _json({"counts": counts, "recent_records": enriched[:40]}))

        if "enrollments" in intents or "timetable" in intents:
            enrollments = await self._rows("enrollments", [
                ("select", "id,offering_id,course_id,term_id,status,enrolled_at,final_percentage,final_grade_letter"),
                ("student_id", f"eq.{student_id}"),
                ("order", "enrolled_at.desc"),
                ("limit", "50"),
            ])
            if enrollments:
                course_ids = sorted({str(row["course_id"]) for row in enrollments if row.get("course_id")})
                term_ids = sorted({str(row["term_id"]) for row in enrollments if row.get("term_id")})
                courses = await self._rows("courses", [
                    ("select", "id,code,title,credit_hours,level"),
                    ("id", f"in.({','.join(course_ids)})"),
                ]) if course_ids else []
                terms = await self._rows("terms", [
                    ("select", "id,name,starts_on,ends_on"),
                    ("id", f"in.({','.join(term_ids)})"),
                ]) if term_ids else []
                course_map = {str(row["id"]): row for row in courses}
                term_map = {str(row["id"]): row for row in terms}
                enriched = [{**row, "course": course_map.get(str(row.get("course_id"))),
                             "term": term_map.get(str(row.get("term_id")))} for row in enrollments]
                if "enrollments" in intents:
                    context.append("STUDENT ENROLLMENTS: " + _json(enriched))
                if "timetable" in intents:
                    offering_ids = sorted({str(row["offering_id"]) for row in enrollments
                                            if row.get("offering_id") and row.get("status") == "enrolled"})
                    sections = await self._rows("sections", [
                        ("select", "id,code,kind,offering_id"),
                        ("offering_id", f"in.({','.join(offering_ids)})"),
                    ]) if offering_ids else []
                    section_ids = sorted({str(row["id"]) for row in sections})
                    entries = await self._rows("timetable_entries", [
                        ("select", "section_id,weekday,starts_at,ends_at,valid_from,valid_until,note,room_id"),
                        ("section_id", f"in.({','.join(section_ids)})"),
                        ("order", "weekday.asc,starts_at.asc"),
                    ]) if section_ids else []
                    section_map = {str(row["id"]): row for row in sections}
                    scheduled = [{**row, "section": section_map.get(str(row.get("section_id")))}
                                 for row in entries]
                    context.append("STUDENT TIMETABLE (only currently enrolled offerings): " + _json(scheduled))
        return context

    async def _university_knowledge(self, message: str) -> tuple[list[str], list[str]]:
        # RLS on documents, versions and chunks enforces tenant, publication, role, department,
        # and course-enrolment visibility. This uses the existing FTS index; no parallel RAG tables.
        safe_query = " ".join(message.split())[:300]
        if not safe_query:
            return [], []
        chunks = await self._rows("chunks", [
            ("select", "id,content,document_id,document_version_id,chunk_index"),
            ("fts", f"websearch.{safe_query}"),
            ("limit", "6"),
        ])
        if not chunks:
            return [], []
        document_ids = sorted({str(row["document_id"]) for row in chunks if row.get("document_id")})
        documents = await self._rows("documents", [
            ("select", "id,title,kind,scope"),
            ("id", f"in.({','.join(document_ids)})"),
        ]) if document_ids else []
        title_map = {str(row["id"]): row for row in documents}
        context: list[str] = []
        sources: list[str] = []
        for chunk in chunks:
            doc = title_map.get(str(chunk.get("document_id")), {})
            title = str(doc.get("title") or "University document")
            context.append(f"OFFICIAL UNIVERSITY SOURCE [{title}]: {str(chunk.get('content') or '')[:5000]}")
            if title not in sources:
                sources.append(title)
        return context, sources

    async def retrieve(self, message: str) -> tuple[list[str], list[str], list[str]]:
        student_id = await self.verified_student_id()
        intents = classify_intents(message)
        context = await self._personal_records(student_id, intents) if intents else []
        knowledge, sources = await self._university_knowledge(message)
        return context + knowledge, sources, sorted(intents)


def _json(value: Any) -> str:
    import json
    return json.dumps(value, ensure_ascii=False, default=str)
