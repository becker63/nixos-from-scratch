"""Bounded stratified log evidence, deterministic taxonomy, existing Jev MCP."""
import argparse
import asyncio
from collections import Counter
import json
import os
from pathlib import Path
import re

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from .server import BASE, Client, HistoryError, credential

CATEGORIES={
    'compiler':'Compiler or type-checking failure supported by exact compiler diagnostic',
    'bazel_configuration':'Bazel target, package, BUILD/Starlark configuration error',
    'scientific_assertion':'Failed scientific or test assertion with exact assertion evidence',
    'expected_negative':'Explicitly documented expected negative experiment; never assume intentional failure',
    'dependency':'Dependency download, resolution, or acquisition failure',
    'infrastructure':'Infrastructure or remote-execution failure',
    'timeout':'Explicit timeout',
    'unknown':'Insufficient evidence or unsupported category; interruption without identified cause belongs here',
}
RULES=[
 ('dependency',r'(failed to (fetch|download)|error downloading|repository rule.*failed|could not resolve.*dependency)'),
 ('infrastructure',r'(remote execution.*(failed|unavailable)|rpc error.*(Unavailable|Internal)|no (registered|available).*executor)'),
 ('timeout',r'(timed out|timeout exceeded|DEADLINE_EXCEEDED)'),
 ('compiler',r'(error: expected type|error:.*(undeclared identifier|incompatible types)|type mismatch|error TS\d+|compilation failed|error:.*(expected|found).*type)'),
 ('bazel_configuration',r'(no such (target|package)|BUILD.*(syntax error|not defined)|Starlark.*error|invalid.*bazel.*option|unrecognized option)'),
 ('scientific_assertion',r'(AssertionError|assertion (failed|failure)|FAIL.*expected.*(actual|got))'),
]


def redact(text, key):
    text=text.replace(key,'[REDACTED]')
    text=re.sub(r'(?i)((?:api[_-]?key|authorization|token|password|secret)\s*[=:]\s*)([^\s,;]+)',r'\1[REDACTED]',text)
    text=re.sub(r'(?i)Bearer\s+[A-Za-z0-9_./:+=\-]+','Bearer [REDACTED]',text)
    text=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',text)
    return text


def excerpt(text):
    lines=text.splitlines();hits=[i for i,line in enumerate(lines) if re.search(r'(?i)(error:|ERROR:|FAIL:|failed|assert|exception|timeout|interrupted)',line)]
    selected=sorted({j for i in hits[:12] for j in range(max(0,i-1),min(len(lines),i+3))})
    result='\n'.join(lines[i] for i in selected)
    # Preserve an exact contiguous portion; do not rewrite diagnostics.
    return result[:4000] if result else '\n'.join(lines[-12:])[:4000]


def deterministic(record):
    code=record['bazel_exit_code'];text=record.get('diagnostic_excerpt') or ''
    if code in ('INTERRUPTED','8','CANCELED','CANCELLED'):
        return {'category':'unknown','termination': 'interrupted' if code in ('INTERRUPTED','8') else 'canceled','basis':'explicit Bazel exit status; initiating cause not established'}
    if code == 'EXTERNAL_DEPS_ERROR':
        return {'category':'dependency','basis':'explicit Bazel external-dependencies exit status'}
    if code == 'REMOTE_ERROR':
        return {'category':'infrastructure','basis':'explicit Bazel remote-error exit status'}
    if code in ('TIMEOUT','36'):
        return {'category':'timeout','basis':'explicit Bazel exit status'}
    if code in ('PARSING_FAILURE','COMMAND_LINE_ERROR','2'):
        return {'category':'bazel_configuration','basis':'explicit Bazel command/parse exit status'}
    if code in ('NO_TESTS_FOUND','4'):
        return {'category':'bazel_configuration','basis':'explicit no-tests-found exit status'}
    for category,pattern in RULES:
        match=re.search(pattern,text,re.I)
        if match:return {'category':category,'basis':'exact diagnostic pattern','matched_text':match[0]}
    return None


