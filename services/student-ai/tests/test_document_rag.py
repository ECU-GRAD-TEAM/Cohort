import unittest

from app.ingest_documents import extract_pages, split_text


class DocumentChunkingTests(unittest.TestCase):
    def test_split_text_preserves_page_metadata(self):
        chunks = split_text("A " * 1800, 7, max_chars=100, overlap=10)
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(chunk["metadata"] == {"page": 7} for chunk in chunks))
        self.assertTrue(all(chunk["content"] for chunk in chunks))

    def test_empty_text_produces_no_chunks(self):
        self.assertEqual(split_text(" \n ", 1), [])

    def test_unsupported_file_is_rejected(self):
        with self.assertRaises(ValueError):
            extract_pages("notes.txt", b"plain text")


if __name__ == "__main__":
    unittest.main()
