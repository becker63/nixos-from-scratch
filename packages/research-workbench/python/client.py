"""Small Textual observer and Codex App Server stdio client."""

from __future__ import annotations

import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any

from textual.app import App, ComposeResult
from textual.containers import Horizontal
from textual.widgets import Input, Label, RichLog
from textual_plotext import PlotextPlot
from events import load_events
from visualization import JevRouter, evaluate_fixture, load_visualizations, research_curve, validate_spec, visualization_candidate, visualization_from_jev, visualize_tool


class AppServer:
    """JSON-RPC over the Codex CLI's newline-delimited stdio transport."""

    def __init__(self, cwd: Path | None = None, model: str | None = None) -> None:
        executable = shutil.which("codex")
        if not executable:
            raise RuntimeError("codex CLI not found; install it with the existing npm setup")
        self.proc = subprocess.Popen(
            [executable, "app-server", "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
            text=True,
            bufsize=1,
        )
        self.inbox: queue.Queue[dict[str, Any]] = queue.Queue()
        self.events: queue.Queue[dict[str, Any]] = queue.Queue(maxsize=512)
        self.visualizations: queue.Queue[dict[str, Any]] = queue.Queue(maxsize=64)
        self.write_lock = threading.Lock()
        self.request_lock = threading.Lock()
        self.visualization_lock = threading.Lock()
        self.pending_approvals: dict[str, dict[str, Any]] = {}
        self.next_id = 1
        self.cwd = cwd or Path.cwd()
        self.requested_model = model
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.request("initialize", {"clientInfo": {"name": "attune-textual-workbench", "title": "Attune Research Workbench", "version": "0.1.0"}, "capabilities": {"experimentalApi": True}})
            self.notify("initialized", {})
            self.models = self.request("model/list", {"limit": 100}).get("data", [])
        except Exception:
            self.close()
            raise
        args = sys.argv[1:]
        self.thread_id = args[args.index("--resume") + 1] if "--resume" in args and len(args) > args.index("--resume") + 1 else None
        self.thread_ready = False
        self.active_turn_id: str | None = None
        self.active_model = model or next((entry["id"] for entry in self.models if entry.get("isDefault")), None)

    def _read(self) -> None:
        assert self.proc.stdout
        for line in self.proc.stdout:
            try:
                message = json.loads(line)
                if "method" in message:
                    self._put_bounded(self.events, message)
                else:
                    self.inbox.put(message)
            except json.JSONDecodeError:
                self._put_bounded(self.events, {"method": "client/error", "params": {"message": line.rstrip()}})
        self._put_bounded(self.events, {"method": "client/closed", "params": {}})

    @staticmethod
    def _put_bounded(target: queue.Queue[dict[str, Any]], message: dict[str, Any]) -> None:
        try:
            target.put_nowait(message)
        except queue.Full:
            # Keep the protocol reader moving. The most recent state is more
            # useful than stale deltas; requests stay visible under normal load.
            try:
                target.get_nowait()
            except queue.Empty:
                pass
            try:
                target.put_nowait(message)
            except queue.Full:
                pass

    def queue_visualization(self, spec: dict[str, Any]) -> None:
        with self.visualization_lock:
            pending: list[dict[str, Any]] = []
            while True:
                try:
                    old = self.visualizations.get_nowait()
                except queue.Empty:
                    break
                if old.get("id") != spec.get("id"):
                    pending.append(old)
            for old in pending[-63:]:
                self.visualizations.put_nowait(old)
            self.visualizations.put_nowait(spec)

    def _send(self, message: dict[str, Any]) -> None:
        if not self.proc.stdin or self.proc.poll() is not None:
            raise RuntimeError("Codex App Server has exited")
        with self.write_lock:
            self.proc.stdin.write(json.dumps(message) + "\n")
            self.proc.stdin.flush()

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        with self.request_lock:
            ident = self.next_id
            self.next_id += 1
            self._send({"jsonrpc": "2.0", "id": ident, "method": method, "params": params})
            while True:
                message = self.inbox.get(timeout=120)
                if "id" in message and message["id"] == ident:
                    if "error" in message:
                        raise RuntimeError(f"{method}: {message['error']}")
                    return message.get("result", {})
                if message.get("method") and message.get("id") is not None:
                    self.respond_to_server_request(message)

    def respond_to_server_request(self, message: dict[str, Any]) -> str:
        if "method" not in message or "id" not in message:
            return ""
        # Never approve an operation without an explicit, visible user decision.
        method = message["method"]
        if method == "item/tool/call":
            params = message.get("params", {})
            try:
                if params.get("tool") != "visualize":
                    raise ValueError("unsupported tool")
                spec = validate_spec(params.get("arguments"))
                spec["provenance"] = {**spec["provenance"], "source": "Codex visualize tool", "producer": "codex-app-server"}
                self.queue_visualization(spec)
                response = {"success": True, "contentItems": [{"type": "inputText", "text": f"Visualization {spec['id']} shown with provenance."}]}
                notice = f"Codex visualization: {spec['title']} ({spec['type']})"
            except (ValueError, TypeError):
                response = {"success": False, "contentItems": [{"type": "inputText", "text": "Invalid visualization specification; provide bounded typed data and provenance."}]}
                notice = "Invalid visualization request was rejected."
            self._send({"jsonrpc": "2.0", "id": message["id"], "result": response})
            return notice
        if "Approval" in method or method.endswith("/requestApproval"):
            key = str(message["id"])
            self.pending_approvals[key] = message
            detail = json.dumps(message.get("params", {}), ensure_ascii=False)[:1200]
            return f"Approval pending id={key}; review: {detail}; use /approve {key} or /deny {key}."
        if method == "item/tool/requestUserInput":
            self._send({"jsonrpc": "2.0", "id": message["id"], "result": {"answers": {}}})
            return "Codex requested user input; returned no answers."
        else:
            self._send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "unsupported server request"}})
            return f"Unsupported App Server request: {method}"

    def notify(self, method: str, params: dict[str, Any]) -> None:
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def start_turn(self, prompt: str) -> str:
        model = self.active_model
        if model is None and self.models:
            model = self.models[0]["id"]
        if self.thread_id:
            thread_id = self.thread_id
            if not self.thread_ready:
                self.request("thread/resume", {"threadId": thread_id, "cwd": str(self.cwd), **({"model": self.requested_model} if self.requested_model else {})})
                self.thread_ready = True
        else:
            thread = self.request("thread/start", {
                "cwd": str(self.cwd),
                **({"model": self.requested_model or model} if self.requested_model or model else {}),
                "dynamicTools": [visualize_tool()],
                "developerInstructions": (
                    "Favor visual explanation when available evidence has meaningful structure, trends, comparisons, dependencies, or distributions. "
                    "Use visualize proactively when a graph improves understanding. Automatic visualization may already show the same evidence; avoid duplicates. "
                    "Use only grounded values and relationships, with provenance. Prefer clear text when a graph adds no information."
                ),
            })
            thread_id = thread["thread"]["id"]
            self.thread_id = thread_id
            self.thread_ready = True
        turn = self.request("turn/start", {"threadId": thread_id, "input": [{"type": "text", "text": prompt}], **({"model": self.active_model} if self.active_model else {})})
        self.active_turn_id = turn.get("turn", {}).get("id")
        return thread_id

    def interrupt(self) -> None:
        if self.thread_id and self.active_turn_id:
            self.request("turn/interrupt", {"threadId": self.thread_id, "turnId": self.active_turn_id})

    def poll_event(self) -> dict[str, Any] | None:
        try:
            return self.events.get_nowait()
        except queue.Empty:
            return None

    def resolve_approval(self, request_id: str, allow: bool) -> str:
        request = self.pending_approvals.get(request_id)
        if request is None:
            return f"No pending approval id={request_id}"
        method = request["method"]
        if allow and method not in {"item/commandExecution/requestApproval", "item/fileChange/requestApproval", "execCommandApproval", "applyPatchApproval"}:
            return f"Approval type {method} cannot be accepted from this frontend; use Codex native CLI."
        self._send({"jsonrpc": "2.0", "id": request["id"], "result": {"decision": "accept" if allow else "decline"}})
        del self.pending_approvals[request_id]
        return f"Approval {'accepted' if allow else 'declined'}: {request_id}"

    def close(self) -> None:
        if self.proc.poll() is None:
            if self.proc.stdin:
                self.proc.stdin.close()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.terminate()
                try:
                    self.proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                self.proc.wait(timeout=3)