async def collect(root, use_jev):
    os.umask(0o077);root=Path(root);sample=json.loads((root/'evidence-sample.json').read_text())
    if len(sample)>48:raise ValueError('Evidence extraction bounded at 48 records')
    key=credential();c=Client(key);pending=[];results=[]
    for record in sample:
        r=dict(record);r['invocation_url']=BASE+'/invocation/'+r['invocation_id']
        if r['stratum']['outcome']=='success':
            r['deterministic']={'category':'successful_control','basis':'provider complete-success outcome'}
            r['log_fetch']={'performed':False};results.append(r);continue
        chunks=[];token='';exhausted=False;fetch_error=None
        for page in range(3):
            try:body=await c.rpc('GetLog',{'selector':{'invocation_id':r['invocation_id']},'page_token':token})
            except HistoryError as e:fetch_error=str(e);break
            chunks.append(redact(body.get('log',{}).get('contents',''),key));token=body.get('nextPageToken','')
            if not token:exhausted=True;break
        # Raw logs are never persisted; only bounded, sanitized diagnostic lines.
        text='\n'.join(chunks);r['diagnostic_excerpt']=excerpt(text)
        target=re.search(r'(?:FAIL:\s*|Target\s+)(//[^\s]+)',text)
        r['failed_target']=target[1] if target else None
        r['log_fetch']={'performed':True,'pages':len(chunks),'exhausted':exhausted,'error':fetch_error,'max_pages':3,'excerpt_truncated':len(text)>4000}
        r['deterministic']=deterministic(r)
        if r['deterministic'] is None:pending.append(r)
        results.append(r)
    (root/'failure-evidence.json').write_text(json.dumps(results,indent=2)+'\n')
    if use_jev and pending:
        # Reuse the current Jev stdio executable and protected launcher; no implementation replacement.
        cfg=json.loads((Path.home()/'.config/tunnel-client/jev.yaml').read_text())
        executable=cfg['mcp']['commands'][0]['command']
        if not executable.startswith('/nix/store/') or not executable.endswith('/bin/jev-native-mcp'):
            raise ValueError('Expected existing Nix-managed Jev MCP command')
        params=StdioServerParameters(command=executable)
        async with stdio_client(params) as (read,write):
            async with ClientSession(read,write) as session:
                await session.initialize()
                request_records=[]
                for r in pending:
                    state={k:r[k] for k in ('invocation_id','bazel_exit_code','failed_target','target_pattern','diagnostic_excerpt','preceding','subsequent')}
                    request_records.append({'id':r['invocation_id'],'state':state,'questions':{
                        'cause':{'type':'choice','instructions':'Classify this failed build from exact diagnostics. Exit codes and explicit error messages take precedence. Expected negative requires explicit evidence; otherwise abstain. Do not guess mission intent from nearby successes.','criteria':CATEGORIES},
                        'sufficient':{'type':'noul','instructions':'Is the supplied excerpt sufficient to identify a cause?'},
                        'ambiguity':{'type':'score','instructions':'How ambiguous is failure attribution from this evidence?','criteria':['Clear evidence','Several plausible explanations','Insufficient evidence']}}})
                outputs=[]
                for i in range(0,len(request_records),32):
                    result=await session.call_tool('jev_decide_batch',{'records':request_records[i:i+32],'concurrency':4})
                    if result.isError:
                        outputs.append({'error':'Existing Jev MCP call failed'});continue
                    body=result.structuredContent or json.loads(result.content[0].text)
                    assert key not in json.dumps(body)
                    outputs.append(body)
                (root/'jev-classification-native-responses.json').write_text(json.dumps(outputs,indent=2)+'\n')
                outcomes={r['id']:r for b in outputs for r in b.get('results',[])}
                for r in pending:r['jev']=outcomes.get(r['invocation_id'],{'success':False,'error':'No semantic result'})
    counts=Counter()
    for r in results:
        if r.get('deterministic'):category=r['deterministic']['category']
        elif r.get('jev',{}).get('success'):category=r['jev']['answers']['cause']['choice']
        else:category='unknown'
        r['category']=category;counts[category]+=1
    (root/'failure-taxonomy.json').write_text(json.dumps({'records':results,'sample_counts':dict(counts),'limits':['Stratified illustrative sample, not population category prevalence.','Exit status and exact diagnostic rules override semantic guesses.','Local request neighbors are not confirmed mission membership.','Partial/missing logs remain unknown; Jev probabilities are evidence, not causation.']},indent=2)+'\n')
    lines=['# Stratified failure taxonomy','','Sampling spans creation dates, deterministic target namespace proxies, command, outcome, and duration bands. 36 failure strata and 12 successful controls were requested; available strata may reduce those totals. Selected-stratum sizes and inclusion probabilities are recorded; unselected strata are not represented. Category counts below must not be extrapolated as population prevalence.','','| Category | Sample records |','|---|---:|']
    lines.extend(f'| {k} | {v} |' for k,v in sorted(counts.items()))
    lines.extend(['','## Representative invocations'])
    for category in sorted(counts):
        r=next(r for r in results if r['category']==category)
        if category=='successful_control':continue
        basis=r['deterministic']['basis'] if r.get('deterministic') else 'Jev probability evidence; see native response'
        lines.append(f"- **{category}**: [{r['invocation_id']}]({r['invocation_url']}) — {r['bazel_exit_code']}; {basis}.")
        if r.get('diagnostic_excerpt'):lines.extend(['','```text',r['diagnostic_excerpt'][:600].replace('```',''), '```',''])
    lines.extend(['','Native semantic probability distributions, confidence, score legends, model IDs and usage are preserved in `jev-classification-native-responses.json` when inference ran. Missing logs are not evidence of build failure. No causal claims are established by these classifications.'])
    (root/'failure-taxonomy.md').write_text('\n'.join(lines)+'\n')
    for p in root.iterdir():
        if p.is_file():p.chmod(0o600)
    print(json.dumps({'sample_records':len(results),'semantic_records':len(pending) if use_jev else 0,'sample_counts':dict(counts),'taxonomy_path':str(root/'failure-taxonomy.md')},indent=2))


def main():
    p=argparse.ArgumentParser();p.add_argument('export_directory');p.add_argument('--jev',action='store_true');args=p.parse_args();asyncio.run(collect(args.export_directory,args.jev))


if __name__=='__main__':main()
