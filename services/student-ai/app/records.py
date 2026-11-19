"""Read-only retrieval of the authenticated student's own Cohort records.

The service uses the Supabase Data API with the student's verified access token.
Postgres RLS remains the authorization boundary; no service-role key is used.
"""
from __future__ import annotations

import os
import re
from datetime import datetime, timezone
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

            if intent == "student_specialization":
                # The assigned specialization is authoritative. Do not use the
                # tenant-readable request table: it can contain other students'
                # pending selections. Technical elective selections have an own-row RLS policy.
                assignments = await self._get(client, access_token, "student_specializations", {
                    "select": "program_id,specialization_id,status,starts_on,ends_on",
                    "student_id": f"eq.{student_id}",
                    "limit": "20",
                })
                specialization_ids = list(dict.fromkeys(
                    row["specialization_id"] for row in assignments
                    if isinstance(row.get("specialization_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["specialization_id"])
                ))
                program_ids = list(dict.fromkeys(
                    row["program_id"] for row in assignments
                    if isinstance(row.get("program_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["program_id"])
                ))

                specializations: list[dict[str, Any]] = []
                programs: list[dict[str, Any]] = []
                specialization_courses: list[dict[str, Any]] = []
                technical_selections: list[dict[str, Any]] = []
                course_ids: list[str] = []
                if specialization_ids:
                    id_filter = "in.(" + ",".join(specialization_ids) + ")"
                    specializations = await self._get(client, access_token, "specializations", {
                        "select": "id,program_id,code,name,description,is_active",
                        "id": id_filter,
                        "limit": "50",
                    })
                    specialization_courses = await self._get(client, access_token, "specialization_courses", {
                        "select": "specialization_id,course_id,is_required",
                        "specialization_id": id_filter,
                        "limit": "300",
                    })
                    technical_selections = await self._get(client, access_token, "student_technical_elective_selections", {
                        "select": "specialization_id,requirement_group_id,course_id,status,selected_at,withdrawn_at",
                        "student_id": f"eq.{student_id}",
                        "specialization_id": id_filter,
                        "order": "selected_at.desc",
                        "limit": "200",
                    })
                    course_ids.extend(
                        row["course_id"] for row in specialization_courses + technical_selections
                        if isinstance(row.get("course_id"), str)
                        and re.fullmatch(r"[0-9a-fA-F-]{36}", row["course_id"])
                    )
                if program_ids:
                    programs = await self._get(client, access_token, "programs", {
                        "select": "id,code,name,degree_level",
                        "id": "in.(" + ",".join(program_ids) + ")",
                        "limit": "20",
                    })

                course_ids = list(dict.fromkeys(course_ids))
                courses: list[dict[str, Any]] = []
                course_attempts: list[dict[str, Any]] = []
                if course_ids:
                    course_filter = "in.(" + ",".join(course_ids) + ")"
                    courses = await self._get(client, access_token, "courses", {
                        "select": "id,code,title,credit_hours",
                        "id": course_filter,
                        "limit": "300",
                    })
                    # Only this student's own enrollment records are requested.
                    course_attempts = await self._get(client, access_token, "student_courses", {
                        "select": "course_id,enrollment_status,term_code,term_name,final_grade_letter,recorded_at,attempt_number",
                        "student_id": f"eq.{student_id}",
                        "course_id": course_filter,
                        "order": "recorded_at.desc.nullslast",
                        "limit": "300",
                    })

                context = {
                    "assignments": assignments,
                    "specializations": specializations,
                    "programs": programs,
                    "required_and_optional_specialization_courses": specialization_courses,
                    "my_technical_elective_selections": technical_selections,
                    "course_catalogue": courses,
                    "my_enrollment_attempts_for_these_courses": course_attempts,
                }
                return (
                    "The student's official Cohort specialization assignment and related curriculum records. "
                    "Only student_specializations rows returned under this student's JWT are assigned specializations; "
                    "status is the official program_membership_status (active, completed, withdrawn, transferred). "
                    "specialization_courses describes the specialization course catalogue; is_required distinguishes "
                    "required from optional courses. Technical elective selections are restricted by RLS to this student. "
                    "Enrollment attempts are restricted to this student and are supplied as recorded; do not calculate "
                    "completion percentages or claim a course is complete unless an explicit completed enrollment status "
                    "is present. Do not infer a specialization from course choices or pending requests. If assignments "
                    "are empty, say no official specialization assignment is recorded. This is read-only: "
                    + _json(context),
                    ["student_specializations", "specializations", "specialization_courses",
                     "student_technical_elective_selections", "programs", "courses", "student_courses"],
                )

            if intent == "student_course_history":
                rows = await self._get(client, access_token, "student_courses", {
                    "select": "course_code,course_title,credit_hours,term_code,term_name,academic_year_code,academic_year_name,enrollment_status,final_percentage,final_grade_letter,final_grade_points,attempt_number,recorded_at,gpa_exclusion_reason",
                    "student_id": f"eq.{student_id}",
                    "order": "academic_year_code.asc,term_code.asc,course_code.asc,attempt_number.asc",
                    "limit": "500",
                })
                return (
                    "Official Cohort course history for this student. Each row is a separate enrollment attempt. "
                    "Report course, credits, academic year, term, status, recorded final grade, and attempt number "
                    "only when present. Do not infer pass, failure, completion, GPA, or earned credits beyond supplied "
                    "fields. The view excludes waitlisted enrollments. Missing grade fields mean no final grade is "
                    "recorded in this view; do not describe that as zero. This is read-only: "
                    + _json(rows),
                    ["student_courses", "enrollments", "course_offerings", "courses", "terms", "academic_years"],
                )

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
                # The aggregate is computed by the existing security-invoker view.
                # Detail queries are restricted to the programme in the authenticated
                # student's own profile and to that student's own enrollment rows.
                progress_rows = await self._get(client, access_token, "student_degree_progress", {
                    "select": "program_name,specialization_name,total_required_credits,completed_credits,in_progress_credits,remaining_credits,completion_percentage,required_courses_count,completed_required_courses,in_progress_required_courses,remaining_required_courses,last_updated_at",
                    "student_id": f"eq.{student_id}",
                    "limit": "1",
                })
                profile_rows = await self._get(client, access_token, "student_profile", {
                    "select": "program_id,program_name,specialization_id,specialization_name,academic_level",
                    "student_id": f"eq.{student_id}",
                    "limit": "1",
                })
                profile = profile_rows[0] if profile_rows else {}
                program_id = profile.get("program_id")
                if not isinstance(program_id, str) or not re.fullmatch(r"[0-9a-fA-F-]{36}", program_id):
                    return (
                        "No active programme is available in the student's official profile, so detailed "
                        "degree progress, curriculum requirements, and programme prerequisites cannot be calculated. "
                        "Do not infer a programme from course history: " + _json({"progress": progress_rows, "profile": profile_rows}),
                        ["student_degree_progress", "student_profile"],
                    )

                curriculum = await self._get(client, access_token, "program_curriculum_courses", {
                    "select": "course_id,academic_level_id,requirement_type,minimum_grade_points",
                    "program_id": f"eq.{program_id}",
                    "is_active": "eq.true",
                    "limit": "500",
                })
                groups = await self._get(client, access_token, "curriculum_requirement_groups", {
                    "select": "id,academic_level_id,code,title,category,required_course_count,minimum_credit_hours,maximum_credit_hours,is_required,notes,sort_order",
                    "program_id": f"eq.{program_id}",
                    "is_active": "eq.true",
                    "order": "sort_order.asc",
                    "limit": "200",
                })
                group_ids = list(dict.fromkeys(
                    row["id"] for row in groups
                    if isinstance(row.get("id"), str) and re.fullmatch(r"[0-9a-fA-F-]{36}", row["id"])
                ))
                group_options: list[dict[str, Any]] = []
                if group_ids:
                    group_options = await self._get(client, access_token, "curriculum_requirement_group_courses", {
                        "select": "requirement_group_id,course_id,is_active",
                        "requirement_group_id": "in.(" + ",".join(group_ids) + ")",
                        "is_active": "eq.true",
                        "limit": "500",
                    })

                elective_selections = await self._get(client, access_token, "student_technical_elective_selections", {
                    "select": "requirement_group_id,course_id,status,selected_at,withdrawn_at",
                    "student_id": f"eq.{student_id}",
                    "program_id": f"eq.{program_id}",
                    "limit": "200",
                })
                enrollment_rows = await self._get(client, access_token, "enrollments", {
                    "select": "course_id,offering_id,status,final_grade_points,final_grade_letter,credit_hours_attempted,term_id,status_changed_at,enrolled_at",
                    "student_id": f"eq.{student_id}",
                    "order": "enrolled_at.desc",
                    "limit": "500",
                })
                offering_ids = list(dict.fromkeys(
                    row["offering_id"] for row in enrollment_rows
                    if not row.get("course_id") and isinstance(row.get("offering_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["offering_id"])
                ))
                offerings: list[dict[str, Any]] = []
                if offering_ids:
                    offerings = await self._get(client, access_token, "course_offerings", {
                        "select": "id,course_id",
                        "id": "in.(" + ",".join(offering_ids) + ")",
                        "limit": "500",
                    })
                offering_courses = {
                    row["id"]: row.get("course_id") for row in offerings
                    if isinstance(row.get("id"), str)
                }
                attempts_by_course: dict[str, list[dict[str, Any]]] = {}
                for attempt in enrollment_rows:
                    course_id = attempt.get("course_id") or offering_courses.get(attempt.get("offering_id"))
                    if isinstance(course_id, str) and re.fullmatch(r"[0-9a-fA-F-]{36}", course_id):
                        attempts_by_course.setdefault(course_id, []).append({
                            "status": attempt.get("status"),
                            "final_grade_points": attempt.get("final_grade_points"),
                            "final_grade_letter": attempt.get("final_grade_letter"),
                            "term_id": attempt.get("term_id"),
                            "status_changed_at": attempt.get("status_changed_at"),
                            "enrolled_at": attempt.get("enrolled_at"),
                        })

                curriculum_course_ids = [
                    row["course_id"] for row in curriculum
                    if isinstance(row.get("course_id"), str) and re.fullmatch(r"[0-9a-fA-F-]{36}", row["course_id"])
                ]
                option_course_ids = [
                    row["course_id"] for row in group_options
                    if isinstance(row.get("course_id"), str) and re.fullmatch(r"[0-9a-fA-F-]{36}", row["course_id"])
                ]
                selected_course_ids = [
                    row["course_id"] for row in elective_selections
                    if row.get("status") == "selected" and isinstance(row.get("course_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["course_id"])
                ]
                programme_course_ids = list(dict.fromkeys(curriculum_course_ids + option_course_ids + selected_course_ids))
                prerequisite_rows: list[dict[str, Any]] = []
                if programme_course_ids:
                    prerequisite_rows = await self._get(client, access_token, "course_prerequisites", {
                        "select": "course_id,prerequisite_course_id,kind,minimum_grade_points",
                        "course_id": "in.(" + ",".join(programme_course_ids) + ")",
                        "limit": "1000",
                    })
                all_course_ids = list(dict.fromkeys(
                    programme_course_ids + [
                        row["prerequisite_course_id"] for row in prerequisite_rows
                        if isinstance(row.get("prerequisite_course_id"), str)
                        and re.fullmatch(r"[0-9a-fA-F-]{36}", row["prerequisite_course_id"])
                    ]
                ))
                courses: list[dict[str, Any]] = []
                if all_course_ids:
                    courses = await self._get(client, access_token, "courses", {
                        "select": "id,code,title,credit_hours,level",
                        "id": "in.(" + ",".join(all_course_ids) + ")",
                        "limit": "1000",
                    })
                course_by_id = {
                    row["id"]: row for row in courses if isinstance(row.get("id"), str)
                }
                level_ids = list(dict.fromkeys(
                    row["academic_level_id"] for row in curriculum + groups
                    if isinstance(row.get("academic_level_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["academic_level_id"])
                ))
                levels: list[dict[str, Any]] = []
                if level_ids:
                    levels = await self._get(client, access_token, "academic_semesters", {
                        "select": "id,code,name,sequence_number,period_unit,stage_key",
                        "id": "in.(" + ",".join(level_ids) + ")",
                        "limit": "200",
                    })
                level_by_id = {row["id"]: row for row in levels if isinstance(row.get("id"), str)}

                def course_state(course_id: str, minimum_grade_points: Any = None) -> dict[str, Any]:
                    attempts = attempts_by_course.get(course_id, [])
                    completed = any(
                        item.get("status") == "completed"
                        and (minimum_grade_points is None or (
                            item.get("final_grade_points") is not None
                            and float(item["final_grade_points"]) >= float(minimum_grade_points)
                        ))
                        for item in attempts
                    )
                    in_progress = any(item.get("status") == "enrolled" for item in attempts)
                    return {
                        "status": "completed" if completed else ("in_progress" if in_progress else "not_recorded_as_completed"),
                        "attempt_statuses": list(dict.fromkeys(
                            item.get("status") for item in attempts if item.get("status") is not None
                        )),
                    }

                course_progress = []
                for row in curriculum:
                    course_id = row.get("course_id")
                    course = course_by_id.get(course_id, {})
                    state = course_state(course_id, row.get("minimum_grade_points")) if isinstance(course_id, str) else {"status": "unavailable", "attempt_statuses": []}
                    course_progress.append({
                        "requirement_type": row.get("requirement_type"),
                        "minimum_grade_points": row.get("minimum_grade_points"),
                        "study_plan_level": level_by_id.get(row.get("academic_level_id")),
                        "course": {key: course.get(key) for key in ("code", "title", "credit_hours", "level")},
                        **state,
                    })

                group_progress = []
                for group in groups:
                    options = []
                    for option in group_options:
                        if option.get("requirement_group_id") != group.get("id"):
                            continue
                        course_id = option.get("course_id")
                        course = course_by_id.get(course_id, {})
                        state = course_state(course_id) if isinstance(course_id, str) else {"status": "unavailable", "attempt_statuses": []}
                        options.append({
                            "course": {key: course.get(key) for key in ("code", "title", "credit_hours", "level")},
                            **state,
                            "selected_as_technical_elective": any(
                                selection.get("requirement_group_id") == group.get("id")
                                and selection.get("course_id") == course_id
                                and selection.get("status") == "selected"
                                for selection in elective_selections
                            ),
                        })
                    group_progress.append({
                        "code": group.get("code"),
                        "title": group.get("title"),
                        "category": group.get("category"),
                        "is_required": group.get("is_required"),
                        "required_course_count": group.get("required_course_count"),
                        "minimum_credit_hours": group.get("minimum_credit_hours"),
                        "maximum_credit_hours": group.get("maximum_credit_hours"),
                        "notes": group.get("notes"),
                        "study_plan_level": level_by_id.get(group.get("academic_level_id")),
                        "options": options,
                    })

                prerequisites = []
                for rule in prerequisite_rows:
                    target = course_by_id.get(rule.get("course_id"), {})
                    required = course_by_id.get(rule.get("prerequisite_course_id"), {})
                    rule_minimum = rule.get("minimum_grade_points")
                    required_state = course_state(rule.get("prerequisite_course_id"), rule_minimum)
                    prerequisites.append({
                        "course": {key: target.get(key) for key in ("code", "title")},
                        "kind": rule.get("kind"),
                        "minimum_grade_points": rule_minimum,
                        "prerequisite_course": {key: required.get(key) for key in ("code", "title")},
                        "recorded_satisfaction": (
                            required_state["status"] == "completed"
                            or (rule.get("kind") == "corequisite" and required_state["status"] == "in_progress")
                        ),
                        "prerequisite_course_status": required_state["status"],
                    })

                context = {
                    "official_progress_summary": progress_rows,
                    "official_student_programme": profile_rows,
                    "programme_curriculum_courses": course_progress,
                    "curriculum_requirement_groups_and_options": group_progress,
                    "official_prerequisite_and_corequisite_rules": prerequisites,
                    "data_notes": [
                        "The progress summary comes from the existing security-invoker student_degree_progress view.",
                        "Completed course state requires an enrollment status of completed and, when the curriculum specifies it, a final grade meeting minimum_grade_points.",
                        "Choice-group options are alternatives; required_course_count and credit-hour constraints define the group requirement. Do not describe every option as mandatory.",
                        "An unsatisfied prerequisite is a potential planning issue, not a guaranteed registration block; waivers, transfer credit, equivalencies, or registrar overrides may not be represented.",
                        "Only this student's own enrollment rows were used. No academic records were modified.",
                    ],
                }
                return (
                    "Official read-only academic advising context for this student. Use the aggregate progress values as supplied; "
                    "distinguish completed from in-progress credits. Explain curriculum by study-plan level, keep required courses "
                    "separate from choice-group options, and state prerequisite/corequisite rules as recorded. A prerequisite not "
                    "satisfied in Cohort is only a potential issue, not proof that registration will be blocked: "
                    + _json(context),
                    ["student_degree_progress", "student_profile", "program_curriculum_courses", "curriculum_requirement_groups",
                     "curriculum_requirement_group_courses", "student_technical_elective_selections", "academic_semesters",
                     "course_prerequisites", "courses", "enrollments", "course_offerings"],
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

            if intent == "assignments":
                # Assessments RLS exposes only non-draft assessments for offerings/sections
                # in which this authenticated student is enrolled.
                assignments = await self._get(client, access_token, "assessments", {
                    "select": "id,offering_id,title,instructions,status,opens_at,due_at,closes_at,late_policy,grades_released_at",
                    "kind": "eq.assignment",
                    "status": "neq.draft",
                    "order": "due_at.asc.nullslast",
                    "limit": "300",
                })
                assessment_ids = list(dict.fromkeys(
                    row["id"] for row in assignments
                    if isinstance(row.get("id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["id"])
                ))
                offering_ids = list(dict.fromkeys(
                    row["offering_id"] for row in assignments
                    if isinstance(row.get("offering_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["offering_id"])
                ))
                if not assessment_ids:
                    return (
                        "No published assignment assessments are currently visible in Cohort "
                        "for the authenticated student's enrolled courses. This does not mean "
                        "that no assignments exist outside Cohort.",
                        ["assessments", "enrollments"],
                    )

                offerings: list[dict[str, Any]] = []
                courses: list[dict[str, Any]] = []
                terms: list[dict[str, Any]] = []
                if offering_ids:
                    offering_filter = "in.(" + ",".join(offering_ids) + ")"
                    offerings = await self._get(client, access_token, "course_offerings", {
                        "select": "id,course_id,term_id",
                        "id": offering_filter,
                        "limit": "300",
                    })
                    course_ids = list(dict.fromkeys(
                        row["course_id"] for row in offerings
                        if isinstance(row.get("course_id"), str)
                        and re.fullmatch(r"[0-9a-fA-F-]{36}", row["course_id"])
                    ))
                    term_ids = list(dict.fromkeys(
                        row["term_id"] for row in offerings
                        if isinstance(row.get("term_id"), str)
                        and re.fullmatch(r"[0-9a-fA-F-]{36}", row["term_id"])
                    ))
                    if course_ids:
                        courses = await self._get(client, access_token, "courses", {
                            "select": "id,code,title",
                            "id": "in.(" + ",".join(course_ids) + ")",
                            "limit": "300",
                        })
                    if term_ids:
                        terms = await self._get(client, access_token, "terms", {
                            "select": "id,code,name,starts_on,ends_on",
                            "id": "in.(" + ",".join(term_ids) + ")",
                            "limit": "100",
                        })

                submissions = await self._get(client, access_token, "submissions", {
                    "select": "assessment_id,attempt_no,status,started_at,deadline_at,submitted_at,is_late,late_minutes,late_penalty_amount,late_policy_snapshot",
                    "student_id": f"eq.{student_id}",
                    "assessment_id": "in.(" + ",".join(assessment_ids) + ")",
                    "order": "started_at.desc",
                    "limit": "500",
                })

                # Do not expose a published grade until the explicit assessment
                # release timestamp has passed. Grade-entry RLS restricts rows to
                # this student's published results.
                now = datetime.now(timezone.utc)
                released_ids: list[str] = []
                for assignment in assignments:
                    release_at = assignment.get("grades_released_at")
                    if not isinstance(release_at, str):
                        continue
                    try:
                        release_time = datetime.fromisoformat(release_at.replace("Z", "+00:00"))
                    except ValueError:
                        continue
                    if release_time.tzinfo is None:
                        release_time = release_time.replace(tzinfo=timezone.utc)
                    if release_time <= now:
                        released_ids.append(assignment["id"])

                published_grades: list[dict[str, Any]] = []
                if released_ids:
                    published_grades = await self._get(client, access_token, "grade_entries", {
                        "select": "assessment_id,score,max_score,feedback,published_at",
                        "student_id": f"eq.{student_id}",
                        "status": "eq.published",
                        "assessment_id": "in.(" + ",".join(dict.fromkeys(released_ids)) + ")",
                        "order": "published_at.desc.nullslast",
                        "limit": "500",
                    })

                course_by_id = {row.get("id"): row for row in courses}
                term_by_id = {row.get("id"): row for row in terms}
                offering_by_id = {row.get("id"): row for row in offerings}
                submissions_by_assessment: dict[str, list[dict[str, Any]]] = {}
                for submission in submissions:
                    key = submission.get("assessment_id")
                    if isinstance(key, str):
                        submissions_by_assessment.setdefault(key, []).append(submission)
                grades_by_assessment: dict[str, list[dict[str, Any]]] = {}
                for grade in published_grades:
                    key = grade.get("assessment_id")
                    if isinstance(key, str):
                        grades_by_assessment.setdefault(key, []).append(grade)

                for assignment in assignments:
                    offering = offering_by_id.get(assignment.get("offering_id"), {})
                    assignment["course"] = course_by_id.get(offering.get("course_id"))
                    assignment["term"] = term_by_id.get(offering.get("term_id"))
                    assignment["my_submissions"] = submissions_by_assessment.get(assignment["id"], [])
                    assignment["my_published_grades"] = grades_by_assessment.get(assignment["id"], [])

                return (
                    "Official Cohort assignment assessments for the authenticated student, ordered by due date. "
                    "Only non-draft assignment-kind assessments visible under the student's enrollment/section RLS "
                    "are included. Each row includes its course and academic term where those catalogue records "
                    "are available, the recorded instructions and opening/due/closing timestamps, and the official "
                    "late_policy. my_submissions contains only this student's own attempts and recorded submission "
                    "status, timestamp, deadline snapshot and late indicators. my_published_grades contains only "
                    "this student's published grade entries and is populated only after grades_released_at has passed; "
                    "never reveal draft or unreleased marks/feedback. Timestamps include their source timezone offset; "
                    "do not convert to another timezone unless an authoritative student timezone is available. "
                    "Classify upcoming/overdue/completed only from the supplied timestamps and submission status. "
                    "This is read-only: never submit, edit, delete, or claim to submit assignments: "
                    + _json(assignments),
                    ["assessments", "submissions", "grade_entries", "course_offerings", "courses", "terms", "enrollments"],
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
                # Query enrollment rows directly: student_courses intentionally excludes
                # waitlisted rows, while enrollments carries the authoritative status and
                # waitlist_position. RLS limits these rows to the authenticated student.
                enrollment_rows = await self._get(client, access_token, "enrollments", {
                    "select": "id,offering_id,course_id,term_id,status,waitlist_position,enrolled_at,status_changed_at,final_percentage,final_grade_letter,final_grade_points",
                    "student_id": f"eq.{student_id}",
                    "order": "enrolled_at.desc",
                    "limit": "300",
                })
                summary_rows = await self._get(client, access_token, "student_enrollment_summary", {
                    "select": "term_code,term_name,total_enrollments,enrolled_courses_count,waitlisted_courses_count,dropped_courses_count,withdrawn_courses_count,completed_courses_count,failed_courses_count,incomplete_courses_count,registered_credit_hours,last_updated_at",
                    "student_id": f"eq.{student_id}",
                    "order": "term_name.desc",
                    "limit": "30",
                })

                offering_ids = list(dict.fromkeys(
                    row["offering_id"] for row in enrollment_rows
                    if isinstance(row.get("offering_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["offering_id"])
                ))
                offerings: list[dict[str, Any]] = []
                if offering_ids:
                    offerings = await self._get(client, access_token, "course_offerings", {
                        "select": "id,course_id,term_id",
                        "id": "in.(" + ",".join(offering_ids) + ")",
                        "limit": "300",
                    })

                offering_by_id = {row["id"]: row for row in offerings if isinstance(row.get("id"), str)}
                course_ids = list(dict.fromkeys(
                    row.get("course_id") or offering_by_id.get(row.get("offering_id"), {}).get("course_id")
                    for row in enrollment_rows
                    if isinstance(
                        row.get("course_id") or offering_by_id.get(row.get("offering_id"), {}).get("course_id"),
                        str,
                    )
                ))
                term_ids = list(dict.fromkeys(
                    row.get("term_id") or offering_by_id.get(row.get("offering_id"), {}).get("term_id")
                    for row in enrollment_rows
                    if isinstance(
                        row.get("term_id") or offering_by_id.get(row.get("offering_id"), {}).get("term_id"),
                        str,
                    )
                ))

                courses: list[dict[str, Any]] = []
                terms: list[dict[str, Any]] = []
                if course_ids:
                    courses = await self._get(client, access_token, "courses", {
                        "select": "id,code,title,credit_hours",
                        "id": "in.(" + ",".join(course_ids) + ")",
                        "limit": "300",
                    })
                if term_ids:
                    # Term catalogue access is tenant-scoped; IDs originate only from
                    # this student's enrollment rows or their linked offerings.
                    terms = await self._get(client, access_token, "terms", {
                        "select": "id,code,name,starts_on,ends_on,registration_opens_at,registration_closes_at,add_drop_ends_at,status",
                        "id": "in.(" + ",".join(term_ids) + ")",
                        "limit": "100",
                    })

                course_by_id = {row["id"]: row for row in courses if isinstance(row.get("id"), str)}
                term_by_id = {row["id"]: row for row in terms if isinstance(row.get("id"), str)}
                detailed_enrollments = []
                for row in enrollment_rows:
                    offering = offering_by_id.get(row.get("offering_id"), {})
                    course_id = row.get("course_id") or offering.get("course_id")
                    term_id = row.get("term_id") or offering.get("term_id")
                    detailed_enrollments.append({
                        **row,
                        "course": course_by_id.get(course_id),
                        "term": term_by_id.get(term_id),
                    })

                return (
                    "The student's official Cohort enrollment records and term-level summary. "
                    "Enrollment rows are filtered by this student's ID under their authenticated JWT. "
                    "Report each row's recorded status exactly (enrolled, waitlisted, dropped, withdrawn, "
                    "completed, failed, or incomplete), and include waitlist_position only when present. "
                    "Course code, title, and credit hours come from the linked official course catalogue. "
                    "Term dates and registration/add-drop deadlines come only from the linked term record "
                    "when present; do not infer that registration is open or closed without comparing the "
                    "recorded timestamps to the current date/time. registered_credit_hours in the summary "
                    "counts only enrolled rows. No pending enrollment status exists in the database. "
                    "This lookup is read-only: "
                    + _json({"term_summaries": summary_rows, "enrollments": detailed_enrollments}),
                    ["enrollments", "student_enrollment_summary", "course_offerings", "courses", "terms"],
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
                    "select": "request_kind,category,subject,description,status,priority,department_code,department_name,sla_due_at,first_response_at,resolved_at,created_at,updated_at,public_comments",
                    "order": "created_at.desc",
                    "limit": "100",
                })
                return (
                    "Official Cohort support requests submitted by the student and publicly visible ticket comments. Internal staff comments, AI triage metadata, and the internal ticket UUID are excluded. No separate human-readable ticket reference is recorded in this source. Report the ticket category, subject, description, official status, priority, department, timestamps, SLA deadline, and public comment history only as returned. Preserve status values exactly (open, in_progress, waiting_on_requester, escalated, resolved, closed); do not invent a pending status. This is a read-only view; do not claim to create, update, or close requests: "
                    + _json(rows),
                    ["student_support_requests", "tickets", "ticket_comments", "departments"],
                )

            if intent == "complaints_incidents":
                rows = await self._get(client, access_token, "student_support_requests", {
                    "select": "request_kind,category,subject,description,status,priority,department_code,department_name,sla_due_at,first_response_at,resolved_at,created_at,updated_at,public_comments",
                    "request_kind": "eq.complaint",
                    "order": "created_at.desc",
                    "limit": "100",
                })
                return (
                    "Official Cohort complaint tickets submitted by this student, filtered to request_kind=complaint under the student's JWT and the student_support_requests security-invoker view. Report only returned complaint fields and public comments. Internal comments, AI triage metadata, and internal UUIDs are excluded. Preserve recorded ticket statuses exactly. Important limitation: incidents and incident_tickets are operations-staff-only tables under current RLS, so this assistant cannot retrieve or confirm incident-report records; an empty complaint list does not mean no incident report exists. Do not imply complaint and incident records are interchangeable. This is read-only: "
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

            if intent == "lost_and_found":
                rows = await self._get(client, access_token, "lost_and_found", {
                    "select": "item_id,item_kind,title,description,category,building_id,building_code,building_name,location_text,occurred_at,status,created_at",
                    "order": "created_at.desc",
                    "limit": "200",
                })
                return (
                    "Official Cohort lost-and-found reports visible to this authenticated student, newest first. The security-invoker view preserves the existing tenant-scoped RLS policies on lost_items and buildings. Report the item kind, title, description, category, location, occurred date, and official status only as supplied. Reporter identities and photo storage paths are intentionally excluded. This is read-only; do not create, update, or delete lost-and-found reports: "
                    + _json(rows),
                    ["lost_and_found", "lost_items", "buildings"],
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


            if intent == "surveys":
                # Survey visibility is governed by the surveys table's RLS.
                # Participation is fetched separately and RLS limits it to auth.uid().
                rows = await self._get(client, access_token, "surveys", {
                    "select": "id,title,description,offering_id,is_anonymous,questions,opens_at,closes_at,created_at",
                    "order": "opens_at.desc",
                    "limit": "200",
                })
                participation = await self._get(client, access_token, "survey_participation", {
                    "select": "survey_id,responded_at",
                    "user_id": f"eq.{student_id}",
                    "order": "responded_at.desc",
                    "limit": "500",
                })
                participation_by_survey = {
                    row["survey_id"]: row.get("responded_at")
                    for row in participation
                    if isinstance(row.get("survey_id"), str)
                }
                for survey in rows:
                    survey["my_responded_at"] = participation_by_survey.get(survey.get("id"))
                    survey["has_participated"] = survey.get("id") in participation_by_survey
                return (
                    "Official Cohort surveys visible to this authenticated student, ordered by opening date. The surveys table RLS enforces tenant, institution-wide opening, course-offering enrollment, creator, and survey-manager visibility. The student's own participation timestamp is fetched separately under survey_participation RLS. Determine upcoming/open/closed from opens_at and closes_at relative to the current date/time; do not infer that a survey is open merely because it is visible. questions contains survey structure, not submitted answers. Never retrieve or disclose survey_responses, any other student's participation, or individual answers; preserve the anonymous setting. This is read-only: do not submit, edit, or withdraw responses: "
                    + _json(rows),
                    ["surveys", "survey_participation"],
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

            if intent == "student_financial_transactions":
                rows = await self._get(client, access_token, "student_financial_transaction_history", {
                    "select": "transaction_id,transaction_type,status,amount,currency_code,description,reference_number,occurred_at,posted_at,term_id,term_code,term_name",
                    "student_id": f"eq.{student_id}",
                    "order": "occurred_at.desc",
                    "limit": "500",
                })
                return (
                    "Official Cohort financial transaction history for this student, newest first. "
                    "Each row is an individual recorded charge, payment, scholarship, discount, or refund. "
                    "Report amount and currency exactly as supplied; never combine different currencies. "
                    "Show transaction type, status, date, academic term, description, and reference number only "
                    "when present. Distinguish posted, pending, and void records. Pending transactions are not "
                    "payments and do not affect the posted balance; void records are not effective transactions. "
                    "Filter by a requested term, type, or status only using returned fields. Do not infer missing "
                    "transactions, payment completion, or a balance from this history. This is read-only: "
                    + _json(rows),
                    ["student_financial_transaction_history", "student_financial_transactions", "terms"],
                )

            if intent == "student_financial_summary":
                summary = await self._get(client, access_token, "student_financial_summary", {
                    "select": "currency_code,posted_transaction_count,pending_transaction_count,posted_charge_total,posted_payment_total,posted_scholarship_total,posted_discount_total,posted_refund_total,outstanding_balance,pending_transaction_amount,latest_transaction_at",
                    "student_id": f"eq.{student_id}",
                    "limit": "20",
                })
                history = await self._get(client, access_token, "student_financial_transaction_history", {
                    "select": "transaction_id,transaction_type,status,amount,currency_code,description,reference_number,occurred_at,posted_at,term_code,term_name",
                    "student_id": f"eq.{student_id}",
                    "order": "occurred_at.desc",
                    "limit": "500",
                })
                if not summary:
                    context_note = (
                        "No official financial transactions are currently returned for this student by Cohort. "
                        "This does not establish a zero balance; the balance is unavailable and must not be inferred."
                    )
                else:
                    context_note = (
                        "Official financial summary from Cohort. outstanding_balance is calculated only from posted "
                        "charges and refunds minus posted payments, scholarships, and discounts. Pending amounts are "
                        "reported separately and excluded from the balance. Refunds increase the amount owed. "
                        "Currency totals must never be combined across currencies."
                    )
                return (
                    context_note
                    + " Summary: " + _json(summary)
                    + " Transaction history by academic term: " + _json(history)
                    + " This is read-only; do not initiate payments or modify financial records.",
                    ["student_financial_summary", "student_financial_transaction_history", "student_financial_transactions", "terms", "users"],
                )

            if intent == "instructor_office_hours":
                # Resolve only sections visible in the authenticated student's timetable.
                timetable = await self._get(client, access_token, "student_timetable", {
                    "select": "course_code,course_title,term_code,term_name,section_id,section_code",
                    "student_id": f"eq.{student_id}",
                    "order": "term_code.asc,course_code.asc,section_code.asc",
                    "limit": "300",
                })
                section_ids = list(dict.fromkeys(
                    row["section_id"] for row in timetable
                    if isinstance(row.get("section_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["section_id"])
                ))
                if not section_ids:
                    return (
                        "Cohort has no assigned timetable sections available for this student, "
                        "so instructor assignments and course-specific office hours cannot be resolved. "
                        "This does not establish that the courses have no instructors or office hours.",
                        ["student_timetable", "student_meetings", "enrollments"],
                    )

                # section_instructors is tenant-readable; constrain it to this student's section IDs.
                assignments = await self._get(client, access_token, "section_instructors", {
                    "select": "section_id,user_id,role",
                    "section_id": "in.(" + ",".join(section_ids) + ")",
                    "limit": "300",
                })
                staff_ids = list(dict.fromkeys(
                    row["user_id"] for row in assignments
                    if isinstance(row.get("user_id"), str)
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", row["user_id"])
                ))
                office_hours: list[dict[str, Any]] = []
                if staff_ids:
                    office_hours = await self._get(client, access_token, "office_hours", {
                        "select": "staff_id,weekday,starts_at,ends_at,mode,location,slot_minutes,valid_from,valid_until",
                        "staff_id": "in.(" + ",".join(staff_ids) + ")",
                        "order": "weekday.asc,starts_at.asc",
                        "limit": "500",
                    })

                hours_by_staff: dict[str, list[dict[str, Any]]] = {}
                for hours in office_hours:
                    staff_id = hours.get("staff_id")
                    if isinstance(staff_id, str):
                        hours_by_staff.setdefault(staff_id, []).append({
                            "weekday": hours.get("weekday"),
                            "starts_at": hours.get("starts_at"),
                            "ends_at": hours.get("ends_at"),
                            "mode": hours.get("mode"),
                            "location": hours.get("location"),
                            "slot_minutes": hours.get("slot_minutes"),
                            "valid_from": hours.get("valid_from"),
                            "valid_until": hours.get("valid_until"),
                        })
                assignments_by_section: dict[str, list[dict[str, Any]]] = {}
                for assignment in assignments:
                    section_id, staff_id = assignment.get("section_id"), assignment.get("user_id")
                    if isinstance(section_id, str) and isinstance(staff_id, str):
                        assignments_by_section.setdefault(section_id, []).append({
                            "role": assignment.get("role"),
                            "office_hours": hours_by_staff.get(staff_id, []),
                        })

                courses: list[dict[str, Any]] = []
                seen_sections: set[str] = set()
                for row in timetable:
                    section_id = row.get("section_id")
                    if not isinstance(section_id, str) or section_id in seen_sections:
                        continue
                    seen_sections.add(section_id)
                    courses.append({
                        "course_code": row.get("course_code"),
                        "course_title": row.get("course_title"),
                        "term_code": row.get("term_code"),
                        "term_name": row.get("term_name"),
                        "section_code": row.get("section_code"),
                        "instructor_assignments": assignments_by_section.get(section_id, []),
                    })

                return (
                    "Official instructor assignments and office-hour schedules for sections in this authenticated "
                    "student's own timetable. Instructor assignments are sourced from section_instructors and "
                    "office hours from office_hours under the student's JWT and existing tenant RLS. Weekday values "
                    "use PostgreSQL numbering (0=Sunday through 6=Saturday). Apply valid_from and valid_until before "
                    "describing a schedule as current; a null valid_until means no end date is recorded. The office "
                    "hours table has no email, phone, or meeting-link columns. Current user_profiles and "
                    "person_profile_emails RLS policies allow students to read only their own profile/contact records, "
                    "so instructor names and direct contact details are intentionally not queried or exposed. "
                    "Do not reveal staff UUIDs or infer identities from role labels. If no assignment or office-hour "
                    "rows are returned, report that the information is unavailable in these records, not that the "
                    "instructor or schedule does not exist. This is read-only; do not book appointments or modify "
                    "office hours: " + _json(courses),
                    ["student_timetable", "student_meetings", "section_meetings", "enrollments",
                     "section_instructors", "office_hours", "user_profiles", "person_profile_emails"],
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
