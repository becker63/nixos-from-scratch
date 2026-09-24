from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("factory-config-merge.py")
SPEC = importlib.util.spec_from_file_location("factory_config_merge", MODULE_PATH)
assert SPEC and SPEC.loader
factory_config = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(factory_config)


class FactoryConfigTests(unittest.TestCase):
    def test_complete_routing_preserves_unknown_values_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / ".factory"
            root.mkdir()
            (root / "mcp.json").write_text(
                json.dumps({"mcpServers": {"other": {"command": "other"}}, "future": 1})
            )
            (root / "settings.json").write_text(
                json.dumps(
                    {
                        "futureSetting": True,
                        "sessionDefaultSettings": {
                            "interactionMode": "auto",
                            "futureSessionSetting": "kept",
                        },
                        "subagentModelSettings": {"futureTier": "kept"},
                        "missionModelSettings": {"futureMissionSetting": "kept"},
                        "modelFallbacks": {"some-model": "other-model"},
                    }
                )
            )

            factory_config.configure(root, "/nix/store/example-jev/bin/jev-mcp")
            first_mcp = (root / "mcp.json").read_bytes()
            first_settings = (root / "settings.json").read_bytes()
            factory_config.configure(root, "/nix/store/example-jev/bin/jev-mcp")

            self.assertEqual(first_mcp, (root / "mcp.json").read_bytes())
            self.assertEqual(first_settings, (root / "settings.json").read_bytes())
            mcp = json.loads(first_mcp)
            settings = json.loads(first_settings)

            self.assertEqual(mcp["mcpServers"]["other"]["command"], "other")
            self.assertEqual(mcp["future"], 1)
            self.assertEqual(
                mcp["mcpServers"]["jev"]["env"]["OPENROUTER_API_KEY"],
                "${OPENROUTER_JEV_KEY}",
            )
            self.assertEqual(settings["model"], "glm-5.3-flash")
            self.assertEqual(settings["reasoningEffort"], "max")
            self.assertTrue(settings["showTokenUsageIndicator"])
            self.assertTrue(settings["blockOnMcpLoad"])
            self.assertEqual(settings["subagentAutonomyLevel"], "inherit")
            self.assertEqual(settings["subagentModelSettings"]["lightModel"], "glm-5.3-flash")
            self.assertEqual(settings["subagentModelSettings"]["lightReasoningEffort"], "high")
            self.assertEqual(settings["subagentModelSettings"]["mediumModel"], "glm-5.3-flash")
            self.assertEqual(settings["subagentModelSettings"]["mediumReasoningEffort"], "max")
            self.assertEqual(settings["subagentModelSettings"]["heavyModel"], "glm-5.3")
            self.assertEqual(settings["subagentModelSettings"]["heavyReasoningEffort"], "max")
            self.assertEqual(settings["missionModelSettings"]["workerModel"], "glm-5.3-flash")
            self.assertEqual(settings["missionModelSettings"]["validationWorkerModel"], "glm-5.3")
            self.assertEqual(settings["missionOrchestratorModel"], "glm-5.3")
            self.assertEqual(settings["modelFallbacks"]["glm-5.3-flash"], "glm-5.3")
            self.assertEqual(settings["sessionDefaultSettings"]["specModeModel"], "glm-5.3")
            self.assertEqual(settings["sessionDefaultSettings"]["interactionMode"], "auto")
            self.assertEqual(settings["sessionDefaultSettings"]["futureSessionSetting"], "kept")
            self.assertEqual(settings["subagentModelSettings"]["futureTier"], "kept")
            self.assertEqual(settings["missionModelSettings"]["futureMissionSetting"], "kept")
            self.assertEqual(settings["modelFallbacks"]["some-model"], "other-model")
            self.assertTrue(settings["futureSetting"])
            self.assertNotIn("OPENROUTER", first_settings.decode())
            self.assertEqual(os.stat(root / "mcp.json").st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(root / "settings.json").st_mode & 0o777, 0o600)

    def test_malformed_file_is_not_clobbered(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / ".factory"
            root.mkdir()
            malformed = b"{not-json\n"
            (root / "settings.json").write_bytes(malformed)
            with self.assertRaises(factory_config.ConfigError):
                factory_config.configure(root, "/nix/store/example/bin/jev-mcp")
            self.assertEqual((root / "settings.json").read_bytes(), malformed)
            self.assertFalse((root / "mcp.json").exists())

    def test_existing_interaction_mode_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / ".factory"
            root.mkdir()
            (root / "settings.json").write_text(
                json.dumps({"sessionDefaultSettings": {"interactionMode": "spec"}})
            )
            factory_config.configure(root, "/nix/store/example/bin/jev-mcp")
            settings = json.loads((root / "settings.json").read_text())
            self.assertEqual(settings["sessionDefaultSettings"]["interactionMode"], "spec")


if __name__ == "__main__":
    unittest.main()
