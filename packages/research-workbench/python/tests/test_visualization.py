import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "python"))
from events import load_events
from visualization import JevRouter, _compact_jev_evidence, evaluate_fixture, load_visualizations, research_curve, validate_spec, visualization_candidate, visualization_from_jev


class VisualizationTests(unittest.TestCase):
    def test_shared_versioned_fixture_has_provenance_and_all_treatments(self):
        specs = load_visualizations()
        self.assertEqual(len(specs), 1)
        spec = specs[0]
        self.assertEqual(spec["schema"], "attune.visualization.v1")
        self.assertEqual(spec["epistemic"], "observed")
        self.assertEqual(spec["provenance"]["eventCount"], 8)
        self.assertEqual([series["label"] for series in spec["data"]["series"]], ["J0", "J32", "J100", "uniform"])

    def test_deterministic_measurements_make_replaceable_line_spec(self):
        spec = research_curve(load_events(), session_id="fixture-session")
        self.assertEqual(spec["type"], "line")
        self.assertEqual(spec["identifiers"]["sessionId"], "fixture-session")
        self.assertEqual(spec["update"]["mode"], "replace")
        self.assertEqual(spec["data"]["series"][0]["y"], [0.31, 0.46, 0.63])

    def test_invalid_or_unbounded_data_is_rejected(self):
        with self.assertRaises(ValueError):
            validate_spec({"schema": "attune.visualization.v0"})
        spec = load_visualizations()[0]
        spec["data"]["series"][0]["x"].append(4)
        with self.assertRaises(ValueError):
            validate_spec(spec)

    def test_routing_study_compares_four_strategies_and_finds_structural_gain(self):
        result = evaluate_fixture()
        strategies = result["strategies"]
        self.assertEqual(strategies["deterministic"]["fixture_cases"], 12)
        self.assertEqual(strategies["deterministic"]["missed_opportunities"], 3)
        self.assertEqual(strategies["deterministic+jev-fixture"]["missed_opportunities"], 0)
        self.assertEqual(strategies["deterministic+jev-fixture"]["unnecessary_graphs"], 0)
        self.assertEqual(strategies["deterministic+jev-fixture"]["duplicate_graph_cases"], 1)
        self.assertEqual(strategies["deterministic+jev-fixture"]["simulated_inference_requests"], 3)
        self.assertEqual(strategies["deterministic+jev-fixture"]["duplicate_graphs_emitted"], 0)
        self.assertEqual(result["evidence"], "deterministic synthetic fixture; fixtureJeV labels simulate classifier outputs, not live JEv")

    def test_disabled_jev_stays_disabled_without_credentials(self):
        router = JevRouter(None, budget=1)
        self.assertIsNone(router.decide({"small": "evidence"}))
        self.assertEqual(router.requests, 0)

    def test_structured_candidate_uses_mocked_jev_choice_to_change_rendered_spec(self):
        observation = {
            "schema": "attune.visualization-candidate.v1",
            "id": "reward-cost-frontier",
            "title": "Reward and inference cost",
            "source": "benchmark-mcp",
            "xField": "cost_usd",
            "yField": "reward",
            "records": [
                {"candidate": "a", "cost_usd": 0.04, "reward": 0.82},
                {"candidate": "b", "cost_usd": 0.01, "reward": 0.79},
                {"candidate": "c", "cost_usd": 0.03, "reward": 0.91},
            ],
        }
        candidate = visualization_candidate(observation, session_id="s1", turn_id="t1", tool_call_id="tool1")
        self.assertIn("scatter", candidate["compatibleTypes"])
        fake_mcp_result = {"answers": {
            "worth": {"type": "choice", "choice": "graph"},
            "type": {"type": "choice", "choice": "scatter"},
            "priority": {"type": "score", "score": 4.0},
        }}
        rendered = visualization_from_jev(candidate, fake_mcp_result)
        self.assertEqual(rendered["type"], "scatter")
        self.assertEqual(rendered["data"]["series"][0]["x"], [0.04, 0.01, 0.03])
        self.assertEqual(rendered["data"]["series"][0]["y"], [0.82, 0.79, 0.91])
        self.assertEqual(rendered["epistemic"], "inferred")
        self.assertEqual(rendered["provenance"]["toolCallId"], "tool1")
        self.assertIsNone(visualization_from_jev(candidate, {"answers": {"worth": {"choice": "prose"}, "type": {"choice": "scatter"}}}))

    def test_tree_edges_must_be_explicit_and_reference_given_nodes(self):
        payload = {"schema": "attune.visualization-candidate.v1", "nodes": [{"id": "a"}, {"id": "b"}], "edges": [{"source": "a", "target": "b"}]}
        candidate = visualization_candidate(payload)
        self.assertIn("tree", candidate["compatibleTypes"])
        payload["edges"] = [{"source": "a", "target": "invented"}]
        self.assertIsNone(visualization_candidate(payload))

    def test_jev_receives_compact_chart_fields_without_source_or_secret_strings(self):
        candidate = {
            "title": "Cost frontier",
            "compatibleTypes": {"scatter": "two numeric dimensions"},
            "records": [{"cost_usd": 0.03, "reward": 0.9, "source": "full source text", "candidate": "or-secretvalue12345"}],
            "nodes": [], "edges": [], "values": None, "matrix": None,
        }
        safe = _compact_jev_evidence(candidate)
        self.assertNotIn("source", safe["sampleRecords"][0])
        self.assertEqual(safe["sampleRecords"][0]["candidate"], "or-[redacted]")
        self.assertNotIn("provenance", safe)


if __name__ == "__main__":
    unittest.main()
