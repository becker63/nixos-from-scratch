"""Small typed visualization contract and bounded routing helpers."""

from __future__ import annotations

import json
import hashlib
import math
import os
import re
import select
import subprocess
import threading
import time
from pathlib import Path
from typing import Any

MAX_SPEC_BYTES = 32_768
KINDS = {"line", "bar", "histogram", "scatter", "heatmap", "tree", "timeline", "sparkline", "table"}


def _openrouter_key(cwd: Path | None = None) -> str | None:
    """Read only OPENROUTER_API_KEY from an owner-private .env at runtime."""
    direct = os.environ.get("OPENROUTER_API_KEY") or os.environ.get("OPENROUTER_JEV_KEY")
    if direct:
        return direct
    configured = os.environ.get("CODEX_JEV_ENV_FILE")
    candidates = [Path(configured).expanduser()] if configured else [parent / ".env" for parent in (cwd or Path.cwd()).resolve().parents]
    if not configured:
        candidates.insert(0, (cwd or Path.cwd()).resolve() / ".env")
    for path in candidates:
        key = _read_openrouter_key(path)
        if key:
            return key
    return None


def _read_openrouter_key(path: Path) -> str | None:
    try:
        stat = path.stat()
        if path.is_symlink() or stat.st_uid != os.getuid() or stat.st_mode & 0o077:
            return None
        found = []
        for line in path.read_text().splitlines():
            match = re.fullmatch(r"\s*(?:export\s+)?OPENROUTER_API_KEY\s*=\s*(['\"]?)([A-Za-z0-9_./:+=-]+)\1\s*", line)
            if match:
                found.append(match[2])
        return found[0] if len(found) == 1 else None
    except (OSError, UnicodeError):
        return None


def validate_spec(value: dict[str, Any]) -> dict[str, Any]:
    """Validate and bound the shared JSON visualization contract."""
    if not isinstance(value, dict) or value.get("schema") != "attune.visualization.v1":
        raise ValueError("unsupported visualization schema")
    if not isinstance(value.get("id"), str) or not value["id"].strip():
        raise ValueError("visualization id is required")
    if value.get("type") not in KINDS:
        raise ValueError("unsupported visualization type")
    if not isinstance(value.get("title"), str) or len(value["title"]) > 200:
        raise ValueError("visualization title is invalid")
    if value.get("epistemic") not in ("observed", "inferred"):
        raise ValueError("epistemic must be observed or inferred")
    if not isinstance(value.get("provenance"), dict):
        raise ValueError("provenance is required")
    if not isinstance(value.get("data"), dict):
        raise ValueError("data object is required")
    def inspect_keys(node: Any) -> None:
        if isinstance(node, dict):
            for key, child in node.items():
                if any(word in str(key).lower() for word in ("secret", "token", "password", "credential", "authorization", "api_key")):
                    raise ValueError("credential-like fields are not allowed")
                inspect_keys(child)
        elif isinstance(node, list):
            for child in node:
                inspect_keys(child)
    inspect_keys(value)
    nodes = value["data"].get("nodes", [])
    edges = value["data"].get("edges", [])
    if not isinstance(nodes, list) or len(nodes) > 2000 or not isinstance(edges, list) or len(edges) > 4000:
        raise ValueError("graph node/edge payload exceeds bounds")
    if nodes:
        node_ids = {node.get("id") for node in nodes if isinstance(node, dict) and isinstance(node.get("id"), str)}
        if len(node_ids) != len(nodes):
            raise ValueError("graph nodes require unique string IDs")
        if any(not isinstance(edge, dict) or edge.get("source") not in node_ids or edge.get("target") not in node_ids for edge in edges):
            raise ValueError("graph edges must reference observed node IDs")
    if value.get("type") in {"line", "bar", "scatter", "sparkline"}:
        series = value["data"].get("series")
        if not isinstance(series, list) or not series or len(series) > 32:
            raise ValueError("chart requires at most 32 series")
        for row in series:
            if not isinstance(row, dict) or not isinstance(row.get("label"), str):
                raise ValueError("invalid series")
            xs, ys = row.get("x"), row.get("y")
            if not isinstance(xs, list) or not isinstance(ys, list) or len(xs) != len(ys) or len(xs) > 2000:
                raise ValueError("series data must have matching bounded x and y arrays")
            if any(not isinstance(n, (int, float)) or isinstance(n, bool) or not math.isfinite(n) for n in xs + ys):
                raise ValueError("series values must be finite numbers")
    if value.get("type") == "histogram":
        values = value["data"].get("values")
        if not isinstance(values, list) or not values or len(values) > 2000 or any(not isinstance(n, (int, float)) or isinstance(n, bool) or not math.isfinite(n) for n in values):
            raise ValueError("histogram requires bounded finite values")
    if value.get("type") == "tree":
        if not nodes or not edges:
            raise ValueError("tree requires observed nodes and edges")
    if value.get("type") == "heatmap":
        matrix = value["data"].get("matrix")
        if not isinstance(matrix, list) or not matrix or len(matrix) > 200 or not isinstance(matrix[0], list) or not matrix[0] or len(matrix[0]) > 200:
            raise ValueError("heatmap requires a bounded matrix")
        if any(not isinstance(row, list) or len(row) != len(matrix[0]) or any(not isinstance(n, (int, float)) or isinstance(n, bool) or not math.isfinite(n) for n in row) for row in matrix):
            raise ValueError("heatmap must be a rectangular finite numeric matrix")
    encoded = json.dumps(value, allow_nan=False, separators=(",", ":")).encode()
    if len(encoded) > MAX_SPEC_BYTES:
        raise ValueError("visualization exceeds 32768 bytes")
    return value


