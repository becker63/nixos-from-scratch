// Real current-source experiment. Setup alone inserts one fault; policy receives
// only the ordinary task. No patch/ranking/target override enters the kernel.
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,readdirSync,readFileSync,writeFileSync,cpSync,symlinkSync,rmSync} from 'node:fs';
import {join,dirname,relative} from 'node:path';
import {tmpdir,homedir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {dependencyModules} from '../semantic-check.mjs';
const runtime=dirname(dirname(fileURLToPath(import.meta.url)));
const source=process.argv.find(a=>a.startsWith('--source='))?.slice(9)??runtime;
const repository=process.argv.find(a=>a.startsWith('--repository='))?.slice(13);
const receiptPath=process.argv.find(a=>a.startsWith('--output='))?.slice(9)??join(tmpdir(),'pi-real-self-repair.json');
const policies=process.argv.find(a=>a.startsWith('--policies='))?.slice(11).split(',')??['jev','random','heuristic'];
const task='Fix the failing semantic-policy behavior and verify the change.';
const temporary=mkdtempSync(join(tmpdir(),'jev-real-repair-'));
const hash=text=>createHash('sha256').update(text).digest('hex');
const manifest={};
function snapshot(destination){mkdirSync(destination,{recursive:true});for(const folder of ['','jev-agent','skill']){mkdirSync(join(destination,folder),{recursive:true});for(const name of readdirSync(join(source,folder)).filter(n=>/\.(ts|mjs|md|json)$/.test(n)&&!n.includes('results')&&n!=='self-repair.mjs')){const path=join(folder,name);const text=readFileSync(join(source,path),'utf8');manifest[path]=hash(text);writeFileSync(join(destination,path),text);}}symlinkSync(dependencyModules,join(destination,'node_modules'));}
const before=readFileSync(join(source,'semantic-policy.ts'),'utf8');
const correct='margin:(sorted[0]?.[1]??0)-(sorted[1]?.[1]??0)';const fault='margin:(sorted[0]?.[1]??0)+(sorted[1]?.[1]??0)';
assert.equal(before.split(correct).length,2,'Expected exactly one setup span');
process.env.PI_AGENT_MODE='jev';
const ts=createRequire(import.meta.url)('typescript');const compiled=join(temporary,'kernel');snapshot(compiled);writeFileSync(join(compiled,'package.json'),'{"type":"module"}');
for(const folder of ['','jev-agent'])for(const name of readdirSync(join(source,folder)).filter(n=>n.endsWith('.ts')))writeFileSync(join(compiled,folder,name.replace(/\.ts$/,'.js')),ts.transpileModule(readFileSync(join(source,folder,name),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText);
const {RepositoryWorld}=await import(join(compiled,'jev-agent/actions.js'));const {generateEdits,symbols}=await import(join(compiled,'jev-agent/transforms.js'));
const {default:extension}=await import(join(compiled,'semantic-extension.js'));
const {createAgentSession,SessionManager,DefaultResourceLoader,SettingsManager,ModelRuntime,initTheme}=await import(join(dependencyModules,'@earendil-works/pi-coding-agent/dist/index.js'));
initTheme();const originalDir=process.env.PI_CODING_AGENT_DIR;
const config=JSON.parse(readFileSync(join(homedir(),'.pi/agent/fabric.json'),'utf8'));
const modelRuntime=await ModelRuntime.create({authPath:join(homedir(),'.pi/agent/auth.json'),modelsPath:join(homedir(),'.pi/agent/models.json')});
const model=modelRuntime.getModel('openai-codex','gpt-6.1-sol');assert(model);
const records=[];
async function run(workspace,policy,seed,query){const agent=join(temporary,`agent-${records.length}`);mkdirSync(agent);writeFileSync(join(agent,'fabric.json'),JSON.stringify(config));process.env.PI_CODING_AGENT_DIR=agent;
 const settingsManager=SettingsManager.inMemory({packages:[],extensions:[],skills:[]});
 const loader=new DefaultResourceLoader({cwd:workspace,agentDir:agent,settingsManager,extensionFactories:[pi=>extension({...pi,getFlag:name=>name==='jev-policy'?policy:name==='jev-grammar'?'J2':name==='jev-seed'?String(seed):pi.getFlag(name)})]});await loader.reload();
 const created=await createAgentSession({cwd:workspace,modelRuntime,model,settingsManager,resourceLoader:loader,sessionManager:SessionManager.inMemory()});const session=created.session;
 try{assert.equal(created.extensionsResult.errors.length,0);const errors=[];await session.bindExtensions({mode:'json',onError:e=>errors.push(e.event)});await session.prompt('/mode jev');await session.prompt(query);const entry=session.sessionManager.getEntries().filter(e=>e.type==='custom'&&e.customType==='jev-agent-result').at(-1);assert(entry,'No pure task receipt');assert.equal(errors.length,0,JSON.stringify(errors));return entry.data;}finally{await session.extensionRunner.emit('session_shutdown',{});session.dispose();}}
try {
 if(repository&&policies.includes('jev')){const query='find me what file i would use to configure alacritty and produce its full path';const record=await run(repository,'jev',0,query);assert.equal(record.taskKind,'Locate');assert.equal(record.kind,'Success');assert.equal(record.result.path,join(repository,'config/alacritty/alacritty.toml'));assert.equal(record.metrics.mutations,0);assert.equal(record.metrics.checks,0);assert.equal(record.metrics.codexCalls,0);assert.equal(record.metrics.workerCalls,0);records.push({experiment:'Locate',task:query,receipt:record});console.log(JSON.stringify({experiment:'Locate',result:record.result,metrics:record.metrics}));}
 for(const policy of policies)for(const seed of policy==='random'?[0,7,19]:[0]) {
  const workspace=join(temporary,`${policy}-${seed}`);snapshot(workspace);writeFileSync(join(workspace,'semantic-policy.ts'),before.replace(correct,fault));
  const world=new RepositoryWorld(workspace,'J2');world.prioritize(task);
  const reproduced=await world.verify(90000);assert.equal(reproduced.passed,false,'Controlled fault did not fail existing test');assert(reproduced.failures.some(l=>/Assertion|margin|0\.9/.test(l)),'Failure not the intended existing assertion');
  // Diagnostic enumeration is recorded, not supplied as a target override.
  const target=world.files.find(f=>f.path==='semantic-policy.ts');const text=world.source(target.id);const symbol=symbols(target,join(workspace,target.path),text).find(s=>s.name==='shape');const generated=generateEdits(target,join(workspace,target.path),text,'J2',symbol);
  assert(generated.edits.some(e=>e.family==='ReplaceOperator'&&e.from==='+'&&e.to==='-'),'Generic J2 could not enumerate the controlled arithmetic repair');
  const record=await run(workspace,policy,seed,task);assert.equal(record.metrics.codexCalls,0);assert.equal(record.metrics.workerCalls,0);
  const repaired=readFileSync(join(workspace,'semantic-policy.ts'),'utf8');
  const observed={experiment:'Repair',policy,seed,sourceHash:manifest['semantic-policy.ts'],faultHash:hash(before.replace(correct,fault)),afterHash:hash(repaired),reproduced,filesConsidered:world.files.map(f=>({id:f.id,path:f.path})),symbolsConsidered:symbols(target,join(workspace,target.path),text).map(s=>({id:s.id,name:s.name})),genericEdits:generated.edits.map(e=>({id:e.id,node:e.node,family:e.family,from:e.from,to:e.to,description:e.description})),receipt:record};records.push(observed);
  console.log(JSON.stringify({experiment:'Repair',policy,seed,result:record.kind,reason:record.missingCapability,metrics:record.metrics,trajectory:record.trajectory}));
 }
 assert.equal(hash(readFileSync(join(source,'semantic-policy.ts'),'utf8')),hash(before),'Main source was altered');
 writeFileSync(receiptPath,JSON.stringify({source,manifest,mainBeforeHash:hash(before),mainAfterHash:hash(readFileSync(join(source,'semantic-policy.ts'),'utf8')),records},null,2)+'\n');
 for(const r of records.filter(r=>r.policy==='jev'))assert.equal(r.receipt.kind,'Success','Real Jev repair acceptance failed');
 console.log(JSON.stringify({receiptPath,mainCheckoutUnfaulted:true}));
}finally{if(originalDir===undefined)delete process.env.PI_CODING_AGENT_DIR;else process.env.PI_CODING_AGENT_DIR=originalDir;rmSync(temporary,{recursive:true,force:true});}
process.exit(0);
