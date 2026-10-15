"""Bounded native TypeSafe MCP. No fallback provider and no inference cache."""
from __future__ import annotations

import asyncio
import json
import math
import os
import re
import sys
import time
from pathlib import Path
from typing import Annotated, Any, Literal

import httpx
from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, ConfigDict, Field, JsonValue

ENDPOINT = 'https://api.typesafe.ai/v1/systemone'
MODEL = 'jev-1.13.0'
MAX_STATE_BYTES = 32768
MAX_REQUEST_BYTES = 65536
MAX_BATCH_BYTES = 524288
TRANSIENT = {408, 429, 500, 502, 503, 504, 529}
NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$')
State = str | dict[str, JsonValue] | list[JsonValue]


class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Noul(Strict):
    type: Literal['noul']
    instructions: State
    criteria: dict[Literal['true', 'false'], State] | None = None


class Choice(Strict):
    type: Literal['choice']
    instructions: State
    criteria: Annotated[dict[str, State | None], Field(min_length=2, max_length=255)]


class Score(Strict):
    type: Literal['score']
    instructions: State
    criteria: Annotated[list[State], Field(min_length=2, max_length=10)]


Question = Annotated[Noul | Choice | Score, Field(discriminator='type')]
Questions = Annotated[dict[str, Question], Field(min_length=1, max_length=64)]
Model = Annotated[str, Field(pattern=r'^jev-[A-Za-z0-9][A-Za-z0-9.\-]{0,63}$')]


class Record(Strict):
    id: Annotated[str, Field(min_length=1, max_length=128)]
    state: State
    questions: Questions


class JevError(RuntimeError):
    """Only constant or numeric messages may escape the provider boundary."""


def encode(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False, separators=(',', ':'))
    except (ValueError, TypeError):
        raise JevError('Input must contain finite JSON values') from None


def validate(state: State, questions: dict, model: str) -> dict:
    if not re.fullmatch(r'jev-[A-Za-z0-9][A-Za-z0-9.\-]{0,63}', model):
        raise JevError('Invalid native Jev model')
    if len(encode(state).encode()) > MAX_STATE_BYTES:
        raise JevError('State exceeds 32768 bytes; compress evidence first')
    if not isinstance(questions, dict) or not 1 <= len(questions) <= 64:
        raise JevError('Each native request requires 1..64 questions')
    clean = {}
    for key, value in questions.items():
        if not NAME.fullmatch(key):
            raise JevError('Invalid question name')
        if isinstance(value, BaseModel):
            value = value.model_dump(exclude_none=True)
        # Pydantic validation exceptions include input values: never expose them.
        from pydantic import TypeAdapter
        try:
            value = TypeAdapter(Question).validate_python(value).model_dump(exclude_none=True)
        except Exception:
            raise JevError('Invalid typed question schema') from None
        if not value['instructions']:
            raise JevError('Question instructions must be nonempty')
        if value['type'] == 'choice' and any(not NAME.fullmatch(k) for k in value['criteria']):
            raise JevError('Invalid choice name')
        if value['type'] == 'noul' and 'criteria' in value and set(value['criteria']) != {'true', 'false'}:
            raise JevError('Noul criteria must describe true and false')
        clean[key] = value
    payload = {'state': state, 'questions': clean, 'model': model}
    if len(encode(payload).encode()) > MAX_REQUEST_BYTES:
        raise JevError('Native request exceeds 65536 bytes')
    return payload


