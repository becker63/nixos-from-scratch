import {installTestBoundary} from './test-boundary.mjs';
import {dependencyModules} from './runtime.mjs';
installTestBoundary(dependencyModules);
import {mkdirSync,writeFileSync,readFileSync,rmSync,cpSync,existsSync} from 'node:fs';
import {join,resolve,basename} from 'node:path';
import {compileKernel} from './runtime.mjs';
import {freeze,hash} from './freeze.mjs';
export function synthetic({index=0,branching=4,files=2,symbols=1,family='variable',boundary=false,navigation=false,unsupported=false,seed=42}={}){
 for(const [name,value,min,max]of [['branching',branching,1,64],['files',files,1,64],['symbols',symbols,1,32],['seed',seed,0,2147483647]])if(!Number.isInteger(value)||value<min||value>max)throw Error('Invalid generator '+name);
 const source={};let code,local,broad,grammar='J2';
 if(boundary){code='export function compute(text:string):number { return 0; }\n';local='assert.equal(compute("ABC"),198);';broad='assert.equal(compute("Z"),90);';grammar='J3';}
 else if(family==='variable'){
  const names=['start','end','margin','policy','probability','threshold',...Array.from({length:64},(_,i)=>`value${i}`)].slice(0,branching+1);
  // Rotate the owning value independently of candidate labels. Local inputs share
  // some plausible values; broader inputs disambiguate the required behavior.
  const target=1+(seed+index)%branching;
  code=`export function compute(${names.map(n=>n+':number').join(',')}):number { return start; }\n`;
  const values=names.map((_,i)=>i===0?2:8);const wide=names.map((_,i)=>i*7+3);
  local=`assert.equal(compute(${values}),8);`;broad=`assert.equal(compute(${wide}),${wide[target]});`;
 }else if(family==='two-edit'){
  code='export function compute(a:number,b:number,c:number):number { return a+a; }\n';local='assert.equal(compute(1,2,3),5);';broad='assert.equal(compute(4,7,11),18);';
 }else if(family==='operator'){
  code='export function compute(start:number,end:number):number { return end + start; }\n';local='assert.equal(compute(2,8),6);';broad='assert.equal(compute(3,10),7);';
 }else if(family==='callable'){
  grammar='J3';code='function add(a:number,b:number):number { return a+b; }\nfunction subtract(a:number,b:number):number { return a-b; }\nfunction distance(a:number,b:number):number { return Math.abs(a-b); }\nfunction scale(a:number,b:number):number { return a*b; }\nexport function compute(a:number,b:number):number { return add(a,b); }\n';local='assert.equal(compute(8,2),6);';broad='assert.equal(compute(2,8),6);';
 }else if(family==='argument'){
  code='function span(start:number,end:number):number { return end-start; }\nexport function compute(start:number,end:number,margin:number,policy:number):number { return span(start); }\n';local='assert.equal(compute(2,8,8,8),6);';broad='assert.equal(compute(3,10,13,20),7);';
 }else throw Error('Unknown synthetic family');
 code+=Array.from({length:symbols-1},(_,i)=>`export function policy${i}(margin:number,probability:number):number { return margin + probability; }\n`).join('');
 source['subject.ts']=code;
 source['subject.test.mjs']=`import {test} from 'node:test'; import assert from 'node:assert/strict'; import {compute} from './subject.ts'; test('required behavior',()=>{${local}});\n`;
 source['checks/behavior.test.mjs']=`import {test} from 'node:test'; import assert from 'node:assert/strict'; import {compute} from '../subject.ts'; test('adjacent behavior',()=>{${broad}});\n`;
 for(let i=1;i<files;i++)source[`policy${i}.ts`]=`export function semanticMargin${i}(policy:number,probability:number):number { return policy - probability; }\n`;
 return {taskShape:navigation?'Inspect':unsupported?'Unsupported':'Repair',relationChain:navigation?['Symbol','ContainingFile','Tests']:undefined,files:source,targetFile:'subject.ts',targetSymbol:'compute',grammar,task:navigation?'Find the function compute and identify its containing file and tests.':unsupported?'Write a README explaining this architecture beautifully.':'Repair the current behavior regression and verify it with the existing checks.',expected:unsupported?'Unsupported':boundary?'NeedsGeneration':'Success',difficulty:{localizationDistractors:files-1,symbolDistractors:symbols-1,actionBranching:branching,requiredSuccessfulMutations:boundary?0:family==='two-edit'?2:1,misleadingEvidence:true,broadVerificationTrap:!boundary},seed};
}
// Author-supplied bounded files + a controlled exact span, not main-checkout writes.
export function mutatedSource({files,targetFile,targetSymbol,from,to,task,grammar='J3',seed=42,expected='Success',generator}){
 const text=files[targetFile];if(!text||text.split(from).length!==2)throw Error('Mutation span must be unique');
 return {source:'mutated-source',generator,files:{...files,[targetFile]:text.replace(from,to)},targetFile,targetSymbol,task,grammar,seed,expected,difficulty:{localizationDistractors:0,symbolDistractors:0,actionBranching:0,requiredSuccessfulMutations:1,misleadingEvidence:false,broadVerificationTrap:false}};
}
export async function generate(destination,proposal,{id='instance',budgets={},grammar=proposal.grammar}={}){
 if(!['J0','J1','J2','J3'].includes(grammar))throw Error('Invalid grammar');
 const start=Date.now(),root=join(resolve(destination),'workspace'),hidden=join(resolve(destination),'private');if(existsSync(root)||existsSync(hidden))throw Error('Challenge destination already exists');mkdirSync(root,{recursive:true});
 if(Object.keys(proposal.files).length>80)throw Error('Bounded challenge exceeds 80 files');
 for(const [name,text] of Object.entries(proposal.files)){
  if(typeof text!=='string'||Buffer.byteLength(text)>48000)throw Error('Bounded file must be text of at most 48000 bytes');
  if(resolve(root,name).startsWith(root+'/')===false)throw Error('Unsafe challenge path');
  mkdirSync(join(root,name,'..'),{recursive:true});writeFileSync(join(root,name),text);
 }
 const generationMs=Date.now()-start,admissionStart=Date.now(),compiled=compileKernel();
 try{
  const {RepositoryWorld}=await import(join(compiled,'jev-agent/actions.js'));
  const {generateEdits,symbols}=await import(join(compiled,'jev-agent/transforms.js'));
  const world=new RepositoryWorld(root,grammar);if(world.checks.length!==Object.keys(proposal.files).filter(path=>/\.(?:test|spec)\.(?:ts|js|mjs)$/.test(path)).length)throw Error('All declared tests must fit the check frontier');const initial=await world.verify(30000);if(initial.passed&&(!proposal.taskShape||proposal.taskShape==='Repair'))throw Error('Initial exact check must fail');
  const successfulEdits=[],successfulPaths=[];let legalCount=0;const admission=[];
  // Exhaustively test every single legal edit in every bounded source file.
  for(const file of world.files){const path=join(root,file.path),text=readFileSync(path,'utf8');const result=generateEdits(file,path,text,grammar);legalCount+=result.edits.length;
   for(const edit of result.edits){writeFileSync(path,text.slice(0,edit.start)+edit.to+text.slice(edit.end));
    const probe=new RepositoryWorld(root,grammar);let check=await probe.verify(30000);const local=check.passed;if(local&&probe.checks.length>1)check=await probe.verify(30000,true);
    admission.push({id:edit.id,file:file.path,local,broad:check.passed});
    if(check.passed)successfulEdits.push({...edit,file:file.path,finalHash:hash(readFileSync(path))});writeFileSync(path,text);
   }
  }
  if(proposal.difficulty.requiredSuccessfulMutations===2&&!successfulEdits.length){
   const target=world.files.find(f=>f.path===proposal.targetFile),path=join(root,target.path),original=readFileSync(path,'utf8');
   search:for(const first of generateEdits(target,path,original,grammar).edits){
    const intermediate=original.slice(0,first.start)+first.to+original.slice(first.end);writeFileSync(path,intermediate);
    for(const second of generateEdits(target,path,intermediate,grammar).edits){
     const final=intermediate.slice(0,second.start)+second.to+intermediate.slice(second.end);writeFileSync(path,final);
     const probe=new RepositoryWorld(root,grammar);let check=await probe.verify(30000);if(check.passed&&probe.checks.length>1)check=await probe.verify(30000,true);
     if(check.passed){const pathEdits=[first,second].map(edit=>({...edit,file:target.path,finalHash:hash(final),singleStepSuccessful:false}));successfulPaths.push(pathEdits);successfulEdits.push(...pathEdits);break search;}
     writeFileSync(path,intermediate);
    }
   }writeFileSync(path,original);
  }
  if(proposal.expected==='Success'&&(!proposal.taskShape||proposal.taskShape==='Repair')&&!successfulEdits.length)throw Error('No successful generic single-edit repair');
  if(proposal.expected==='NeedsGeneration'&&successfulEdits.length)throw Error('Boundary has successful generic repair');
  const target=world.files.find(f=>f.path===proposal.targetFile),targetText=readFileSync(join(root,proposal.targetFile),'utf8');
  const targetSymbol=symbols(target,join(root,proposal.targetFile),targetText).find(s=>s.name===proposal.targetSymbol);
  const targetLegalCount=generateEdits(target,join(root,proposal.targetFile),targetText,grammar,targetSymbol).edits.length;
  const expectedTests=world.checks.filter(t=>readFileSync(join(root,t.path),'utf8').includes(basename(proposal.targetFile).replace(/\.[^.]+$/,''))).map(t=>t.path);
  const oracle={expectedTests,targetLegalCount,expected:proposal.expected,targetFile:proposal.targetFile,targetSymbol:proposal.targetSymbol,successfulEdits,successfulPaths,legalCount,admission,proofScope:successfulPaths.length?'All single transforms failed; one generic two-transform witness passed':'All enumerated single transforms; not exhaustive multi-edit reachability',leakIdentifiers:['solution.json','correct-fix',...successfulEdits.flatMap(e=>[e.id,e.finalHash,...(e.to.length>=4?[e.to]:[])])]};
  const spec={id,taskShape:proposal.taskShape??'Repair',relationChain:proposal.relationChain,task:proposal.task,grammar,source:proposal.source??'synthetic',difficulty:{...proposal.difficulty,actionBranching:targetLegalCount,broadVerificationTrap:admission.some(e=>e.local&&!e.broad)},seed:proposal.seed,budgets:{maxSteps:32,maxTransforms:10,maxTests:24,maxEvaluations:40,maxWallMs:120000,...budgets},generator:{model:proposal.generator?.model??null,provider:proposal.generator?.provider??null,timestamp:new Date().toISOString()},timings:{generationMs,admissionMs:Date.now()-admissionStart}};
  return freeze(root,hidden,spec,oracle);
 }finally{rmSync(compiled,{recursive:true,force:true});}
}
