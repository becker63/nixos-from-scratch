"""Deterministic chronology diagnostics; no inference or provider mutation."""
from __future__ import annotations
import argparse
from collections import Counter
import json
import math
import os
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import optimize, special, stats


def scope(patterns):
    parts=[]
    for p in patterns:
        if p == '//...': parts.append('all-targets')
        elif p.startswith('//'): parts.append(p[2:].split(':')[0].split('/')[0] or 'root-targets')
        else: parts.append('other-pattern')
    return '+'.join(sorted(set(parts))) or 'missing-pattern'


def family(patterns):
    names=[]
    for p in patterns:
        if p.startswith("//experiments/"):
            names.append("experiments/"+p[len("//experiments/"):].split("/")[0].split(":")[0])
        else:names.append(scope([p]))
    return "+".join(sorted(set(names))) or "missing-pattern"


def sessions(d, minutes):
    gaps=d['created_at_usec'].diff()/60e6
    return (gaps.isna() | (gaps>minutes)).cumsum().astype(int)


def grouped_rates(d, column):
    out=d.groupby(column, dropna=False)['success'].agg(['count','sum','mean']).reset_index()
    return out.rename(columns={'count':'n','sum':'passed','mean':'pass_rate'})


def streaks(y):
    if not len(y): return []
    result=[];last=int(y[0]);count=0
    for v in y:
        if int(v)!=last:
            result.append({'outcome':last,'length':count});last=int(v);count=0
        count+=1
    result.append({'outcome':last,'length':count})
    return result


def transition_counts(y, sid):
    out=np.zeros((2,2),int)
    for i in range(1,len(y)):
        if sid[i]==sid[i-1]:out[int(y[i-1]),int(y[i])]+=1
    return out


def beta_fit(counts):
    n=counts['n'].to_numpy();k=counts['passed'].to_numpy()
    mu=(k.sum()+.5)/(n.sum()+1)
    def neg(z):
        a,b=np.exp(z)
        return -np.sum(special.betaln(k+a,n-k+b)-special.betaln(a,b))
    fit=optimize.minimize(neg,np.log([mu*5,(1-mu)*5]),bounds=[(-6,12),(-6,12)])
    a,b=np.exp(fit.x)
    return float(a),float(b)


def model_comparison(d):
    y=d['success'].to_numpy(dtype=int);sid=d['session'].to_numpy();cut=int(.7*len(d));train=d.iloc[:cut]
    if cut<20 or len(d)-cut<10:return {'limitation':'Too few observations'}
    p=(y[:cut].sum()+.5)/(cut+1)
    trans=transition_counts(y[:cut],sid[:cut]);mp=(trans[:,1]+1)/(trans.sum(axis=1)+2)
    strat=train.groupby('workload')['success'].agg(['sum','count'])
    ps={k:float((r['sum']+10*p)/(r['count']+10)) for k,r in strat.iterrows()}
    a,b=beta_fit(grouped_rates(train,'session'))
    seen={}
    preds={k:[] for k in ('bernoulli','markov','workload_stratified','session_beta_binomial')}
    for i,row in d.iterrows():
        s=row['session'];k,n=seen.get(s,(0,0))
        if i>=cut:
            preds['bernoulli'].append(p)
            preds['markov'].append(float(mp[y[i-1]]) if i and sid[i]==sid[i-1] else p)
            preds['workload_stratified'].append(ps.get(row['workload'],p))
            preds['session_beta_binomial'].append((a+k)/(a+b+n))
        seen[s]=(k+int(row['success']),n+1)
    test=y[cut:];scores={};losses={}
    for name,values in preds.items():
        pr=np.clip(np.array(values),1e-8,1-1e-8)
        losses[name]=-(test*np.log(pr)+(1-test)*np.log1p(-pr))
        scores[name]={'heldout_log_loss':float(-np.mean(test*np.log(pr)+(1-test)*np.log1p(-pr))), 'heldout_brier':float(np.mean((pr-test)**2))}
    rng=np.random.default_rng(20261009);testsid=sid[cut:];testblocks=[np.flatnonzero(testsid==s) for s in np.unique(testsid)];paired={}
    for name in losses:
        if name=='bernoulli':continue
        differences=losses[name]-losses['bernoulli'];samples=[]
        for _ in range(999):
            idx=np.concatenate([testblocks[i] for i in rng.integers(0,len(testblocks),len(testblocks))]);samples.append(float(differences[idx].mean()))
        paired[name]={'mean_log_loss_difference':float(differences.mean()),'session_bootstrap_95_interval':np.quantile(samples,[.025,.975]).tolist()}
    return {'paired_session_bootstrap_difference_vs_bernoulli':paired,'train_n':cut,'test_n':len(test),'split':'chronological 70/30; only past outcomes used for online Markov/session predictions', 'training_pass_rate':float(p),'session_prior_alpha':a,'session_prior_beta':b,'scores':scores,'limitation':'Predictive comparison is descriptive; train/test workload drift and few sessions constrain interpretation.'}


