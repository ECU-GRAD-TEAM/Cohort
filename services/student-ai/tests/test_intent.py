import unittest

from app.intent import _rule_hint, classify_intent


class IntentRuleTests(unittest.TestCase):
    def test_english_record_prompts(self):
        self.assertEqual(_rule_hint("What is my GPA?"), "gpa")
        self.assertEqual(_rule_hint("How many absences do I have?"), "attendance")
        self.assertEqual(_rule_hint("Show me my published grades"), "grades")
        self.assertEqual(_rule_hint("Which courses am I enrolled in?"), "enrollments")
        self.assertEqual(_rule_hint("Show my timetable"), "timetable")

    def test_arabic_record_prompts(self):
        self.assertEqual(_rule_hint("ما هو معدلي التراكمي؟"), "gpa")
        self.assertEqual(_rule_hint("كم عدد مرات غيابي؟"), "attendance")
        self.assertEqual(_rule_hint("ما هي درجاتي؟"), "grades")
        self.assertEqual(_rule_hint("ما هي موادي؟"), "enrollments")
        self.assertEqual(_rule_hint("اعرض جدولي"), "timetable")

    def test_ambiguous_prompts_use_model_fallback(self):
        self.assertIsNone(_rule_hint("Can you help me understand recursion?"))

    def test_intent_model_output_is_allow_listed(self):
        async def model_call(_messages):
            return '{"intent":"DROP TABLE users"}'

        async def run():
            self.assertEqual(await classify_intent("please look this up", model_call), "none")

        import asyncio
        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