def number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate_response(body: Any, questions: dict) -> None:
    if not isinstance(body, dict) or not isinstance(body.get('model'), str) or not isinstance(body.get('usage'), dict):
        raise JevError('Invalid native response envelope')
    if not isinstance(body.get('answers'), dict) or set(body['answers']) != set(questions):
        raise JevError('Incomplete native answer set')
    for field in ('input_tokens', 'output_tokens'):
        v = body['usage'].get(field)
        if not isinstance(v, int) or isinstance(v, bool) or v < 0:
            raise JevError('Invalid native usage')
    for key, q in questions.items():
        a = body['answers'][key]
        if not isinstance(a, dict) or a.get('type') != q['type']:
            raise JevError('Invalid native answer type')
        if 'confidence' in a and (not number(a['confidence']) or not 0 <= a['confidence'] <= 1):
            raise JevError('Invalid native confidence')
        if q['type'] == 'noul':
            if not number(a.get('noul')) or not 0 <= a['noul'] <= 1:
                raise JevError('Invalid native noul probability')
            continue
        probs = a.get('probabilities')
        expected = set(q['criteria']) if q['type'] == 'choice' else {str(i) for i in range(len(q['criteria']))}
        if (not isinstance(probs, dict) or set(probs) != expected or
                any(not number(p) or not 0 <= p <= 1 for p in probs.values()) or
                not math.isclose(sum(probs.values()), 1, abs_tol=0.01)):
            raise JevError('Invalid native probability distribution')
        if q['type'] == 'choice' and a.get('choice') not in expected:
            raise JevError('Invalid native chosen alternative')
        if q['type'] == 'score' and (not number(a.get('score')) or not 0 <= a['score'] <= len(expected)-1 or not isinstance(a.get('legend'), dict) or set(a['legend']) != expected):
            raise JevError('Invalid native score or legend')


class Client:
    def __init__(self, key: str, *, transport=None, sleep=asyncio.sleep):
        if not key:
            raise JevError('Native Jev credential unavailable')
        self.key, self.transport, self.sleep = key, transport, sleep
        self.slots = asyncio.Semaphore(4)

    async def request(self, payload: dict) -> dict:
        started = time.monotonic()
        attempts = 0
        async def run():
            nonlocal attempts
            async with self.slots, httpx.AsyncClient(
                transport=self.transport, timeout=httpx.Timeout(15, connect=5), trust_env=False,
                headers={'Authorization': 'Bearer ' + self.key},
            ) as http:
                for attempt in range(3):
                    attempts += 1
                    try:
                        r = await http.post(ENDPOINT, json=payload)
                    except (httpx.TimeoutException, httpx.NetworkError):
                        if attempt == 2:
                            raise JevError('Native Jev network failure') from None
                        await self.sleep(0.5 * 2**attempt)
                        continue
                    if r.status_code in TRANSIENT and attempt < 2:
                        try:
                            delay = float(r.headers.get('retry-after', 0.5 * 2**attempt))
                            if not math.isfinite(delay):
                                delay = 1
                        except ValueError:
                            delay = 1
                        await self.sleep(min(5, max(0.5, delay)))
                        continue
                    if r.is_error:
                        # Provider bodies may echo the credential or request. Discard them.
                        raise JevError(f'Native Jev HTTP {r.status_code}')
                    try:
                        body = r.json()
                        serialized = encode(body)
                    except Exception:
                        raise JevError('Native Jev returned invalid JSON') from None
                    if self.key in serialized:
                        raise JevError('Native response rejected: credential reflection')
                    validate_response(body, payload['questions'])
                    return body
        try:
            body = await asyncio.wait_for(run(), timeout=60)
            return {'response': body, 'metrics': {'latency_ms': round((time.monotonic()-started)*1000, 1), 'attempts': attempts}}
        except asyncio.TimeoutError:
            raise JevError('Native Jev request deadline exceeded') from None
        except JevError:
            raise
        except Exception:
            raise JevError('Native Jev request failed') from None

    async def decide(self, state, questions, model=MODEL):
        return await self.request(validate(state, questions, model))

    async def batch(self, records: list[Record], model=MODEL, concurrency=4):
        started = time.monotonic()
        if not 1 <= len(records) <= 32 or not 1 <= concurrency <= 4:
            raise JevError('Batch permits 1..32 records and concurrency 1..4')
        if len({r.id for r in records}) != len(records):
            raise JevError('Record IDs must be unique')
        if sum(len(r.questions) for r in records) > 128:
            raise JevError('Batch exceeds 128 questions')
        if len(encode([r.model_dump(exclude_none=True) for r in records]).encode()) > MAX_BATCH_BYTES:
            raise JevError('Batch exceeds 524288 bytes')
        groups = {}
        for i, r in enumerate(records):
            p = validate(r.state, r.questions, model)
            g = groups.setdefault(encode(r.state), {'state': r.state, 'questions': {}, 'records': []})
            mapping = {k: f'r{i}.{k}' for k in p['questions']}
            g['questions'].update({mapping[k]: v for k, v in p['questions'].items()})
            g['records'].append((i, mapping))
        # Validate every merged request before doing any paid inference.
        payloads = [validate(g['state'], g['questions'], model) for g in groups.values()]
        limit = asyncio.Semaphore(concurrency)
        async def one(p):
            async with limit:
                try:
                    return await self.request(p)
                except JevError as e:
                    return {'error': str(e)}
        requests = await asyncio.gather(*(one(p) for p in payloads))
        results = [None] * len(records)
        usage: dict[str, int | float] = {'input_tokens': 0, 'output_tokens': 0}
        for request_index, (g, outcome) in enumerate(zip(groups.values(), requests)):
            if 'response' in outcome:
                for k, v in outcome['response']['usage'].items():
                    if number(v):
                        usage[k] = usage.get(k, 0) + v
            for i, mapping in g['records']:
                entry = {'id': records[i].id, 'request_index': request_index}
                if 'error' in outcome:
                    entry.update(success=False, error=outcome['error'])
                else:
                    body = outcome['response']
                    entry.update(success=True, model=body['model'], answers={k: body['answers'][v] for k, v in mapping.items()})
                results[i] = entry
        return {'results': results, 'requests': requests, 'usage': usage,
                'metrics': {'latency_ms': round((time.monotonic()-started)*1000, 1), 'native_requests': len(groups),
                            'successful_records': sum(r['success'] for r in results),
                            'failed_records': sum(not r['success'] for r in results)},
                'usage_scope': 'Successful native requests counted once; retried or failed attempts may incur unreported usage. requests preserves complete native envelopes.'}


