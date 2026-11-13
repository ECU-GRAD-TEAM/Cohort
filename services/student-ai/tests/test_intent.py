import asyncio
import unittest

from app.intent import classify_intents


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
