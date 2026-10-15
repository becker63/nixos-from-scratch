import asyncio
import importlib.util
import json
import os
import sys
from pathlib import Path

import httpx
import pytest
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from jev_mcp.native import Client, MODEL, ENDPOINT, JevError, Record, validate

CHOICE = {'type': 'choice', 'instructions': 'Cause? Exact errors override guesses.', 'criteria': {'compiler': 'Compiler or type errors', 'unknown': 'Insufficient evidence'}}
NOUL = {'type': 'noul', 'instructions': 'Is the evidence sufficient?'}
SCORE = {'type': 'score', 'instructions': 'Ambiguity?', 'criteria': ['Clear', 'Ambiguous', 'Unknown']}


def response(payload):
    answers = {}
    for k, q in payload['questions'].items():
        if q['type'] == 'choice':
            a = {'choice': 'compiler', 'probabilities': {'compiler': .9, 'unknown': .1}, 'confidence': .8}
        elif q['type'] == 'score':
            a = {'score': .2, 'legend': {'0': 'Clear', '1': 'Ambiguous', '2': 'Unknown'}, 'probabilities': {'0': .8, '1': .2, '2': 0}, 'confidence': .6}
        else:
            a = {'noul': .92}
        answers[k] = dict(type=q['type'], **a)
    return {'model': MODEL, 'answers': answers, 'usage': {'input_tokens': 100, 'output_tokens': 20, 'cost': .0000042}, 'provider_extension': {'preserved': True}}


@pytest.mark.asyncio
async def test_all_types_and_full_envelope():
    seen = []
    def handler(r):
        assert str(r.url) == ENDPOINT
        assert r.headers['authorization'] == 'Bearer test-secret'
        seen.append(json.loads(r.content))
        return httpx.Response(200, json=response(seen[-1]))
    out = await Client('test-secret', transport=httpx.MockTransport(handler)).decide({'exit_code': 1, 'log': 'error: expected type u32, found []u8'}, {'cause': CHOICE, 'sufficient': NOUL, 'ambiguity': SCORE})
    assert len(seen) == 1 and seen[0]['model'] == MODEL
    assert out['response'] == response(seen[0])
    assert out['response']['answers']['sufficient']['noul'] == .92


@pytest.mark.asyncio
async def test_shared_states_order_usage_partial_failure_concurrency():
    calls, active, peak = [], 0, 0
    async def handler(r):
        nonlocal active, peak
        p = json.loads(r.content)
        calls.append(p)
        active += 1
        peak = max(peak, active)
        await asyncio.sleep(.01)
        active -= 1
        if p['state'] == 'fail':
            return httpx.Response(401, json={'error': 'do not expose test-secret'})
        return httpx.Response(200, json=response(p))
    records = [Record(id=str(i), state=state, questions={'q': NOUL}) for i, state in enumerate([{'b': 2, 'a': 1}, 'second', {'a': 1, 'b': 2}, 'fail', 'third'])]
    out = await Client('test-secret', transport=httpx.MockTransport(handler)).batch(records, concurrency=2)
    assert len(calls) == 4 and peak == 2
    assert [r['id'] for r in out['results']] == ['0', '1', '2', '3', '4']
    assert out['results'][0]['answers']['q'] == out['results'][2]['answers']['q']
    assert out['results'][3]['success'] is False
    assert 'test-secret' not in json.dumps(out)
    assert out['usage'] == {'input_tokens': 300, 'output_tokens': 60, 'cost': pytest.approx(.0000126)}
    assert len(calls[0]['questions']) == 2
    assert out['metrics']['failed_records'] == 1


@pytest.mark.asyncio
@pytest.mark.parametrize('status', [429, 529, 503, 'network'])
async def test_bounded_retries(status):
    attempts, delays = [], []
    def handler(r):
        attempts.append(1)
        if len(attempts) < 3:
            if status == 'network':
                raise httpx.ReadTimeout('test-secret')
            return httpx.Response(status, headers={'retry-after': '999'}, text='test-secret')
        return httpx.Response(200, json=response(json.loads(r.content)))
    async def sleep(d):
        delays.append(d)
    out = await Client('test-secret', transport=httpx.MockTransport(handler), sleep=sleep).decide('state', {'q': NOUL})
    assert len(attempts) == 3 and len(delays) == 2 and max(delays) <= 5
    assert out['metrics']['attempts'] == 3


@pytest.mark.asyncio
async def test_retry_exhaustion_and_no_credential_reflection():
    for mode in ('network', 'http', 'response'):
        def handler(r):
            if mode == 'network':
                raise httpx.ConnectError('test-secret')
            if mode == 'http':
                return httpx.Response(400, text='test-secret')
            p = response(json.loads(r.content)); p['extra'] = 'test-secret'
            return httpx.Response(200, json=p)
        async def sleep(d):
            pass
        with pytest.raises(JevError) as caught:
            await Client('test-secret', transport=httpx.MockTransport(handler), sleep=sleep).decide('state', {'q': NOUL})
        assert 'test-secret' not in str(caught.value)
        assert caught.value.__cause__ is None


@pytest.mark.parametrize('state,questions', [
    ('x'*32769, {'q': NOUL}), ('x', {}), ('x', {'q': {'type': 'noul', 'instructions': ''}}),
    ('x', {'q': {'type': 'noul', 'instructions': 'x', 'criteria': {'true': 'yes'}}}),
    ('x', {'q': {'type': 'score', 'instructions': 'x', 'criteria': ['x']*11}}),
    ('x', {'q': {'type': 'choice', 'instructions': 'x', 'criteria': {'a': None}}}),
    ('x', {'q': {'type': 'noul', 'instructions': 'x', 'extra': 'test-secret'}}),
    ({'v': float('nan')}, {'q': NOUL}),
])
def test_reject_invalid_request(state, questions):
    with pytest.raises(JevError):
        validate(state, questions, MODEL)


