import {join,basename} from 'node:path';
import {realpathSync,readFileSync} from 'node:fs';
import type {JevRequest,JevResponse} from 'pi-fabric/jev';
import type {TaskKind,NavigationResult,FileTarget} from './state.js';
import type {Evaluator} from '../semantic-policy.js';
import {shape} from '../semantic-policy.js';
import {safeText} from '../semantic-controller.js';
import {symbols} from './transforms.js';
import type {RepositoryWorld} from './actions.js';
import type {PurePolicy} from './policy.js';
export type Relation='File'|'Tests'|'References'|'Symbol'|'Config'|'Unknown';
function selected(response:JevResponse,key:string,legal:string[]) {
  const a=response.answers[key];return a?.type==='choice'&&legal.includes(a.choice)&&shape(a).top>=.55&&shape(a).margin>=.10?a.choice:undefined;
}
export async function classifyTask(task:string,world:RepositoryWorld,policy:PurePolicy,evaluate:Evaluator):Promise<{kind:TaskKind;relation:Relation;answers?:JevResponse['answers']}> {
  if(policy!=='jev')return {kind:/\b(fix|repair|bug)\b/i.test(task)?'Repair':/\b(verify|run|check)\b/i.test(task)?'Verify':/\b(references|covers|function)\b/i.test(task)?'Inspect':'Locate',relation:'File'};
  const response=await evaluate({state:{task:safeText(task,1024),repository:{files:world.objects.length,codeFiles:world.files.length,checks:world.checks.map(c=>({id:c.id,path:c.path}))},candidateFiles:world.navigationCandidates(task).map(f=>({id:f.id,path:f.path,bytes:f.bytes}))},questions:{
    taskKind:{type:'choice',instructions:'Classify the requested operation, not a plan. Read-only discovery never requires reproducing a failure or changing code.',criteria:{Locate:'Find an existing repository file/path/package/config',Inspect:'Return existing symbols, references, test relationships or config facts',Repair:'Change faulty source behavior and verify it',Verify:'Run existing exact checks without changing source',Unsupported:'Requires an unavailable operation or generating new content'}},
    relation:{type:'choice',instructions:'Which finite existing-fact result is requested? Symbol means an existing named function/symbol or definition, including its containing file path. Choose File only for a plain file/path request; Unknown if the relation is unclear.',criteria:{File:'Existing file/path',Tests:'Tests covering a module',References:'Files referencing a module',Symbol:'Existing function/symbol name and definition, including its containing file',Config:'Existing configuration assignments',Unknown:'Unclear or unsupported existing-fact relation'}},
  }});
  return {kind:(selected(response,'taskKind',['Locate','Inspect','Repair','Verify','Unsupported'])??'Unsupported') as TaskKind,relation:(selected(response,'relation',['File','Tests','References','Symbol','Config','Unknown'])??'Unknown') as Relation,answers:response.answers};
}
export async function navigate(task:string,kind:'Locate'|'Inspect',relation:Relation,world:RepositoryWorld,policy:PurePolicy,evaluate:Evaluator):Promise<{result?:NavigationResult;answers:JevResponse['answers'][];candidates:number}> {
  const candidates=world.navigationCandidates(task);const answers:JevResponse['answers'][]=[];
  if(kind==='Inspect'&&relation==='Unknown')return {answers,candidates:candidates.length};
  let file:FileTarget|undefined;
  if(policy==='jev') {
    const response=await evaluate({state:{task:safeText(task,1024),taskKind:kind,candidates:candidates.map(f=>({id:f.id,path:f.path,bytes:f.bytes,excerpt:world.matchingExcerpt(f,task,320)}))},questions:{target:{type:'choice',instructions:'Select the existing repository object answering the task. Paths are finite host-owned IDs. Choose unknown if none fits; do not invent a path.',criteria:Object.fromEntries([...candidates.map(f=>[f.id,f.path]),['unknown','No suitable existing object']])}}});answers.push(response.answers);
    const id=selected(response,'target',candidates.map(f=>f.id));file=candidates.find(f=>f.id===id);
  } else file=candidates[0];
  if(!file)return {answers,candidates:candidates.length};
  const path=realpathSync(join(world.root,file.path));
  if(kind==='Locate'||relation==='File')return {result:{kind:'LocatedFile',path},answers,candidates:candidates.length};
  const source=readFileSync(path,'utf8');
  if(relation==='Symbol') {
    const finite=symbols(file,path,source);if(!finite.length)return {answers,candidates:candidates.length};
    let symbol=finite[0];
    if(policy==='jev') {const response=await evaluate({state:{task:safeText(task,1024),symbols:finite.map(s=>({id:s.id,name:s.name,excerpt:safeText(s.excerpt,512)}))},questions:{symbol:{type:'choice',instructions:'Select the existing function defining the requested behavior; unknown if not present.',criteria:Object.fromEntries([...finite.map(s=>[s.id,s.name]),['unknown','No suitable symbol']])}}});answers.push(response.answers);const id=selected(response,'symbol',finite.map(s=>s.id));const found=finite.find(s=>s.id===id);if(!found)return {answers,candidates:candidates.length};symbol=found;}
    return {result:{kind:'LocatedSymbol',path,symbol:symbol.name},answers,candidates:candidates.length};
  }
  const needle=basename(file.path).replace(/\.[^.]+$/,'');
  const facts:NonNullable<NavigationResult['facts']>=[];
  if(relation==='Tests'||relation==='References') {
    for(const other of world.objects) {
      if(other.id===file.id||relation==='Tests'&&!/\.(?:test|spec)\./.test(other.path))continue;
      const lines=readFileSync(join(world.root,other.path),'utf8').split('\n');
      const line=lines.findIndex(text=>text.includes(needle));if(line>=0)facts.push({path:realpathSync(join(world.root,other.path)),line:line+1,text:safeText(lines[line],180)});
      if(facts.length>=16)break;
    }
  }else {
    const terms=world.terms(task);source.split('\n').forEach((line,i)=>{if(facts.length<12&&terms.some(t=>line.toLowerCase().includes(t)))facts.push({path,line:i+1,text:safeText(line,180)});});
  }
  return {result:{kind:'RepositoryFacts',path,facts},answers,candidates:candidates.length};
}
export function formatReceipt(receipt:import('./state.js').Terminal):string {
  const lines=[`Jev · ${receipt.taskKind} · ${receipt.kind}`];
  if(receipt.result){lines.push(receipt.result.path);if(receipt.result.symbol)lines.push(receipt.result.symbol);for(const fact of receipt.result.facts??[])lines.push(`${fact.path}${fact.line?':'+fact.line:''}${fact.text?' '+fact.text:''}`);}
  if(receipt.taskKind==='Repair')for(const step of receipt.trajectory??[])if(step.selectedEdit)lines.push(`${step.file??''}\n${step.selectedEdit.family}: ${step.selectedEdit.from} → ${step.selectedEdit.to}`);
  if(receipt.verification.checked?.length){const checks=new Map(receipt.verification.checked.map(c=>[c.path,c.passed]));for(const [path,passed]of checks)lines.push(`${path} ${passed?'✓':'✗'}`);}else if(receipt.verification.testsRun)lines.push(`Exact checks ${receipt.verification.passed?'✓':'✗'} (${receipt.verification.testsRun})`);
  if(receipt.missingCapability)lines.push(receipt.missingCapability);
  lines.push(`${receipt.metrics.jevEvaluations} Jev evaluations · ${receipt.metrics.mutations} mutations · ${receipt.metrics.codexCalls} Codex calls · ${receipt.metrics.workerCalls} workers`);
  return lines.join('\n');
}
