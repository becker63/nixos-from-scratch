from __future__ import annotations

import argparse
import asyncio
from collections import Counter
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid
from typing import Annotated, Any, Literal

import httpx
from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, ConfigDict, Field

BASE = 'https://becker63.buildbuddy.io'
REVISION = '1152ba9d7979edbe60aa17aaeba295f9e5578e9d'
METHODS = {'SearchInvocation', 'GetInvocationStat', 'GetLog', 'GetTarget'}
STATUS = Literal['SUCCESS', 'FAILURE', 'IN_PROGRESS', 'DISCONNECTED']
GROUPINGS = {'user': 1, 'host': 2, 'group': 3, 'repository': 4, 'commit': 5, 'date': 6, 'branch': 7, 'pattern': 8}
Group = Literal['date', 'repository', 'user', 'host', 'group', 'commit', 'branch', 'pattern']


class HistoryError(RuntimeError):
    pass


def state_root():
    root = Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'buildbuddy-history'
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    if root.is_symlink() or root.stat().st_uid != os.getuid():
        raise HistoryError('Unsafe history state directory')
    root.chmod(0o700)
    return root


def credential():
    p = Path.home()/'.config/tunnel-client/buildbuddy-secrets/buildbuddy-bearer-header'
    try:
        if p.stat().st_uid != os.getuid() or p.stat().st_mode & 0o077:
            raise ValueError()
        header = p.read_text().strip()
        if not header.startswith('Bearer ') or not re.fullmatch(r'[A-Za-z0-9_./:+=\-]+', header[7:]):
            raise ValueError()
        return header[7:]
    except Exception:
        raise HistoryError('BuildBuddy Reader credential unavailable or not owner-private') from None


def timestamp(value: str) -> int:
    try:
        t = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if t.tzinfo is None:
            raise ValueError()
        return int(t.timestamp()*1_000_000)
    except (ValueError, TypeError, OverflowError):
        raise HistoryError('Time bounds must be ISO-8601 with a timezone') from None


class Filters(BaseModel):
    model_config = ConfigDict(extra='forbid')
    created_after: str | None = None
    created_before: str | None = None
    updated_after: str | None = None
    updated_before: str | None = None
    statuses: Annotated[list[STATUS], Field(max_length=5)] = []
    repository: Annotated[str, Field(max_length=1024)] | None = None
    command: Annotated[str, Field(max_length=128)] | None = None
    user: Annotated[str, Field(max_length=128)] | None = None
    pattern: Annotated[str, Field(max_length=2048)] | None = None

    def query(self):
        q = {}
        for key in ('updated_after', 'updated_before'):
            if getattr(self, key):
                timestamp(getattr(self, key))
                q[key] = getattr(self, key)
        for key in ('created', 'updated'):
            a, b = getattr(self, key+'_after'), getattr(self, key+'_before')
            if a and b and timestamp(a) >= timestamp(b):
                raise HistoryError('Time bounds must be ordered')
        # Generic filters are native provider fields. Lower bound inclusive; upper exclusive.
        for key, operand, negate in [('created_after', 'LESS_THAN_OPERAND', True), ('created_before', 'LESS_THAN_OPERAND', False)]:
            if getattr(self, key):
                q.setdefault('generic_filters', []).append({'type': 'INVOCATION_CREATED_AT_USEC_FILTER_TYPE', 'operand': operand, 'negate': negate, 'value': {'int_value': [str(timestamp(getattr(self, key)))]}})
        for source, dest in [('repository', 'repo_url'), ('command', 'command'), ('user', 'user'), ('pattern', 'pattern')]:
            if getattr(self, source) is not None:
                q[dest] = getattr(self, source)
        if self.statuses:
            q['status'] = self.statuses
        return q


def iso(usec):
    return datetime.fromtimestamp(int(usec)/1e6, timezone.utc).isoformat() if usec else None


