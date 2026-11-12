"""Read-only retrieval of the authenticated student's own Cohort records.

The service uses the Supabase Data API with the student's verified access token.
Postgres RLS remains the authorization boundary; no service-role key is used.
"""
from __future__ import annotations

import os
from typing import Any
from urllib.parse import quote

import httpx


class RecordRetrievalError(RuntimeError):
    """Raised when Cohort records cannot be safely retrieved."""


class StudentRecordRetriever:
    def __init__(self) -> None:
        self.base_url = os.getenv("SUPABASE_URL", "").rstrip("/")
        self.anon_key = os.getenv("SUPABASE_ANON_KEY", "")

    def configured(self) -> bool:
        return bool(self.base_url and self.anon_key)

    async def _get(
        self,
        client: httpx.AsyncClient,
        token: str,
        table: str,
        params: dict[str, str],
    ) -> list[dict[str, Any]]:
        response = await client.get(
            f"{self.base_url}/rest/v1/{quote(table, safe='')}",
            params=params,
            headers={
                "apikey": self.anon_key,
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
        )
        if response.status_code in (401, 403):
            raise RecordRetrievalError("The student's database session was rejected.")
        if response.is_error:
            # Do not leak SQL, schema, or provider response details into the chat.
            raise RecordRetrievalError(f"Could not retrieve the requested {table} records.")
        data = response.json()
        if not isinstance(data, list):
            raise RecordRetrievalError("The database returned an unexpected response.")
        return data

    async def retrieve(
        self, intent: str, access_token: str, student_id: str
    ) -> tuple[str, list[str]]:
        if not self.configured():
            raise RecordRetrievalError("Student record retrieval is not configured.")

        timeout = httpx.Timeout(15.0, connect=5.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            if intent == "gpa":
                rows = await self._get(client, access_token, "gpa_snapshots", {
                    "select": "term_gpa,cgpa,credits_attempted,credits_earned,computed_at,terms(name,code)",
                    "student_id": f"eq.{student_id}",
                    "order": "computed_at.desc",
                    "limit": "10",
                })
                return ("Student GPA records (newest first): " + _json(rows), ["gpa_snapshots"])

            if intent == "attendance":
                rows = await self._get(client, access_token, "attendance_records", {
                    "select": "status,confirmation,checked_in_at,attendance_sessions!inner(starts_at,ends_at,section_id)",
                    "student_id": f"eq.{student_id}",
                    "order": "checked_in_at.desc.nullslast",
                    "limit": "200",
                })
                return ("Student attendance records (up to 200 recent records): " + _json(rows), ["attendance_records", "attendance_sessions"])

            if intent == "grades":
                rows = await self._get(client, access_token, "published_grades", {
                    "select": "id,offering_id,component_id,score,max_score,published_at",
                    "student_id": f"eq.{student_id}",
                    "order": "published_at.desc",
                    "limit": "200",
                })
                offering_ids = sorted({str(row["offering_id"]) for row in rows if row.get("offering_id")})
                component_ids = sorted({str(row["component_id"]) for row in rows if row.get("component_id")})
                offerings: list[dict[str, Any]] = []
                components: list[dict[str, Any]] = []
                if offering_ids:
                    offerings = await self._get(client, access_token, "course_offerings", {
                        "select": "id,courses(code,title)",
                        "id": _uuid_in_filter(offering_ids),
                    })
                if component_ids:
                    components = await self._get(client, access_token, "grade_components", {
                        "select": "id,name",
                        "id": _uuid_in_filter(component_ids),
                    })
                return (
                    "Student published grades: " + _json({
                        "grades": rows,
                        "course_offerings": offerings,
                        "grade_components": components,
                    }),
                    ["published_grades", "course_offerings", "courses", "grade_components"],
                )

            if intent == "enrollments":
                rows = await self._get(client, access_token, "enrollments", {
                    "select": "status,waitlist_position,enrolled_at,sections(code),course_offerings(term_id,courses(code,title,credit_hours),terms(name,code))",
                    "student_id": f"eq.{student_id}",
                    "order": "enrolled_at.desc",
                    "limit": "100",
                })
                return ("Student course enrollments: " + _json(rows), ["enrollments", "sections", "course_offerings", "courses", "terms"])

            if intent == "timetable":
                rows = await self._get(client, access_token, "student_meetings", {
                    "select": "assigned_at,enrollments!inner(student_id),section_meetings!inner(day_of_week,starts_at,ends_at,meeting_type,rooms(code,name),sections(code),course_offerings(courses(code,title)))",
                    "enrollments.student_id": f"eq.{student_id}",
                    "order": "assigned_at.desc",
                    "limit": "200",
                })
                return ("Student's assigned timetable meetings: " + _json(rows), ["student_meetings", "section_meetings", "rooms"])

        return ("No personal record lookup was required for this prompt.", [])

def _uuid_in_filter(values: list[str]) -> str:
    # IDs came from our own database response; validate before interpolating into PostgREST's
    # comma-delimited IN filter so values cannot alter the filter expression.
    from uuid import UUID
    safe = [str(UUID(value)) for value in values]
    return "in.(" + ",".join(safe) + ")"

def _json(value: Any) -> str:
    import json
    return json.dumps(value, ensure_ascii=False, default=str)
