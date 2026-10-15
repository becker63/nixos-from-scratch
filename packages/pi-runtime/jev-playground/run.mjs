import {readFileSync,writeFileSync,mkdirSync,cpSync,rmSync,existsSync} from 'node:fs';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {compileKernel,dependencyModules,runtime} from './runtime.mjs';
import {assertFrozen,manifest,hash} from './freeze.mjs';
export async function run(instance,policy='jev',{task,seed}={}){
 if(!['jev','random','heuristic'].includes(policy))throw Error('Unknown policy');
 instance=resolve(instance);const spec=JSON.parse(readFileSync(join(instance,'private/manifest.json'),'utf8'));
 assertFrozen(join(instance,'workspace'),spec);
 const runId=`${policy}-${seed??spec.seed}-${hash(task??spec.task).slice(0,8)}`;
 let attempt=0;while(existsSync(join(instance,'runs',runId+'-'+attempt)))attempt++;
 const output=join(instance,'runs',runId+'-'+attempt);mkdirSync(output,{recursive:true});
 const workspace=join(output,'workspace');cpSync(join(instance,'workspace'),workspace,{recursive:true});
 // Copies are mutable. The canonical snapshot is never a solve target.
 const {chmodSync}=await import('node:fs');for(const name of Object.keys(manifest(workspace)))chmodSync(join(workspace,name),0o644);
 const kernel=compileKernel();
 try{
  const env=Object.fromEntries(['PATH','HOME','TMPDIR','SSL_CERT_FILE'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]));env.PI_AGENT_MODE='jev';
  const result=await new Promise((resolveResult,reject)=>{
   const child=spawn(process.execPath,[join(dirname(fileURLToPath(import.meta.url)),'solve-child.mjs')],{cwd:workspace,env,stdio:['pipe','pipe','pipe']});
   let stdout='',stderr='';const timer=setTimeout(()=>child.kill('SIGTERM'),spec.budgets.maxWallMs+30000);
   child.stdout.on('data',b=>stdout+=b);child.stderr.on('data',b=>stderr=(stderr+b).slice(-2048));
   child.on('error',reject);child.on('close',code=>{clearTimeout(timer);if(code!==0)return reject(Error(`Pure child failed (${code}): ${stderr}`));try{resolveResult(JSON.parse(stdout));}catch(e){reject(e);}});
   child.stdin.end(JSON.stringify({kernel,modules:dependencyModules,policy,relationChain:spec.relationChain,options:{root:workspace,task:task??spec.task,grammar:spec.grammar,seed:seed??spec.seed,budgets:spec.budgets}}));
  });
  if(result.receipt.metrics.codexCalls!==0||result.receipt.metrics.workerCalls!==0)throw Error('Zero generation invariant failed');
  assertFrozen(join(instance,'workspace'),spec);
  const runnerFiles=['run.mjs','solve-child.mjs','isolation.mjs','test-boundary.mjs','test-preload.cjs'];
  const record={nodeVersion:process.version,dependencyModules,dependencyLockHash:hash(readFileSync(join(runtime,'package-lock.json'))),playgroundCodeHash:hash(runnerFiles.map(name=>readFileSync(join(dirname(fileURLToPath(import.meta.url)),name),'utf8')).join('\n')),challengeId:spec.id,workspaceHash:spec.workspaceHash,policy,seed:seed??spec.seed,task:task??spec.task,solverSourceHash:hash(['semantic-state','semantic-policy','semantic-controller',...['state','actions','transforms','policy','tasks','controller','retrieval'].map(n=>'jev-agent/'+n)].map(n=>readFileSync(join(kernel,n+'.js'),'utf8')).join('\n')),playgroundRunnerHash:hash(readFileSync(join(dirname(fileURLToPath(import.meta.url)),'solve-child.mjs'))),...result};
  writeFileSync(join(output,'receipt.json'),JSON.stringify(record,null,2)+'\n');return {record,output,spec};
 }finally{rmSync(kernel,{recursive:true,force:true});}
}
