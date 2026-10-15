import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {sweVerifier,sha256} from './swe-verifier.mjs';
const root=mkdtempSync(join(tmpdir(),'swe-verifier-cache-')),savedHost=process.env.DOCKER_HOST;
try{
 const taskDir=join(root,'task'),output=join(root,'results');mkdirSync(taskDir);writeFileSync(join(taskDir,'task.yaml'),'instance_id: cache-test\nimage: test-image\n');
 // A nonexistent evaluator makes every cache miss observable without Docker/Python.
 process.env.DOCKER_HOST='tcp://127.0.0.1:1';
 const options={instanceId:'cache-test',taskDir,output,python:join(root,'absent-evaluator'),graderIdentity:'environment-A'};
 const verifier=sweVerifier(options),patch='finite candidate patch',patchHash=sha256(patch),runId=`pure-jev-cache-test-${patchHash}-${verifier.environmentHash.slice(0,16)}`;
 const dir=join(output,runId);mkdirSync(dir);writeFileSync(join(dir,'receipt.json'),JSON.stringify({instanceId:'cache-test',patchHash,environmentHash:verifier.environmentHash,infrastructureFailure:false,passed:true,officialResolved:true,fingerprint:'exact-test-result'}));
 const hit=await verifier.evaluatePatch(patch);assert.equal(hit.passed,true);assert.equal(hit.cached,true);assert.equal(hit.wallMs,0);
 assert.equal((await sweVerifier(options).evaluatePatch(patch)).cached,true,'Persistent exact cache reused');
 assert.equal((await verifier.evaluatePatch(patch+' changed')).infrastructureFailure,true,'Different patch must miss');
 assert.equal((await sweVerifier({...options,graderIdentity:'environment-B'}).evaluatePatch(patch)).infrastructureFailure,true,'Different grader/runtime must miss');
 writeFileSync(join(taskDir,'task.yaml'),'instance_id: cache-test\nimage: different-image\n');assert.equal((await sweVerifier(options).evaluatePatch(patch)).infrastructureFailure,true,'Different task definition must miss');
 console.log(JSON.stringify({cache:'instance + exact patch + grader/runtime + task definition',infrastructure:'never a semantic pass',officialProcesses:0}));
}finally{if(savedHost===undefined)delete process.env.DOCKER_HOST;else process.env.DOCKER_HOST=savedHost;rmSync(root,{recursive:true,force:true});}