class ResearchWorkbench(App[None]):
    BINDINGS = [
        ("escape", "quit_workbench", "Quit"),
        ("ctrl+c", "interrupt_turn", "Interrupt"),
        ("ctrl+g", "toggle_graph", "Graphs"),
        ("ctrl+n", "next_graph", "Next graph"),
    ]

    CSS = """
    Screen { layout: vertical; }
    #top { height: 3; padding: 0 1; background: $primary; color: $text; }
    #body { height: 1fr; }
    #plot { width: 1fr; height: 1fr; border: round $accent; }
    #output { width: 2fr; height: 1fr; border: round $accent; }
    #prompt { dock: bottom; }
    """

    def __init__(self, events: list[dict[str, Any]]) -> None:
        super().__init__()
        self.events = events
        self.server: AppServer | None = None
        self.visualizations = load_visualizations()
        self.show_graph = True
        self.mode = os.environ.get("CODEX_VISUAL_MODE", "automatic")
        if self.mode not in {"automatic", "minimal", "manual"}:
            self.mode = "automatic"
        if self.mode == "manual":
            self.visualizations = []
        self.jev = JevRouter(os.environ.get("CODEX_JEV_MCP"), budget=3, cwd=getattr(self, "cwd", Path.cwd()))
        self.jev_enabled = os.environ.get("CODEX_JEV_ENABLED", "1") != "0" and self.jev.available
        self.agent_text = ""
        self.seen_candidates: set[str] = set()
        self.command_output: dict[str, str] = {}
        self.observed_events: dict[tuple[str, str, str], dict[str, Any]] = {}
        self.turn_starting = False
        self.pinned_visualization: str | None = None

    def compose(self) -> ComposeResult:
        resume = " · resumed thread" if "--resume" in sys.argv else ""
        yield Label(f"Codex · {self.mode} visualization · JEv {'ready' if self.jev_enabled else 'unavailable/off'} · fixture events{resume} · Ctrl+G graphs", id="top")
        with Horizontal(id="body"):
            plot = PlotextPlot(id="plot")
            self._draw_plot(plot)
            yield plot
            yield RichLog(id="output", auto_scroll=True, wrap=True)
        yield Input(placeholder="Prompt Codex (Enter sends; Ctrl+C interrupts; Esc exits)", id="prompt")

    def on_mount(self) -> None:
        self.set_interval(0.1, self._drain_events)

    def _drain_events(self) -> None:
        if not self.server:
            return
        output = self.query_one("#output", RichLog)
        try:
            while True:
                self._accept_visualization(self.server.visualizations.get_nowait())
        except queue.Empty:
            pass
        while message := self.server.poll_event():
            if message.get("id") is not None:
                notice = self.server.respond_to_server_request(message)
                if notice:
                    output.write_line(notice)
                continue
            method = message.get("method", "")
            params = message.get("params", {})
            if method == "item/agentMessage/delta":
                delta = params.get("delta", "")
                output.write(delta)
            elif method == "commandExecution/outputDelta":
                item_id = params.get("itemId")
                if item_id:
                    self.command_output[item_id] = (self.command_output.get(item_id, "") + params.get("delta", ""))[-32768:]
            elif method == "item/completed":
                self._observe_completed_item(params)
            elif method == "turn/completed":
                self.server.active_turn_id = None
                output.write_line("\n[turn completed]")
            elif method in ("error", "warning", "guardianWarning"):
                output.write_line(f"[{method}] {params}")

    def on_input_submitted(self, event: Input.Submitted) -> None:
        prompt = event.value.strip()
        if not prompt:
            return
        if prompt.startswith("/"):
            self._command(prompt)
            event.input.value = ""
            return
        if self.turn_starting or (self.server and self.server.active_turn_id):
            self.query_one("#output", RichLog).write_line("A Codex turn is already running; use Ctrl+C to interrupt it first.")
            event.input.value = ""
            return
        event.input.value = ""
        output = self.query_one("#output", RichLog)
        output.write_line(f"> {prompt}")
        self.turn_starting = True
        threading.Thread(target=self._run_prompt, args=(prompt,), daemon=True).start()

    def _run_prompt(self, prompt: str) -> None:
        try:
            if self.server is None:
                self.server = AppServer(cwd=getattr(self, "cwd", Path.cwd()), model=getattr(self, "model", None))
            thread_id = self.server.start_turn(prompt)
            self.call_from_thread(self.query_one("#output", RichLog).write_line, f"Started Codex thread {thread_id}")
        except Exception as exc:  # surfaced in the UI
            self.call_from_thread(self.query_one("#output", RichLog).write_line, f"Codex error: {exc}")
        finally:
            self.turn_starting = False

    def action_interrupt_turn(self) -> None:
        if self.server:
            threading.Thread(target=self.server.interrupt, daemon=True).start()
            self.query_one("#output", RichLog).write_line("Interrupt requested")

    def action_quit_workbench(self) -> None:
        if self.server:
            self.server.close()
        self.exit()

    def on_unmount(self) -> None:
        if self.server:
            self.server.close()

    def _draw_plot(self, widget: PlotextPlot) -> None:
        widget.plt.clear_data()
        if not self.show_graph or not self.visualizations:
            widget.border_title = "Visualization hidden · Ctrl+G"
            return
        spec = next((entry for entry in self.visualizations if entry["id"] == self.pinned_visualization), None) or self.visualizations[-1]
        widget.plt.title(spec["title"])
        if spec.get("xAxis", {}).get("label"):
            widget.plt.xlabel(spec["xAxis"]["label"])
        if spec.get("yAxis", {}).get("label"):
            widget.plt.ylabel(spec["yAxis"]["label"])
        if spec["type"] == "heatmap" and spec["data"].get("matrix"):
            widget.plt.matrix_plot(spec["data"]["matrix"])
        for row in spec["data"].get("series", []):
            if spec["type"] == "bar":
                widget.plt.bar(row.get("x", []), row.get("y", []), label=row["label"])
            elif spec["type"] == "scatter":
                widget.plt.scatter(row.get("x", []), row.get("y", []), label=row["label"])
            else:
                widget.plt.plot(row.get("x", []), row.get("y", []), label=row["label"])
        if spec["type"] == "histogram" and spec["data"].get("values"):
            widget.plt.hist(spec["data"]["values"])
        widget.border_title = f"{spec['type']} · {spec.get('provenance', {}).get('source', 'observed')}"

    def _accept_visualization(self, spec: dict[str, Any]) -> None:
        self.visualizations = [old for old in self.visualizations if old["id"] != spec["id"]]
        self.visualizations.append(spec)
        self.visualizations.sort(key=lambda chart: chart.get("routing", {}).get("priorityScore", 3.0))
        self.visualizations = self.visualizations[-8:]
        if self.is_mounted:
            self._draw_plot(self.query_one("#plot", PlotextPlot))
            if spec["type"] in {"tree", "timeline", "table", "heatmap"} or not spec["data"].get("series"):
                output = self.query_one("#output", RichLog)
                output.write_line(f"[{spec['type']}] {spec['title']} · {spec.get('epistemic')} · {json.dumps(spec.get('provenance', {}), separators=(',', ':'))}")
                for row in spec["data"].get("rows", [])[:40]:
                    output.write_line(json.dumps(row, ensure_ascii=False))
                for edge in spec["data"].get("edges", [])[:40]:
                    output.write_line(f"{edge.get('source')} → {edge.get('target')}")
                for node in spec["data"].get("nodes", [])[:40]:
                    output.write_line(f"node {node.get('id')}: {node.get('label', '')}")
                for row in spec["data"].get("matrix", [])[:20]:
                    output.write_line("heatmap row: " + "  ".join(map(str, row)))

    def _observe_completed_item(self, params: dict[str, Any]) -> None:
        """Extract only structured tool results and bounded App Server JSONL output."""
        item = params.get("item", {})
        ids = {"session_id": params.get("threadId"), "turn_id": params.get("turnId"), "tool_call_id": item.get("id")}
        if item.get("type") == "commandExecution":
            output = self.command_output.pop(item.get("id", ""), "")
            for line in output.splitlines():
                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    continue
                self._process_structured_payload(payload, ids)
            return
        if item.get("type") != "mcpToolCall":
            return
        structured = (item.get("result") or {}).get("structuredContent")
        if isinstance(structured, dict):
            self._process_structured_payload(structured, ids)

    def _process_structured_payload(self, structured: Any, ids: dict[str, Any]) -> None:
        if not isinstance(structured, dict):
            return
        if isinstance(structured, dict) and isinstance(structured.get("events"), list):
            for event in structured["events"][:2000]:
                self._process_structured_payload(event, ids)
            return
        if structured.get("schema") == "attune.research-event.v1":
            event_key = (str(structured.get("run", "")), str(structured.get("candidate", "")), str(structured.get("iteration", "")))
            self.observed_events[event_key] = structured
            if len(self.observed_events) > 2000:
                self.observed_events.pop(next(iter(self.observed_events)))
            events = list(self.observed_events.values())
            spec = research_curve(events, session_id=ids.get("session_id"))
            if spec:
                spec["identifiers"].update({"turnId": ids.get("turn_id"), "toolCallId": ids.get("tool_call_id")})
                self._accept_visualization(spec)
            return
        candidate = visualization_candidate(structured, session_id=ids.get("session_id"), turn_id=ids.get("turn_id"), tool_call_id=ids.get("tool_call_id"))
        if not candidate or not self.jev_enabled or self.mode != "automatic":
            return
        fingerprint = candidate["evidenceHash"]
        if fingerprint in self.seen_candidates:
            return
        self.seen_candidates.add(fingerprint)
        if len(self.seen_candidates) > 4096:
            self.seen_candidates.pop()
        def decide() -> None:
            started = time.monotonic()
            result = self.jev.decide(candidate)
            if not result:
                return
            spec = visualization_from_jev(candidate, result)
            elapsed = round((time.monotonic() - started) * 1000, 1)
            usage = result.get("usage", {})
            summary = f"JEv decision · {result.get('model', 'model unknown')} · {elapsed} ms · cost {usage.get('cost', 'unreported')}"
            if spec:
                self.call_from_thread(self._accept_visualization, spec)
                self.call_from_thread(self.query_one("#output", RichLog).write_line, f"{summary} · showing {spec['type']}")
            else:
                self.call_from_thread(self.query_one("#output", RichLog).write_line, f"{summary} · no graph selected")
        threading.Thread(target=decide, daemon=True).start()

    def _command(self, command: str) -> None:
        output = self.query_one("#output", RichLog)
        if command == "/graphs":
            self.show_graph = not self.show_graph
            self._draw_plot(self.query_one("#plot", PlotextPlot))
        elif command == "/next":
            self.action_next_graph()
        elif command == "/jev on":
            self.jev_enabled = self.jev.available
            if not self.jev_enabled:
                output.write_line("JEv unavailable: configure an owner-private .env with OPENROUTER_API_KEY")
        elif command == "/jev off":
            self.jev_enabled = False
        elif command.startswith("/mode ") and command.split(maxsplit=1)[1] in {"automatic", "minimal", "manual"}:
            self.mode = command.split(maxsplit=1)[1]
            output.write_line(f"Visualization mode: {self.mode}")
            if self.mode == "manual":
                self.visualizations = [item for item in self.visualizations if item.get("provenance", {}).get("source") == "Codex visualize tool"]
                self._draw_plot(self.query_one("#plot", PlotextPlot))
            elif self.mode == "automatic":
                self.visualizations = load_visualizations()
                self._draw_plot(self.query_one("#plot", PlotextPlot))
        elif command == "/provenance":
            output.write_line(json.dumps(self.visualizations[-1].get("provenance", {}), indent=2) if self.visualizations else "No graphs")
        elif command == "/data":
            output.write_line(json.dumps(self.visualizations[-1].get("data", {}), indent=2) if self.visualizations else "No graphs")
        elif command == "/table":
            spec = self.visualizations[-1] if self.visualizations else None
            if spec and spec["data"].get("series"):
                for row in spec["data"]["series"]:
                    output.write_line(f"{row['label']}: " + ", ".join(f"({x}, {y})" for x, y in zip(row.get("x", []), row.get("y", []))))
            elif spec:
                rows = spec["data"].get("rows", []) or spec["data"].get("nodes", []) or spec["data"].get("edges", [])
                if rows:
                    for row in rows[:40]:
                        output.write_line(json.dumps(row, ensure_ascii=False))
                elif spec["data"].get("matrix"):
                    for row in spec["data"]["matrix"][:40]:
                        output.write_line(" | ".join(map(str, row)))
                else:
                    output.write_line("No tabular data in this visualization")
            else:
                output.write_line("No graphs")
        elif command == "/pin":
            self.pinned_visualization = self.visualizations[-1]["id"] if self.visualizations else None
            output.write_line("Graph pinned" if self.pinned_visualization else "No graph to pin")
        elif command == "/unpin":
            self.pinned_visualization = None
            output.write_line("Graph unpinned")
        elif command.startswith("/approve ") or command.startswith("/deny "):
            verb, request_id = command.split(maxsplit=1)
            if self.server:
                output.write_line(self.server.resolve_approval(request_id, allow=verb == "/approve"))
            else:
                output.write_line("No active Codex session")
        elif command == "/fixture-study":
            output.write_line(json.dumps(evaluate_fixture(), separators=(",", ":")))
        elif command == "/models":
            if self.server:
                output.write_line("Models: " + ", ".join(f"{m['id']}{' (default)' if m.get('isDefault') else ''}" for m in self.server.models))
            else:
                output.write_line("Models are discovered after the first prompt; launch with codex --model MODEL_ID to preselect.")
        elif command.startswith("/model "):
            model = command.split(maxsplit=1)[1]
            if self.server and any(m.get("id") == model for m in self.server.models):
                self.server.active_model = model
                output.write_line(f"Model selected for following turns: {model}")
            else:
                output.write_line("Unknown model; use /models to list account models after the first prompt.")
        else:
            output.write_line("Commands: /graphs, /next, /pin, /unpin, /data, /table, /provenance, /models, /model ID, /approve ID, /deny ID, /jev on|off, /mode automatic|minimal|manual, /fixture-study")
        jev_state = "ready" if self.jev_enabled else "unavailable/off"
        self.query_one("#top", Label).update(f"Codex · {self.mode} visualization · JEv {jev_state} · Ctrl+G graphs")

    def action_toggle_graph(self) -> None:
        self._command("/graphs")

    def action_next_graph(self) -> None:
        if len(self.visualizations) > 1:
            self.visualizations.append(self.visualizations.pop(0))
            self._draw_plot(self.query_one("#plot", PlotextPlot))


