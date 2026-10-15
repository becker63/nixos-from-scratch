import assert from 'node:assert/strict';
import {checkedProgram,dependencyModules} from '../semantic-check.mjs';
import {createRequire} from 'node:module';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,symlinkSync,existsSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir,homedir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
const root=dirname(dirname(fileURLToPath(import.meta.url)));const require=createRequire(import.meta.url),ts=require('typescript');
const files=['semantic-state','semantic-policy','semantic-controller','semantic-extension',...['state','actions','transforms','policy','tasks','controller','retrieval'].map(n=>'jev-agent/'+n)];
const options={strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext,moduleResolution:ts.ModuleResolutionKind.Bundler,skipLibCheck:true,types:['node'],typeRoots:[join(root,'node_modules/@types')]};
const diagnostics=ts.getPreEmitDiagnostics(checkedProgram(ts,files.map(n=>join(root,n+'.ts')),options));
assert.equal(diagnostics.length,0,ts.formatDiagnosticsWithColorAndContext(diagnostics,{getCanonicalFileName:f=>f,getCurrentDirectory:()=>root,getNewLine:()=> '\n'}));
const directory=mkdtempSync(join(tmpdir(),'jev-grammar-tests-'));mkdirSync(join(directory,'jev-agent'));writeFileSync(join(directory,'package.json'),'{"type":"module"}');symlinkSync(dependencyModules,join(directory,'node_modules'));
const fixtures=[
 {id:'A',grammar:'J2',source:'export function valid(index:number,items:number[]):boolean { return index <= items.length; }\n',checks:'assert.equal(valid(2,[1,2]),false); assert.equal(valid(1,[1,2]),true);',imports:'valid',family:'ReplaceOperator'},
 {id:'B',grammar:'J2',source:'export function sliceEnd(start:number,end:number):number { return start; }\n',checks:'assert.equal(sliceEnd(2,8),8); assert.equal(sliceEnd(4,12),12);',imports:'sliceEnd',family:'ReplaceVariable'},
 {id:'C',grammar:'J3',source:'function add(a:number,b:number):number { return a+b; }\nfunction subtract(a:number,b:number):number { return a-b; }\nexport function compute(a:number,b:number):number { return subtract(a,b); }\n',checks:'assert.equal(compute(2,3),5); assert.equal(compute(7,4),11);',imports:'compute',family:'ReplaceCallable'},
 {id:'D',grammar:'J2',source:'function range(start:number,end:number):number { return end-start; }\nexport function length(start:number,end:number):number { return range(start); }\n',checks:'assert.equal(length(2,8),6); assert.equal(length(3,10),7);',imports:'length',family:'InsertArgument'},
 {id:'E',grammar:'J3',source:'export function checksum(text:string):number { return 0; }\n',checks:'assert.equal(checksum("ABC"),198); assert.equal(checksum("Z"),90);',imports:'checksum',family:'none'},
];
function writeFixture(fixture,path){mkdirSync(path);writeFileSync(join(path,'subject.ts'),fixture.source);writeFileSync(join(path,'subject.test.mjs'),`import {test} from 'node:test'; import assert from 'node:assert/strict'; import {${fixture.imports}} from './subject.ts'; test('required behavior',()=>{${fixture.checks}});\n`);writeFileSync(join(path,'distractor.ts'),'export function identity(value:string):string { return value; }\n');}
const mock=async request=>{
 const answers={};const frame=request.state;
 for(const [key,q] of Object.entries(request.questions)) {
  if(q.type==='noul')answers[key]={type:'noul',noul:key==='goalSatisfied'?(frame.verification.passed?.99:.01):key==='unknownActionRequired'?(frame.candidates.length===1?.99:.01):key==='likelyProgress'?.99:.01};
  else if(q.type==='choice') {
   const candidates=Object.entries(q.criteria);const desired=key==='taskKind'?candidates.find(([id])=>id==='Repair'):key==='relation'?candidates.find(([id])=>id==='File'):candidates.find(([id,facts])=>/Exact current checks passed|Replace numeric binary operator <= with <|value end instead of start|helper add instead of subtract|argument end at position 1/.test(facts))??candidates.find(([id,facts])=>/subject\.ts|export function/.test(facts))??candidates.find(([id])=>id!=='unknown'&&id!=='ANeedsGeneration')??candidates.find(([id])=>id==='ANeedsGeneration');
   const choice=desired[0];answers[key]={type:'choice',choice,confidence:1,probabilities:Object.fromEntries(candidates.map(([id])=>[id,id===choice?1:0]))};
  }
 }
 return {model:'mock',answers,usage:{input_tokens:1,output_tokens:1}};
};
try {
 for(const name of files)writeFileSync(join(directory,name+'.js'),ts.transpileModule(readFileSync(join(root,name+'.ts'),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText);
 const {runJevAgent}=await import(join(directory,'jev-agent/controller.js'));
 const {ModelRuntime}=await import(join(dependencyModules,'@earendil-works/pi-coding-agent/dist/index.js'));
 // All public Pi generation entry points must refuse before any provider dispatch.
 const runtime=await ModelRuntime.create();const model=runtime.getModel('openai-codex','gpt-6.1-sol');assert(model);
 process.env.PI_AGENT_MODE='jev';for(const method of ['stream','streamSimple','streamDeferred'])assert.throws(()=>runtime[method](model,method==='streamDeferred'?'fake':{messages:[]}),/forbidden/);delete process.env.PI_AGENT_MODE;
 if(!process.argv.includes('--only-live')) {
  const {default:extension}=await import(join(directory,'semantic-extension.js'));
  const handlers=new Map(),commands=new Map(),flags=new Map(),entries=[];let active=['fabric_exec'];let aborted=false;
  const api={registerFlag:(name,options)=>flags.set(name,options.default),getFlag:name=>flags.get(name),on:(name,handler)=>handlers.set(name,handler),events:{on:()=>()=>{},emit:()=>{}},registerCommand:(name,command)=>commands.set(name,command),getActiveTools:()=>active.slice(),setActiveTools:tools=>{active=tools;},appendEntry:(type,data)=>entries.push({type,data}),sendMessage:()=>{}};
  extension(api);flags.set('jev-policy','heuristic');
  const workspace=join(directory,'slash-mode');writeFixture(fixtures[0],workspace);
  const ctx={cwd:workspace,mode:'json',ui:{notify:()=>{}},isIdle:()=>true,abort:()=>{aborted=true;}};
  await commands.get('mode').handler('jev',ctx);assert.equal(process.env.PI_AGENT_MODE,'jev');assert.deepEqual(active,[]);
  const handled=await handlers.get('input')({text:'Fix the bug and verify the change.',source:'interactive'},ctx);
  assert.equal(handled.action,'handled');const result=entries.findLast(e=>e.type==='jev-agent-result').data;assert.equal(result.kind,'Success');assert.equal(result.metrics.codexCalls,0);assert.equal(result.metrics.workerCalls,0);
  assert.equal((await handlers.get('tool_call')({toolName:'agents.run'},ctx)).block,true);
  handlers.get('before_agent_start')({},ctx);assert(aborted);
  // Even client initialization failure must consume input instead of falling through.
  flags.set('jev-policy','jev');const outage=await handlers.get('input')({text:'Fix it',source:'interactive'},ctx);assert.equal(outage.action,'handled');assert.equal(entries.findLast(e=>e.type==='jev-agent-result').data.kind,'ProviderFailure');
  await commands.get('mode').handler('hybrid',ctx);assert.equal(process.env.PI_AGENT_MODE,undefined);assert.deepEqual(active,['fabric_exec']);
 }
 const receipts=[];
 if(!process.argv.includes('--only-live'))for(const fixture of fixtures) {
  const path=join(directory,fixture.id);writeFixture(fixture,path);
  const result=await runJevAgent({root:path,task:'Fix the bug and verify the change.',grammar:fixture.grammar,evaluate:mock,budgets:{maxWallMs:120000}});
  assert.equal(result.kind,fixture.id==='E'?'NeedsGeneration':'Success',JSON.stringify({fixture:fixture.id,result}));assert.equal(result.metrics.codexCalls,0);assert.equal(result.metrics.workerCalls,0);assert(result.metrics.jevEvaluations>0);assert(result.evidenceCollected>0);
  if(fixture.id!=='E'){assert(result.verification.passed);assert(result.metrics.actionFamilies[fixture.family]>0);}
  receipts.push({fixture:fixture.id,grammar:fixture.grammar,result:result.kind,steps:result.metrics.steps,legal:result.metrics.candidatesAfter});
 }
 // No transforms at J0, no fallback, and provider outages are terminal.
 if(!process.argv.includes('--only-live')) {
 const j0=join(directory,'J0');writeFixture(fixtures[0],j0);const boundary=await runJevAgent({root:j0,task:'Fix the bug',grammar:'J0',evaluate:mock});assert.equal(boundary.kind,'NeedsGeneration');assert.equal(boundary.metrics.mutations,0);
 const failed=join(directory,'failure');writeFixture(fixtures[0],failed);const unavailable=await runJevAgent({root:failed,task:'Fix the bug',evaluate:async()=>{throw new Error('offline');}});assert.equal(unavailable.kind,'ProviderFailure');assert.equal(unavailable.metrics.codexCalls,0);assert.equal(unavailable.metrics.workerCalls,0);
 const exhausted=await runJevAgent({root:failed,task:'Fix the bug',evaluate:mock,budgets:{maxSteps:0}});assert.equal(exhausted.kind,'Exhausted');
 // Canonical host seam: both scopes in one check, never execute local Node tests.
 writeFileSync(join(failed,'adjacent.test.mjs'),"throw Error('Canonical verification must not run this file');");
 let canonicalCalls=0;
 const canonical=await runJevAgent({root:failed,task:'Fix the bug',evaluate:mock,exactVerifier:{verificationScope:'canonical',verify:async workspace=>{canonicalCalls++;const passed=readFileSync(join(workspace,'subject.ts'),'utf8').includes('index < items.length');return {passed,failures:passed?[]:['required behavior: FAILED'],fingerprint:String(canonicalCalls)};}}});
 assert.equal(canonical.kind,'Success');assert.equal(canonicalCalls,2,'Reproduction + mutation; no duplicate broad canonical check');
 // Protocol routing must preserve the live shadow classifier and interactive behavior.
 const inspectPrediction=async request=>{const response=await mock(request);if(response.answers.taskKind)response.answers.taskKind={type:'choice',choice:'Inspect',confidence:1,probabilities:{Locate:0,Inspect:1,Repair:0,Verify:0,Unsupported:0}};return response;};
 let routedChecks=0;const routingVerifier={verificationScope:'canonical',verify:async()=>{routedChecks++;return {passed:false,failures:['behavior: FAILED'],fingerprint:'routing'};}};
 const interactive=await runJevAgent({root:failed,task:'Find the existing file',evaluate:inspectPrediction,exactVerifier:routingVerifier});
 assert.equal(interactive.taskKind,'Inspect');assert.equal(routedChecks,0);
 const routed=await runJevAgent({root:failed,task:'Original issue',protocolTaskKind:'Repair',evaluate:inspectPrediction,exactVerifier:routingVerifier,budgets:{maxSteps:1}});
 assert.equal(routed.taskKind,'Repair');assert.equal(routed.shadowClassification.kind,'Inspect');assert.equal(routedChecks,1);
 const {ExactVerificationUnavailable}=await import(join(directory,'jev-agent/state.js'));
 const infra=await runJevAgent({root:failed,task:'Fix the bug',evaluate:mock,exactVerifier:{verificationScope:'canonical',verify:async()=>{throw new ExactVerificationUnavailable();}}});
 assert.equal(infra.kind,'BenchmarkBootstrapFailure');assert.equal(infra.metrics.mutations,0);
 assert.equal(infra.metrics.codexCalls,0);assert.equal(infra.metrics.workerCalls,0);

 // Cheap evidence can submit a patch, but cannot return exact Success.
 const faithfulRoot=join(directory,'faithful');writeFixture(fixtures[0],faithfulRoot);let cheapCount=0;
 const submitted=await runJevAgent({root:faithfulRoot,task:'Fix the bug',evaluate:mock,exactVerifier:{verificationScope:'cheap',verify:async()=>{cheapCount++;const passed=readFileSync(join(faithfulRoot,'subject.ts'),'utf8').includes('index < items.length');return {passed,failures:[],fingerprint:String(cheapCount)};}}});
 assert.equal(submitted.kind,'Submitted');assert.equal(submitted.verification.scope,'cheap');assert.equal(cheapCount,2);assert(readFileSync(join(faithfulRoot,'subject.ts'),'utf8').includes('index < items.length'));assert.equal(submitted.metrics.codexCalls,0);
 // J4 families must come from finite typed donors and retain provenance.
 const {generateEdits,symbols,analyze,nonWorsening}=await import(join(directory,'jev-agent/transforms.js'));
 const j4root=join(directory,'J4');mkdirSync(j4root);const j4path=join(j4root,'source.ts');
 const j4source='export function literal():number { const zero=0; return 1; }\nexport function boolean(a:boolean,b:boolean):boolean { if(a&&b)return a; return a||b; }\nexport function member(o:{first:number;second:number}):number { return o.first; }\nfunction helper(a:number,b:number,c?:number):number { return a+b; }\nexport function argumentsFn(x:number,y:number):number { return helper(x,y,x); }\n';writeFileSync(j4path,j4source);
 const namedExpressions='const adapter = function namedAdapter(){return [1].map(function nestedCallback(value:number){return value;});};';assert(symbols({id:'FX',path:'callbacks.ts',family:'GX',bytes:namedExpressions.length},'callbacks.ts',namedExpressions,true).some(s=>s.name==='nestedCallback'));
 const manyFunctions=Array.from({length:120},(_,i)=>'function f'+i+'(){return '+i+';}').join('\n');assert.equal(symbols({id:'FY',path:'many.ts',family:'GY',bytes:manyFunctions.length},'many.ts',manyFunctions,true).length,120);
 const target={id:'FJ4',path:'source.ts',family:'GJ4',bytes:j4source.length};const j4edits=symbols(target,j4path,j4source).flatMap(symbol=>generateEdits(target,j4path,j4source,'J4',symbol).edits);
 for(const family of ['ReplaceLiteral','NegateExpression','ReplaceMember','ReplaceArgument','RemoveArgument','PermuteArguments','ReplaceReturn','ReplaceCondition'])assert(j4edits.some(e=>e.family===family),family);
 assert(j4edits.every(e=>e.typeValid&&e.provenance&&j4source.slice(e.start,e.end)===e.from));
 assert(j4edits.some(e=>e.family==='ReplaceOperator'&&e.from==='&&'&&e.to==='||'));
 // Real transaction mechanics: two files, deferred verification, exact rollback.
 const {RepositoryWorld}=await import(join(directory,'jev-agent/actions.js'));const patchRoot=join(directory,'patch');mkdirSync(patchRoot);
 const patchSource='export function valid(index:number,limit:number):boolean { return index <= limit; }\n';
 for(const name of ['a.ts','b.ts'])writeFileSync(join(patchRoot,name),patchSource);
 let patchChecks=0;const patchWorld=new RepositoryWorld(patchRoot,'J4',{verificationScope:'canonical',verify:async()=>{patchChecks++;return {passed:true,failures:[],fingerprint:'exact'};}},{patchDepth:2,boundedExploration:true});
 const applyFinite=path=>{const file=patchWorld.files.find(f=>f.path===path);patchWorld.inspect(file.id);patchWorld.prepare(patchWorld.symbols[0].id);const edit=patchWorld.edits.find(e=>e.family==='ReplaceOperator'&&e.from==='<='&&e.to==='<');assert(edit);if(!patchWorld.patch.length)assert(patchWorld.legal('Transform').some(a=>a.kind==='Relocalize'));return patchWorld.execute({id:'A'+edit.id,kind:'ApplyEdit',edit:edit.id});};
 assert.equal(applyFinite('a.ts'),'Compose');assert(!patchWorld.legal('Transform').some(a=>a.kind==='Relocalize'));assert.equal(patchChecks,0);assert(patchWorld.legal('Compose').some(a=>a.kind==='ContinuePatch'));const baseRevision=patchWorld.patchState.baseRevision;
 assert.equal(applyFinite('b.ts'),'Verify');assert.equal(patchWorld.patchState.edits.length,2);assert.equal(patchWorld.patchState.changedFiles.length,2);assert.equal(patchChecks,0);assert.throws(()=>patchWorld.apply(patchWorld.edits[0].id),/depth/);
 patchWorld.execute({id:'RollbackLast',kind:'RollbackLast'});assert.equal(patchWorld.patchState.baseRevision,baseRevision);assert.equal(readFileSync(join(patchRoot,'b.ts'),'utf8'),patchSource);
 patchWorld.execute({id:'RollbackPatch',kind:'RollbackPatch'});assert.equal(patchWorld.patch.length,0);assert.equal(readFileSync(join(patchRoot,'a.ts'),'utf8'),patchSource);
 patchWorld.rejected.clear();applyFinite('a.ts');const applied=readFileSync(join(patchRoot,'a.ts'),'utf8');writeFileSync(join(patchRoot,'a.ts'),applied+'// external change\n');assert.throws(()=>patchWorld.rollbackPatch(),/External mutation/);writeFileSync(join(patchRoot,'a.ts'),applied);patchWorld.rollbackPatch();
 const baseDiagnostics=analyze(j4path,j4source).diagnostics;assert(!nonWorsening(baseDiagnostics,analyze(j4path,j4source+'missingIdentifier();').diagnostics));
 console.log(JSON.stringify({j4Families:[...new Set(j4edits.map(e=>e.family))],deterministicFixtures:receipts,generationGuard:'three stream entry points denied',J0:'NeedsGeneration',providerFailure:'closed',budget:'bounded'}));
 }
 if(process.argv.includes('--live')) {
  const config=JSON.parse(readFileSync(join(homedir(),'.pi/agent/fabric.json'),'utf8'));
  const policies=process.argv.find(a=>a.startsWith('--policies='))?.split('=')[1].split(',')??['jev','random','heuristic'];
  const resultPath=process.env.PI_JEV_RESULTS??(root.startsWith('/nix/store/')?join(homedir(),'.local/state/pi/experiments/jev-fixture-results.json'):join(root,'jev-fixture-results.json'));
  mkdirSync(dirname(resultPath),{recursive:true});
  const selectedFixtures=process.argv.find(a=>a.startsWith('--fixtures='))?.split('=')[1].split(',')??fixtures.map(f=>f.id);
  const results=existsSync(resultPath)?JSON.parse(readFileSync(resultPath,'utf8')).filter(row=>!(policies.includes(row.policy)&&selectedFixtures.includes(row.fixture))):[];
  for(const policy of policies)for(const fixture of fixtures.filter(f=>selectedFixtures.includes(f.id))) {
   const path=join(directory,`live-${policy}-${fixture.id}`);writeFixture(fixture,path);const agent=join(path,'agent');mkdirSync(agent);
   writeFileSync(join(agent,'fabric.json'),JSON.stringify(config));
   writeFileSync(join(agent,'settings.json'),JSON.stringify({packages:[join(root,'node_modules/pi-fabric')],extensions:[join(root,'semantic-extension.ts')],skills:[],defaultProvider:'openai-codex',defaultModel:'gpt-6.1-sol',defaultThinkingLevel:'medium'}));
   const args=[join(root,'node_modules/@earendil-works/pi-coding-agent/dist/cli.js'),'--agent-mode','jev','--jev-grammar',fixture.grammar,'--jev-policy',policy,'--jev-receipt','--no-session','-p','Fix the bug and verify the change.'];
   const record=await new Promise((resolve,reject)=>{const child=spawn(process.execPath,args,{cwd:path,env:{...process.env,PI_CODING_AGENT_DIR:agent,PI_AGENT_MODE:'jev'},stdio:['ignore','pipe','pipe']});let output='',error='';const timer=setTimeout(()=>child.kill('SIGTERM'),150000);child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>{error+=b;if(error.length>8192)error=error.slice(-8192);});child.on('error',reject);child.on('exit',code=>{clearTimeout(timer);const line=(output+'\n'+error).split('\n').map(l=>l.replace(/^.*?(?=\{"kind":)/,'' )).findLast(l=>l.startsWith('{"kind":'));if(!line)return reject(new Error(`CLI did not return a terminal state (${code}); ${error.slice(-256)}`));resolve(JSON.parse(line));});});
   assert.equal(record.metrics?.codexCalls??record.codexCalls,0);assert.equal(record.metrics?.workerCalls??record.workerCalls,0);
   const row={fixture:fixture.id,grammar:fixture.grammar,policy,result:record.kind,reason:record.missingCapability,metrics:record.metrics,choiceDistributions:record.distributions?.map(vector=>({bestAction:vector.bestAction,goalSatisfied:vector.goalSatisfied,unknownActionRequired:vector.unknownActionRequired}))};results.push(row);console.log(JSON.stringify({live:row}));
  }
  writeFileSync(resultPath,JSON.stringify(results,null,2)+'\n');
  for(const row of results.filter(row=>row.policy==='jev')){assert.equal(row.result,row.fixture==='E'?'NeedsGeneration':'Success',JSON.stringify(row));assert(row.metrics.jevInputTokens>0,'No real Jev dispatch');}
 }
} finally {rmSync(directory,{recursive:true,force:true});}
