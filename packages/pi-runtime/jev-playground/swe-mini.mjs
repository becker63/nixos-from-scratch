#!/usr/bin/env node
// SWE-JS8: an outer adapter, not a second agent or benchmark implementation.
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,rmSync,existsSync,realpathSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn,execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {tmpdir} from 'node:os';
import {compileKernel,dependencyModules} from './runtime.mjs';
import {sweVerifier,sha256} from './swe-verifier.mjs';
const exec=promisify(execFile),here=dirname(fileURLToPath(import.meta.url));
export const budgets={maxSteps:24,maxEvaluations:32,maxTransforms:6,maxRepeated:2};
const metadataSelection=String.raw`
import json, math, subprocess, sys
from pathlib import Path
import yaml
root=Path(sys.argv[1]).resolve()
repos=['babel/babel','vuejs/core','facebook/docusaurus','immutable-js/immutable-js','mrdoob/three.js','axios/axios','preactjs/preact']
rows=[]
for p in sorted((root/'tasks').glob('*/task.yaml')):
    m=yaml.safe_load(p.read_text())
    if m['repo'] not in repos: continue
    tests=json.loads((p.parent/'tests.json').read_text())
    stat=subprocess.check_output(['git','apply','--numstat','-'],input=(p.parent/'gold.patch').read_bytes()).decode().splitlines()
    changed=sum(int(n) for l in stat for n in l.split('\t')[:2] if n.isdigit())
    rows.append(dict(instanceId=m['instance_id'],repo=m['repo'],baseCommit=m['base_commit'],taskDir=str(p.parent),image=m['image'],goldChangedLines=changed,goldChangedFiles=len(stat),f2pCount=len(tests['FAIL_TO_PASS']),p2pCount=len(tests['PASS_TO_PASS'])))
assert len(rows)==43, f'Expected 43 JS/TS tasks, got {len(rows)}'
selected=[];fallback={}
for repo in repos:
    group=[r for r in rows if r['repo']==repo]
    for r in group:r['difficulty']=0
    for metric in ['goldChangedLines','goldChangedFiles','f2pCount','p2pCount']:
        vals=[math.log1p(r[metric]) for r in group];lo=min(vals);hi=max(vals)
        for r,v in zip(group,vals):r['difficulty']+=(v-lo)/(hi-lo)/4 if hi>lo else 0
    vals=sorted(r['difficulty'] for r in group)
    used=set()
    for q in ([.25,.75] if repo=='preactjs/preact' else [.5]):
        x=q*(len(vals)-1);target=vals[int(x)]+(vals[min(int(x)+1,len(vals)-1)]-vals[int(x)])*(x-int(x))
        order=sorted((r for r in group if r['instanceId'] not in used),key=lambda r:(abs(r['difficulty']-target),r['instanceId']))
        choice=dict(order[0],desiredQuantile=q,targetDifficulty=target);selected.append(choice);used.add(choice['instanceId'])
        fallback[choice['instanceId']]=[r['instanceId'] for r in order]
print(json.dumps(dict(name='SWE-JS8',diagnosticOnly=True,metadataOnly=True,taskRepoCommit=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD']).decode().strip(),selectionRule='Mean of four repo-local min-max-normalized log1p metrics; closest to interpolated scalar median, or Preact quartiles; instance ID tie-break',selected=selected,sameRepoFallbackOrder=fallback,allJsMetadata=rows)))
`;
export async function selectTasks(taskRepo,python){return JSON.parse((await exec(python,['-c',metadataSelection,resolve(taskRepo)],{maxBuffer:1024*1024})).stdout);}
export async function materialize(task){
 const workspace=realpathSync(mkdtempSync(join(tmpdir(),'pure-jev-swe-'))),started=Date.now();
 try{for(const args of [['init','--quiet'],['remote','add','origin',`https://github.com/${task.repo}.git`],['fetch','--quiet','--depth','1','origin',task.baseCommit],['checkout','--quiet','--detach','FETCH_HEAD']])await exec('git',args,{cwd:workspace,timeout:120000,maxBuffer:1024*1024});
 if((await exec('git',['rev-parse','HEAD'],{cwd:workspace})).stdout.trim()!==task.baseCommit)throw Error('Wrong base commit');
 if((await exec('git',['status','--porcelain'],{cwd:workspace})).stdout)throw Error('Dirty initial checkout');
 return {workspace,checkoutMs:Date.now()-started,baseHash:task.baseCommit};
 }catch(e){rmSync(workspace,{recursive:true,force:true});throw e;}
}
export async function solve(task,workspace,verifier,solverOptions={}){
 const {kernelSnapshot,...agentOptions}=solverOptions;const kernel=kernelSnapshot??compileKernel(),started=Date.now(),env=Object.fromEntries(['PATH','HOME','TMPDIR','SSL_CERT_FILE'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]));env.PI_AGENT_MODE='jev';
 const options={root:workspace,task:task.problemStatement,grammar:'J3',budgets,...agentOptions};
 // Only original issue + clean source + existing kernel. No task directory,
 // hidden tests, selection metrics, gold patch, or evaluation assets cross IPC.
 const input={kernel,modules:dependencyModules,policy:'jev',externalVerifier:true,verificationScope:verifier.verificationScope,options};
 try{
  const result=await new Promise((res,rej)=>{
   const child=spawn(process.execPath,[join(here,'solve-child.mjs')],{cwd:workspace,env,stdio:['pipe','pipe','pipe','ipc']});let out='',err='';
   const timer=setTimeout(()=>child.kill('SIGTERM'),Math.max(480000,(verifier.timeoutSeconds+120)*1000));
   child.stdout.on('data',b=>{out+=b;if(out.length>16*1024*1024)child.kill('SIGTERM');});child.stderr.on('data',b=>err=(err+b).slice(-2000));
   child.on('message',async message=>{
    if(message.kind!=='verify')return;
    let reply;try{reply=await verifier.verify(workspace);}catch{reply={infrastructureFailure:true};}
    if(child.connected)child.send({kind:'verification-result',requestId:message.requestId,passed:reply.passed,failures:reply.failures??[],fingerprint:reply.fingerprint??'',infrastructureFailure:reply.infrastructureFailure===true});
   });
   child.on('error',rej);child.on('close',code=>{clearTimeout(timer);if(code!==0)return rej(Error(`Pure child failed (${code}): ${err}`));try{res(JSON.parse(out));}catch(e){rej(e);}});
   child.stdin.end(JSON.stringify(input));
  });
  if(result.isolation.codexCalls!==0||result.isolation.workerCalls!==0||result.receipt.metrics.codexCalls!==0||result.receipt.metrics.workerCalls!==0)throw Error('Generation firewall failed');
  return {...result,solverWallMs:Date.now()-started,solverSourceHash:sha256(readFileSync(join(kernel,'jev-agent/controller.js'))),inputHash:sha256(JSON.stringify(options)),visibleGoldPatch:false};
 }finally{if(!kernelSnapshot)rmSync(kernel,{recursive:true,force:true});}
}
export function analyzeRun(result,goldFiles){
 const frontier=result.events.find(e=>e.kind==='frontier')?.files.map(f=>f.path)??[],inspected=result.events.filter(e=>e.kind==='inspect').map(e=>e.file);
 const retained=goldFiles.some(f=>frontier.includes(f)),correctInspected=goldFiles.some(f=>inspected.includes(f)),r=result.receipt;
 let failureStage=r.kind==='BenchmarkBootstrapFailure'?r.kind:r.kind==='Exhausted'?'BudgetExhaustion':r.kind==='ProviderFailure'?'ProviderFailure':r.taskKind!=='Repair'?'TaskClassificationFailure':r.kind==='Success'?null:!retained?'CandidateRecallFailure':!correctInspected?'FileSelectionFailure':r.metrics.mutations===0?'ActionGenerationFailure':r.metrics.reverts?'RecoveryFailure':'ActionSelectionFailure';
 return {goldFileRetained:retained,goldFileInspected:correctInspected,goldOperationExpressible:null,grammarAnalysis:'Not established; an exact single-edit comparison is evidence only, not a semantic reachability proof',failureStage,filesInspected:new Set(inspected).size,symbolsInspected:result.events.filter(e=>e.kind==='execute'&&e.args[0]?.kind==='InspectSymbol').length};
}
// POST-HOC only. Uses the same generator, without changing the solve or source.
export async function analyzeGold(task,workspace,result,grammar='J3'){
 const goldPatch=join(task.taskDir,'gold.patch');
 const goldFiles=(await exec('git',['apply','--numstat',goldPatch])).stdout.trim().split('\n').filter(Boolean).map(l=>l.split('\t').slice(2).join('\t'));
 const analysis=analyzeRun(result,goldFiles),privateIndex=mkdtempSync(join(tmpdir(),'swe-gold-index-')),kernel=compileKernel();
 const env={...process.env,GIT_INDEX_FILE:join(privateIndex,'index')};const perFile=[];
 try{
  await exec('git',['read-tree','HEAD'],{cwd:workspace,env});
  await exec('git',['apply','--cached',goldPatch],{cwd:workspace,env});
  for(const file of goldFiles){
   if(!/\.(?:ts|js|mjs|tsx|jsx)$/.test(file))continue;
   try{
    const base=(await exec('git',['show',`HEAD:${file}`],{cwd:workspace,maxBuffer:1024*1024})).stdout;
    const gold=(await exec('git',['show',`:${file}`],{cwd:workspace,env,maxBuffer:1024*1024})).stdout;
    // Original source is read from git, even if Jev left a successful mutation.
    const target=result.events.find(e=>e.kind==='frontier')?.files.find(f=>f.path===file)??{id:'PostHoc',path:file,family:'Outer',bytes:base.length};
    const code=`import {generateEdits,symbols} from ${JSON.stringify(join(kernel,'jev-agent/transforms.js'))};const source=${JSON.stringify(base)};const r=generateEdits(${JSON.stringify(target)},${JSON.stringify(join(workspace,file))},source,${JSON.stringify(grammar)});console.log(JSON.stringify({...r,symbols:symbols(${JSON.stringify(target)},${JSON.stringify(join(workspace,file))},source)}));`;
    const generated=JSON.parse((await exec(process.execPath,['--input-type=module','-e',code],{timeout:30000,maxBuffer:1024*1024})).stdout);
    const matches=generated.edits.filter(e=>base.slice(0,e.start)+e.to+base.slice(e.end)===gold);
    perFile.push({file,legalEdits:generated.edits.length,rawEdits:generated.before,diagnostics:generated.diagnostics,exactGoldSingleEditMatch:matches.length>0,families:matches.map(e=>e.family),goldEditIds:matches.map(e=>e.id),owningSymbols:generated.symbols.filter(s=>matches.some(e=>e.start>=s.start&&e.end<=s.end)).map(s=>s.name)});
   }catch(e){perFile.push({file,exactGoldSingleEditMatch:null,error:String(e.message).slice(0,300)});}
  }
 }finally{rmSync(privateIndex,{recursive:true,force:true});rmSync(kernel,{recursive:true,force:true});}
 const expected=perFile.flatMap(f=>(f.goldEditIds??[]).map(id=>({id,file:f.file}))),correctActions=expected.map(e=>'A'+e.id);
 if(analysis.goldFileInspected&&result.receipt.kind!=='Success'&&expected.length){
  const prepared=result.events.filter(e=>e.kind==='prepare').flatMap(e=>e.edits??[]);
  const generated=prepared.some(e=>expected.some(g=>g.id===e.id&&g.file===e.file));
  const choices=result.events.filter(e=>e.kind==='evaluation'&&e.request.questions.bestAction?.type==='choice');
  const survived=choices.some(e=>correctActions.some(a=>Object.hasOwn(e.request.questions.bestAction.criteria,a)));
  if(!generated)analysis.failureStage='SymbolSelectionFailure';
  else if(!survived)analysis.failureStage='NarrowingFailure';
  else if(result.receipt.metrics.reverts)analysis.failureStage='RecoveryFailure';
  else analysis.failureStage='ActionSelectionFailure';
 }
 const exactPatchReachable=goldFiles.length===1&&perFile.length===1&&perFile[0].exactGoldSingleEditMatch===true;
 return {...analysis,goldFiles,perFile,exactGoldPatchReachable:exactPatchReachable,goldOperationExpressible:exactPatchReachable?true:null,grammarAnalysis:'Exact one-transform gold match is a sufficient positive control. No match does not prove absence of a semantically equivalent finite repair.'};
}
export async function runSlice(selection,{python,output,releaseImages=false,verificationTimeoutSeconds=300}){
 if(!Number.isInteger(verificationTimeoutSeconds)||verificationTimeoutSeconds<1||verificationTimeoutSeconds>900)throw Error("Verification timeout must be an integer from 1 to 900 seconds");
 output=resolve(output);mkdirSync(output,{recursive:true});
 const actualTaskCommit=(await exec('git',['-C',dirname(dirname(selection.selected[0].taskDir)),'rev-parse','HEAD'])).stdout.trim();
 if(actualTaskCommit!==selection.taskRepoCommit)throw Error('Frozen task repository commit mismatch');
 const {name,diagnosticOnly,taskRepoCommit,selectionRule,metadataOnly,selected,sameRepoFallbackOrder,allJsMetadata}=selection;
 const report={name,diagnosticOnly,taskRepoCommit,selectionRule,metadataOnly,selected,sameRepoFallbackOrder,allJsMetadata,selectionHash:sha256(JSON.stringify(selection.selected.map(({taskDir,...m})=>m))),frozenAt:new Date().toISOString(),grammar:'J3',budgets,verificationTimeoutSeconds,officialHarnessVersion:(await exec(python,['-c','import importlib.metadata;print(importlib.metadata.version("swebench"))'])).stdout.trim(),smokeGate:false,attempts:[],results:[]};
 const save=()=>{
  const runs=report.results.filter(r=>r.agent),count=runs.length;
  report.actualPureRuns=count;
  report.funnel={selected:selection.selected.length,executed:count,candidateFileRetained:count?runs.filter(r=>r.analysis?.goldFileRetained).length:null,correctFileInspected:count?runs.filter(r=>r.analysis?.goldFileInspected).length:null,goldOperationExpressible:count?runs.filter(r=>r.analysis?.goldOperationExpressible===true).length:null,grammarReachabilityUnestablished:count?runs.filter(r=>r.analysis?.goldOperationExpressible!==true).length:null,mutationAttempted:count?runs.filter(r=>r.agent.mutations>0).length:null,officiallyResolved:count?runs.filter(r=>r.officialResolved===true).length:null,correctNeedsGeneration:null};
  writeFileSync(join(output,'swe-js8.json'),JSON.stringify(report,null,2)+'\n');
 };save();
 for(let slot=0;slot<selection.selected.length;slot++){
  const desired=selection.selected[slot];let completed=false;const occupied=new Set([...report.results.map(r=>r.instanceId),...selection.selected.filter(r=>r.instanceId!==desired.instanceId).map(r=>r.instanceId)]);
  // One fallback maximum; never replace a repository or fan out on image errors.
  for(const id of selection.sameRepoFallbackOrder[desired.instanceId].filter(id=>!occupied.has(id)).slice(0,2)){
   const metadata=selection.allJsMetadata.find(r=>r.instanceId===id),attempt={instanceId:id,selectedInstanceId:desired.instanceId,repo:metadata.repo,bootstrap:{image:metadata.image,reused:false,pulled:false,built:false,environmentSuccess:false}};report.attempts.push(attempt);save();
   let workspace;
   try{
    await exec('git',['-C',dirname(dirname(metadata.taskDir)),'sparse-checkout','add',`/tasks/${id}/`],{timeout:60000});
    try{await exec('docker',['image','inspect',metadata.image],{maxBuffer:1024*1024});attempt.bootstrap.reused=true;}catch{
     const disk=(await exec('df',['--output=avail','-B1','/'])).stdout.trim().split('\n').at(-1).trim();if(Number(disk)<4*1024**3)throw Error('Less than 4 GiB available; refusing image pull');
     const start=Date.now();await exec('docker',['pull','--platform','linux/amd64',metadata.image],{timeout:180000,maxBuffer:1024*1024});attempt.bootstrap.imageMs=Date.now()-start;attempt.bootstrap.pulled=true;
    }
    attempt.bootstrap.imageDigests=JSON.parse((await exec('docker',['image','inspect',metadata.image,'--format','{{json .RepoDigests}}'],{timeout:10000,maxBuffer:8192})).stdout.trim());
    const start=Date.now();try{await exec('docker',['run','--pull=never','--rm','--platform','linux/amd64','--entrypoint','/bin/true',metadata.image],{timeout:30000,maxBuffer:8192});}finally{attempt.bootstrap.smokeMs=Date.now()-start;}
    const runtimeStart=Date.now();try{const probe=await exec('docker',['run','--pull=never','--rm','--platform','linux/amd64','--entrypoint','node',metadata.image,'--version'],{timeout:30000,maxBuffer:8192});attempt.bootstrap.nodeVersion=probe.stdout.trim();}finally{attempt.bootstrap.runtimeProbeMs=Date.now()-runtimeStart;}
    const task={instanceId:id,repo:metadata.repo,baseCommit:metadata.baseCommit,taskDir:metadata.taskDir,problemStatement:readFileSync(join(metadata.taskDir,'problem_statement.md'),'utf8')};
    const checkout=await materialize(task);workspace=checkout.workspace;attempt.checkoutMs=checkout.checkoutMs;attempt.problemStatementLength=task.problemStatement.length;
    const verifier=sweVerifier({instanceId:id,taskDir:task.taskDir,python,output:join(output,'private-evaluation'),timeoutSeconds:verificationTimeoutSeconds});
    const empty=await verifier.verify(workspace);attempt.emptyPatch=empty;
    if(empty.infrastructureFailure)throw Error(empty.error);
    if(empty.passed){attempt.terminal='InvalidInstanceState';throw Error('Empty patch already resolves task');}
    attempt.bootstrap.environmentSuccess=true;attempt.workspaceBaseCommit=checkout.baseHash;attempt.workspaceFrozenHash=sha256(checkout.baseHash+'\n'+task.problemStatement);
    if(!report.smokeGate){
     // Gold stays outer-only and is evaluated without ever applying it to source.
     attempt.goldSmoke=await verifier.evaluatePatch(readFileSync(join(task.taskDir,'gold.patch'),'utf8'));
     if(!attempt.goldSmoke.passed)throw Error(attempt.goldSmoke.error||'Official gold smoke did not resolve');
    }
    const result=await solve(task,workspace,verifier);writeFileSync(join(output,`${id}.pure.json`),JSON.stringify(result,null,2)+'\n');
    attempt.verificationCalls=verifier.calls.length;attempt.verificationMs=verifier.calls.reduce((n,c)=>n+c.wallMs,0);attempt.terminal=result.receipt.kind;attempt.agent=result.receipt.metrics;attempt.isolation=result.isolation;const finalPatch=(await exec('git',['diff','--binary','HEAD'],{cwd:workspace,maxBuffer:8*1024*1024})).stdout;const finalCheck=verifier.calls.findLast(c=>c.patchHash===sha256(finalPatch));attempt.officialResolved=finalCheck?.officialResolved??null;attempt.finalPatchHash=sha256(finalPatch);
    try{attempt.analysis=await analyzeGold(task,workspace,result);}catch(e){attempt.analysis={failureStage:'PostHocUnavailable',error:String(e.message).slice(0,300)};}attempt.trajectory=result.receipt.trajectory;attempt.agentDeterministicMs=Math.max(0,result.receipt.metrics.deterministicMs-result.verificationMs);attempt.jevInferenceMs=result.receipt.metrics.jevLatencyMs;attempt.solveVerificationMs=result.verificationMs;
    report.results.push(attempt);completed=true;
    if(slot===0){report.smokeGate=result.isolation.jevRequests>0&&result.receipt.metrics.jevInputTokens>0&&!['ProviderFailure','BenchmarkBootstrapFailure'].includes(result.receipt.kind)&&result.isolation.codexCalls===0&&result.isolation.workerCalls===0&&attempt.goldSmoke.passed&&!attempt.emptyPatch.passed;if(!report.smokeGate)attempt.smokeFailure='Pure first-instance smoke invariant failed';}
    save();break;
   }catch(e){attempt.terminal??='BootstrapUnavailable';attempt.bootstrap.error=String(e.stderr||e.stdout||e.message).slice(-2000);save();
    // All published tasks here use AMD64. If the host cannot execute that ISA,
    // inspect the next same-repo manifest rather than pulling an equivalent image.
    if(/exec format error|no such file or directory/i.test(attempt.bootstrap.error)&&!attempt.bootstrap.environmentSuccess){
     const nextId=selection.sameRepoFallbackOrder[desired.instanceId].find(x=>x!==id),next=selection.allJsMetadata.find(r=>r.instanceId===nextId);
     if(next){const fallback={instanceId:nextId,selectedInstanceId:desired.instanceId,repo:next.repo,terminal:'BootstrapUnavailable',bootstrap:{image:next.image,reused:false,pulled:false,built:false,environmentSuccess:false,error:'Same AMD64 architecture as failed first environment; no rebuild or second pull attempted'}};try{const manifest=JSON.parse((await exec('docker',['manifest','inspect',next.image],{timeout:30000,maxBuffer:1024*1024})).stdout);fallback.bootstrap.platforms=manifest.manifests?.map(m=>m.platform);}catch(e){fallback.bootstrap.manifestError=String(e.message).slice(0,300);}report.attempts.push(fallback);}break;
    }
   }finally{if(workspace)rmSync(workspace,{recursive:true,force:true});if(releaseImages){try{await exec('docker',['image','rm',metadata.image],{timeout:30000,maxBuffer:8192});attempt.bootstrap.imageReleased=true;}catch{attempt.bootstrap.imageReleased=false;}}}
  }
  if(!completed)report.results.push({instanceId:desired.instanceId,repo:desired.repo,terminal:'BootstrapUnavailable',officialResolved:null});if(slot===0&&!report.smokeGate){for(const m of selection.selected.slice(1))report.results.push({instanceId:m.instanceId,repo:m.repo,terminal:'NotRunBootstrapGate',officialResolved:null});save();break;}
 }
 save();return report;
}
// Immutable ablation receipts; this reuses the existing pure child and official grader.
export async function runStage(stage,{python,output,cacheOutput,variant,verificationMode='research',baselinePath=join(here,'results/swe-js8-A-baseline.json')}){
 const names={B:'protocol',C:'retrieval',D:'j4',E:'patchsets',F:'jev-max'};
 if(!names[stage])throw Error('Unknown stage');
 const id=`swe-js8-${stage}-${variant??names[stage]}`,receiptPath=join(here,'results',id+'.json');
 if(existsSync(receiptPath))throw Error('Immutable stage receipt already exists: '+id);
 const baseline=JSON.parse(readFileSync(baselinePath,'utf8')),kernel=compileKernel(),started=Date.now();
 const sourceHash=sha256(['state','actions','transforms','policy','tasks','controller','retrieval'].map(n=>readFileSync(join(kernel,'jev-agent',n+'.js'))).join(''));
 output=resolve(output);mkdirSync(output,{recursive:true});
 writeFileSync(join(output,'source-snapshot.json'),JSON.stringify(Object.fromEntries(['state','actions','transforms','policy','tasks','controller','retrieval'].map(n=>[n,readFileSync(join(kernel,'jev-agent',n+'.js'),'utf8')])),null,2),{flag:'wx'});
 if(stage!=='B'&&!existsSync(join(here,'results',`swe-js8-${String.fromCharCode(stage.charCodeAt(0)-1)}-${names[String.fromCharCode(stage.charCodeAt(0)-1)]}.json`)))throw Error('Previous stage must be frozen');
 const sourceHashes=Object.fromEntries(['jev-agent/state.ts','jev-agent/actions.ts','jev-agent/transforms.ts','jev-agent/policy.ts','jev-agent/tasks.ts','jev-agent/controller.ts','jev-agent/retrieval.ts','semantic-policy.ts','semantic-state.ts','semantic-controller.ts','jev-playground/solve-child.mjs','jev-playground/isolation.mjs','jev-playground/test-boundary.mjs','jev-playground/runtime.mjs','jev-playground/swe-mini.mjs','jev-playground/swe-verifier.mjs'].map(p=>[p,sha256(readFileSync(join(here,'..',p)))]));
 const report={id,stage,sourceHashes,taskSelectionHash:baseline.selectionHash,selected:baseline.selected,budgets:stage==='F'?{...budgets,maxEvaluations:variant?.includes('facts')?128:96,maxSteps:48,maxTests:3}:budgets,patchDepth:stage>='E'?2:1,boundedExploration:variant?.includes('exploration')===true,policyBreadth:stage==='F'?'Jev eight plus deterministic top-eight anchors':'Jev eight',solverSourceHash:sourceHash,retrievalImplementationHash:sha256(readFileSync(join(kernel,'jev-agent/retrieval.js'))),grammar:stage<'D'?'J3':'J4',verificationMode,startedAt:new Date().toISOString(),results:[]};
 // Reuse authoritative baseline empty-patch results. Gold metadata is outer-only.
 const cached=baseline.officialVerificationReceipts.filter(c=>!c.infrastructureFailure&&c.patchHash===sha256(''));
 try{
  for(const selected of baseline.selected){
   const previous=baseline.results.find(r=>r.instanceId===selected.instanceId);
   if(!previous?.agent){report.results.push({instanceId:selected.instanceId,terminal:'BootstrapUnavailable',failureStage:'InfrastructureFailure',agent:null});continue;}
   const task={instanceId:selected.instanceId,repo:selected.repo,baseCommit:selected.baseCommit,taskDir:selected.taskDir,problemStatement:readFileSync(join(selected.taskDir,'problem_statement.md'),'utf8')};
   const checkout=await materialize(task),workspace=checkout.workspace,calls=[];
   let canonical;const bootstrap={imageReused:null,imageId:null,pullMs:0,inspectionMs:0};
   const verifier={verificationScope:'canonical',timeoutSeconds:600,verify:async root=>{
    const patch=(await exec('git',['diff','--binary','HEAD'],{cwd:root,maxBuffer:8*1024*1024})).stdout;
    const hit=[...calls,...cached].find(c=>!c.infrastructureFailure&&c.instanceId===task.instanceId&&c.patchHash===sha256(patch));
    if(hit){const c={...hit,cached:true,wallMs:0,sourceReceipt:hit.sourceReceipt??(cached.includes(hit)?'swe-js8-A-baseline':'current-stage')};calls.push(c);return c;}
    if(!canonical){const begin=Date.now();let image;
     try{image=JSON.parse((await exec('docker',['image','inspect',selected.image])).stdout)[0];bootstrap.imageReused=true;}catch{const pull=Date.now();await exec('docker',['pull','--platform','linux/amd64',selected.image],{timeout:180000,maxBuffer:1024*1024});bootstrap.pullMs=Date.now()-pull;bootstrap.imageReused=false;image=JSON.parse((await exec('docker',['image','inspect',selected.image])).stdout)[0];}
     bootstrap.inspectionMs=Date.now()-begin-bootstrap.pullMs;bootstrap.imageId=image.Id;
     canonical=sweVerifier({instanceId:task.instanceId,taskDir:task.taskDir,python,output:join(output,'canonical'),timeoutSeconds:600,graderIdentity:sha256(JSON.stringify({officialHarnessVersion:baseline.officialHarnessVersion,taskRepoCommit:baseline.taskRepoCommit,imageId:image.Id,runtime:'QEMU-v10.0.4-56/muvm-4KiB'}))});
    }
    const c=await canonical.evaluatePatch(patch);calls.push(c);return c;
   }};
   try{
    const cheapCalls=[];
    const solverVerifier=verificationMode==='benchmark-faithful'?{verificationScope:'cheap',timeoutSeconds:30,verify:async root=>{
     const began=Date.now();const dirty=(await exec('git',['diff','--name-only','HEAD'],{cwd:root})).stdout.trim().split('\n').filter(Boolean);let passed=dirty.length>0;const failures=[];
     for(const file of dirty){const before=(await exec('git',['show','HEAD:'+file],{cwd:root,maxBuffer:1024*1024})).stdout,after=readFileSync(join(root,file),'utf8');
      const code=`import{cheapLegality}from${JSON.stringify(join(kernel,'jev-agent/transforms.js'))};console.log(cheapLegality(${JSON.stringify(join(root,file))},${JSON.stringify(before)},${JSON.stringify(after)}));`;
      if((await exec(process.execPath,['--input-type=module','-e',code],{timeout:30000,maxBuffer:8192})).stdout.trim()!=='true'){passed=false;failures.push(file+': cheap syntax/diagnostic gate failed');}
     }const result={passed,failures,fingerprint:sha256((await exec('git',['diff','--binary','HEAD'],{cwd:root,maxBuffer:8*1024*1024})).stdout+JSON.stringify({passed,failures})),wallMs:Date.now()-began};cheapCalls.push(result);return result;
    }}:verifier;
    const result=await solve(task,workspace,solverVerifier,{kernelSnapshot:kernel,protocolTaskKind:'Repair',grammar:report.grammar,...(stage!=='B'?{retrieval:'conventional',...(stage>='E'?{patchDepth:2}:{}),...(stage==='F'?{verificationAware:true,boundedExploration:variant?.includes('exploration')===true,budgets:{...budgets,maxEvaluations:variant?.includes('facts')?128:96,maxSteps:48,maxTests:3}}:{})}:{})});
    const patch=(await exec('git',['diff','--binary','HEAD'],{cwd:workspace,maxBuffer:8*1024*1024})).stdout;
    if(verificationMode==='benchmark-faithful')await verifier.verify(workspace);
    const analysis=stage>='D'?await analyzeGold(task,workspace,result,report.grammar):{...previous.analysis,...analyzeRun(result,previous.analysis.goldFiles)};
    const retrieval=result.receipt.retrieval,goldFiles=previous.analysis.goldFiles;
    if(retrieval){
     analysis.goldFileGenerated=goldFiles.some(p=>retrieval.generated.some(f=>f.path===p));
     analysis.goldFileRetained=goldFiles.some(p=>retrieval.compressed.includes(p));
     analysis.goldFileSurvivedRanking=goldFiles.some(p=>retrieval.ranked.includes(p));
     analysis.goldFileFirstCompression=goldFiles.some(p=>(retrieval.rankStages[0]?.paths??retrieval.compressed).includes(p));
     if(result.receipt.kind==='NeedsGeneration')analysis.failureStage=!analysis.goldFileGenerated?'CandidateSourceFailure':!analysis.goldFileRetained?'CandidateCompressionFailure':!analysis.goldFileInspected?'JevLocalizationFailure':'EditEnumerationFailure';
    }
    const row={instanceId:task.instanceId,checkoutMs:checkout.checkoutMs,terminal:result.receipt.kind,hostTaskKind:'Repair',shadow:result.receipt.shadowClassification,enteredRepair:result.receipt.taskKind==='Repair',initialCheckReproduced:verificationMode==='benchmark-faithful'?cached.some(c=>c.instanceId===task.instanceId&&c.officialResolved===false):result.events.some(e=>e.kind==='verify'&&!e.result.passed),initialCheckVisibility:verificationMode==='benchmark-faithful'?'outer-only':'solver',analysis,rawPureRun:result,canonicalCalls:calls,cheapCalls,bootstrap,finalPatch:patch,officialResolved:calls.findLast(c=>c.patchHash===sha256(patch))?.officialResolved??null};
    report.results.push(row);writeFileSync(join(output,task.instanceId+'.json'),JSON.stringify(row,null,2)+'\n',{flag:'wx'});
   }finally{rmSync(workspace,{recursive:true,force:true});}
  }
  report.wallMs=Date.now()-started;report.completedAt=new Date().toISOString();report.immutable=true;
  report.funnel={selected:8,runnable:report.results.filter(r=>r.agent!==null).length,enteredRepair:report.results.filter(r=>r.enteredRepair).length,goldFileRetained:report.results.filter(r=>r.analysis?.goldFileRetained).length,goldFileInspected:report.results.filter(r=>r.analysis?.goldFileInspected).length,mutations:report.results.reduce((n,r)=>n+(r.rawPureRun?.receipt.metrics.mutations??0),0),officialResolved:report.results.filter(r=>r.officialResolved===true).length};
  writeFileSync(receiptPath,JSON.stringify(report,null,2)+'\n',{flag:'wx'});return report;
 }finally{rmSync(kernel,{recursive:true,force:true});}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const [command,...args]=process.argv.slice(2),get=(flag,defaultValue)=>args.includes(flag)?args[args.indexOf(flag)+1]:defaultValue;
 const taskRepo=resolve(get('--task-repo','.tmp/swe-mini/task-repo')),python=resolve(get('--python','.tmp/swe-mini/venv/bin/python')),output=resolve(get('--output',join(here,'results')));
 if(command==='stage'){console.log(JSON.stringify((await runStage(get('--stage','B'),{python,output,variant:get('--variant'),verificationMode:get('--verification-mode','research'),cacheOutput:get('--cache-output','.tmp/swe-mini/nix-local-clean/private-evaluation')})).funnel));}
 else if(command==='select'){mkdirSync(output,{recursive:true});const selection=await selectTasks(taskRepo,python);writeFileSync(join(output,'swe-js8.selection.json'),JSON.stringify(selection,null,2)+'\n');console.log(selection.selected.map(t=>t.instanceId).join('\n'));}
 else if(command==='run'){const selection=JSON.parse(readFileSync(get('--selection',existsSync(join(output,'swe-js8.selection.json'))?join(output,'swe-js8.selection.json'):join(here,'results/swe-js8.json')),'utf8'));for(const row of [...selection.selected,...selection.allJsMetadata])row.taskDir=join(taskRepo,'tasks',row.instanceId);console.log(JSON.stringify((await runSlice(selection,{python,output,releaseImages:args.includes('--release-images'),verificationTimeoutSeconds:Number(get('--verification-timeout-seconds','300'))})).results,null,2));}
 else throw Error('Use select or run [--task-repo DIR --python VENV/bin/python --output DIR --selection FILE]');
}