def load_visualizations(path: Path | None = None) -> list[dict[str, Any]]:
    path = path or Path(__file__).resolve().parents[1] / "visualizations.jsonl"
    output = []
    for line in path.read_text().splitlines():
        if line.strip():
            output.append(validate_spec(json.loads(line)))
    return output


def research_curve(events: list[dict[str, Any]], *, session_id: str | None = None) -> dict[str, Any] | None:
    """Obvious structured treatment measurements render without inference."""
    valid = [row for row in events if isinstance(row, dict) and row.get("schema") == "attune.research-event.v1" and isinstance(row.get("treatment"), str) and isinstance(row.get("iteration"), int) and not isinstance(row.get("iteration"), bool) and isinstance(row.get("best_objective"), (int, float)) and not isinstance(row.get("best_objective"), bool) and __import__("math").isfinite(row["best_objective"])]
    treatments = sorted({row["treatment"] for row in valid})
    if len(valid) < 2 or len(treatments) < 2:
        return None
    series = []
    for treatment in treatments:
        rows = sorted((r for r in valid if r["treatment"] == treatment), key=lambda r: r["iteration"])
        series.append({"label": treatment, "x": [r["iteration"] for r in rows], "y": [r["best_objective"] for r in rows]})
    return validate_spec({
        "schema": "attune.visualization.v1", "id": "research:best-objective", "type": "line",
        "title": "Best objective by evaluation", "xAxis": {"label": "iteration", "unit": "evaluation"},
        "yAxis": {"label": "best objective", "unit": "reward"}, "data": {"series": series},
        "identifiers": {"sessionId": session_id, "experimentId": events[0].get("experiment")},
        "provenance": {"source": "attune.research-event.v1", "eventCount": len(valid)},
        "epistemic": "observed", "update": {"mode": "replace", "key": "research:best-objective"},
    })