def changepoint(y, sid, rng):
    n=len(y);minseg=max(50,int(.1*n))
    if n<2*minseg:return {'limitation':'Too few observations'}
    def ll(k,n):
        p=np.clip(k/n,1e-9,1-1e-9)
        return k*np.log(p)+(n-k)*np.log1p(-p)
    ks=np.arange(minseg,n-minseg+1)
    def scan(v):
        cs=np.cumsum(v);total=cs[-1]
        gains=2*(ll(cs[ks-1],ks)+ll(total-cs[ks-1],n-ks)-ll(total,n))
        best=int(np.argmax(gains));return float(gains[best]),int(ks[best])
    gain,idx=scan(y)
    blocks=[y[sid==s] for s in np.unique(sid)]
    null=[]
    for _ in range(499):
        order=rng.permutation(len(blocks));null.append(scan(np.concatenate([blocks[i] for i in order]))[0])
    return {'max_likelihood_gain':gain,'split_invocation_index':idx,'before_rate':float(y[:idx].mean()),'after_rate':float(y[idx:].mean()),'session_block_permutation_p':float((1+sum(v>=gain for v in null))/500),'null':'Permutation of whole sessions preserves within-session dependence; assumes exchangeable sessions, does not control workload drift.'}


def null_process_diagnostics(y, sid, transitions, overall):
    rng=np.random.default_rng(20261008)
    probabilities=(transitions[:,1]+1)/(transitions.sum(axis=1)+2)
    nulls={}
    if len(y)<100:return {'limitation':'Fewer than 100 observations','markov_equilibrium_pass_probability':float(probabilities[0]/(probabilities[0]+1-probabilities[1]))}
    for name in ('independent_bernoulli','stationary_first_order_markov'):
        minima=[];maxima=[];longest=[]
        for _ in range(499):
            if name=='independent_bernoulli':sim=rng.binomial(1,overall,len(y))
            else:
                uniforms=rng.random(len(y));sim=np.zeros(len(y),dtype=int)
                for i,u in enumerate(uniforms):
                    pr=overall if i==0 or sid[i]!=sid[i-1] else probabilities[sim[i-1]]
                    sim[i]=int(u<pr)
            rolled=np.convolve(sim,np.ones(100)/100,mode='valid')
            minima.append(float(rolled.min()));maxima.append(float(rolled.max()))
            longest.append(max((r['length'] for s in np.unique(sid) for r in streaks(sim[sid==s]) if r['outcome']==0),default=0))
        nulls[name]={'rolling_100_min_95_interval':np.quantile(minima,[.025,.975]).tolist(),'rolling_100_max_95_interval':np.quantile(maxima,[.025,.975]).tolist(),'longest_failure_streak_95_interval':np.quantile(longest,[.025,.975]).tolist()}
    nulls['markov_equilibrium_pass_probability']=float(probabilities[0]/(probabilities[0]+1-probabilities[1]))
    nulls['interpretation']='Fitted-process simulations are descriptive diagnostics, not independently validated significance tests or causal mechanisms.'
    return nulls


