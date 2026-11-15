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
            if intent == "profile":
                rows = await self._get(client, access_token, "student_profile", {
                    "select": "tenant_id,student_id,full_name,email,program_id,program_name,specialization_id,specialization_name,department_id,department_name,faculty_id,faculty_name,academic_level,enrollment_status",
                    "student_id": f"eq.{student_id}",
                    "limit": "1",
                })
                return ("Student's official Cohort profile: " + _json(rows), ["student_profile", "users", "user_profiles", "student_academic_progressions", "student_programs", "student_specialization_selections"])

            if intent == "gpa":
                rows = await self._get(client, access_token, "student_gpa", {
                    "select": "academic_year_code,academic_year_name,term_id,term_code,term_name,term_kind,term_sequence,term_gpa,cumulative_gpa,term_credits_attempted,cumulative_credits_attempted,cumulative_credits_earned,term_quality_points,cumulative_quality_points,gpa_computed_at",
                    "student_id": f"eq.{student_id}",
                    "order": "academic_year_code.asc,term_sequence.asc,gpa_computed_at.asc",
                    "limit": "100",
                })
                return ("Student GPA and cumulative GPA by academic year and term: " + _json(rows), ["student_gpa", "gpa_snapshots", "terms", "academic_years"])

            if intent == "attendance":
                rows = await self._get(client, access_token, "student_assessments", {
                    "select": "course_code,course_title,academic_year_name,term_name,component_name,component_type,score,max_score,score_percentage,component_weight,result_status,recorded_at,attempt_number",
                    "student_id": f"eq.{student_id}",
                    "component_type": "eq.attendance",
                    "order": "recorded_at.desc.nullslast",
                    "limit": "200",
                })
                return ("Student attendance component records by course and term: " + _json(rows), ["student_assessments", "attendance_records", "attendance_sessions"])

            if intent == "grades":
                course_rows = await self._get(client, access_token, "student_courses", {
                    "select": "course_code,course_title,academic_year_name,term_name,credit_hours,enrollment_status,final_percentage,final_grade_letter,final_grade_points,gpa_exclusion_reason,recorded_at,attempt_number,offering_id",
                    "student_id": f"eq.{student_id}",
                    "order": "recorded_at.desc.nullslast",
                    "limit": "150",
                })
                assessment_rows = await self._get(client, access_token, "student_assessments", {
                    "select": "course_code,course_title,academic_year_name,term_name,component_type,component_name,assessment_title,score,max_score,score_percentage,component_weight,result_status,recorded_at,attempt_number,offering_id",
                    "student_id": f"eq.{student_id}",
                    "order": "recorded_at.desc.nullslast",
                    "limit": "300",
                })
                return ("Student course results and individual assessment components: " + _json({"course_results": course_rows, "assessments": assessment_rows}), ["student_courses", "student_assessments", "enrollments", "grade_entries"])

            if intent == "enrollments":
                rows = await self._get(client, access_token, "student_courses", {
                    "select": "course_code,course_title,credit_hours,term_code,term_name,academic_year_name,enrollment_status,final_percentage,final_grade_letter,final_grade_points,attempt_number,offering_id",
                    "student_id": f"eq.{student_id}",
                    "order": "recorded_at.desc.nullslast",
                    "limit": "100",
                })
                return ("Student course enrollments and final results: " + _json(rows), ["student_courses", "enrollments", "course_offerings", "courses", "terms"])

            if intent == "timetable":
                rows = await self._get(client, access_token, "student_timetable", {
                    "select": "course_code,course_title,term_name,section_code,day_of_week,starts_at,ends_at,meeting_type,room_code,room_name,building_code,building_name",
                    "student_id": f"eq.{student_id}",
                    "order": "day_of_week.asc,starts_at.asc",
                    "limit": "200",
                })
                return ("Student's assigned timetable: " + _json(rows), ["student_timetable", "student_meetings", "section_meetings", "rooms", "buildings"])

        return ("No personal record lookup was required for this prompt.", [])


def _json(value: Any) -> str:
    import json
    return json.dumps(value, ensure_ascii=False, default=str)