def visualization_candidate(payload: Any, *, session_id: str | None = None, turn_id: str | None = None, tool_call_id: str | None = None) -> dict[str, Any] | None:
    """Discover candidates only from explicitly structured tool result payloads."""
    if not isinstance(payload, dict) or payload.get("schema") != "attune.visualization-candidate.v1":
        return None
    try:
        if len(json.dumps(payload, ensure_ascii=False, allow_nan=False).encode()) > MAX_SPEC_BYTES:
            return None
        validate_spec({"schema": "attune.visualization.v1", "id": "candidate-validation", "type": "table", "title": "Candidate validation", "data": {"rows": payload.get("records", [])[:2000], "nodes": payload.get("nodes", []), "edges": payload.get("edges", []), "values": payload.get("values", []), "matrix": payload.get("matrix", [])}, "provenance": {"source": "candidate"}, "epistemic": "observed"})
    except (TypeError, ValueError):
        return None
    rows = payload.get("records")
    nodes, edges = payload.get("nodes", []), payload.get("edges", [])
    if not isinstance(rows, list) or len(rows) > 2000 or not rows or any(not isinstance(row, dict) for row in rows):
        rows = []
    fields: set[str] = set().union(*(row.keys() for row in rows if isinstance(row, dict))) if rows else set()
    compatible: dict[str, str] = {}
    if rows and {"iteration"}.issubset(fields) and fields.intersection({"value", "reward", "objective", "best_objective"}):
        compatible["line"] = "repeated numeric observations indexed by evaluation"
        compatible["sparkline"] = "compact repeated numeric observations indexed by evaluation"
    if rows and fields.intersection({"category", "treatment", "candidate"}) and fields.intersection({"value", "reward", "objective", "best_objective"}):
        compatible["bar"] = "named categories with observed numeric values"
    x_field = payload.get("xField")
    y_field = payload.get("yField")
    if rows and isinstance(x_field, str) and isinstance(y_field, str) and x_field in fields and y_field in fields and all(isinstance(row.get(x_field), (int, float)) and isinstance(row.get(y_field), (int, float)) for row in rows if isinstance(row, dict)):
        compatible["scatter"] = f"paired numeric measures {x_field} and {y_field}"
    if nodes and edges:
        compatible["tree"] = "explicit nodes and parent/edge relationships from the evidence"
    if rows and fields.intersection({"timestamp", "time"}) and fields.intersection({"event", "state", "stage"}):
        compatible["timeline"] = "timestamped observed events"
    values = payload.get("values")
    if isinstance(values, list) and 2 <= len(values) <= 2000 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in values):
        compatible["histogram"] = "distribution of observed numeric measurements"
    matrix = payload.get("matrix")
    if isinstance(matrix, list) and matrix and all(isinstance(row, list) and len(row) == len(matrix[0]) for row in matrix):
        compatible["heatmap"] = "rectangular observed parameter/value grid"
    if rows and not compatible:
        compatible["table"] = "small structured records whose relationships do not support a clear plot"
    if not compatible:
        return None
    if rows:
        compatible["table"] = "inspect the observed rows without adding a graphical transformation"
    compatible["none"] = "do not display a visualization"
    raw = json.dumps(payload, sort_keys=True, allow_nan=False, separators=(",", ":"))
    digest = hashlib.sha256(raw.encode()).hexdigest()[:12]
    return {"id": str(payload.get("id") or f"candidate:{digest}"), "evidenceHash": digest, "title": str(payload.get("title") or "Structured observation")[:200], "records": rows, "nodes": nodes, "edges": edges, "values": values, "matrix": matrix, "xField": x_field, "yField": y_field, "compatibleTypes": compatible, "provenance": {"source": "Codex App Server structured tool result", "schema": payload["schema"], "sessionId": session_id, "turnId": turn_id, "toolCallId": tool_call_id}}


def visualization_from_jev(candidate: dict[str, Any], decision: dict[str, Any]) -> dict[str, Any] | None:
    """Use JEv only to approve and choose a compatible view; values stay observed."""
    answers = decision.get("answers", {}) if isinstance(decision, dict) else {}
    worth = answers.get("worth", {}).get("choice")
    if worth not in {"graph", "table"}:
        return None
    kind = answers.get("type", {}).get("choice")
    if kind not in candidate["compatibleTypes"]:
        return None
    if worth == "table" and kind != "table":
        kind = "table"
    if kind == "none":
        return None
    score = answers.get("priority", {}).get("score")
    if isinstance(score, (int, float)) and score < 1.5:
        return None
    records = candidate["records"]
    data: dict[str, Any]
    if kind in {"line", "sparkline", "bar", "scatter"}:
        x_field, y_field = candidate.get("xField"), candidate.get("yField")
        if kind == "scatter":
            series = [{"label": f"{y_field} vs {x_field}", "x": [row[x_field] for row in records], "y": [row[y_field] for row in records]}]
            x_axis, y_axis = {"label": x_field}, {"label": y_field}
        else:
            groups: dict[str, list[dict[str, Any]]] = {}
            for row in records:
                label = str(row.get("treatment", row.get("category", row.get("candidate", "observed"))))
                groups.setdefault(label, []).append(row)
            metric = next((name for name in (y_field, "best_objective", "objective", "reward", "value") if records and name in records[0]), "value")
            series = []
            for label, group in groups.items():
                ordered = sorted(group, key=lambda row: row.get("iteration", 0))
                series.append({"label": label, "x": [row.get("iteration", index + 1) for index, row in enumerate(ordered)], "y": [row[metric] for row in ordered]})
            x_axis, y_axis = {"label": "iteration"}, {"label": metric}
        data = {"series": series, "rows": records}
    elif kind == "tree":
        data = {"nodes": candidate["nodes"], "edges": candidate["edges"]}
        x_axis, y_axis = {}, {}
    elif kind == "histogram":
        data = {"values": candidate["values"]}
        x_axis, y_axis = {"label": "observed value"}, {"label": "count"}
    elif kind == "heatmap":
        data = {"matrix": candidate["matrix"]}
        x_axis, y_axis = {}, {}
    elif kind == "timeline":
        data = {"rows": sorted(records, key=lambda row: row.get("timestamp", row.get("time", "")))}
        x_axis, y_axis = {"label": "timestamp"}, {"label": "event"}
    else:
        data = {"rows": records}
        x_axis, y_axis = {}, {}
    spec = {"schema": "attune.visualization.v1", "id": candidate["id"], "type": kind, "title": candidate["title"], "xAxis": x_axis, "yAxis": y_axis, "data": data, "identifiers": {key: value for key, value in candidate["provenance"].items() if key.endswith("Id")}, "provenance": candidate["provenance"], "epistemic": "inferred", "update": {"mode": "replace", "key": candidate["id"]}}
    if isinstance(score, (int, float)):
        spec["routing"] = {"method": "jev", "priorityScore": score, "scoreScale": "ordinal; not a calibrated probability"}
    return validate_spec(spec)


