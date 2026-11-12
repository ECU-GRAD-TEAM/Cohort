import unittest

from app.supabase_data import classify_intents


class IntentClassificationTests(unittest.TestCase):
    def test_english_personal_record_questions(self):
        self.assertEqual(classify_intents("What is my current CGPA?"), {"gpa"})
        self.assertEqual(classify_intents("Show my published grades"), {"grades"})
        self.assertEqual(classify_intents("How many absences do I have?"), {"attendance"})
        self.assertEqual(classify_intents("Which courses am I registered for?"), {"enrollments"})
        self.assertEqual(classify_intents("Show my weekly timetable"), {"timetable"})

    def test_arabic_personal_record_questions(self):
        self.assertEqual(classify_intents("ما هو معدلي التراكمي؟"), {"gpa"})
        self.assertEqual(classify_intents("اعرض درجاتي"), {"grades"})
        self.assertEqual(classify_intents("كم عدد مرات غيابي؟"), {"attendance"})
        self.assertEqual(classify_intents("ما هي موادي المسجلة؟"), {"enrollments"})
        self.assertEqual(classify_intents("اعرض جدولي"), {"timetable"})

    def test_multiple_intents_are_returned(self):
        self.assertEqual(classify_intents("Compare my GPA and grades"), {"gpa", "grades"})

    def test_general_tutoring_does_not_trigger_personal_records(self):
        self.assertEqual(classify_intents("Explain recursion with a simple example"), set())


if __name__ == "__main__":
    unittest.main()
