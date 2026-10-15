// Outer-only adapter. Gold/test patches and official grading stay in this process.
import {mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec=promisify(execFile);
export const sha256=text=>createHash('sha256').update(text).digest('hex');
const officialSingleInstance=String.raw`
import json, sys, os
from pathlib import Path
os.chdir(Path(sys.argv[5]).parent.parent)
from swebench.task.repo import load_task
from swebench.harness.utils import make_test_spec
from swebench.harness.run_evaluation import run_instance, _docker_client
pred = json.loads(Path(sys.argv[2]).read_text())[0]
instance = load_task(sys.argv[1])
assert instance['instance_id'] == pred['instance_id']
client = _docker_client()
# Fail closed: preparation is explicit. Never implicitly pull or build here.
client.images.get(instance['image'])
try:
    result = run_instance(make_test_spec(instance), pred, client, sys.argv[3],
                          timeout=int(sys.argv[4]), skip_patch=not pred['model_patch'],
                          task_repo=str(Path(sys.argv[1]).parent.parent))
    Path(sys.argv[5]).write_text(json.dumps(result[1] if result else None))
finally:
    client.close()
`;
export function sweVerifier({instanceId,taskDir,python,output,timeoutSeconds=300,graderIdentity='official-swe-02e7a74-qemu10-4k'}){
 taskDir=resolve(taskDir);python=resolve(python);output=resolve(output);mkdirSync(output,{recursive:true});
 const calls=[],cache=new Map();
 const environmentHash=sha256(JSON.stringify({graderIdentity,script:officialSingleInstance,task:readFileSync(join(taskDir,'task.yaml'),'utf8')}));
 async function evaluatePatch(modelPatch){
  const patchHash=sha256(modelPatch),runId=`pure-jev-${instanceId}-${patchHash}-${environmentHash.slice(0,16)}`;
  const dir=join(output,runId),saved=join(dir,'receipt.json');
  const cachedReceipt=cache.get(runId)??(existsSync(saved)?JSON.parse(readFileSync(saved,'utf8')):null);
  if(cachedReceipt?.environmentHash===environmentHash&&cachedReceipt.instanceId===instanceId&&cachedReceipt.patchHash===patchHash&&!cachedReceipt.infrastructureFailure){const hit={...cachedReceipt,cached:true,wallMs:0};calls.push(hit);return hit;}
  mkdirSync(dir,{recursive:true});
  const predictions=join(dir,'predictions.json'),resultPath=join(dir,'official-result.json');
  writeFileSync(predictions,JSON.stringify([{instance_id:instanceId,model_patch:modelPatch,model_name_or_path:'pure-jev'}])+'\n');
  const started=Date.now(),cached=existsSync(join(output,'logs/evaluation',runId,'pure-jev',instanceId,'report.json'));let error;
  // No provider credentials, no inherited environment in benchmark containers.
  const env=Object.fromEntries(['PATH','HOME','TMPDIR','SSL_CERT_FILE','DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH','SSH_AUTH_SOCK','XDG_RUNTIME_DIR'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]));
  try{
   // docker-py ignores Docker CLI contexts; explicitly use the same endpoint.
   if(!env.DOCKER_HOST)env.DOCKER_HOST=(await exec('docker',['context','inspect','--format','{{.Endpoints.docker.Host}}'],{env,timeout:10000,maxBuffer:8192})).stdout.trim();
   const result=await exec(python,['-c',officialSingleInstance,taskDir,predictions,runId,String(timeoutSeconds),resultPath],{cwd:output,env,timeout:(timeoutSeconds+60)*1000,maxBuffer:1024*1024});
   writeFileSync(join(dir,'harness.log'),result.stdout+'\n'+result.stderr);
  }catch(e){error=String((e.stdout??'')+'\n'+(e.stderr??'')).trim().slice(-2000)||String(e.message).slice(-300);writeFileSync(join(dir,'harness-error.log'),error);}
  const report=!error&&existsSync(resultPath)?JSON.parse(readFileSync(resultPath,'utf8'))?.[instanceId]:null;
  const infrastructureFailure=!!error||!report||report.infra_failure===true||!report.patch_successfully_applied||!report.tests_status;
  // Consume official structured grading only. Never parse test logs or expose
  // expected F2P/P2P categories/success lists to the policy.
  const failures=[];
  for(const group of Object.values(report?.tests_status??{}))for(const name of group?.failure??[])failures.push(`${String(name).slice(0,180)}: FAILED`);
  const passed=!infrastructureFailure&&report.resolved===true;
  const bounded=failures.slice(0,20),fingerprint=sha256(JSON.stringify({patchHash,passed,failures:bounded,infrastructureFailure}));
  const receipt={instanceId,runId,patchHash,environmentHash,cached,passed,officialResolved:infrastructureFailure?null:report.resolved,infrastructureFailure,status:infrastructureFailure?'BenchmarkBootstrapFailure':passed?'Resolved':'TaskFailure',failures:bounded,fingerprint,wallMs:Date.now()-started,error:infrastructureFailure?(error||report?.infra_failure_reason||'No authoritative test results'):undefined,reportPath:resultPath};
  if(!infrastructureFailure)cache.set(runId,receipt);
  calls.push(receipt);writeFileSync(join(dir,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');return receipt;
 }
 return {verificationScope:'canonical',timeoutSeconds,environmentHash,calls,evaluatePatch,async verify(workspace){const {stdout}=await exec('git',['diff','--binary','HEAD'],{cwd:workspace,maxBuffer:8*1024*1024});return evaluatePatch(stdout);}};
}
