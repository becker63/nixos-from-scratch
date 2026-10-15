import numpy as np
import pandas as pd
from buildbuddy_history.analysis import scope, sessions, transition_counts, streaks
from buildbuddy_history.evidence import deterministic, redact


def test_sessions_and_dependency_counts():
    d=pd.DataFrame({'created_at_usec':[0,60e6,3600e6,3660e6]})
    assert list(sessions(d,30))==[1,1,2,2]
    t=transition_counts(np.array([0,1,1,0]),np.array([1,1,2,2]))
    assert t.tolist()==[[0,1],[1,0]]
    assert streaks([0,0,1,1,1,0])==[{'outcome':0,'length':2},{'outcome':1,'length':3},{'outcome':0,'length':1}]


def test_taxonomy_rules_and_secret_redaction():
    r={'bazel_exit_code':'BUILD_FAILURE','diagnostic_excerpt':'error: expected type u32, found []u8'}
    assert deterministic(r)['category']=='compiler'
    r['bazel_exit_code']='INTERRUPTED';assert deterministic(r)['category']=='unknown'
    r['bazel_exit_code']='BUILD_FAILURE';r['diagnostic_excerpt']='';assert deterministic(r) is None
    out=redact('api_key=private-other Bearer fake-key actual-key','actual-key')
    assert 'actual-key' not in out and 'fake-key' not in out and 'private-other' not in out
    assert scope(['//...'])=='all-targets'


def test_numeric_pipeline_and_artifacts(tmp_path):
    import json
    from buildbuddy_history.analysis import analyze
    records=[]
    for i in range(120):
        passed=i%4!=0;t=1790226000000000+i*60_000_000+(i//20)*3_600_000_000
        records.append({'invocation_id':str(i),'created_at_usec':t,'created_at':'2026-09-24T00:00:00+00:00','status':'SUCCESS' if passed else 'FAILURE','success':passed,'pattern':'["//test:sample"]','command':'test','duration_usec':1000000,'cache_metrics':'null','repository':None,'commit_sha':'abc','bazel_exit_code':'SUCCESS' if passed else 'BUILD_FAILURE'})
    path=tmp_path/'invocations.parquet';pd.DataFrame(records).to_parquet(path,index=False)
    (tmp_path/'manifest.json').write_text(json.dumps({'records':120,'status_counts':{'SUCCESS':90,'FAILURE':30},'verified_accessible_population':True,'earliest_created_at':'2026-09-24','latest_created_at':'2026-09-24'}))
    d=analyze(path)
    assert d['pass_rate']==.75 and d['completed_n']==120
    assert sum(pd.read_csv(tmp_path/'day-rates.csv')['n'])==120
    assert d['model_comparison']['test_n']==36
    assert (tmp_path/'rolling-rates.png').is_file() and (tmp_path/'analysis.md').is_file()