def visualize_tool() -> dict[str, Any]:
    return {"type": "function", "name": "visualize", "description": "Show a grounded chart or relationship graph from supplied data. Use only observed values and supported relationships; include provenance. Updates replace an existing chart with the same id.", "inputSchema": {
        "type": "object", "required": ["schema", "id", "type", "title", "data", "provenance", "epistemic"], "additionalProperties": False,
        "properties": {"schema": {"const": "attune.visualization.v1"}, "id": {"type": "string"}, "type": {"enum": sorted(KINDS)}, "title": {"type": "string"}, "xAxis": {"type": "object"}, "yAxis": {"type": "object"}, "data": {"type": "object"}, "identifiers": {"type": "object"}, "provenance": {"type": "object"}, "epistemic": {"enum": ["observed", "inferred"]}, "uncertainty": {"type": "object"}, "update": {"type": "object"}}}}


def _compact_jev_evidence(candidate: dict[str, Any]) -> dict[str, Any]:
    """Send only chart-relevant fields and a small sample to the router."""
    def safe_text(value: Any) -> str:
        return re.sub(r"(?i)(bearer\s+|(?:sk|or|jev)-)[A-Za-z0-9._-]{8,}", r"\1[redacted]", str(value))[:100]

    allowed = {"iteration", "value", "reward", "objective", "best_objective", "cost_usd", "latency_ms", "treatment", "category", "candidate", "timestamp", "time", "event", "state", "stage"}
    records = []
    for row in candidate.get("records", [])[:40]:
        compact = {key: value for key, value in row.items() if key in allowed}
        for key, value in compact.items():
            if isinstance(value, str):
                compact[key] = safe_text(value)
        records.append(compact)
    nodes = [{key: safe_text(node.get(key, "")) for key in ("id", "label", "state", "candidate") if key in node} for node in candidate.get("nodes", [])[:40]]
    edges = [{key: safe_text(edge[key]) if isinstance(edge[key], str) else edge[key] for key in ("source", "target", "label", "kind") if key in edge} for edge in candidate.get("edges", [])[:80]]
    values = candidate.get("values")
    matrix = candidate.get("matrix")
    return {
        "title": safe_text(candidate.get("title", ""))[:160],
        "compatibleTypes": candidate["compatibleTypes"],
        "recordCount": len(candidate.get("records", [])),
        "sampleRecords": records,
        "nodes": nodes,
        "edges": edges,
        "values": values[:80] if isinstance(values, list) else None,
        "matrixShape": [len(matrix), len(matrix[0])] if isinstance(matrix, list) and matrix and isinstance(matrix[0], list) else None,
    }