def normalize(raw):
    # Protobuf JSON omits false/zero defaults. COMPLETE + omitted success is failure.
    completion = raw.get('invocationStatus', 'UNKNOWN_INVOCATION_STATUS')
    success = bool(raw.get('success', False)) if completion == 'COMPLETE_INVOCATION_STATUS' else None
    overall = ('SUCCESS' if success else 'FAILURE') if success is not None else {
        'PARTIAL_INVOCATION_STATUS': 'IN_PROGRESS', 'DISCONNECTED_INVOCATION_STATUS': 'DISCONNECTED',
    }.get(completion, 'UNKNOWN_OVERALL_STATUS')
    code = raw.get('bazelExitCode')
    termination = 'interrupted' if code in ('INTERRUPTED', '8') else 'canceled' if code in ('CANCELED', 'CANCELLED') else None
    fields = ['invocationId', 'success', 'user', 'host', 'durationUsec', 'command', 'pattern', 'actionCount',
              'invocationStatus', 'createdAtUsec', 'updatedAtUsec', 'repoUrl', 'commitSha', 'cacheStats', 'role',
              'branchName', 'attempt', 'bazelExitCode', 'tags', 'targetConfiguredCount', 'runId', 'parentRunId', 'runStatus']
    return {'invocation_id': raw['invocationId'], 'created_at_usec': int(raw.get('createdAtUsec', 0)) or None,
            'updated_at_usec': int(raw.get('updatedAtUsec', 0)) or None,
            'created_at': iso(raw.get('createdAtUsec')), 'updated_at': iso(raw.get('updatedAtUsec')),
            # updated_at is finalization/update time, not a fabricated BuildFinished timestamp.
            'completed_at': iso(raw.get('updatedAtUsec')) if success is not None else None,
            'completion_time_basis': 'last provider update for complete invocation; exact build-finished time unavailable',
            'status': overall, 'invocation_status': completion, 'success': success, 'termination': termination,
            'bazel_exit_code': code, 'duration_usec': int(raw['durationUsec']) if 'durationUsec' in raw else None,
            'command': raw.get('command'), 'pattern': raw.get('pattern', []), 'repository': raw.get('repoUrl'),
            'commit_sha': raw.get('commitSha'), 'branch': raw.get('branchName'), 'user': raw.get('user'),
            'host': raw.get('host'), 'role': raw.get('role'), 'action_count': int(raw.get('actionCount', 0)),
            'cache_metrics': raw.get('cacheStats'), 'raw_metadata': {k: raw[k] for k in fields if k in raw}}