def analyze(path):
    os.umask(0o077)
    path=Path(path);root=path.parent;manifest=json.loads((root/'manifest.json').read_text())
    allrows=pd.read_parquet(path)
    if len(allrows)==0:raise ValueError('No invocation data')
    allrows=allrows.sort_values(['created_at_usec','invocation_id']).reset_index(drop=True)
    allrows['patterns']=allrows['pattern'].map(json.loads)
    allrows['target_scope']=allrows['patterns'].map(scope)
    # No native mission identity is available; this family is explicitly a target namespace proxy.
    allrows['experiment_family']=allrows['patterns'].map(family)
    allrows['pattern_key']=allrows['patterns'].map(lambda x:json.dumps(sorted(x)))
    allrows['time']=pd.to_datetime(allrows['created_at_usec'],unit='us',utc=True)
    allrows['day']=allrows['time'].dt.tz_convert('America/New_York').dt.strftime('%Y-%m-%d')
    allrows['week']=allrows['time'].dt.tz_convert('America/New_York').dt.tz_localize(None).dt.to_period('W-SUN').astype(str)
    allrows['session']=sessions(allrows,30)
    d=allrows[allrows['status'].isin(['SUCCESS','FAILURE'])].copy().reset_index(drop=True)
    d['success']=d['success'].astype(int)
    if len(d)<2:raise ValueError('Not enough completed invocations')
    d['workload']=d['target_scope']+'|'+d['command'].fillna('missing')
    d['duration_seconds']=pd.to_numeric(d['duration_usec'])/1e6
    d['duration_band']=pd.cut(d['duration_seconds'],[-np.inf,1,10,60,300,np.inf],labels=['<=1s','1-10s','10-60s','1-5min','>5min']).astype(str)
    def cache_ratio(value):
        c=json.loads(value)
        if not c:return np.nan
        h=int(c.get('actionCacheHits',0));m=int(c.get('actionCacheMisses',0))
        return h/(h+m) if h+m else np.nan
    d['cache_hit_ratio']=d['cache_metrics'].map(cache_ratio)
    d['cache_band']=pd.cut(d['cache_hit_ratio'],[-.001,.25,.5,.75,1.001],labels=['0-.25','.25-.5','.5-.75','.75-1']).astype(str)
    for col in ('day','week','target_scope','command','experiment_family','duration_band','bazel_exit_code','cache_band'):
        grouped_rates(d,col).to_csv(root/(col+'-rates.csv'),index=False)
    daily=grouped_rates(d,'day');weekly=grouped_rates(d,'week')
    y=d['success'].to_numpy();sid=d['session'].to_numpy();rng=np.random.default_rng(20261007)
    overall=float(y.mean());blocks=[y[sid==s] for s in np.unique(sid)]
    boot=[float(np.concatenate([blocks[i] for i in rng.integers(0,len(blocks),size=len(blocks))]).mean()) for _ in range(999)]
    interval=np.quantile(boot,[.025,.975]).tolist()
    sensitivity=[]
    for minutes in (10,20,30,60,120):
        ss=sessions(allrows,minutes);tmp=allrows[allrows['status'].isin(['SUCCESS','FAILURE'])].copy();tmp['success']=tmp['success'].astype(int);tmp['session']=ss.loc[tmp.index]
        g=grouped_rates(tmp,'session');t=transition_counts(tmp['success'].to_numpy(),tmp['session'].to_numpy())
        g.to_csv(root/f'sessions-{minutes}min.csv',index=False)
        sensitivity.append({'gap_minutes':minutes,'sessions':len(g),'median_n':float(g['n'].median()),'session_rate_sd':float(g['pass_rate'].std()),'transition_counts':t.tolist()})
    transitions=transition_counts(y,sid)
    rates=(transitions[:,1]/np.maximum(transitions.sum(axis=1),1)).tolist()
    observed_streaks=[s for block in blocks for s in streaks(block)]
    counts=Counter((s['outcome'],s['length']) for s in observed_streaks)
    pd.DataFrame([{'outcome':o,'length':n,'streak_count':v} for (o,n),v in sorted(counts.items())]).to_csv(root/'streak-distribution.csv',index=False)
    # Match only immediate same-workload successor within 30-minute session.
    repairs=[]
    for _,g in d.groupby(['session','repository','command','pattern_key'],dropna=False):
        r=g.to_dict('records')
        for a,b in zip(r,r[1:]):
            if a['success']==0 and b['success']==1:
                repairs.append({'failure_id':a['invocation_id'],'success_id':b['invocation_id'],'elapsed_seconds':(b['created_at_usec']-a['created_at_usec'])/1e6,'target_scope':a['target_scope'],'same_commit': bool(a['commit_sha'] and a['commit_sha']==b['commit_sha'])})
    pd.DataFrame(repairs).to_csv(root/'same-target-repairs.csv',index=False)
    cp=changepoint(y,sid,rng)
    if 'split_invocation_index' in cp:cp['split_created_at']=d.iloc[cp['split_invocation_index']]['created_at']
    # Lag dependence diagnostics; significance is not based on independent invocation trials.
    acf={str(lag):float(np.corrcoef(y[:-lag],y[lag:])[0,1]) if len(y)>lag+2 else None for lag in (1,2,5,10,20,50)}
    session_rates=grouped_rates(d,'session');session_rates.to_csv(root/'session-rates.csv',index=False)
    local_ranges={}
    rolling=pd.DataFrame({'invocation_id':d['invocation_id'],'created_at':d['created_at'],'cumulative':d['success'].expanding().mean()})
    for width in (50,100,200,500):
        values=d['success'].rolling(width,min_periods=width).mean();rolling[f'rolling_{width}']=values
        local_ranges[str(width)]={'min':float(values.min()),'max':float(values.max())} if values.notna().any() else None
    rolling.to_csv(root/'chronological-rates.csv',index=False)
    # Bernoulli baseline simulated with exact observed session lengths for longest streak context.
    longest=[]
    for _ in range(499):
        simulated=[rng.binomial(1,overall,size=len(b)) for b in blocks]
        longest.append(max((s['length'] for b in simulated for s in streaks(b) if s['outcome']==0),default=0))
    obs_long=max((s['length'] for s in observed_streaks if s['outcome']==0),default=0)
    diag={'records':len(allrows),'completed_n':len(d),'passed':int(y.sum()),'failed':int(len(y)-y.sum()),'pass_rate':overall,
          'session_cluster_bootstrap_95_interval':interval,'interval_assumptions':'Whole 30-minute-gap sessions resampled; assumes independent/exchangeable sessions; sensitivity tables provided.',
          'status_counts':manifest['status_counts'],'rolling_ranges':local_ranges,'transition_counts_failure_success_rows':transitions.tolist(),'next_pass_given_failure_or_success':rates,'lag_autocorrelation':acf,
          'session_sensitivity':sensitivity,'same_target_fail_to_pass':{'count':len(repairs),'median_elapsed_seconds':float(np.median([r['elapsed_seconds'] for r in repairs])) if repairs else None},
          'longest_failure_streak':obs_long,'bernoulli_simulated_longest_failure_streak_95_interval':np.quantile(longest,[.025,.975]).tolist(),'change_point':cp,'model_comparison':model_comparison(d),
          'null_process_diagnostics':null_process_diagnostics(y,sid,transitions,overall),'coverage_verified':manifest['verified_accessible_population'],'cache_ratio_observed_n':int(d['cache_hit_ratio'].notna().sum()),'repository_observed_n':int(d['repository'].notna().sum()),
          'stationarity_limitations':'Binary invocation outcomes violate usual continuous-series ADF assumptions. Rolling ranges, scan statistic with session permutations, lag correlation, and chronological predictive diagnostics test implications of constant-probability models; none proves stationarity.'}
    (root/'diagnostics.json').write_text(json.dumps(diag,indent=2)+'\n')
    # Charts contain actual measured chronology; bands are separately reported cluster intervals.
    fig,ax=plt.subplots(figsize=(11,5))
    for width in (50,100,200,500):ax.plot(np.arange(len(d))+1,rolling[f'rolling_{width}'],label=f'{width} invocations',alpha=.85)
    ax.axhline(overall,color='black',linestyle='--',label=f'overall {overall:.1%}');ax.set(xlabel='Completed invocation, chronological order',ylabel='Pass rate',ylim=(0,1));ax.legend();fig.tight_layout();fig.savefig(root/'rolling-rates.png',dpi=160);plt.close(fig)
    fig,ax=plt.subplots(figsize=(11,4));ax.plot(np.arange(len(d))+1,rolling['cumulative']);ax.axhline(.683,color='gray',linestyle='--',label='original dashboard 68.3%');ax.set(xlabel='Completed invocation, chronological order',ylabel='Cumulative pass rate',ylim=(0,1));ax.legend();fig.tight_layout();fig.savefig(root/'cumulative-rate.png',dpi=160);plt.close(fig)
    fig,(ax,counts_ax)=plt.subplots(2,1,figsize=(11,6),sharex=True,gridspec_kw={'height_ratios':[2,1]});ax.plot(session_rates['session'],session_rates['pass_rate'],marker='o',markersize=3);ax.axhline(overall,color='gray',linestyle='--');ax.set(ylabel='Pass rate',ylim=(0,1));counts_ax.bar(session_rates['session'],session_rates['n']);counts_ax.set(xlabel='Session (gap >30 min, chronological)',ylabel='n');fig.tight_layout();fig.savefig(root/'session-rates.png',dpi=160);plt.close(fig)
    fig,(ax,bx)=plt.subplots(2,1,figsize=(11,6),sharex=True);ax.plot(daily['day'],daily['pass_rate'],marker='o');ax.set(ylabel='Daily pass rate',ylim=(0,1));bx.bar(daily['day'],daily['n']);bx.set(ylabel='Completed n');bx.tick_params(axis='x',rotation=45);fig.tight_layout();fig.savefig(root/'daily-rates.png',dpi=160);plt.close(fig)
    # Reproducible stratified sample: failures and matched successful controls. No logs fetched here.
    candidates=d.copy();candidates['outcome']=candidates['success'].map({0:'failure',1:'success'})
    columns=['day','experiment_family','command','outcome','duration_band']
    grouped=list(candidates.groupby(columns,dropna=False,sort=True));selected=[]
    # Largest strata first, interleave outcomes; one deterministically sampled record per stratum.
    failure_groups=sorted([(k,g) for k,g in grouped if k[3]=='failure'],key=lambda z:(-len(z[1]),str(z[0])))
    success_groups=sorted([(k,g) for k,g in grouped if k[3]=='success'],key=lambda z:(-len(z[1]),str(z[0])))
    for outcome,groups,limit in [('failure',failure_groups,36),('success',success_groups,12)]:
        # Round-robin dates prevents large recent strata swallowing earlier periods.
        dates=sorted({k[0] for k,g in groups});queues={day:[(k,g) for k,g in groups if k[0]==day] for day in dates};done=0
        while done<limit and any(queues.values()):
            for day in dates:
                if not queues[day] or done>=limit:continue
                k,g=queues[day].pop(0);row=g.iloc[int(rng.integers(len(g)))];i=int(row.name)
                prev=d.iloc[i-1] if i>0 else None;next_=d.iloc[i+1] if i+1<len(d) else None
                def meta(x):return None if x is None else {k:x[k] for k in ('invocation_id','created_at','command','pattern_key','bazel_exit_code','status','commit_sha')}
                selected.append({'invocation_id':row['invocation_id'],'bazel_exit_code':row['bazel_exit_code'],'target_pattern':row['patterns'],'failed_target':None,'diagnostic_excerpt':None,'preceding':meta(prev),'subsequent':meta(next_),'stratum':dict(zip(columns,k)),'stratum_n':len(g),'selection_probability_within_stratum':1/len(g),'sampling_seed':20261007,'sampling_note':'Date-round-robin one per selected stratum; unselected strata have zero inclusion. Not an unbiased population taxonomy estimate.'});done+=1
    if not (root/'failure-evidence.json').exists():
        (root/'evidence-sample.json').write_text(json.dumps(selected,indent=2)+'\n')
    model=diag['model_comparison'];scores=model.get('scores',{})
    lines=['# BuildBuddy invocation chronology', '',f"Export: {len(allrows):,} visible records; {len(d):,} complete, {int(y.sum()):,} successful, {len(y)-int(y.sum()):,} failed. Pass rate **{overall:.2%}**.",f"Creation range: {manifest['earliest_created_at']} to {manifest['latest_created_at']}.",f"Accessible population coverage verified: **{manifest['verified_accessible_population']}**. See manifest for API scope and retention limitations.",'', '## Rates and dependence',f"Session-cluster bootstrap 95% interval: {interval[0]:.2%}–{interval[1]:.2%} under exchangeable-session assumptions.",f"Next invocation passes after failure: {rates[0]:.2%}; after success: {rates[1]:.2%} (within 30-minute-gap sessions).",f"Lag-1 correlation: {acf['1']:.3f}. Longest within-session failure streak: {obs_long}; IID Bernoulli simulation reference: {diag['bernoulli_simulated_longest_failure_streak_95_interval']}.",f"Same-target/command/repository failed-to-passed transitions: {len(repairs)}; median elapsed seconds: {diag['same_target_fail_to_pass']['median_elapsed_seconds']}.",'', '| Rolling window | Minimum pass rate | Maximum pass rate |','|---|---:|---:|']
    for w,r in local_ranges.items():
        if r:lines.append(f"| {w} | {r['min']:.1%} | {r['max']:.1%} |")
    lines.extend(['','## Competing models (chronological held-out scoring)','| Model | Log loss (lower better) | Brier (lower better) |','|---|---:|---:|'])
    for name,s in scores.items():lines.append(f"| {name} | {s['heldout_log_loss']:.4f} | {s['heldout_brier']:.4f} |")
    lines.extend(['',f"Model comparison details: `{json.dumps(model)}`.",'', '## Change-point and stationarity',f"Scan diagnostic: `{json.dumps(cp)}`.",diag['stationarity_limitations'],'','## Interpretation','A cumulative mean averages an increasing number of observations and smooths local changes mechanically. A stable final aggregate does not imply a stable local probability. Chronological rolling ranges and held-out model scores above distinguish those claims.','Repair-loop evidence is the measured same-target-pattern/command failure-to-success pairing and elapsed time. Broad patterns such as //... are not exact failed-target matches. It is an association: matching targets and timing do not establish that an agent repaired the underlying bug. Session clustering, command/target mix, and cache reuse are measured process correlates; their causal effects are not identified.','Duration and cache counters are measured after execution, so outcome associations cannot be interpreted as causal or used as leak-free pre-build predictors.',f"Fitted Markov equilibrium pass probability: {diag['null_process_diagnostics']['markov_equilibrium_pass_probability']:.2%}; this descriptive outcome balance approximates the aggregate without establishing a causal process.",'Experiment family is a deterministic target namespace proxy; the API does not provide verified mission boundaries. Missing repository metadata cannot be reconstructed from guesses.','Only two weeks or fewer of visible history may be insufficient to infer long-term stationarity. Missing/unknown/incomplete statuses are excluded from completed-outcome rate denominators and retained in the dataset.','','## Artifacts','Daily/weekly and stratified CSV tables, chronological rolling/cumulative CSV, session-boundary sensitivity tables, transitions/streaks/repairs, diagnostics JSON, a manifest, and the Parquet dataset are in this directory.','![Rolling rates](rolling-rates.png)','![Cumulative rate](cumulative-rate.png)','![Session rates and sample counts](session-rates.png)','![Daily rates and sample counts](daily-rates.png)'])
    (root/'analysis.md').write_text('\n'.join(lines)+'\n')
    for p in root.iterdir():
        if p.is_file():p.chmod(0o600)
    print(json.dumps({'analysis_path':str(root/'analysis.md'),'diagnostics':diag},indent=2))
    return diag


def main():
    p=argparse.ArgumentParser();p.add_argument('parquet');args=p.parse_args();analyze(args.parquet)


if __name__=='__main__':main()
