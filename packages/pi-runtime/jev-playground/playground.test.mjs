import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,chmodSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {synthetic,generate,mutatedSource} from './generate.mjs';
import {rejectLeakage,assertFrozen,workspaceHash} from './freeze.mjs';
import {run} from './run.mjs';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {classifierTransport} from './isolation.mjs';
import {score} from './score.mjs';
const directory=mkdtempSync(join(tmpdir(),'jev-playground-test-'));
try{
 const audit={classifierRequests:0,deniedRequests:0};let dispatches=0;
 const transport=classifierTransport('https://classifier.invalid','jev',async()=>{dispatches++;return {};},audit);
 for(const body of [{model:'codex',messages:[]},{model:'jev',questions:{x:{type:'generate'}}},{model:'jev',questions:{},workers:[]}])await assert.rejects(()=>transport('https://classifier.invalid',{method:'POST',body:JSON.stringify(body)}),/forbidden/);
 await assert.rejects(()=>transport('https://chat.invalid',{method:'POST',body:JSON.stringify({model:'jev',questions:{}})}),/forbidden/);
 assert.equal(dispatches,0);assert.equal(audit.deniedRequests,4);
 await transport('https://classifier.invalid',{method:'POST',body:JSON.stringify({model:'jev',state:{},questions:{x:{type:'noul'}}})});assert.equal(dispatches,1);
 const guarded=join(directory,'guarded');mkdirSync(guarded);const secret=join(directory,'private-value');writeFileSync(secret,'hidden value');
 writeFileSync(join(guarded,'guard.test.mjs'),`import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {execFileSync} from 'node:child_process';test('capabilities',()=>{assert.throws(()=>readFileSync(${JSON.stringify(secret)}),/denied|Access/i);assert.throws(()=>fetch('https://example.invalid'),/cannot/);assert.throws(()=>execFileSync(process.execPath,['-e','process.exit(0)']),/denied|Access/i);});`);
 await promisify(execFile)(process.execPath,['--test',join(guarded,'guard.test.mjs')],{cwd:guarded});
 const oracle={leakIdentifiers:['E123456789abc','private-answer-id']};
 for(const [name,text,task]of [
  ['solution.json','{}','Fix the behavior'],['correct-fix.txt','x','Fix the behavior'],
  ['subject.ts','// TODO use minus here\n','Fix the behavior'],
  ['subject.test.mjs',`test("should subtract margin",()=>{});`,'Fix the behavior'],
  ['metadata.json','{"note":"private-answer-id"}','Fix the behavior'],
  ['subject.ts','// E123456789abc\n','Fix the behavior'],
  ['generate.mjs','export const x=1;','Fix the behavior'],
  ['subject.ts','export const x=1;','Use private-answer-id'],
 ]){
  const root=join(directory,'leak-'+Math.random());mkdirSync(root);writeFileSync(join(root,name),text);
  assert.throws(()=>rejectLeakage(root,task,oracle),/leakage/);
 }
 const instance=join(directory,'finite');const spec=await generate(instance,synthetic({branching:4}),{id:'finite'});
 const hidden=JSON.parse(readFileSync(join(instance,'private/oracle.json'),'utf8'));
 assert(hidden.successfulEdits.length>0);assert.equal(hidden.targetLegalCount,4);
 assert(hidden.admission.some(e=>e.local&&!e.broad),'Broad trap must be real');
 await assert.rejects(()=>generate(instance,synthetic()),/already exists/);
 assertFrozen(join(instance,'workspace'),spec);const originalHash=workspaceHash(join(instance,'workspace'));
 const execution=await run(instance,'random');const repeat=await run(instance,'random');assert.notEqual(execution.output,repeat.output);assert(readFileSync(join(execution.output,'receipt.json'),'utf8'));const result=await score(instance,execution);
 assert(execution.record.events.filter(e=>e.kind==='verify').every(e=>e.result.passed===(e.result.exitStatus===0)),'Verification snapshots must survive terminal cleanup');
 assert.equal(result.isolation.codexCalls,0);assert.equal(result.isolation.workerCalls,0);assert.equal(result.isolation.oracleSupplied,false);
 assert.equal(result.isolation.generativeRuntimeLoaded,false);assert.equal(result.isolation.jevRequests,0);assert.equal(result.metrics.jevEvaluations,0);
 assert.equal(originalHash,workspaceHash(join(instance,'workspace')));
 const changedTest=join(execution.output,'workspace/subject.test.mjs');writeFileSync(changedTest,readFileSync(changedTest,'utf8')+'\n// changed');const tampered=await score(instance,execution);assert.equal(tampered.legalFinalArtifact,false);assert.equal(tampered.failure,'VerificationFailure');
 assert(!JSON.stringify(execution.record.events.filter(e=>e.kind==='evaluation')).includes('successfulEdits'));
 const file=join(instance,'workspace/subject.ts');chmodSync(file,0o644);writeFileSync(file,'changed');assert.throws(()=>assertFrozen(join(instance,'workspace'),spec),/changed/);
 const cleanup=join(directory,'cleanup');await generate(cleanup,synthetic({branching:1,files:1}),{id:'cleanup',budgets:{maxSteps:4}});const cleanupRun=await run(cleanup,'heuristic');assert.equal(cleanupRun.record.receipt.kind,'Exhausted');assert.equal(cleanupRun.record.receipt.metrics.reverts,1);assert(cleanupRun.record.events.filter(e=>e.kind==='verify'&&e.result.exitStatus===0).every(e=>e.result.passed),'Green snapshots must remain green after rollback');
 const boundary=join(directory,'boundary');const boundarySpec=await generate(boundary,synthetic({boundary:true}),{id:'boundary'});
 assert.equal(JSON.parse(readFileSync(join(boundary,'private/oracle.json'),'utf8')).successfulEdits.length,0);
 const boundaryRun=await run(boundary,'heuristic');const boundaryScore=await score(boundary,boundaryRun);assert.equal(boundaryScore.failure,'CorrectNeedsGeneration');
 const proposal=mutatedSource({files:synthetic({family:'operator'}).files,targetFile:'subject.ts',targetSymbol:'compute',from:'end + start',to:'end * start',task:'Repair and verify the regression.'});
 assert(proposal.files['subject.ts'].includes('end * start'));assert.throws(()=>mutatedSource({...proposal,from:'absent',to:'x'}),/unique/);
 await assert.rejects(()=>generate(join(directory,'junk'),{...synthetic({boundary:true}),expected:'Success'}),/No successful/);
 console.log(JSON.stringify({leakageCases:8,admission:'generic exhaustive single-edit',freezeTamper:'denied',freshProcess:'baseline zero provider calls',boundary:boundarySpec.grammar,oracle:'separate',broadTrap:'proven'}));
}finally{rmSync(directory,{recursive:true,force:true});}
