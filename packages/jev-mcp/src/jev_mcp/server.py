from __future__ import annotations

import asyncio
import json
import math
import os
import re
import time
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Awaitable, Callable

import httpx
from mcp.server.fastmcp import FastMCP

MODEL = "typesafe/jev-1.13"
ENDPOINT = "https://openrouter.ai/api/alpha/decisions"
MAX_STATE_BYTES = 262_144
MAX_QUESTIONS = 64
TRANSIENT_STATUS = frozenset({408, 429, 500, 502, 503, 504})
QUESTION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")

TOOL_DESCRIPTION = """Use Jev proactively for inexpensive bounded semantic judgments when a problem naturally reduces to selecting among explicit alternatives (choice), estimating whether a semantic proposition holds (noul), or scoring something on a defined ordered scale (score). Good uses include classifying failures, testing whether evidence supports a hypothesis, judging semantic agreement or change/failure relatedness, categorizing user intervention, assessing explicit milestone criteria, ranking semantic severity, and choosing among already-generated bounded candidates. Batch related questions sharing compact, relevant state. Do not use Jev for code or prose generation, planning, arithmetic, counts, dates, exact lookups, repository queries answerable by deterministic tools, shell execution, open-ended brainstorming, or Factory model selection. Never send secrets, credentials, or gratuitously large logs/source dumps. Prefer deterministic code for exact facts. Jev supplies semantic evidence; the calling agent remains responsible for action."""

mcp = FastMCP(
    "jev-mcp",
    instructions="One pinned Jev semantic-decision tool; it is not a model router.",
    log_level="WARNING",
)


class JevError(RuntimeError):
    """A safe, user-facing Jev request failure."""


def _json_size(value: Any, label: str) -> int:
    try:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} must be JSON-compatible: {exc}") from exc
    return len(encoded)


def _nonempty_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    return value


def validate_request(state: Any, questions: Any) -> tuple[dict[str, Any], int, Counter[str]]:
    if not isinstance(state, (str, dict, list)):
        raise ValueError("state must be a string, object, or array")
    state_size = _json_size(state, "state")
    if state_size > MAX_STATE_BYTES:
        raise ValueError(f"state exceeds the {MAX_STATE_BYTES}-byte limit")

    if not isinstance(questions, dict) or not questions:
        raise ValueError("questions must be a non-empty mapping")
    if len(questions) > MAX_QUESTIONS:
        raise ValueError(f"questions exceeds the {MAX_QUESTIONS}-question limit")

    clean: dict[str, Any] = {}
    counts: Counter[str] = Counter()
    for question_id, question in questions.items():
        if not isinstance(question_id, str) or not QUESTION_ID.fullmatch(question_id):
            raise ValueError(f"invalid question ID: {question_id!r}")
        if not isinstance(question, dict):
            raise ValueError(f"questions.{question_id} must be an object")
        extra = set(question) - {"type", "instructions", "criteria"}
        if extra:
            raise ValueError(
                f"questions.{question_id} has unsupported fields: {', '.join(sorted(extra))}"
            )

        kind = question.get("type")
        instructions = _nonempty_text(
            question.get("instructions"), f"questions.{question_id}.instructions"
        )
        output: dict[str, Any] = {"type": kind, "instructions": instructions}

        if kind == "choice":
            criteria = question.get("criteria")
            if not isinstance(criteria, dict) or len(criteria) < 2:
                raise ValueError(
                    f"questions.{question_id}.criteria must contain at least two named choices"
                )
            clean_criteria: dict[str, str] = {}
            for name, description in criteria.items():
                if not isinstance(name, str) or not QUESTION_ID.fullmatch(name):
                    raise ValueError(
                        f"questions.{question_id}.criteria has invalid choice name: {name!r}"
                    )
                clean_criteria[name] = _nonempty_text(
                    description, f"questions.{question_id}.criteria.{name}"
                )
            output["criteria"] = clean_criteria
        elif kind == "noul":
            criteria = question.get("criteria")
            if criteria is not None:
                if not isinstance(criteria, dict) or set(criteria) != {"true", "false"}:
                    raise ValueError(
                        f"questions.{question_id}.criteria must describe both true and false"
                    )
                output["criteria"] = {
                    key: _nonempty_text(
                        criteria[key], f"questions.{question_id}.criteria.{key}"
                    )
                    for key in ("true", "false")
                }
        elif kind == "score":
            criteria = question.get("criteria")
            if not isinstance(criteria, list) or len(criteria) < 2:
                raise ValueError(
                    f"questions.{question_id}.criteria must be an ordered scale with at least two levels"
                )
            output["criteria"] = [
                _nonempty_text(level, f"questions.{question_id}.criteria[{index}]")
                for index, level in enumerate(criteria)
            ]
        else:
            raise ValueError(
                f"questions.{question_id}.type must be choice, noul, or score"
            )

        counts[kind] += 1
        clean[question_id] = output

    _json_size(clean, "questions")
    return clean, state_size, counts


def _redact(text: str, api_key: str) -> str:
    return text.replace(api_key, "[REDACTED]") if api_key else text


def _safe_upstream_error(response: httpx.Response, api_key: str) -> str:
    detail = ""
    try:
        body = response.json()
        error = body.get("error") if isinstance(body, dict) else None
        if isinstance(error, dict):
            code = error.get("code")
            message = error.get("message")
            pieces = [str(value) for value in (code, message) if value]
            detail = ": ".join(pieces)
        elif isinstance(error, str):
            detail = error
    except (ValueError, TypeError):
        pass
    detail = _redact(detail, api_key).replace("\n", " ")[:500]
    suffix = f": {detail}" if detail else ""
    return f"OpenRouter Decisions API returned HTTP {response.status_code}{suffix}"


