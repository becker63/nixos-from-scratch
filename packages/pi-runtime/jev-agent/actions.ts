import {readdirSync,readFileSync,lstatSync,realpathSync,writeFileSync} from 'node:fs';
import {join,relative,dirname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import type {Action,Check,Edit,FileTarget,Frame,Grammar,Phase,SymbolTarget,Verification,ExactVerifier} from './state.js';
import {generateEdits,symbols,cheapLegality} from './transforms.js';
import {inventory,compileCandidates,type Retrieval} from './retrieval.js';
import {safeText,sensitivePath} from '../semantic-controller.js';
const execute=promisify(execFile);
const dependencyModules=dirname(dirname(createRequire(import.meta.url).resolve('typescript/package.json')));
export const fingerprint=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex').slice(0,16);
export class RepositoryWorld {
  objects:FileTarget[]=[];files:FileTarget[]=[];checks:Check[]=[];symbolUniverse:SymbolTarget[]=[];symbols:SymbolTarget[]=[];edits:Edit[]=[];
  evidence:Array<{id:string;excerpt:string}>=[];
  focus?:{file:string;symbol?:string;node?:string};family?:string;
  revision=0;verification:Verification={revision:-1,passed:false,testsRun:0,failures:[],exitStatus:null,fingerprint:''};
  original?:{edit:Edit;source:string;applied:string};
  patchBaseRevision=0;
  patch:Array<{edit:Edit;source:string;applied:string}>=[];
  get patchState(){return {baseRevision:this.patch.length?this.patchBaseRevision:this.revision,edits:this.patch.map(p=>({id:p.edit.id,family:p.edit.family,file:p.edit.file})),changedFiles:[...new Set(this.patch.map(p=>p.edit.file))],depthLimit:this.worldOptions.patchDepth??1};}
  rollbackPatch(){while(this.original)this.revert(false);}
  rejected=new Set<string>();mutations:Array<{id:string;family:string;revision:number}>=[];
  retrieval?:Retrieval;rankedFiles:string[]=[];rankStages:Array<{limit:number;paths:string[];scores:Array<{id:string;score:number}>}>=[];
  diagnostics:string[]=[];before=0;private issueTask='';private relevance=new Map<string,number>();
  constructor(readonly root:string,readonly grammar:Grammar,readonly exactVerifier?:ExactVerifier,readonly worldOptions:{boundedExploration?:boolean;verificationAware?:boolean;patchDepth?:1|2|3;retrieval?:'conventional'}={}) {
    if(realpathSync(root)!==root)throw new Error('Workspace must be a canonical path');
    const paths:string[]=[];
    const walk=(dir:string,depth:number)=>{if(depth>7||paths.length>=2048)return;for(const entry of readdirSync(dir,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))){const path=join(dir,entry.name),rel=relative(root,path);if(entry.isSymbolicLink()||sensitivePath(rel)||entry.name.startsWith('.')||['node_modules','vendor','dist','build','agent'].includes(entry.name))continue;if(entry.isDirectory())walk(path,depth+1);else if(entry.isFile()&&/\.(?:ts|js|mjs|nix|toml|json|md|yaml|yml|conf|patch)$/.test(entry.name)&&lstatSync(path).size<=48000)paths.push(rel);}};
    if(worldOptions.retrieval==='conventional')paths.push(...inventory(root).map(f=>f.path));else walk(root,0);
    paths.sort().forEach((path,i)=>{const target={id:`F${i}`,path,family:`G${fingerprint(path.includes('/')?path.split('/')[0]:'root').slice(0,6)}`,bytes:lstatSync(join(root,path)).size};this.objects.push(target);if(/\.(?:test|spec)\.(?:ts|js|mjs)$/.test(path))this.checks.push({id:`T${this.checks.length}`,path});else if(/\.(?:[cm]?js|[jt]sx?)$/.test(path))this.files.push(target);});
    this.checks.sort((a,b)=>a.path.split('/').length-b.path.split('/').length||a.path.localeCompare(b.path));this.checks=this.checks.slice(0,8);
  }
  terms(task:string){return [...new Set(task.toLowerCase().split(/[^a-z0-9]+/).filter(t=>t.length>2&&!['find','file','which','what','would','use','the','and','for','its','full','path','produce','fix','failing','behavior','verify','change','configure','configures'].includes(t)))].slice(0,12);}
  rank(file:FileTarget,task:string){if(this.retrieval)return this.retrieval.generated.find(f=>f.id===file.id)?.score??0;const terms=this.terms(task),key=file.id+terms.join('|');const previous=this.relevance.get(key);if(previous!==undefined)return previous;const content=safeText(readFileSync(join(this.root,file.path),'utf8'),48000).toLowerCase();const score=terms.reduce((n,t)=>n+(file.path.toLowerCase().includes(t)?3:0)+(content.includes(t)?1:0),0);this.relevance.set(key,score);return score;}
  navigationCandidates(task:string){return this.objects.slice().sort((a,b)=>this.rank(b,task)-this.rank(a,task)||a.path.localeCompare(b.path)).slice(0,24);}
  prioritize(task:string){this.issueTask=task;if(this.worldOptions.retrieval==='conventional'){this.retrieval=compileCandidates(this.root,this.objects,task,this.verification.failures);this.files=this.retrieval.compressed;return;}this.files.sort((a,b)=>this.rank(b,task)-this.rank(a,task)||a.path.localeCompare(b.path));this.files=this.files.slice(0,64);}
  matchingExcerpt(file:FileTarget,task:string,limit=512){const terms=this.retrieval?.terms??this.terms(task);return safeText(readFileSync(join(this.root,file.path),'utf8').split('\n').filter(l=>terms.some(t=>l.toLowerCase().includes(t))).slice(0,5).join('\n'),limit);
  }
  file(id:string){const target=this.files.find(f=>f.id===id);if(!target)throw new Error('Unknown file ID');return target;}
  source(id:string){return readFileSync(join(this.root,this.file(id).path),'utf8');}
  inspect(fileId:string) {
    const file=this.file(fileId),source=this.source(fileId);this.focus={file:fileId};
    this.symbols=symbols(file,join(this.root,file.path),source,this.worldOptions.retrieval==='conventional');
    this.symbolUniverse=this.symbols.slice();
    if(this.worldOptions.verificationAware){
     const terms=[...new Set(this.issueTask.replace(/([a-z])([A-Z])/g,'$1 $2').toLowerCase().split(/[^a-z0-9]+/).filter(t=>t.length>2))].slice(0,160);
     const score=(s:SymbolTarget)=>terms.reduce((n,t)=>n+(s.name.toLowerCase().includes(t)?12:0)+(s.excerpt.toLowerCase().includes(t)?1:0),0);
     const seed=this.symbols.slice().sort((a,b)=>score(b)-score(a)||a.start-b.start).slice(0,8),references=new Set(seed.flatMap(s=>s.references??[]));
     this.symbols.sort((a,b)=>(score(b)+(references.has(b.name)?8:0))-(score(a)+(references.has(a.name)?8:0))||a.start-b.start);this.symbols=this.symbols.slice(0,64);
    }
    this.evidence=this.evidence.filter(e=>e.id!==fileId);
    this.evidence.push({id:fileId,excerpt:safeText(source,1024)});
    // InspectFile is a macro: definition summaries, import facts, and adjacent tests.
    for(const target of this.checks.slice(0,4))if(!this.evidence.some(e=>e.id===target.id))this.evidence.push({id:target.id,excerpt:safeText(readFileSync(join(this.root,target.path),'utf8'),1024)});
    this.evidence=this.evidence.slice(-8);
  }
  prepare(symbolId?:string) {
    if(!this.focus)throw new Error('No focus');
    const file=this.file(this.focus.file);
    const symbol=symbolId?this.symbols.find(s=>s.id===symbolId):undefined;
    if(symbolId&&!symbol)throw new Error('Unknown symbol ID');
    this.focus.symbol=symbol?.id;
    const result=generateEdits(file,join(this.root,file.path),this.source(file.id),this.grammar,symbol);
    this.edits=result.edits.filter(e=>!this.rejected.has(e.id));this.before=result.before;this.diagnostics=result.diagnostics;
  }
  legal(phase:Phase):Action[] {
    if(phase==='Localize'&&this.worldOptions.retrieval==='conventional')return this.files.filter(f=>!this.rejected.has(`inspect:${f.id}`)).map(f=>({id:`AF${f.id}`,kind:'InspectFile',file:f.id}));
    if(phase==='Localize') {
      const available=this.files.filter(f=>!this.rejected.has(`inspect:${f.id}`)&&!this.rejected.has(`family:${f.family}`));
      const files=this.family?available.filter(f=>f.family===this.family):available;
      if(!this.family&&files.length>8)return [...new Set(files.map(f=>f.family))].slice(0,8).map(family=>({id:`A${family}`,kind:'InspectFamily',family}));
      return files.filter(f=>!this.rejected.has(`inspect:${f.id}`)).slice(0,8).map(f=>({id:`AF${f.id}`,kind:'InspectFile',file:f.id}));
    }
    if(phase==='Compose')return [{id:'AVerifyPatch',kind:'VerifyPatch',target:'TAll'}, {id:'ARollbackLast',kind:'RollbackLast'},{id:'ARollbackPatch',kind:'RollbackPatch'},...(this.patch.length<(this.worldOptions.patchDepth??1)?[{id:'AContinuePatch',kind:'ContinuePatch'} as Action]:[])];
    if(phase==='Inspect'&&this.patch.length)return [...this.symbols.filter(s=>!this.rejected.has('symbol:'+s.id)).slice(0,64).map(s=>({id:'AS'+s.id,kind:'InspectSymbol',symbol:s.id} as Action)),...this.files.map(f=>({id:'AF'+f.id,kind:'InspectFile',file:f.id} as Action))];
    if(phase==='Inspect'&&this.worldOptions.boundedExploration&&!this.patch.length)return [...this.symbols.filter(s=>!this.rejected.has('symbol:'+s.id)).slice(0,64).map(s=>({id:'AS'+s.id,kind:'InspectSymbol',symbol:s.id} as Action)),...(this.files.some(f=>!this.rejected.has('inspect:'+f.id))?[{id:'ARelocalize',kind:'Relocalize'} as Action]:[])];
    if(phase==='Inspect')return this.symbols.filter(s=>!this.rejected.has(`symbol:${s.id}`)).slice(0,this.worldOptions.retrieval==='conventional'?64:8).map(s=>({id:`AS${s.id}`,kind:'InspectSymbol',symbol:s.id}));
    if(phase==='Transform')return [...this.edits.map(e=>({id:`A${e.id}`,kind:'ApplyEdit',edit:e.id} as Action)),...(this.worldOptions.boundedExploration&&!this.patch.length&&this.files.some(f=>!this.rejected.has('inspect:'+f.id))?[{id:'ARelocalize',kind:'Relocalize'} as Action]:[])];
    if(phase==='Verify')return (this.exactVerifier||this.checks.length)?[{id:'AVerify',kind:'VerifyAffectedRegion',target:'TAll'}]:[];
    if(phase==='Recover'&&(this.worldOptions.patchDepth??1)>1)return this.patch.length?[{id:'ARollbackLast',kind:'RollbackLast'},{id:'ARollbackPatch',kind:'RollbackPatch'}]:[];
    if(phase==='Recover')return this.original?[{id:`AR${this.original.edit.id}`,kind:'Revert',edit:this.original.edit.id}]:[];
    return [];
  }
  advanceRegion(){if(this.family&&!this.legal('Localize').length){this.rejected.add(`family:${this.family}`);this.family=undefined;}}
  description(action:Action) {
    if(action.kind==='InspectFamily')return `Repository region ${action.family}, files ${this.files.filter(f=>f.family===action.family).map(f=>f.id+':'+f.path).slice(0,8).join(', ')}`;
    if(action.kind==='InspectFile')return `${this.file(action.file).path}, ${this.file(action.file).bytes} bytes${this.worldOptions.verificationAware?' '+JSON.stringify(this.retrieval?.generated.find(f=>f.id===action.file)?.signals.slice(0,4)??[])+' '+this.matchingExcerpt(this.file(action.file),this.retrieval?.terms.join(' ')??'',384):''}`;
    if(action.kind==='InspectSymbol'){const s=this.symbols.find(s=>s.id===action.symbol)!;return `${s.name}: ${safeText(s.excerpt,768)}${this.worldOptions.verificationAware?' existing calls '+JSON.stringify(s.references??[]):''}`;}
    if(action.kind==='ApplyEdit'){const e=this.edits.find(e=>e.id===action.edit)!;return `${e.family} ${e.node}: ${e.description}; exact type/syntax filter passed; ${safeText(e.from,96)} → ${safeText(e.to,96)}`;}
    if((action.kind==='VerifyAffectedRegion'||action.kind==='VerifyPatch')&&this.exactVerifier)return 'Run host-owned canonical exact verification';
    if(action.kind==='VerifyAffectedRegion')return `Run enumerated Node test targets ${this.checks.map(t=>t.id+':'+t.path).join(', ')}`;
    if(action.kind==='SubmitPatch')return 'Submit current finite patch; cheap gates do not prove issue resolution';
    if(action.kind==='Relocalize')return 'Abstain at this local edit site and inspect another retained file; no new paths or source';
    if(action.kind==='ContinuePatch')return 'Inspect another existing symbol or file, depth at most '+(this.worldOptions.patchDepth??1);
    if(action.kind==='RollbackLast'||action.kind==='RollbackPatch')return 'Restore exact owned patch snapshot';
    if(action.kind==='Revert')return `Restore exact prior snapshot for ${action.edit}`;
    return action.kind==='NeedsGeneration'?action.reason:'Exact verified success';
  }
  apply(editId:string) {
    if(this.patch.length>=(this.worldOptions.patchDepth??1))throw new Error('Unverified patch depth exhausted');
    const edit=this.edits.find(e=>e.id===editId);if(!edit)throw new Error('Unknown edit ID');
    const source=this.source(edit.file);if(source.slice(edit.start,edit.end)!==edit.from)throw new Error('Stale edit span');
    const applied=source.slice(0,edit.start)+edit.to+source.slice(edit.end);
    const file=this.file(edit.file),path=join(this.root,file.path);
    if(realpathSync(path)!==path||sensitivePath(file.path))throw new Error('Unsafe mutation target');
    if((this.worldOptions.patchDepth??1)>1&&!cheapLegality(path,source,applied))throw new Error('Cheap patch legality failed');
    if(!this.patch.length)this.patchBaseRevision=this.revision;
    this.patch.push({edit,source,applied});
    writeFileSync(path,applied);this.evidence=this.evidence.filter(e=>e.id!==edit.file);this.evidence.push({id:edit.file,excerpt:safeText(applied,1024)});this.original={edit,source,applied};this.revision++;this.verification.passed=false;this.mutations.push({id:edit.id,family:edit.family,revision:this.revision});
  }
  revert(regenerate=true) {
    const previous=this.original;if(!previous)throw new Error('Nothing to revert');
    if(this.source(previous.edit.file)!==previous.applied)throw new Error('External mutation; refuse destructive revert');
    writeFileSync(join(this.root,this.file(previous.edit.file).path),previous.source);
    this.evidence=this.evidence.filter(e=>e.id!==previous.edit.file);this.evidence.push({id:previous.edit.file,excerpt:safeText(previous.source,1024)});
    this.rejected.add(previous.edit.id);this.patch.pop();this.original=this.patch.at(-1);this.revision++;this.verification.passed=false;
    // Preserve chosen symbol so alternate candidates solve the same bounded problem.
    if(regenerate)this.prepare(this.focus?.symbol);
  }
  async verify(timeoutMs:number,broad=false) {
    if(this.exactVerifier){
      const result=await this.exactVerifier.verify(this.root);
      this.verification={scope:this.exactVerifier.verificationScope,revision:this.revision,passed:result.passed,testsRun:this.verification.testsRun+1,failures:result.failures.slice(0,20).map(f=>safeText(f,200)),exitStatus:result.passed?0:1,fingerprint:result.fingerprint};
      return this.verification;
    }
    if(!this.checks.length)throw new Error('No enumerated exact check target');
    // argv, never shell source. Tests run without inherited API-key environment.
    const env=Object.fromEntries(['PATH','HOME','TMPDIR','SSL_CERT_FILE'].filter(k=>process.env[k]!==undefined).map(k=>[k,process.env[k]!]));env.PI_AGENT_MODE='jev';env.NODE_PATH=dependencyModules;
    let status=0,output='';
    try {const result=await execute(process.execPath,['--test',...(broad?this.checks.slice(1):this.checks.slice(0,1)).map(t=>join(this.root,t.path))],{cwd:this.root,env,timeout:Math.max(1,Math.min(90000,timeoutMs)),maxBuffer:131072});output=result.stdout+'\n'+result.stderr;}
    catch(error){const e=error as {code?:number;stdout?:string;stderr?:string};status=typeof e.code==='number'?e.code:1;output=(e.stdout??'')+'\n'+(e.stderr??'');}
    const failures=safeText(output,12000).split('\n').filter(l=>/not ok|fail|error|Assertion|expected|actual|^\s*[+-]/i.test(l)).slice(0,20).map(l=>l.slice(0,200));
    this.verification={checked:[...(this.verification.checked??[]),...(broad?this.checks.slice(1):this.checks.slice(0,1)).map(t=>({path:t.path,passed:status===0}))],revision:this.revision,passed:status===0,testsRun:this.verification.testsRun+1,failures,exitStatus:status,fingerprint:fingerprint({status,failures,revision:this.revision})};return this.verification;
  }
  execute(action:Action):Phase {
    if(action.kind==='InspectFamily'){this.family=action.family;return 'Localize';}
    if(action.kind==='InspectFile'){this.inspect(action.file);if(!this.symbols.length){this.prepare();return 'Transform';}return 'Inspect';}
    if(action.kind==='InspectSymbol'){this.prepare(action.symbol);return 'Transform';}
    if(action.kind==='ApplyEdit'){this.apply(action.edit);return (this.worldOptions.patchDepth??1)>1&&this.patch.length<(this.worldOptions.patchDepth??1)?'Compose':'Verify';}
    if(action.kind==='Relocalize'){this.focus=undefined;this.symbols=[];this.edits=[];return 'Localize';}
    if(action.kind==='ContinuePatch')return 'Inspect';
    if(action.kind==='RollbackLast'){this.revert(false);return this.original?'Compose':'Localize';}
    if(action.kind==='RollbackPatch'){this.rollbackPatch();return 'Localize';}
    if(action.kind==='Revert'){this.revert();return 'Transform';}
    throw new Error('Action requires controller execution');
  }
}
