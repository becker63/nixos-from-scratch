"""Small Textual observer and Codex App Server stdio client."""

from __future__ import annotations

import json
import queue
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any

from textual.app import App, ComposeResult
from textual.containers import Horizontal
from textual.widgets import Input, Label, RichLog
from textual_plotext import PlotextPlot
from events import load_events


class AppServer:
    """JSON-RPC over the Codex CLI's newline-delimited stdio transport."""

    def __init__(self) -> None:
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
        self.events: queue.Queue[dict[str, Any]] = queue.Queue()
        self.next_id = 1
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.request("initialize", {"clientInfo": {"name": "attune-textual-workbench", "title": "Attune Research Workbench", "version": "0.1.0"}})
            self.notify("initialized", {})
            self.models = self.request("model/list", {"limit": 100}).get("data", [])
        except Exception:
            self.close()
            raise
        args = sys.argv[1:]
        self.thread_id = args[args.index("--resume") + 1] if "--resume" in args and len(args) > args.index("--resume") + 1 else None
        self.thread_ready = False
        self.active_turn_id: str | None = None

    def _read(self) -> None:
        assert self.proc.stdout
        for line in self.proc.stdout:
            try:
                message = json.loads(line)
                if "method" in message:
                    self.events.put(message)
                else:
                    self.inbox.put(message)
            except json.JSONDecodeError:
                self.events.put({"method": "client/error", "params": {"message": line.rstrip()}})
        self.events.put({"method": "client/closed", "params": {}})

    def _send(self, message: dict[str, Any]) -> None:
        if not self.proc.stdin or self.proc.poll() is not None:
            raise RuntimeError("Codex App Server has exited")
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
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
        if "Approval" in method or method.endswith("/requestApproval"):
            self._send({"jsonrpc": "2.0", "id": message["id"], "result": {"decision": "decline"}})
            return f"Approval requested ({method}); denied by default."
        elif method == "item/tool/requestUserInput":
            self._send({"jsonrpc": "2.0", "id": message["id"], "result": {"answers": {}}})
            return "Codex requested user input; returned no answers."
        else:
            self._send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "unsupported server request"}})
            return f"Unsupported App Server request: {method}"

    def notify(self, method: str, params: dict[str, Any]) -> None:
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def start_turn(self, prompt: str) -> str:
        model = next((entry["id"] for entry in self.models if entry.get("isDefault")), None)
        if model is None and self.models:
            model = self.models[0]["id"]
        if self.thread_id:
            thread_id = self.thread_id
            if not self.thread_ready:
                self.request("thread/resume", {"threadId": thread_id, "cwd": str(Path.cwd())})
                self.thread_ready = True
        else:
            thread = self.request("thread/start", {"cwd": str(Path.cwd()), **({"model": model} if model else {})})
            thread_id = thread["thread"]["id"]
            self.thread_id = thread_id
            self.thread_ready = True
        turn = self.request("turn/start", {"threadId": thread_id, "input": [{"type": "text", "text": prompt}]})
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
    ]

    CSS = """
    Screen { layout: vertical; }
    #top { height: 3; padding: 0 1; background: $primary; color: $text; }
    #body { height: 1fr; }
    #plot { width: 2fr; height: 1fr; border: round $accent; }
    #output { width: 1fr; height: 1fr; border: round $accent; }
    #prompt { dock: bottom; }
    """

    def __init__(self, events: list[dict[str, Any]]) -> None:
        super().__init__()
        self.events = events
        self.server: AppServer | None = None

    def compose(self) -> ComposeResult:
        resume = " · resumed thread" if "--resume" in sys.argv else ""
        yield Label(f"Attune research workbench · fixture events · Codex App Server on demand{resume}", id="top")
        with Horizontal(id="body"):
            plot = PlotextPlot(id="plot")
            plot.plt.title("Best objective by evaluation")
            plot.plt.xlabel("iteration")
            plot.plt.ylabel("objective")
            for treatment in ("J0", "J32", "J100", "uniform"):
                points = [event for event in self.events if event["treatment"] == treatment]
                if points:
                    plot.plt.plot([event["iteration"] for event in points], [event["best_objective"] for event in points], label=treatment)
            yield plot
            yield RichLog(id="output", auto_scroll=True, wrap=True)
        yield Input(placeholder="Prompt Codex (Enter sends; Ctrl+C interrupts; Esc exits)", id="prompt")

    def on_mount(self) -> None:
        self.set_interval(0.1, self._drain_events)

    def _drain_events(self) -> None:
        if not self.server:
            return
        output = self.query_one("#output", RichLog)
        while message := self.server.poll_event():
            if message.get("id") is not None:
                notice = self.server.respond_to_server_request(message)
                if notice:
                    output.write_line(notice)
                continue
            method = message.get("method", "")
            params = message.get("params", {})
            if method == "item/agentMessage/delta":
                output.write(params.get("delta", ""))
            elif method == "turn/completed":
                self.server.active_turn_id = None
                output.write_line("\n[turn completed]")
            elif method in ("error", "warning", "guardianWarning"):
                output.write_line(f"[{method}] {params}")

    def on_input_submitted(self, event: Input.Submitted) -> None:
        prompt = event.value.strip()
        if not prompt:
            return
        event.input.value = ""
        output = self.query_one("#output", RichLog)
        output.write_line(f"> {prompt}")
        threading.Thread(target=self._run_prompt, args=(prompt,), daemon=True).start()

    def _run_prompt(self, prompt: str) -> None:
        try:
            if self.server is None:
                self.server = AppServer()
            thread_id = self.server.start_turn(prompt)
            self.call_from_thread(self.query_one("#output", RichLog).write_line, f"Started Codex thread {thread_id}")
        except Exception as exc:  # surfaced in the UI
            self.call_from_thread(self.query_one("#output", RichLog).write_line, f"Codex error: {exc}")

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


def main() -> None:
    if "--check-fixture" in sys.argv:
        events = load_events()
        print(f"events={len(events)} candidates={','.join(e['candidate'] for e in events)} best={max(e['best_objective'] for e in events):.2f}")
        return
    ResearchWorkbench(load_events()).run()


if __name__ == "__main__":
    main()