def _validate_answer(answer: Any, question_id: str, expected_type: str) -> None:
    if not isinstance(answer, dict) or answer.get("type") != expected_type:
        raise JevError(f"OpenRouter returned an invalid answer for {question_id}")
    if expected_type == "noul":
        value = answer.get("noul")
        if not isinstance(value, (int, float)) or isinstance(value, bool) or not 0 <= value <= 1:
            raise JevError(f"OpenRouter returned an invalid noul probability for {question_id}")
    elif expected_type == "choice":
        if not isinstance(answer.get("choice"), str) or not isinstance(
            answer.get("probabilities"), dict
        ):
            raise JevError(f"OpenRouter returned an invalid choice answer for {question_id}")
    elif expected_type == "score":
        score = answer.get("score")
        if (
            not isinstance(score, (int, float))
            or isinstance(score, bool)
            or not math.isfinite(score)
            or not isinstance(answer.get("probabilities"), dict)
            or not isinstance(answer.get("legend"), dict)
        ):
            raise JevError(f"OpenRouter returned an invalid score answer for {question_id}")


def _telemetry_path() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    root = Path(state_home) if state_home else Path.home() / ".local" / "state"
    return root / "factory" / "jev-mcp" / "usage.jsonl"


def write_telemetry(record: dict[str, Any]) -> None:
    path = _telemetry_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        path.parent.chmod(0o700)
    except OSError:
        pass
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    descriptor = os.open(path, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        payload = (json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n").encode()
        os.write(descriptor, payload)
    finally:
        os.close(descriptor)


class JevClient:
    def __init__(
        self,
        *,
        api_key: str,
        transport: httpx.AsyncBaseTransport | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        max_retries: int = 2,
    ) -> None:
        if not api_key:
            raise ValueError("OPENROUTER_API_KEY is not set")
        self.api_key = api_key
        self.transport = transport
        self.sleep = sleep
        self.max_retries = max_retries

    async def decide(self, state: Any, questions: Any) -> dict[str, Any]:
        clean_questions, state_size, counts = validate_request(state, questions)
        payload = {"model": MODEL, "state": state, "questions": clean_questions}
        started = time.monotonic()
        retries = 0
        response_data: dict[str, Any] | None = None
        error_class: str | None = None
        success = False

        timeout = httpx.Timeout(connect=10.0, read=45.0, write=10.0, pool=5.0)
        try:
            async with httpx.AsyncClient(
                timeout=timeout,
                transport=self.transport,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                    "User-Agent": "jev-mcp/0.1.0",
                },
            ) as client:
                for attempt in range(self.max_retries + 1):
                    try:
                        response = await client.post(ENDPOINT, json=payload)
                    except (httpx.TimeoutException, httpx.NetworkError) as exc:
                        if attempt >= self.max_retries:
                            raise JevError(
                                f"OpenRouter Decisions API network failure: {type(exc).__name__}"
                            ) from exc
                        retries += 1
                        await self.sleep(0.25 * (3**attempt))
                        continue

                    if response.status_code in TRANSIENT_STATUS and attempt < self.max_retries:
                        retries += 1
                        await self.sleep(0.25 * (3**attempt))
                        continue
                    if response.is_error:
                        raise JevError(_safe_upstream_error(response, self.api_key))
                    try:
                        parsed = response.json()
                    except ValueError as exc:
                        raise JevError("OpenRouter returned invalid JSON") from exc
                    if not isinstance(parsed, dict):
                        raise JevError("OpenRouter returned an invalid response envelope")
                    response_data = parsed
                    break

            if response_data is None:
                raise JevError("OpenRouter Decisions API did not return a response")
            answers = response_data.get("answers")
            if not isinstance(answers, dict) or set(answers) != set(clean_questions):
                raise JevError("OpenRouter returned an incomplete answer set")
            for question_id, question in clean_questions.items():
                _validate_answer(answers[question_id], question_id, question["type"])

            usage = response_data.get("usage")
            usage = usage if isinstance(usage, dict) else {}
            result = {
                "answers": answers,
                "model": response_data.get("model"),
                "provider": response_data.get("provider"),
                "id": response_data.get("id"),
                "usage": {
                    "input_tokens": usage.get("input_tokens"),
                    "output_tokens": usage.get("output_tokens"),
                    "cost": usage.get("cost"),
                },
            }
            success = True
            return result
        except Exception as exc:
            error_class = type(exc).__name__
            raise
        finally:
            usage = response_data.get("usage", {}) if response_data else {}
            if not isinstance(usage, dict):
                usage = {}
            write_telemetry(
                {
                    "timestamp": datetime.now(UTC).isoformat(),
                    "success": success,
                    "latency_ms": round((time.monotonic() - started) * 1000, 1),
                    "question_count": len(clean_questions),
                    "question_types": dict(counts),
                    "state_bytes": state_size,
                    "input_tokens": usage.get("input_tokens"),
                    "output_tokens": usage.get("output_tokens"),
                    "cost": usage.get("cost"),
                    "model": response_data.get("model") if response_data else None,
                    "provider": response_data.get("provider") if response_data else None,
                    "retry_count": retries,
                    "error_class": error_class,
                }
            )


@mcp.tool(name="jev_decide", description=TOOL_DESCRIPTION)
async def jev_decide(state: Any, questions: dict[str, Any]) -> dict[str, Any]:
    """Answer typed semantic questions about shared state with pinned Jev."""
    client = JevClient(api_key=os.environ.get("OPENROUTER_API_KEY", ""))
    return await client.decide(state, questions)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
