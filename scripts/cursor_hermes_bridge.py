#!/usr/bin/env python3

import json
import os
import subprocess
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


HOST = os.environ.get("CURSOR_HERMES_BRIDGE_HOST", "127.0.0.1")
PORT = int(os.environ.get("CURSOR_HERMES_BRIDGE_PORT", "8383"))
WORKSPACE = os.environ.get("CURSOR_HERMES_WORKSPACE", "/home/becker/nixos-from-scratch")
DEFAULT_MODEL = os.environ.get("CURSOR_HERMES_MODEL", "auto")


def find_cursor_agent() -> str:
    explicit = os.environ.get("CURSOR_AGENT_BIN")
    if explicit and Path(explicit).exists():
        return explicit

    versions_dir = Path.home() / ".local" / "share" / "cursor-agent" / "versions"
    candidates = sorted(versions_dir.glob("*/cursor-agent"), reverse=True)
    if not candidates:
        raise FileNotFoundError("Could not find a local cursor-agent binary")
    return str(candidates[0])


CURSOR_AGENT_BIN = find_cursor_agent()


def extract_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    parts.append(str(item.get("text", "")))
                elif "text" in item:
                    parts.append(str(item["text"]))
            else:
                parts.append(str(item))
        return "\n".join(part for part in parts if part).strip()
    if content is None:
        return ""
    return str(content)


def render_prompt(messages: list[dict[str, Any]]) -> str:
    blocks: list[str] = [
        "You are being called through a local compatibility bridge for Hermes Agent.",
        "Reply naturally to the latest request. You may use your normal Cursor agent tools if needed.",
        "Conversation transcript:",
    ]

    for message in messages:
        role = str(message.get("role", "user")).upper()
        text = extract_text(message.get("content"))
        if not text:
            continue
        blocks.append(f"{role}:\n{text}")

    return "\n\n".join(blocks).strip()


def run_cursor_agent(prompt: str, model: str) -> dict[str, Any]:
    command = [
        CURSOR_AGENT_BIN,
        "--print",
        "--output-format",
        "json",
        "--trust",
        "--workspace",
        WORKSPACE,
    ]

    if model and model not in {"default", "auto"}:
        command.extend(["--model", model])

    command.append(prompt)

    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"cursor-agent failed with exit code {result.returncode}: {result.stderr.strip()}"
        )

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if not lines:
        raise RuntimeError("cursor-agent returned no output")

    try:
        payload = json.loads(lines[-1])
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"cursor-agent returned non-JSON output: {lines[-1]}") from exc

    return payload


def make_completion_payload(request: dict[str, Any], cursor_payload: dict[str, Any]) -> dict[str, Any]:
    model = str(request.get("model") or DEFAULT_MODEL)
    text = str(cursor_payload.get("result", ""))
    usage = cursor_payload.get("usage") or {}

    return {
        "id": f"chatcmpl-{uuid.uuid4().hex}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": usage.get("inputTokens", 0),
            "completion_tokens": usage.get("outputTokens", 0),
            "total_tokens": usage.get("inputTokens", 0) + usage.get("outputTokens", 0),
        },
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "cursor-hermes-bridge/0.1"

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_stream(self, payload: dict[str, Any]) -> None:
        chunk_id = payload["id"]
        model = payload["model"]
        text = payload["choices"][0]["message"]["content"]
        created = payload["created"]

        first = {
            "id": chunk_id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [
                {"index": 0, "delta": {"role": "assistant", "content": text}, "finish_reason": None}
            ],
        }
        second = {
            "id": chunk_id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
        }

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        for event in (first, second):
            self.wfile.write(f"data: {json.dumps(event)}\n\n".encode("utf-8"))
        self.wfile.write(b"data: [DONE]\n\n")

    def do_GET(self) -> None:  # noqa: N802
        if self.path in {"/health", "/v1/health"}:
            self._send_json(
                200,
                {
                    "ok": True,
                    "cursorAgentBin": CURSOR_AGENT_BIN,
                    "workspace": WORKSPACE,
                    "defaultModel": DEFAULT_MODEL,
                },
            )
            return

        if self.path == "/v1/models":
            self._send_json(
                200,
                {
                    "object": "list",
                    "data": [
                        {
                            "id": DEFAULT_MODEL,
                            "object": "model",
                            "owned_by": "cursor-subscription",
                        }
                    ],
                },
            )
            return

        self._send_json(404, {"error": {"message": "Not found"}})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/chat/completions":
            self._send_json(404, {"error": {"message": "Not found"}})
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)

        try:
            request = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json(400, {"error": {"message": "Invalid JSON body"}})
            return

        messages = request.get("messages")
        if not isinstance(messages, list) or not messages:
            self._send_json(400, {"error": {"message": "messages must be a non-empty list"}})
            return

        try:
            prompt = render_prompt(messages)
            cursor_payload = run_cursor_agent(prompt, str(request.get("model") or DEFAULT_MODEL))
            completion = make_completion_payload(request, cursor_payload)
        except Exception as exc:  # noqa: BLE001
            self._send_json(
                500,
                {
                    "error": {
                        "message": str(exc),
                        "type": exc.__class__.__name__,
                    }
                },
            )
            return

        if request.get("stream") is True:
            self._send_stream(completion)
        else:
            self._send_json(200, completion)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        print(f"[cursor-hermes-bridge] {self.address_string()} - {format % args}", flush=True)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(
        json.dumps(
            {
                "event": "cursor-hermes-bridge-started",
                "host": HOST,
                "port": PORT,
                "workspace": WORKSPACE,
                "cursorAgentBin": CURSOR_AGENT_BIN,
                "defaultModel": DEFAULT_MODEL,
            }
        ),
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
