import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))
from client import ResearchWorkbench
from events import load_events


class TextualClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_shared_chart_renders_toggles_and_shuts_down(self):
        app = ResearchWorkbench(load_events())
        async with app.run_test() as pilot:
            await pilot.pause()
            self.assertTrue(app.visualizations)
            self.assertEqual(app.visualizations[0]["schema"], "attune.visualization.v1")
            self.assertTrue(app.show_graph)
            await pilot.press("ctrl+g")
            self.assertFalse(app.show_graph)
            await pilot.press("ctrl+g")
            self.assertTrue(app.show_graph)
            await pilot.press("escape")


if __name__ == "__main__":
    unittest.main()
