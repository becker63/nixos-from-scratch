import json
from pathlib import Path
import httpx
import pytest
from buildbuddy_history.server import Client, Filters, HistoryError, normalize


def raw(i=1,success=True,status='COMPLETE_INVOCATION_STATUS'):
    r={'invocationId':str(i),'createdAtUsec':str(i*1000000),'updatedAtUsec':str(i*1000000+500),'invocationStatus':status,'acl':{'groupId':'GRtest'},'command':'test','pattern':['//...']}
    if success:r['success']=True
    return r


def test_status_defaults_and_nonfailures():
    assert normalize(raw(success=False))['status']=='FAILURE'
    assert normalize(raw(status='PARTIAL_INVOCATION_STATUS'))['success'] is None
    assert normalize(raw(status='DISCONNECTED_INVOCATION_STATUS'))['status']=='DISCONNECTED'
    r=raw();r['invocationStatus']='MISSING_API_KEY_INVOCATION_STATUS';assert normalize(r)['status']=='UNKNOWN_OVERALL_STATUS'
    r=raw(success=False);r['bazelExitCode']='INTERRUPTED';assert normalize(r)['termination']=='interrupted'


def test_typed_filters_native_semantics():
    q=Filters(created_after='2026-01-01T00:00:00Z',created_before='2026-02-01T00:00:00Z',statuses=['FAILURE'],pattern='//...').query()
    assert q['generic_filters'][0]['negate'] is True
    assert q['generic_filters'][0]['type']=='INVOCATION_CREATED_AT_USEC_FILTER_TYPE'
    assert q['status']==['FAILURE']
    with pytest.raises(HistoryError):Filters(updated_after='no timezone').query()
    with pytest.raises(HistoryError):Filters(created_after='2026-02-01T00:00:00Z',created_before='2026-01-01T00:00:00Z').query()


@pytest.mark.asyncio
async def test_pagination_dedup_and_order():
    def handler(r):
        assert 'SearchInvocation' in str(r.url);p=json.loads(r.content)
        if not p['page_token']:return httpx.Response(200,json={'invocation':[raw(1),raw(2)],'nextPageToken':'opaque'})
        return httpx.Response(200,json={'invocation':[raw(2),raw(3)]})
    c=Client('fake-secret',httpx.MockTransport(handler),0)
    rows,audit=await c.collect(Filters(),3,2)
    assert [r['invocation_id'] for r in rows]==['1','2','3']
    assert audit['duplicate_ids']==['2'] and audit['exhausted']
    assert c.group_id=='GRtest'


@pytest.mark.asyncio
async def test_export_reverse_and_native_counts(tmp_path,monkeypatch):
    monkeypatch.setenv('XDG_STATE_HOME',str(tmp_path))
    calls=[]
    def handler(r):
        p=json.loads(r.content);calls.append(p)
        if 'GetInvocationStat' in str(r.url):
            assert p['request_context']['group_id']=='GRtest'
            return httpx.Response(200,json={'invocationStat':[{'totalNumBuilds':'3'}]})
        ascending=p['sort']['ascending'];all_=[raw(i) for i in ([1,2,3] if ascending else [3,2,1])]
        offset=2 if p['page_token'] else 0
        return httpx.Response(200,json={'invocation':all_[offset:offset+p['count']],**({'nextPageToken':'next'} if not offset and p['count']==2 else {})})
    c=Client('fake-secret',httpx.MockTransport(handler),0)
    out=await c.export(max_pages=4,page_size=2)
    assert out['records']==3 and out['verified_accessible_population']
    import pandas as pd
    d=pd.read_parquet(out['data_path']);assert list(d['invocation_id'])==['1','2','3']
    assert 'fake-secret' not in Path(out['manifest_path']).read_text()


@pytest.mark.asyncio
async def test_partial_export_not_complete(tmp_path,monkeypatch):
    monkeypatch.setenv('XDG_STATE_HOME',str(tmp_path))
    def handler(r):
        if 'GetInvocationStat' in str(r.url):return httpx.Response(200,json={'invocationStat':[{'totalNumBuilds':'99'}]})
        return httpx.Response(200,json={'invocation':[raw(1)],'nextPageToken':'more'})
    c=Client('fake-secret',httpx.MockTransport(handler),0)
    out=await c.export(max_pages=1,page_size=1)
    assert out['records']==1 and not out['verified_accessible_population']


@pytest.mark.asyncio
async def test_secret_safe_errors_and_rpc_allowlist():
    c=Client('fake-secret',httpx.MockTransport(lambda r:httpx.Response(403,text='rpc error: code = PermissionDenied desc = fake-secret')),0)
    with pytest.raises(HistoryError) as caught:await c.search()
    assert 'fake-secret' not in str(caught.value)
    with pytest.raises(HistoryError):await c.rpc('DeleteInvocation',{})


@pytest.mark.asyncio
async def test_repeated_token_rejected():
    c=Client('fake-secret',httpx.MockTransport(lambda r:httpx.Response(200,json={'invocation':[raw(1)],'nextPageToken':'same'})),0)
    with pytest.raises(HistoryError,match='repeated'):await c.collect(Filters(),3,1)


@pytest.mark.asyncio
async def test_unfinished_partition_reconciles_completed_only_native_stats():
    c=Client('fake-secret',httpx.MockTransport(lambda r:httpx.Response(200,json={'invocation':[raw(2,status='DISCONNECTED_INVOCATION_STATUS')]})),0)
    rows=[normalize(raw(1)),normalize(raw(2,status='DISCONNECTED_INVOCATION_STATUS'))]
    native={'statistics':[{'totalNumBuilds':'1','totalNumSucessfulBuilds':'1'}]}
    result=await c.reconcile(rows,Filters(),native,native)
    assert result['counts_reconciled'] and result['aggregation_population']=='completed invocations only'
    assert result['unfinished_partition']['records']==1


@pytest.mark.asyncio
async def test_mcp_protocol(tmp_path):
    import os,sys
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
    params=StdioServerParameters(command=sys.executable,args=['-m','buildbuddy_history.server'],env=dict(os.environ))
    async with stdio_client(params) as (read,write):
        async with ClientSession(read,write) as session:
            init=await session.initialize();assert init.serverInfo.name=='buildbuddy-history'
            tools=(await session.list_tools()).tools
            assert [t.name for t in tools]==['search_invocations','invocation_stats','export_invocation_history']
            assert (await session.call_tool('search_invocations',{'page_size':0})).isError