class JevRouter:
    """Optional local MCP caller. Calls are budgeted and run off the UI thread."""

    def __init__(self, executable: str | None, budget: int = 3, cwd: Path | None = None):
        self.executable = executable
        self.cwd = cwd or Path.cwd()
        self.budget = max(0, min(int(os.getenv("CODEX_JEV_BUDGET", budget)), 8))
        self.requests = 0
        self.total_latency_ms = 0.0
        self.lock = threading.Lock()
        self.semaphore = threading.Semaphore(1)

    @property
    def available(self) -> bool:
        return bool(self.executable and _openrouter_key(self.cwd))

    def decide(self, candidate: dict[str, Any], timeout: float = 18) -> dict[str, Any] | None:
        with self.lock:
            if not self.executable or self.requests >= self.budget:
                return None
            self.requests += 1
        self.semaphore.acquire()
        started = time.monotonic()
        p = None
        try:
            key = _openrouter_key(self.cwd)
            if not key:
                return None
            env = dict(os.environ, OPENROUTER_API_KEY=key)
            p = subprocess.Popen([self.executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1, env=env)
            def rpc(ident: int, method: str, params: dict[str, Any]) -> dict[str, Any]:
                assert p and p.stdin and p.stdout
                p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": ident, "method": method, "params": params}) + "\n")
                p.stdin.flush()
                while True:
                    if not select.select([p.stdout], [], [], timeout)[0]:
                        raise TimeoutError("JEv decision deadline")
                    response = json.loads(p.stdout.readline())
                    if response.get("id") == ident:
                        if "error" in response:
                            raise RuntimeError("JEv MCP request failed")
                        return response.get("result", {})
            rpc(1, "initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "codex-visual-router", "version": "0.1.0"}})
            p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}) + "\n")
            p.stdin.flush()
            questions = {
                "worth": {"type": "choice", "instructions": "Choose if a visualization adds meaningful information. Never choose a graph only because text is long. Evidence is compact, observed data only.", "criteria": {"graph": "Graph reveals meaningful structure/trend/comparison", "defer": "Need more evidence", "table": "A table is clearer", "prose": "No useful visualization", "unknown": "Insufficient evidence"}},
                "type": {"type": "choice", "instructions": "Select the most explanatory representation compatible with evidence. Use tree only when explicit edges/parents exist. Include none when no graph is warranted.", "criteria": candidate["compatibleTypes"]},
                "priority": {"type": "score", "instructions": "Score priority from 0 (low) to 5 (high). Assess user relevance, explanatory value, novelty, completeness, clarity, and rendering cost.", "criteria": ["relevance", "explanatory value", "novelty", "completeness", "clarity", "low rendering cost"]},
            }
            result = rpc(2, "tools/call", {"name": "jev_decide", "arguments": {"state": _compact_jev_evidence(candidate), "questions": questions}})
            for part in result.get("content", []):
                if part.get("type") == "text":
                    parsed = json.loads(part["text"])
                    with self.lock:
                        self.total_latency_ms += (time.monotonic() - started) * 1000
                    return parsed
        except Exception:
            return None
        finally:
            if p:
                try:
                    p.terminate()
                    p.wait(timeout=1)
                except Exception:
                    p.kill()
            self.semaphore.release()
        return None


def evaluate_fixture(path: Path | None = None) -> dict[str, Any]:
    """Reproducible fixture study; simulated JEv labels are not live inference."""
    path = path or Path(__file__).resolve().parents[1] / "routing-cases.json"
    cases = json.loads(path.read_text())
    result: dict[str, dict[str, Any]] = {}
    strategies = ("deterministic", "deterministic+jev-fixture", "codex-requested", "combined")
    for strategy in strategies:
        tp = fp = fn = correct = duplicates = suppressed = emitted = 0
        jev_requests = 0
        for case in cases:
            expected = case["expectedType"]
            rule = case["deterministicType"]
            jev = case["fixtureJevType"]
            if rule is None and jev not in (None, "none"):
                jev_requests += 1
            agent = case["agentType"]
            if strategy == "deterministic":
                chosen = rule
            elif strategy == "deterministic+jev-fixture":
                chosen = rule or jev
            elif strategy == "codex-requested":
                chosen = agent
            else:
                chosen = rule or jev or agent
            truth = expected not in (None, "none")
            graph = chosen not in (None, "none")
            tp += int(truth and graph)
            fp += int(not truth and graph)
            fn += int(truth and not graph)
            correct += int(chosen == expected)
            duplicates += int(bool(case.get("duplicate")))
            suppressed += int(bool(case.get("duplicate")) and bool(chosen))
        result[strategy] = {"useful_coverage": tp, "missed_opportunities": fn, "unnecessary_graphs": fp, "chart_selection_correct": correct, "duplicate_graph_cases": duplicates, "duplicate_graphs_suppressed": suppressed, "duplicate_graphs_emitted": emitted, "fixture_cases": len(cases), "simulated_inference_requests": jev_requests if strategy in ("deterministic+jev-fixture", "combined") else 0, "simulated_latency_ms": 0, "inference_cost_usd": None}
    return {"evidence": "deterministic synthetic fixture; fixtureJeV labels simulate classifier outputs, not live JEv", "strategies": result}
