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
                    "select": "institutional_id,full_name,email,program_id,program_name,specialization_id,specialization_name,department_id,department_name,faculty_id,faculty_name,academic_level,enrollment_status",
                    "student_id": f"eq.{student_id}",
                    "limit": "1",
                })
                return ("Student's official Cohort profile: " + _json(rows), ["student_profile", "users", "user_profiles", "student_academic_progressions", "student_programs", "student_specializations"])

            if intent == "degree_progress":
                rows = await self._get(client, access_token, "student_degree_progress", {
                    "select": "program_name,specialization_name,total_required_credits,completed_credits,in_progress_credits,remaining_credits,completion_percentage,required_courses_count,completed_required_courses,in_progress_required_courses,remaining_required_courses,last_updated_at",
                    "student_id": f"eq.{student_id}",
                    "limit": "1",
                })
                return (
                    "Student's official degree progress calculated from the assigned program curriculum, required-course rules, elective requirement groups, confirmed specialization selections, and completed/in-progress enrollments. Completed credits exclude currently in-progress credits; remaining credits exclude both completed and in-progress credits: "
                    + _json(rows),
                    ["student_degree_progress", "student_profile", "programs", "program_curriculum_courses", "curriculum_requirement_groups", "curriculum_requirement_group_courses", "student_technical_elective_selections", "student_courses", "enrollments", "courses"],
                )

            if intent == "academic_standing":
                rows = await self._get(client, access_token, "student_academic_standing", {
                    "select": "academic_standing,standing_reason,standing_term_code,standing_term_name,standing_decided_at,cumulative_gpa,term_gpa,gpa_computed_at,enrollment_status,last_updated_at",
                    "student_id": f"eq.{student_id}",
                    "limit": "1",
                })
                return (
                    "Student's latest official Cohort academic standing and latest recorded GPA snapshot. Standing is an official recorded value; GPA does not imply a standing. Cohort currently exposes no dedicated academic-warning count or academic-restriction records, so do not infer or report either: "
                    + _json(rows),
                    ["student_academic_standing", "academic_standings", "gpa_snapshots", "terms", "student_profile", "users"],
                )

            if intent == "gpa":
                rows = await self._get(client, access_token, "student_gpa", {
                    "select": "academic_year_code,academic_year_name,term_id,term_code,term_name,term_kind,term_sequence,term_gpa,cumulative_gpa,term_credits_attempted,cumulative_credits_attempted,cumulative_credits_earned,term_quality_points,cumulative_quality_points,gpa_computed_at",
                    "student_id": f"eq.{student_id}",
                    "order": "academic_year_code.asc,term_sequence.asc,gpa_computed_at.asc",
                    "limit": "100",
                })
                return ("Student GPA and cumulative GPA by academic year and term: " + _json(rows), ["student_gpa", "gpa_snapshots", "terms", "academic_years"])

            if intent == "attendance":
                rows = await self._get(client, access_token, "student_attendance_summary", {
                    "select": "course_id,course_code,course_title,term_id,term_code,term_name,academic_year_id,academic_year_name,total_sessions,attended_sessions,absent_sessions,late_sessions,excused_sessions,attendance_percentage,absence_percentage,last_attendance_date",
                    "student_id": f"eq.{student_id}",
                    "order": "academic_year_name.desc,term_name.desc,course_code.asc",
                    "limit": "200",
                })
                return (
                    "Student's confirmed attendance summary by course, term, and academic year. Pending, rejected, and unconfirmed attendance records are excluded. Present and late count as attended; excused sessions are reported separately and excluded from attendance/absence percentage denominators: "
                    + _json(rows),
                    ["student_attendance_summary", "attendance_records", "attendance_sessions", "sections", "course_offerings", "courses", "terms", "academic_years"],
                )

            if intent == "assessment_results":
                rows = await self._get(client, access_token, "student_assessments", {
                    "select": "course_code,course_title,academic_year_name,term_name,component_type,component_name,assessment_title,score,max_score,score_percentage,component_weight,result_status,recorded_at,attempt_number,offering_id",
                    "student_id": f"eq.{student_id}",
                    "order": "recorded_at.desc.nullslast",
                    "limit": "300",
                })
                return (
                    "Officially released individual assessment results only. Unreleased and superseded results are excluded by the underlying view. Instructor feedback is not available from this source: "
                    + _json(rows),
                    ["student_assessments", "grade_entries", "student_courses", "assessments", "grade_components"],
                )

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
                summary_rows = await self._get(client, access_token, "student_enrollment_summary", {
                    "select": "term_code,term_name,total_enrollments,enrolled_courses_count,waitlisted_courses_count,dropped_courses_count,withdrawn_courses_count,completed_courses_count,failed_courses_count,incomplete_courses_count,registered_credit_hours,last_updated_at",
                    "student_id": f"eq.{student_id}",
                    "order": "term_name.desc",
                    "limit": "30",
                })
                course_rows = await self._get(client, access_token, "student_courses", {
                    "select": "course_code,course_title,credit_hours,term_code,term_name,academic_year_name,enrollment_status,final_percentage,final_grade_letter,final_grade_points,attempt_number,offering_id",
                    "student_id": f"eq.{student_id}",
                    "order": "recorded_at.desc.nullslast",
                    "limit": "100",
                })
                return (
                    "Student's term-level enrollment summary and course-level enrollment records. Registered credit hours include only status 'enrolled'; waitlisted, dropped, withdrawn, completed, failed, and incomplete statuses are separate. The enrollment_status enum has no pending state, so do not claim pending enrollment counts: "
                    + _json({"term_summaries": summary_rows, "courses": course_rows}),
                    ["student_enrollment_summary", "student_courses", "enrollments", "course_offerings", "courses", "terms"],
                )

            if intent == "course_resources":
                rows = await self._get(client, access_token, "student_course_resources", {
                    "select": "course_code,course_title,term_code,term_name,academic_year_code,academic_year_name,resource_source,resource_title,resource_description,resource_kind,resource_origin,resource_created_at,available_at,document_version,document_language,effective_from,effective_until,document_published_at",
                    "student_id": f"eq.{student_id}",
                    "order": "available_at.desc.nullslast,course_code.asc,resource_title.asc",
                    "limit": "300",
                })
                return (
                    "Student's officially published and currently released course resources for currently enrolled offerings. Material publication/release and document scope/audience/version access are enforced by Cohort RLS. Private storage paths are intentionally not returned: "
                    + _json(rows),
                    ["student_course_resources", "materials", "documents", "document_versions", "enrollments", "course_offerings", "courses", "terms", "academic_years"],
                )

            if intent == "exam_schedule":
                rows = await self._get(client, access_token, "student_exam_schedule", {
                    "select": "course_code,course_title,term_code,term_name,academic_year_code,academic_year_name,exam_title,assessment_title,assessment_kind,exam_mode,starts_at,ends_at,instructions,seats_released_at,room_code,room_name,building_code,building_name,seat_number,enrollment_status",
                    "student_id": f"eq.{student_id}",
                    "order": "starts_at.asc",
                    "limit": "200",
                })
                return (
                    "Student's official exam schedule, including academic term and year. Room and seat details are only available after the university releases seat assignments: "
                    + _json(rows),
                    ["student_exam_schedule", "exam_sessions", "seat_assignments", "assessments", "enrollments", "course_offerings", "courses", "terms", "academic_years", "rooms", "buildings"],
                )

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
