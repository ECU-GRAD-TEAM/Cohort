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
        self.assertIn("Do not publish, edit, delete", INTENT_INSTRUCTIONS)

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
