import {mkdirSync,readFileSync,writeFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {generate,synthetic} from './generate.mjs';
import {run} from './run.mjs';
import {score} from './score.mjs';
export const campaigns=['recovery','branching-scale','localization-scale','symbol-scale','verification-traps','grammar-boundary','paraphrase-stability','generation-boundary','navigation-composition','unsupported','multi-edit'];
export function parameters(name,count=5,seed=42){
 if(!Number.isInteger(count)||count<1||count>100)throw Error('Count must be 1..100');
 if(!campaigns.includes(name))throw Error('Unknown campaign');
 if(name==='branching-scale')return [4,8,16,32].flatMap(branching=>Array.from({length:count},(_,index)=>({branching,index,seed})));
 if(name==='localization-scale')return [2,4,8,16,32,64].flatMap(files=>Array.from({length:count},(_,index)=>({files,index,seed})));
 if(name==='symbol-scale')return [2,4,8,16,32].flatMap(symbols=>Array.from({length:count},(_,index)=>({symbols,index,seed})));
 if(name==='grammar-boundary')return ['J0','J1','J2','J3'].map(grammar=>({family:'operator',grammar,seed}));
 if(name==='multi-edit')return Array.from({length:count},(_,index)=>({family:'two-edit',files:1,index,seed}));
 if(name==='navigation-composition')return Array.from({length:count},(_,index)=>({navigation:true,index,seed}));
 if(name==='unsupported')return Array.from({length:count},(_,index)=>({boundary:true,unsupported:true,index,seed}));
 if(name==='generation-boundary')return Array.from({length:count},(_,index)=>({boundary:true,index,seed}));
 return Array.from({length:count},(_,index)=>({family:name==='verification-traps'?'variable':['variable','callable','argument','operator','variable'][index%5],branching:4+index%3,index,seed}));
}
export async function generateCampaign(directory,name,{count=5,seed=42}={}){
 directory=resolve(directory);mkdirSync(directory,{recursive:true});
 if(existsSync(join(directory,'campaign.json')))throw Error('Campaign exists; use run to reuse frozen instances');
 const instances=[];const params=parameters(name,count,seed);
 for(let index=0;index<params.length;index++){
  const id=`instance-${String(index).padStart(3,'0')}`,p=params[index],proposal=synthetic(p);
  if(p.grammar){proposal.grammar=p.grammar;if(['J0','J1'].includes(p.grammar))proposal.expected='NeedsGeneration';}
  const spec=await generate(join(directory,id),proposal,{id});instances.push({id,workspaceHash:spec.workspaceHash,parameters:p});
  console.log(JSON.stringify({phase:'freeze',id,grammar:spec.grammar,admissionMs:spec.timings.admissionMs}));
 }
 const campaign={version:1,name,seed,count,instances};writeFileSync(join(directory,'campaign.json'),JSON.stringify(campaign,null,2)+'\n');return campaign;
}
export function report(campaign,results){
 const lines=[`# Jev playground: ${campaign.name}`,'','Experimental observations; no benchmark or calibration claim.','', '| Instance | Policy | Legal edits | Result / failure | Mutations / reverts | Local / broad | Inference / deterministic / verification ms |','| --- | --- | ---: | --- | --- | --- | --- |'];
 for(const r of results)lines.push(`| ${r.challengeId} | ${r.policy} | ${r.admittedLegalEdits} | ${r.terminal}${r.failure?' / '+r.failure:''} | ${r.metrics.mutations} / ${r.metrics.reverts} | ${r.exact.local} / ${r.exact.broad} | ${r.timings.jevInferenceMs} / ${r.timings.deterministicMs} / ${r.timings.verificationMs} |`);
 lines.push('','## Trajectories','');
 for(const r of results){lines.push(`- ${r.challengeId} / ${r.policy}: ${(r.trajectory??[]).map(t=>t.action+(t.selectedEdit?`(${t.selectedEdit.family}: ${t.selectedEdit.from} → ${t.selectedEdit.to})`:t.symbol?`(${t.symbol})`:t.file?`(${t.file})`:'')).join(' → ')} → ${r.terminal}. Checks: ${r.checks.map(c=>`${c.localOrBroad} ${c.passed?'pass':'fail'}`).join(', ')}.`);}
 const groups=new Map();for(const r of results){const key=`${r.policy}/${r.difficulty.actionBranching}`;const rows=groups.get(key)??[];rows.push(r);groups.set(key,rows);}
 lines.push('','## Branching groups','', '| Policy / requested branching | Solved | Correct survived narrowing | First edit successful |','| --- | --- | --- | --- |');
 for(const [key,rows]of groups)lines.push(`| ${key} | ${rows.filter(r=>r.solved).length}/${rows.length} | ${rows.filter(r=>r.correctSurvivedNarrowing===true).length}/${rows.filter(r=>r.correctSurvivedNarrowing!==null).length} | ${rows.filter(r=>r.firstEditSuccessful).length}/${rows.length} |`);
 lines.push('','## Choice concentration (not calibrated)','', '| Instance | Top | Runner up | Margin | Unknown | Selected edit passes oracle |','| --- | ---: | ---: | ---: | ---: | --- |');
 for(const r of results)for(const c of r.choices.filter(c=>c.actionSuccessful!==null))lines.push(`| ${r.challengeId} | ${c.top} | ${c.runnerUp} | ${c.margin} | ${c.unknown} | ${c.actionSuccessful} |`);
 return lines.join('\n')+'\n';
}
export async function runCampaign(directory,{policies=['jev','random','heuristic']}={}){
 directory=resolve(directory);const campaign=JSON.parse(readFileSync(join(directory,'campaign.json'),'utf8')),results=[];
 const prompts=campaign.name==='paraphrase-stability'?['Repair the current behavior regression and verify it with the existing checks.','The scoring tests are broken. Repair the regression.','Something in scoring is causing the test suite to fail. Find it and fix it.']: [undefined];
 for(const instance of campaign.instances)for(const policy of policies)for(const task of prompts){
  const path=join(directory,instance.id),execution=await run(path,policy,{task});const result=await score(path,execution);results.push(result);
  console.log(JSON.stringify({phase:'score',id:instance.id,policy,result:result.terminal,failure:result.failure,mutations:result.metrics.mutations,reverts:result.metrics.reverts}));
 }
 const existing=existsSync(join(directory,'report.json'))?JSON.parse(readFileSync(join(directory,'report.json'),'utf8')).results:[];
 for(const previous of existing)if(!results.some(r=>r.challengeId===previous.challengeId&&r.policy===previous.policy&&r.task===previous.task))results.push(previous);
 results.sort((a,b)=>a.challengeId.localeCompare(b.challengeId)||a.policy.localeCompare(b.policy));
 writeFileSync(join(directory,'report.json'),JSON.stringify({campaign,results},null,2)+'\n');writeFileSync(join(directory,'report.md'),report(campaign,results));return results;
}
// Content-free curriculum suggestion. No oracle or prompt/policy mutation.
export function nextDifficulty({failure,difficulty,solved}){return {...difficulty,...(solved?{actionBranching:Math.min(64,difficulty.actionBranching*2)}:failure==='CandidateRecallFailure'?{localizationDistractors:Math.max(1,difficulty.localizationDistractors)}:{})};}
