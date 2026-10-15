from pathlib import Path
import sys
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "client.py"
sys.path.insert(0, str(SOURCE.parent))
from events import load_events

class FixtureTests(unittest.TestCase):
    def test_shared_fixture_has_expected_treatments_and_best_reward(self):
        events = load_events()
        self.assertEqual(len(events), 8)
        self.assertEqual({event["treatment"] for event in events}, {"J0", "J32", "J100", "uniform"})
        self.assertEqual(max(event["best_objective"] for event in events), 0.63)
        self.assertTrue(any(event["state"] == "failed" for event in events))
        self.assertTrue(any(event["state"] == "canceled" for event in events))

    def test_rejects_unknown_schema(self):
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "bad.jsonl"
            invalid.write_text('{"schema":"unknown"}\n')
            with self.assertRaises(ValueError):
                load_events(invalid)


if __name__ == "__main__":
    unittest.main()