class Client:
    def __init__(self, key, transport=None, interval=1.0):
        self.key, self.transport, self.interval = key, transport, interval
        self.lock, self.last = asyncio.Lock(), 0.0
        self.group_id = None

    async def rpc(self, method, payload):
        if method not in METHODS:
            raise HistoryError('RPC is not on the read-only allowlist')
        prefix = '/api/v1/' if method in ('GetLog', 'GetTarget') else '/rpc/BuildBuddyService/'
        async with httpx.AsyncClient(transport=self.transport, timeout=httpx.Timeout(20, connect=5), trust_env=False,
                                     headers={'x-buildbuddy-api-key': self.key, 'Content-Type': 'application/json'}) as h:
            for attempt in range(3):
                async with self.lock:
                    await asyncio.sleep(max(0, self.interval-(time.monotonic()-self.last)))
                    self.last = time.monotonic()
                try:
                    async with h.stream('POST', BASE+prefix+method, json=payload) as r:
                        data = bytearray()
                        async for chunk in r.aiter_bytes():
                            data.extend(chunk)
                            if len(data) > 3_000_000:
                                raise HistoryError('Provider response exceeds 3MB; reduce request size')
                        if self.key.encode() in data:
                            raise HistoryError('Provider response rejected: credential reflection')
                        if r.status_code in (429, 502, 503, 504) and attempt < 2:
                            await asyncio.sleep(2**attempt)
                            continue
                        if r.is_error:
                            grpc = re.search(rb'code = (\w+)', data)
                            label = grpc[1].decode() if grpc else 'unspecified'
                            raise HistoryError(f'BuildBuddy {method}: HTTP {r.status_code}, RPC {label}')
                        body = json.loads(data)
                        if not isinstance(body, dict):
                            raise HistoryError('Invalid provider response')
                        return body
                except (httpx.TimeoutException, httpx.NetworkError):
                    if attempt == 2:
                        raise HistoryError('BuildBuddy network timeout or failure') from None
                    await asyncio.sleep(2**attempt)
                except (ValueError, TypeError):
                    raise HistoryError('Invalid provider JSON response') from None

    async def search(self, filters=None, page_size=100, page_token='', ascending=True, sort_field=1):
        if not 1 <= page_size <= 200 or len(page_token) > 4096:
            raise HistoryError('Page size must be 1..200 and token <=4096 characters')
        body = await self.rpc('SearchInvocation', {'query': (filters or Filters()).query(), 'sort': {'sort_field': sort_field, 'ascending': ascending}, 'count': page_size, 'page_token': page_token})
        raw = body.get('invocation', [])
        if not isinstance(raw, list) or len(raw) > 2*page_size:
            raise HistoryError('Invalid invocation page')
        if raw and not self.group_id:
            self.group_id = raw[0].get('acl', {}).get('groupId')
        try:
            rows = [normalize(r) for r in raw]
        except (ValueError, KeyError, TypeError):
            raise HistoryError('Invalid invocation metadata') from None
        return {'invocations': rows, 'next_page_token': body.get('nextPageToken', ''), 'provenance': BASE+'/rpc/BuildBuddyService/SearchInvocation'}

    async def stats(self, grouping='date', filters=None, limit=1000):
        if grouping not in GROUPINGS or not 1 <= limit <= 1000:
            raise HistoryError('Unsupported aggregation or limit')
        if not self.group_id:
            await self.search(page_size=1)
        if not self.group_id:
            raise HistoryError('Organization group ID unavailable; no readable invocations')
        body = await self.rpc('GetInvocationStat', {'request_context': {'group_id': self.group_id, 'timezone': 'America/New_York'}, 'query': (filters or Filters()).query(), 'aggregation_type': GROUPINGS[grouping], 'limit': limit})
        return {'grouping': grouping, 'statistics': body.get('invocationStat', []), 'possibly_truncated': len(body.get('invocationStat', [])) >= limit, 'raw_response': body, 'time_basis': 'provider updated timestamp; America/New_York'}

    async def collect(self, filters, max_pages, page_size, ascending=True, max_records=20000):
        token, seen_tokens, seen, pages, duplicates = '', set(), {}, [], []
        exhausted = False
        last_time = None
        ordering_violations = 0
        for i in range(max_pages):
            page = await self.search(filters, page_size, token, ascending)
            rows = page['invocations']
            for r in rows:
                t = r['created_at_usec']
                if t is not None and last_time is not None and ((ascending and t < last_time) or (not ascending and t > last_time)):
                    ordering_violations += 1
                if t is not None: last_time = t
                if r['invocation_id'] in seen: duplicates.append(r['invocation_id'])
                seen[r['invocation_id']] = r
            pages.append({'page': i, 'input_token': token, 'output_token': page['next_page_token'], 'count': len(rows), 'first_id': rows[0]['invocation_id'] if rows else None, 'last_id': rows[-1]['invocation_id'] if rows else None})
            token = page['next_page_token']
            if not token:
                exhausted = True; break
            if token in seen_tokens:
                raise HistoryError('Provider repeated pagination token')
            seen_tokens.add(token)
            if len(seen) >= max_records:
                break
        return sorted(seen.values(), key=lambda r: (r['created_at_usec'] or 0, r['invocation_id'])), {'pages': pages, 'exhausted': exhausted, 'continuation_token': token, 'duplicate_ids': duplicates, 'ordering_violations': ordering_violations}

    async def reconcile(self, rows, filters, before, after):
        counts = Counter(r['status'] for r in rows)
        def agg(s):
            if 'statistics' not in s: return None
            return sum(int(r.get('totalNumBuilds', 0)) for r in s['statistics'])
        nb, na = agg(before), agg(after)
        completed = counts['SUCCESS'] + counts['FAILURE']
        if nb == na == len(rows):
            return {'counts_reconciled': True, 'aggregation_population': 'all returned statuses', 'completed_records': completed, 'unfinished_records': len(rows)-completed}
        f = filters.model_copy(deep=True)
        allowed = set(f.statuses) if f.statuses else {'IN_PROGRESS', 'DISCONNECTED'}
        f.statuses = sorted(allowed & {'IN_PROGRESS', 'DISCONNECTED'})
        expected = {r['invocation_id'] for r in rows if r['status'] in f.statuses}
        partition = {'performed': False, 'id_sets_equal': not expected}
        if f.statuses:
            unfinished, audit = await self.collect(f, 200, 100)
            found = {r['invocation_id'] for r in unfinished}
            partition = {'performed': True, 'records': len(unfinished), 'exhausted': audit['exhausted'], 'id_sets_equal': found == expected, 'duplicate_ids': audit['duplicate_ids']}
        reconciled = nb == na == completed and partition['id_sets_equal'] and partition.get('exhausted', True) and not counts['UNKNOWN_OVERALL_STATUS']
        return {'counts_reconciled': reconciled, 'aggregation_population': 'completed invocations only' if nb == na == completed else 'unresolved count difference',
                'completed_records': completed, 'unfinished_records': len(rows)-completed, 'unfinished_partition': partition,
                'explanation': 'This deployment native aggregation excludes disconnected/partial builds; independent native status-filtered search verifies unfinished IDs.'}

    async def export(self, filters=None, max_pages=200, page_size=100, verify_reverse=True):
        import pandas as pd
        if not 1 <= max_pages <= 200 or not 1 <= page_size <= 200 or max_pages*page_size > 20000:
            raise HistoryError('Export bounded at 200 pages and 20000 requested records')
        f = (filters or Filters()).model_copy(deep=True)
        extraction_start = datetime.now(timezone.utc).isoformat()
        if not f.created_before or timestamp(f.created_before) > timestamp(extraction_start): f.created_before = extraction_start
        lock = os.open(state_root()/'export.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError: raise HistoryError('Another export is running') from None
            output = state_root()/('export-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8])
            output.mkdir(mode=0o700)
            try: before = await self.stats('group', f)
            except HistoryError as e: before = {'error': str(e)}
            rows, pagination = await self.collect(f, max_pages, page_size)
            reverse_check = {'performed': False}
            if verify_reverse and pagination['exhausted']:
                reverse, revpages = await self.collect(f, max_pages, page_size, False)
                forward_ids = {r['invocation_id'] for r in rows}; reverse_ids = {r['invocation_id'] for r in reverse}
                reverse_check = {'performed': True, 'exhausted': revpages['exhausted'], 'id_sets_equal': forward_ids == reverse_ids, 'only_forward': sorted(forward_ids-reverse_ids), 'only_reverse': sorted(reverse_ids-forward_ids), 'pagination': revpages}
            try: after = await self.stats('group', f)
            except HistoryError as e: after = {'error': str(e)}
            def total(s):
                return sum(int(r.get('totalNumBuilds', 0)) for r in s.get('statistics', [])) if 'statistics' in s else None
            count_before, count_after = total(before), total(after)
            reconciliation = await self.reconcile(rows, f, before, after) if pagination["exhausted"] else {"counts_reconciled": False, "reason": "export pagination truncated"}
            coverage = pagination['exhausted'] and reverse_check.get('id_sets_equal', False) and reverse_check.get('exhausted', False) and reconciliation['counts_reconciled'] and not pagination['ordering_violations']
            manifest = {'extracted_at': extraction_start, 'finished_at': datetime.now(timezone.utc).isoformat(), 'source': BASE, 'rpc': 'SearchInvocation', 'provider_schema_revision': REVISION, 'filters': f.model_dump(), 'records': len(rows), 'status_counts': dict(Counter(r['status'] for r in rows)), 'earliest_created_at': rows[0]['created_at'] if rows else None, 'latest_created_at': rows[-1]['created_at'] if rows else None, 'pagination': pagination, 'reverse_check': reverse_check, 'native_stats_before': before, 'native_stats_after': after, 'authoritative_count_before': count_before, 'authoritative_count_after': count_after, 'verified_accessible_population': coverage, 'count_reconciliation': reconciliation, 'permission_limitations': ['Native aggregate may omit unfinished invocations; compare completed and unfinished populations separately.', 'Reader-scoped API visibility only; inaccessible/deleted/retention-expired invocations cannot be counted.', 'API is not a transactional snapshot; in-flight outcomes may change during extraction.', 'Updated timestamp is not necessarily exact build completion.', 'Original dashboard count 2601 is historical, not a frozen expected total.'], 'data_path': str(output/'invocations.parquet')}
            flat = []
            for r in rows:
                record = dict(r)
                for k in ('pattern', 'cache_metrics', 'raw_metadata'): record[k] = json.dumps(record[k], sort_keys=True)
                flat.append(record)
            data = output/'invocations.parquet'
            pd.DataFrame(flat).to_parquet(data, index=False)
            manifest['sha256'] = hashlib.sha256(data.read_bytes()).hexdigest()
            (output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
            for p in output.iterdir(): p.chmod(0o600)
            # Return a small summary, not the complete dataset or page audit.
            summary = {k: manifest[k] for k in ('records','status_counts','earliest_created_at','latest_created_at','verified_accessible_population','authoritative_count_before','authoritative_count_after','permission_limitations','data_path','sha256')}
            summary['manifest_path'] = str(output/'manifest.json')
            return summary
        finally:
            os.close(lock)


mcp = FastMCP('buildbuddy-history', instructions='Read-only native BuildBuddy historical search and aggregation. Incomplete or absent data is not failure. Exports persist metadata only; no bulk logs.', log_level='CRITICAL')
_client = None


def client():
    global _client
    if _client is None: _client = Client(credential())
    return _client


@mcp.tool(description='Search native BuildBuddy invocation metadata. Defaults: 100 records, oldest first. Bounds are inclusive-after/exclusive-before, ISO-8601 with timezone; filters are ANDed, statuses ORed; pattern exact match. Includes all readable statuses by default. Token is opaque and must be reused with identical filters/sort. No logs fetched.')
async def search_invocations(filters: Filters | None = None, page_size: Annotated[int, Field(ge=1, le=200)] = 100, page_token: Annotated[str, Field(max_length=4096)] = '', direction: Literal['oldest', 'newest'] = 'oldest') -> dict[str, Any]:
    return await client().search(filters, page_size, page_token, direction == 'oldest')


@mcp.tool(description='Native BuildBuddy invocation aggregation: date, repository, user, host, group, commit, branch, or pattern. Provider dates use last update, America/New_York. Limit <=1000; no invented groupings. Success/failure totals require complete invocations, total builds includes other statuses.')
async def invocation_stats(grouping: Group = 'date', filters: Filters | None = None, limit: Annotated[int, Field(ge=1, le=1000)] = 1000) -> dict[str, Any]:
    return await client().stats(grouping, filters, limit)


@mcp.tool(description='Bounded read-only metadata export to private local Parquet with manifest and coverage checks; never downloads bulk logs. <=20000 records, <=200 pages, default 100/page. Freezes an upper creation bound; deduplicates and orders by timestamp/ID. Optional reverse traversal checks page boundaries. Returns only paths and summary, never a large dataset. In-flight outcomes are not transactionally frozen.')
async def export_invocation_history(filters: Filters | None = None, max_pages: Annotated[int, Field(ge=1, le=200)] = 200, page_size: Annotated[int, Field(ge=1, le=200)] = 100, verify_reverse: bool = True) -> dict[str, Any]:
    return await client().export(filters, max_pages, page_size, verify_reverse)


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser()
    p.add_argument('--export', action='store_true')
    p.add_argument('--schemas', action='store_true')
    args = p.parse_args()
    if args.export:
        try: print(json.dumps(asyncio.run(client().export()), indent=2))
        except HistoryError as e: sys.exit(str(e))
    elif args.schemas:
        tools = asyncio.run(mcp.list_tools())
        print(json.dumps({t.name:t.inputSchema for t in tools}, indent=2))
    else:
        mcp.run(transport='stdio')


if __name__ == '__main__': main()
