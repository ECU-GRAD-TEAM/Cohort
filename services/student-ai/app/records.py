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
        self.api_key = os.getenv("SUPABASE_PUBLISHABLE_KEY") or os.getenv("SUPABASE_ANON_KEY", "")

    def configured(self) -> bool:
        return bool(self.base_url and self.api_key)

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
                "apikey": self.api_key,
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
        )
        if response.status_code in (401, 403):
            raise RecordRetrievalError(f"The student's database session was rejected (HTTP {response.status_code}, table {table}).")
        if response.is_error:
            # Do not leak SQL, schema, or provider response details into the chat.
            raise RecordRetrievalError(f"Could not retrieve the requested {table} records (HTTP {response.status_code}).")
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
                rows = await self._get(client, access_token, "student_academic_overview", {
                    "select": "cumulative_gpa,cumulative_gpa_credits,cumulative_quality_points,latest_term_id,latest_term_name,latest_term_kind,latest_academic_year_id,latest_term_gpa,term_gpa_credits,term_quality_points,cumulative_credits_earned,gpa_computed_at",
                    "student_id": f"eq.{student_id}",
                    "limit": "1",
                })
                return ("Student academic overview (official GPA snapshot): " + _json(rows), ["student_academic_overview", "gpa_snapshots", "terms"])

            if intent == "attendance":
                rows = await self._get(client, access_token, "student_attendance_summary", {
                    "select": "course_code,course_title,term_name,section_code,total_sessions,unrecorded_sessions,present_count,late_count,absent_count,excused_count,attendance_percentage,last_session_at",
                    "student_id": f"eq.{student_id}",
                    "order": "last_session_at.desc.nullslast",
                    "limit": "100",
                })
                return ("Student attendance summary by course and section: " + _json(rows), ["student_attendance_summary", "attendance_records", "attendance_sessions", "student_meetings"])

            if intent == "grades":
                course_results = await self._get(client, access_token, "student_course_results", {
                    "select": "course_code,course_title,credit_hours,term_code,term_name,enrollment_status,final_percentage,final_grade_letter,final_grade_points,gpa_exclusion_reason,quality_points",
                    "student_id": f"eq.{student_id}",
                    "order": "enrolled_at.desc.nullslast",
                    "limit": "200",
                })
                assessment_results = await self._get(client, access_token, "student_assessment_results", {
                    "select": "course_code,course_title,term_name,component_name,assessment_title,assessment_kind,score,max_score,feedback,published_at",
                    "student_id": f"eq.{student_id}",
                    "order": "published_at.desc",
                    "limit": "200",
                })
                return (
                    "Student academic results: " + _json({
                        "final_course_results": course_results,
                        "published_assessment_results": assessment_results,
                    }),
                    ["student_course_results", "student_assessment_results", "published_grades", "enrollments"],
                )

            if intent == "enrollments":
                rows = await self._get(client, access_token, "student_course_results", {
                    "select": "course_code,course_title,credit_hours,term_code,term_name,enrollment_status,enrolled_at,final_grade_letter,final_grade_points",
                    "student_id": f"eq.{student_id}",
                    "order": "enrolled_at.desc.nullslast",
                    "limit": "100",
                })
                return ("Student course enrollments and final results: " + _json(rows), ["student_course_results", "enrollments", "course_offerings", "courses", "terms"])

            if intent == "timetable":
                rows = await self._get(client, access_token, "student_timetable", {
                    "select": "course_code,course_title,term_name,section_code,day_of_week,starts_at,ends_at,meeting_type,room_code,room_name,building_code,building_name",
                    "student_id": f"eq.{student_id}",
                    "order": "day_of_week.asc,starts_at.asc",
                    "limit": "200",
                })
                return ("Student's assigned timetable: " + _json(rows), ["student_timetable", "student_meetings", "section_meetings", "rooms", "buildings"])

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