mcp = FastMCP('jev-native-mcp', instructions='Native TypeSafe Jev: bounded semantic evidence, never a substitute for exact build evidence or statistical analysis. No caching. Maximum four in-flight requests.', log_level='CRITICAL')
_client = None


def client():
    global _client
    if _client is None:
        _client = Client(os.environ.get('TYPESAFE_API_KEY', ''))
    return _client


@mcp.tool(description='Ask independent typed choice, score, or noul questions against compact shared evidence. Preserve probabilities; include unknown for uncertain classification. Exact exit codes and error messages take precedence. Uses native TypeSafe only; one request, up to 64 questions, state <=32KiB, payload <=64KiB. Inference costs money; no caching.')
async def jev_decide(state: State, questions: Questions, model: Model = MODEL) -> dict[str, Any]:
    return await client().decide(state, questions, model)


@mcp.tool(description='Evaluate 1..32 independent records (unique IDs), at most 128 questions and 512KiB total. Identical JSON states share one request with namespaced questions (max 64 per state); separate states use bounded concurrency 1..4. Returns ordered per-record successes/errors and complete native responses plus usage counted once per shared request. No semantic caching; inference costs money.')
async def jev_decide_batch(records: Annotated[list[Record], Field(min_length=1, max_length=32)], model: Model = MODEL, concurrency: Annotated[int, Field(ge=1, le=4)] = 4) -> dict[str, Any]:
    return await client().batch(records, model, concurrency)


def main():
    mcp.run(transport='stdio')


def launch():
    # Reuse the Fabric parser without invoking its stdout credential command.
    from .credential import ENV_FILE, parse
    try:
        if ENV_FILE.is_symlink() or ENV_FILE.stat().st_uid != os.getuid() or ENV_FILE.stat().st_mode & 0o077:
            raise ValueError()
        key = parse(ENV_FILE.read_text())
    except Exception:
        sys.stderr.write('Jev credential unavailable, malformed, or not owner-private\n')
        raise SystemExit(1) from None
    os.environ['TYPESAFE_API_KEY'] = key
    os.environ.pop('JEV_KEY', None)
    main()


if __name__ == '__main__':
    main()
