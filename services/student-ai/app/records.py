"""Read-only retrieval of the authenticated student's own Cohort records.

The service uses the Supabase Data API with the student's verified access token.
Postgres RLS remains the authorization boundary; no service-role key is used.
"""
from __future__ import annotations

import os
import re
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

            if intent == "graduation_audit":
                rows = await self._get(client, access_token, "student_graduation_audit", {
                    "select": "audit_id,program_code,program_name,degree_level,audit_status,credits_earned,cgpa,unmet_requirements,audited_at,created_at,minimum_total_credits,minimum_cgpa,minimum_attendance_percentage,require_all_core_courses,block_unresolved_incomplete_grades,policy_effective_from,policy_effective_until",
                    "order": "audited_at.desc",
                    "limit": "50",
                })
                return (
                    "The student's official Cohort graduation-audit history, newest audit first. audit_status is authoritative and may be pending, eligible, not_eligible, or requires_manual_review. Report eligibility only when the official status is eligible; pending and requires_manual_review are not approvals. Summarize unmet_requirements exactly as supplied. credits_earned and cgpa are the values recorded by that audit, not necessarily current values. Policy thresholds are from the currently linked policy record; do not assume they are a historical snapshot or use them to override the audit_status. Do not infer graduation or award of a degree: "
                    + _json(rows),
                    ["student_graduation_audit", "graduation_audits", "programs", "program_academic_policies"],
                )

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
                rows = await self._get(client, access_token, "student_assessment_results", {
                    "select": "course_code,course_title,term_code,term_name,academic_year_code,academic_year_name,component_type,component_name,component_weight,assessment_title,assessment_kind,assessment_delivery,opens_at,due_at,closes_at,grades_released_at,score,max_score,score_percentage,feedback,result_status,recorded_at,attempt_number",
                    "student_id": f"eq.{student_id}",
                    "order": "recorded_at.desc.nullslast",
                    "limit": "300",
                })
                return (
                    "Officially published individual assessment results, including instructor feedback only when the grade entry is published. Unreleased and superseded grades are excluded by the database view: "
                    + _json(rows),
                    ["student_assessment_results", "grade_entries", "student_courses", "assessments", "grade_components"],
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

            if intent == "support_requests":
                rows = await self._get(client, access_token, "student_support_requests", {
                    "select": "request_id,request_kind,category,subject,description,status,priority,department_code,department_name,sla_due_at,first_response_at,resolved_at,created_at,updated_at,public_comments",
                    "order": "created_at.desc",
                    "limit": "100",
                })
                return (
                    "Official Cohort support requests submitted by the student and publicly visible ticket comments. Internal staff comments and AI triage metadata are excluded. Status, priority, timestamps, department, and SLA deadline are returned as recorded by Cohort. This is a read-only view; do not claim to create, update, or close requests: "
                    + _json(rows),
                    ["student_support_requests", "tickets", "ticket_comments", "departments"],
                )

            if intent == "appointments":
                rows = await self._get(client, access_token, "student_appointments", {
                    "select": "appointment_id,starts_at,ends_at,status,meeting_mode,topic,location,cancel_reason,created_at",
                    "order": "starts_at.desc",
                    "limit": "100",
                })
                return (
                    "The student's own official Cohort appointments. Status values are requested, confirmed, cancelled, completed, and no_show. Meeting modes are in_person and online. Use only the supplied timestamps, topic, location, and cancellation reason. The current profile RLS does not let a student read arbitrary staff profiles, so no staff name is exposed by this view. This is read-only; do not claim to book, reschedule, or cancel appointments: "
                    + _json(rows),
                    ["student_appointments", "appointments"],
                )

            if intent == "announcements":
                rows = await self._get(client, access_token, "announcements", {
                    "select": "id,audience,department_id,offering_id,section_id,role_key,title,body,priority,publish_at,expires_at,created_at,updated_at",
                    "order": "publish_at.desc",
                    "limit": "200",
                })
                return (
                    "Official Cohort announcements visible to this authenticated student. The announcements table's existing RLS policy enforces tenant isolation, publication/expiry windows, and audience eligibility for institution, department, course offering, section, and role audiences. Only rows returned by that policy are visible here. Report title, body, audience, priority, publication/expiry and related IDs exactly as supplied. Attachments and internal author information are intentionally omitted. This is read-only; do not publish, edit, delete, or change announcement preferences: "
                    + _json(rows),
                    ["announcements"],
                )

            if intent == "student_events":
                rows = await self._get(client, access_token, "student_events", {
                    "select": "event_id,event_kind,title,description,starts_at,ends_at,location_text,building_code,building_name,room_code,room_name,capacity,waitlist_enabled,registration_opens_at,registration_closes_at,has_registration_record,registration_status,registered_at",
                    "order": "starts_at.asc",
                    "limit": "200",
                })
                return (
                    "Official Cohort events visible to this student, ordered by start time. The database enforces published-event visibility and tenant scope through security-invoker RLS. Registration status is returned only for the authenticated student's own registration record. Registration status values are registered, waitlisted, cancelled, and attended. has_registration_record indicates that a registration row exists; it does not mean the registration is currently active. Capacity and waitlist_enabled are source fields, not a guarantee that registration is open or seats remain. This is read-only; do not register, cancel, or change participation: "
                    + _json(rows),
                    ["student_events", "events", "event_registrations", "rooms", "buildings"],
                )

            if intent == "emergency_alerts":
                # First resolve only this student's deliveries. RLS independently
                # enforces user_id = auth.uid() and the active tenant.
                deliveries = await self._get(client, access_token, "emergency_alert_deliveries", {
                    "select": "alert_id,channel,delivered_at,failed_reason,acknowledged_at",
                    "user_id": f"eq.{student_id}",
                    "order": "delivered_at.desc.nullslast",
                    "limit": "200",
                })
                alert_ids = list(dict.fromkeys(
                    row.get("alert_id") for row in deliveries
                    if isinstance(row.get("alert_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["alert_id"])
                ))
                alerts: list[dict[str, Any]] = []
                if alert_ids:
                    alerts = await self._get(client, access_token, "emergency_alerts", {
                        "select": "id,title,body,severity,building_id,issued_at,expires_at,cancelled_at",
                        "id": "in.(" + ",".join(alert_ids) + ")",
                        "order": "issued_at.desc",
                        "limit": "200",
                    })
                delivery_by_alert: dict[str, list[dict[str, Any]]] = {}
                for delivery in deliveries:
                    alert_id = delivery.get("alert_id")
                    if isinstance(alert_id, str):
                        delivery_by_alert.setdefault(alert_id, []).append({
                            "channel": delivery.get("channel"),
                            "delivered_at": delivery.get("delivered_at"),
                            "failed_reason": delivery.get("failed_reason"),
                            "acknowledged_at": delivery.get("acknowledged_at"),
                        })
                for alert in alerts:
                    alert["my_deliveries"] = delivery_by_alert.get(alert.get("id"), [])
                return (
                    "Official Cohort emergency alerts linked to this student's own delivery records, newest first. Delivery channel, delivery failure, and acknowledgement are included only when recorded. Alert rows are fetched only for alert IDs returned by the student's RLS-protected deliveries. Use the supplied severity, instructions, building, issue/expiry/cancellation timestamps and delivery records only; do not claim to acknowledge an alert or change delivery status: "
                    + _json(alerts),
                    ["emergency_alert_deliveries", "emergency_alerts"],
                )

            if intent == "notifications":
                rows = await self._get(client, access_token, "notifications", {
                    "select": "id,category,severity,title,body,link,created_at,read_at",
                    "user_id": f"eq.{student_id}",
                    "order": "created_at.desc",
                    "limit": "100",
                })
                return (
                    "The student's own official Cohort notifications, newest first. Severity values are info, warning, critical, and emergency. is_read is true only when read_at is set. Use supplied categories, titles, message bodies, links, and timestamps only. This is read-only: do not claim to mark notifications as read, delete them, or change notification preferences: "
                    + _json(rows),
                    ["notifications"],
                )

            if intent == "academic_calendar":
                rows = await self._get(client, access_token, "student_academic_calendar", {
                    "select": "term_code,term_name,academic_year_code,academic_year_name,academic_year_status,calendar_name,calendar_timezone,event_kind,event_title,description,location,starts_on,ends_on,event_state",
                    "student_id": f"eq.{student_id}",
                    "order": "starts_on.asc,event_title.asc",
                    "limit": "300",
                })
                return (
                    "Official tenant calendar events applicable to the student's faculty, including term-linked and institution-wide events. Event dates, descriptions, and locations come from Cohort; event_state is calculated from the database current_date. The source schema has no separate event publication or audience flag, so do not claim a distinct publication status: "
                    + _json(rows),
                    ["student_academic_calendar", "academic_calendar_events", "academic_calendars", "terms", "academic_years", "student_profile"],
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
                    "select": "course_code,course_title,term_code,term_name,section_code,day_of_week,starts_at,ends_at,meeting_type,room_code,room_name,building_code,building_name,assigned_at",
                    "student_id": f"eq.{student_id}",
                    "order": "term_code.asc,day_of_week.asc,starts_at.asc",
                    "limit": "300",
                })
                return (
                    "Student's assigned class timetable from Cohort. day_of_week uses PostgreSQL numbering: 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday. Convert this to weekday names when answering; sort by term, weekday, and start time. Filter to a requested term or weekday only after interpreting the student's request. Do not infer dates or a next-class date from recurring weekly meeting times. Missing room/building fields mean Cohort has not supplied that location: "
                    + _json(rows),
                    ["student_timetable", "student_meetings", "section_meetings", "rooms", "buildings", "enrollments", "course_offerings", "terms"],
                )

        return ("No personal record lookup was required for this prompt.", [])


def _json(value: Any) -> str:
    import json
    return json.dumps(value, ensure_ascii=False, default=str)
