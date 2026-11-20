import asyncio
import unittest

from app.intent import INTENT_INSTRUCTIONS, classify_intents


class GeminiMultiIntentTests(unittest.TestCase):
    def test_multiple_intents_are_returned_and_deduplicated(self):
        calls = []

        async def model_call(messages):
            calls.append(messages)
            return '{"intents":["gpa","attendance","gpa"]}'

        result = asyncio.run(classify_intents(
            "What is my GPA and how many classes have I missed?", model_call
        ))

        self.assertEqual(result, ["gpa", "attendance"])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0]["role"], "system")

    def test_student_id_is_defined_as_institutional_id_not_uuid(self):
        self.assertIn('"my ID"', INTENT_INSTRUCTIONS)
        self.assertIn("institutional_id", INTENT_INSTRUCTIONS)
        self.assertIn("Never use or reveal the internal student_id UUID", INTENT_INSTRUCTIONS)

    def test_student_events_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["student_events"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show university events and my registrations", model_call)),
            ["student_events"],
        )
        self.assertIn("published activities", INTENT_INSTRUCTIONS)
        self.assertIn("do not register, cancel, or modify participation", INTENT_INSTRUCTIONS)

    def test_announcements_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["announcements"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my university announcements", model_call)),
            ["announcements"],
        )
        self.assertIn("audience rules", INTENT_INSTRUCTIONS)
        self.assertIn("do not publish, edit, delete", INTENT_INSTRUCTIONS.lower())

    def test_lost_and_found_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["lost_and_found"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show lost and found items", model_call)),
            ["lost_and_found"],
        )
        self.assertIn("official lost_and_found view", INTENT_INSTRUCTIONS)
        self.assertIn("Do not reveal reporter identities", INTENT_INSTRUCTIONS)

    def test_surveys_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["surveys"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my surveys and whether I participated", model_call)),
            ["surveys"],
        )
        self.assertIn("survey_participation", INTENT_INSTRUCTIONS)
        self.assertIn("Never retrieve or disclose survey_responses", INTENT_INSTRUCTIONS)

    def test_student_specialization_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["student_specialization"]}'

        self.assertEqual(
            asyncio.run(classify_intents("What is my officially assigned specialization and which courses are required?", model_call)),
            ["student_specialization"],
        )
        self.assertIn("student_specializations", INTENT_INSTRUCTIONS)
        self.assertIn("never infer a specialization from courses", INTENT_INSTRUCTIONS.lower())

    def test_enrollments_intent_includes_waitlist_and_is_read_only(self):
        async def model_call(_messages):
            return '{"intents":["enrollments"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my registered courses and waitlist positions", model_call)),
            ["enrollments"],
        )
        self.assertIn("waitlist_position", INTENT_INSTRUCTIONS)
        self.assertIn("student_enrollment_summary security-invoker view", INTENT_INSTRUCTIONS)
        self.assertIn("Strictly read-only", INTENT_INSTRUCTIONS)

    def test_student_course_history_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["student_course_history"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my course history and repeated attempts", model_call)),
            ["student_course_history"],
        )
        self.assertIn("official student_courses view", INTENT_INSTRUCTIONS)
        self.assertIn("report each attempt separately", INTENT_INSTRUCTIONS)

    def test_student_financial_summary_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["student_financial_summary"]}'

        self.assertEqual(
            asyncio.run(classify_intents("What is my outstanding balance and payment history?", model_call)),
            ["student_financial_summary"],
        )
        self.assertIn("student_financial_transaction_history", INTENT_INSTRUCTIONS)
        self.assertIn("never report a zero balance", INTENT_INSTRUCTIONS)
        self.assertIn("pending transactions", INTENT_INSTRUCTIONS)

    def test_assignments_intent_is_allowed_and_read_only(self):
        async def model_call(_messages):
            return '{"intents":["assignments"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my assignments and due dates", model_call)),
            ["assignments"],
        )
        self.assertIn("kind=assignment", INTENT_INSTRUCTIONS)
        self.assertIn("never submit, edit, delete", INTENT_INSTRUCTIONS)

    def test_support_requests_intent_is_allowed_and_read_only(self):
        async def model_call(_messages):
            return '{"intents":["support_requests"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my support tickets and their latest replies", model_call)),
            ["support_requests"],
        )
        self.assertIn("student_support_requests", INTENT_INSTRUCTIONS)
        self.assertIn("internal staff notes", INTENT_INSTRUCTIONS.lower())
        self.assertIn("do not claim to create, edit, or close a ticket", INTENT_INSTRUCTIONS.lower())

    def test_complaints_incidents_intent_is_allowed_and_read_only(self):
        async def model_call(_messages):
            return '{"intents":["complaints_incidents"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my complaints and incident reports", model_call)),
            ["complaints_incidents"],
        )
        self.assertIn('request_kind=complaint', INTENT_INSTRUCTIONS)
        self.assertIn("operations staff", INTENT_INSTRUCTIONS)
        self.assertIn("do not infer that none exist", INTENT_INSTRUCTIONS.lower())

    def test_instructor_office_hours_intent_is_allowed_and_read_only(self):
        async def model_call(_messages):
            return '{"intents":["instructor_office_hours"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Who teaches my courses and when are their office hours?", model_call)),
            ["instructor_office_hours"],
        )
        self.assertIn("section_instructors", INTENT_INSTRUCTIONS)
        self.assertIn("Do not expose internal staff UUIDs", INTENT_INSTRUCTIONS)
        self.assertIn("do not book appointments", INTENT_INSTRUCTIONS)

    def test_student_financial_transactions_intent_is_allowed(self):
        async def model_call(_messages):
            return '{"intents":["student_financial_transactions"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Show my pending payments for Fall 2026", model_call)),
            ["student_financial_transactions"],
        )
        self.assertIn("student_financial_transaction_history", INTENT_INSTRUCTIONS)
        self.assertIn("void records are ineffective", INTENT_INSTRUCTIONS)
        self.assertIn("Keep currencies separate", INTENT_INSTRUCTIONS)


    def test_course_resources_intent_is_allowed_and_read_only(self):
        async def model_call(_messages):
            return '{"intents":["course_resources"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Find lecture slides for CS101", model_call)),
            ["course_resources"],
        )
        self.assertIn("student_course_resources security-invoker view", INTENT_INSTRUCTIONS)
        self.assertIn("Never expose storage paths", INTENT_INSTRUCTIONS)
        self.assertIn("Never claim to read or summarize files", INTENT_INSTRUCTIONS)


    def test_degree_progress_intent_covers_curriculum_and_prerequisites(self):
        async def model_call(_messages):
            return '{"intents":["degree_progress"]}'

        self.assertEqual(
            asyncio.run(classify_intents(
                "How many credits do I have left and what are the prerequisites for CS301?",
                model_call,
            )),
            ["degree_progress"],
        )
        self.assertIn("student_degree_progress security-invoker view", INTENT_INSTRUCTIONS)
        self.assertIn("course_prerequisites", INTENT_INSTRUCTIONS)
        self.assertIn("potential registration issue", INTENT_INSTRUCTIONS)
        self.assertIn("never register, add/drop courses", INTENT_INSTRUCTIONS)

    def test_course_catalog_intent_is_read_only_and_distinguishes_availability(self):
        async def model_call(_messages):
            return '{"intents":["course_catalog"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Find courses available next semester with prerequisites.", model_call)),
            ["course_catalog"],
        )
        self.assertIn("student_available_courses security-invoker view", INTENT_INSTRUCTIONS)
        self.assertIn("catalogue presence does not mean a course is offered", INTENT_INSTRUCTIONS)
        self.assertIn("Section capacity is not remaining seat availability", INTENT_INSTRUCTIONS)
        self.assertIn("Strictly read-only", INTENT_INSTRUCTIONS)

    def test_graduation_audit_intent_is_official_and_read_only(self):
        async def model_call(_messages):
            return '{"intents":["graduation_audit"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Am I eligible to graduate? Show my audit history.", model_call)),
            ["graduation_audit"],
        )
        self.assertIn("student_graduation_audit security-invoker view", INTENT_INSTRUCTIONS)
        self.assertIn("pending and requires_manual_review are not approval", INTENT_INSTRUCTIONS)
        self.assertIn("Never independently calculate or promise eligibility", INTENT_INSTRUCTIONS)
        self.assertIn("Do not expose internal audit UUIDs", INTENT_INSTRUCTIONS)
        self.assertIn("Strictly read-only", INTENT_INSTRUCTIONS)

    def test_general_question_returns_no_intents(self):
        async def model_call(_messages):
            return '{"intents":[]}'

        self.assertEqual(
            asyncio.run(classify_intents("Explain photosynthesis", model_call)), []
        )

    def test_unknown_intent_fails_closed(self):
        async def model_call(_messages):
            return '{"intents":["gpa","drop_all_tables"]}'

        self.assertEqual(
            asyncio.run(classify_intents("Check my GPA", model_call)), []
        )

    def test_malformed_json_fails_closed(self):
        async def model_call(_messages):
            return "I think the intent is GPA."

        self.assertEqual(
            asyncio.run(classify_intents("Check my GPA", model_call)), []
        )

    def test_json_code_fence_is_accepted(self):
        async def model_call(_messages):
            return '```json\n{"intents":["grades"]}\n```'

        self.assertEqual(
            asyncio.run(classify_intents("Show my marks", model_call)), ["grades"]
        )


if __name__ == "__main__":
    unittest.main()