def main() -> None:
    if "--probe-jev" in sys.argv:
        router = JevRouter(os.environ.get("CODEX_JEV_MCP"), budget=1)
        payload = {"schema": "attune.visualization-candidate.v1", "id": "search-frontier-probe", "title": "Observed search branches", "nodes": [{"id": "root", "label": "initial"}, {"id": "a1", "label": "branch A"}, {"id": "b1", "label": "branch B"}, {"id": "a2", "label": "branch A next"}, {"id": "b2", "label": "branch B next"}, {"id": "a3", "label": "branch A final"}], "edges": [{"source": "root", "target": "a1"}, {"source": "root", "target": "b1"}, {"source": "a1", "target": "a2"}, {"source": "b1", "target": "b2"}, {"source": "a2", "target": "a3"}]}
        candidate = visualization_candidate(payload, session_id="probe", turn_id="probe", tool_call_id="probe")
        started = time.monotonic()
        result = router.decide(candidate)
        if not result:
            print("JEv unavailable or request failed; Codex execution remains independent")
            raise SystemExit(2)
        answers = result.get("answers", {})
        spec = visualization_from_jev(candidate, result)
        print(json.dumps({"provider": "OpenRouter Decisions MCP", "model": result.get("model"), "worth": answers.get("worth", {}).get("choice"), "type": answers.get("type", {}).get("choice"), "rendered_type": spec.get("type") if spec else None, "priority_score": answers.get("priority", {}).get("score"), "latency_ms": round((time.monotonic() - started) * 1000, 1), "usage": result.get("usage")}, separators=(",", ":")))
        return
    if "--evaluate-routing" in sys.argv:
        print(json.dumps(evaluate_fixture(), indent=2))
        return
    if "--check-fixture" in sys.argv:
        events = load_events()
        print(f"events={len(events)} candidates={','.join(e['candidate'] for e in events)} best={max(e['best_objective'] for e in events):.2f}")
        return
    args = sys.argv[1:]
    app = ResearchWorkbench(load_events())
    app.cwd = Path.cwd()
    for index, arg in enumerate(args):
        if arg in {"--cd", "-C"} and index + 1 < len(args):
            app.cwd = Path(args[index + 1]).expanduser().resolve()
        elif arg.startswith("--cd="):
            app.cwd = Path(arg.partition("=")[2]).expanduser().resolve()
        elif arg in {"--model", "-m"} and index + 1 < len(args):
            app.model = args[index + 1]
        elif arg.startswith("--model="):
            app.model = arg.partition("=")[2]
    app.jev = JevRouter(os.environ.get("CODEX_JEV_MCP"), budget=3, cwd=app.cwd)
    app.jev_enabled = os.environ.get("CODEX_JEV_ENABLED", "1") != "0" and app.jev.available
    app.run()


if __name__ == "__main__":
    main()