@pytest.mark.asyncio
async def test_batch_validated_before_inference_and_no_cache():
    calls = []
    def handler(r):
        calls.append(1)
        return httpx.Response(200, json=response(json.loads(r.content)))
    c = Client('test-secret', transport=httpx.MockTransport(handler))
    r = Record(id='same', state='x', questions={'q': NOUL})
    with pytest.raises(JevError):
        await c.batch([r, r])
    with pytest.raises(JevError):
        await c.batch([Record(id=str(i), state='x', questions={str(j): NOUL for j in range(40)}) for i in range(2)])
    assert not calls
    await c.batch([r]); await c.batch([r])
    assert len(calls) == 2


@pytest.mark.asyncio
@pytest.mark.parametrize('mode', ['missing', 'probability', 'usage', 'json'])
async def test_invalid_provider_response(mode):
    def handler(r):
        p = response(json.loads(r.content))
        if mode == 'missing': p['answers'] = {}
        if mode == 'probability': p['answers']['cause']['probabilities']['compiler'] = 2
        if mode == 'usage': p['usage'] = {}
        if mode == 'json': return httpx.Response(200, text='not json')
        return httpx.Response(200, json=p)
    with pytest.raises(JevError):
        await Client('test-secret', transport=httpx.MockTransport(handler)).decide('state', {'cause': CHOICE})


@pytest.mark.asyncio
async def test_native_mcp_discovery_and_invalid_call(tmp_path):
    env = dict(os.environ, TYPESAFE_API_KEY='protocol-secret', XDG_STATE_HOME=str(tmp_path))
    params = StdioServerParameters(command=sys.executable, args=['-m', 'jev_mcp.native'], env=env)
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            initialized = await session.initialize()
            assert initialized.serverInfo.name == 'jev-native-mcp'
            tools = (await session.list_tools()).tools
            assert [t.name for t in tools] == ['jev_decide', 'jev_decide_batch']
            assert tools[0].inputSchema['properties']['model']['default'] == MODEL
            assert tools[1].inputSchema['properties']['concurrency']['maximum'] == 4
            assert (await session.call_tool('jev_decide', {'state': 'x', 'questions': {}})).isError


def test_reused_credential_parser_no_execution():
    # The native derivation installs precisely the Fabric credential parser.
    credential = pytest.importorskip("jev_mcp.credential")
    assert credential.parse('OTHER_KEY=keep\nexport JEV_KEY="fake-key"\n') == 'fake-key'
    with pytest.raises(ValueError):
        credential.parse('JEV_KEY=$(echo unsafe)')


@pytest.mark.asyncio
async def test_request_deadline(monkeypatch):
    from jev_mcp import native
    async def deadline(coro, timeout):
        assert timeout == 60
        coro.close()
        raise asyncio.TimeoutError('test-secret')
    monkeypatch.setattr(native.asyncio, 'wait_for', deadline)
    with pytest.raises(JevError, match='deadline exceeded'):
        await Client('test-secret').decide('x', {'q': NOUL})


def test_protected_launcher_maps_key_and_rejects_permissions(tmp_path, monkeypatch, capsys):
    from jev_mcp import native
    credential = pytest.importorskip('jev_mcp.credential')
    p = tmp_path/'env'
    p.write_text('JEV_KEY=fake-private-key\nOTHER_KEY=preserved\n')
    p.chmod(0o600)
    monkeypatch.setattr(credential, 'ENV_FILE', p)
    def main():
        assert os.environ['TYPESAFE_API_KEY'] == 'fake-private-key'
        assert 'JEV_KEY' not in os.environ
    monkeypatch.setattr(native, 'main', main)
    monkeypatch.setenv('JEV_KEY', 'stale-key')
    monkeypatch.setenv('TYPESAFE_API_KEY', 'stale-key')
    native.launch()
    assert p.read_text() == 'JEV_KEY=fake-private-key\nOTHER_KEY=preserved\n'
    p.chmod(0o644)
    with pytest.raises(SystemExit):
        native.launch()
    captured = capsys.readouterr()
    assert 'fake-private-key' not in captured.out + captured.err


@pytest.mark.asyncio
async def test_valid_calls_over_stdio_mock_provider(tmp_path):
    bootstrap = tmp_path/'mock_server.py'
    bootstrap.write_text('import sys\nsys.path[:0] = ' + repr(sys.path) + '\n' + '''import json, httpx
from jev_mcp import native

def handler(r):
    p = json.loads(r.content)
    return httpx.Response(200, json={"model": native.MODEL, "answers": {k: {"type": "noul", "noul": 0.73} for k in p["questions"]}, "usage": {"input_tokens": 5, "output_tokens": 2}})
native._client = native.Client("protocol-secret", transport=httpx.MockTransport(handler))
native.main()
''')
    params = StdioServerParameters(command=sys.executable, args=[str(bootstrap)])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            a = await session.call_tool('jev_decide', {'state': 'compact evidence', 'questions': {'q': NOUL}})
            assert not a.isError and a.structuredContent['response']['answers']['q']['noul'] == .73
            b = await session.call_tool('jev_decide_batch', {'records': [{'id': 'one', 'state': 'a', 'questions': {'q': NOUL}}, {'id': 'two', 'state': 'b', 'questions': {'q': NOUL}}]})
            assert not b.isError
            assert [r['id'] for r in b.structuredContent['results']] == ['one', 'two']
            assert b.structuredContent['usage']['input_tokens'] == 10
