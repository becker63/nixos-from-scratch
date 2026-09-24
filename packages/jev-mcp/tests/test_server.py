from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import httpx
import pytest
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from jev_mcp.server import ENDPOINT, MODEL, JevClient, validate_request


CHOICE = {
    "type": "choice",
    "instructions": "Which bounded category applies?",
    "criteria": {"bug": "Broken behavior", "request": "Requested behavior"},
}
NOUL = {"type": "noul", "instructions": "Does the evidence support the claim?"}
SCORE = {
    "type": "score",
    "instructions": "How severe is the impact?",
    "criteria": ["Cosmetic", "Degraded", "Blocking"],
}


def response_payload() -> dict:
    return {
        "model": "typesafe/jev-1.13-20260917",
        "provider": "TypeSafe",
        "id": "gen-dec-test",
        "answers": {
            "kind": {
                "type": "choice",
                "choice": "bug",
                "probabilities": {"bug": 0.8, "request": 0.2},
                "confidence": 0.6,
            },
            "supported": {"type": "noul", "noul": 0.73},
            "severity": {
                "type": "score",
                "score": 1.25,
                "legend": {"0": "Cosmetic", "1": "Degraded", "2": "Blocking"},
                "probabilities": {"0": 0.05, "1": 0.65, "2": 0.3},
                "confidence": 0.55,
            },
        },
        "usage": {"input_tokens": 123, "output_tokens": 30, "cost": 0.00001},
    }


def test_request_schema_accepts_all_primitives_and_batch() -> None:
    questions, state_size, counts = validate_request(
        {"report": "A button stopped working"},
        {"kind": CHOICE, "supported": NOUL, "severity": SCORE},
    )
    assert list(questions) == ["kind", "supported", "severity"]
    assert state_size > 0
    assert counts == {"choice": 1, "noul": 1, "score": 1}


@pytest.mark.parametrize(
    "question",
    [
        {},
        {"type": "other", "instructions": "x"},
        {"type": "choice", "instructions": "x", "criteria": {"only": "one"}},
        {"type": "noul", "instructions": "x", "criteria": {"true": "yes"}},
        {"type": "score", "instructions": "x", "criteria": ["only"]},
        {"type": "noul", "instructions": "", "extra": "not allowed"},
    ],
)
def test_malformed_questions_are_rejected(question: dict) -> None:
    with pytest.raises(ValueError):
        validate_request("state", {"bad": question})


@pytest.mark.asyncio
async def test_decision_preserves_structured_answers_and_usage(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=response_payload())

    client = JevClient(api_key="test-key", transport=httpx.MockTransport(handler))
    result = await client.decide(
        "synthetic state", {"kind": CHOICE, "supported": NOUL, "severity": SCORE}
    )

    assert len(requests) == 1
    sent = json.loads(requests[0].content)
    assert str(requests[0].url) == ENDPOINT
    assert sent["model"] == MODEL
    assert result["answers"]["kind"]["probabilities"]["bug"] == 0.8
    assert result["answers"]["kind"]["confidence"] == 0.6
    assert result["answers"]["supported"]["noul"] == 0.73
    assert result["answers"]["severity"]["confidence"] == 0.55
    assert result["usage"] == {
        "input_tokens": 123,
        "output_tokens": 30,
        "cost": 0.00001,
    }


@pytest.mark.asyncio
async def test_transient_failure_retries_are_bounded(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    attempts = 0
    delays: list[float] = []
    payload = response_payload()
    payload["answers"] = {"supported": payload["answers"]["supported"]}

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            return httpx.Response(503, json={"error": {"message": "busy"}})
        return httpx.Response(200, json=payload)

    async def no_sleep(delay: float) -> None:
        delays.append(delay)

    client = JevClient(
        api_key="test-key",
        transport=httpx.MockTransport(handler),
        sleep=no_sleep,
        max_retries=2,
    )
    await client.decide("state", {"supported": NOUL})
    assert attempts == 3
    assert delays == [0.25, 0.75]
    record = json.loads((tmp_path / "factory/jev-mcp/usage.jsonl").read_text())
    assert record["retry_count"] == 2


@pytest.mark.asyncio
async def test_secret_never_appears_in_error_or_telemetry(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    secret = "super-secret-key"

    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            400, json={"error": {"code": "bad_request", "message": f"bad {secret}"}}
        )

    client = JevClient(
        api_key=secret, transport=httpx.MockTransport(handler), max_retries=0
    )
    with pytest.raises(RuntimeError) as caught:
        await client.decide("state", {"supported": NOUL})
    telemetry = (tmp_path / "factory/jev-mcp/usage.jsonl").read_text()
    assert secret not in str(caught.value)
    assert secret not in telemetry
    record = json.loads(telemetry)
    assert record["success"] is False
    assert record["error_class"] == "JevError"
    assert "state" not in record


@pytest.mark.asyncio
async def test_mcp_initialize_list_call_and_clean_stdio(tmp_path: Path) -> None:
    env = os.environ.copy()
    env["OPENROUTER_API_KEY"] = "protocol-test-key"
    env["XDG_STATE_HOME"] = str(tmp_path)
    params = StdioServerParameters(
        command=sys.executable,
        args=["-m", "jev_mcp.server"],
        env=env,
    )
    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            initialized = await session.initialize()
            assert initialized.serverInfo.name == "jev-mcp"
            tools = await session.list_tools()
            assert [tool.name for tool in tools.tools] == ["jev_decide"]
            assert "Factory model selection" in (tools.tools[0].description or "")
            result = await session.call_tool(
                "jev_decide", {"state": "x", "questions": {}}
            )
            assert result.isError
