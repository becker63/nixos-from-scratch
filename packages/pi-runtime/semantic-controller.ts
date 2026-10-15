import { randomUUID, createHash } from 'node:crypto';
import type { JevAnswer, JevQuestion, JevRequest, JevResponse } from 'pi-fabric/jev';
import { SemanticState, definitions, type Register, type Dependency, type Barrier } from './semantic-state.js';
import { allow, baseline, type Evaluator, type PolicyMode, type ActionClass, thresholds, probability } from './semantic-policy.js';

export type Evidence = {id:string;path:string;excerpt:string;kind:'candidate'|'worker';exactMatchCount:number;relationKinds:string[]};
export type Metrics = Record<string,number>;
export type Signal = {kind:'invalidation'|'barrier'|'control'|'permit';count:number;passed:boolean;phase?:'start'|'finish'};
export const CONTINUATION = 'Host verification is not ready. Inspect the current exact failure or run the relevant check after the latest mutation. Do not claim verified completion without that evidence.';
export const EXHAUSTED = 'Host semantic readiness was not established; automatic continuation budget exhausted. This run is unverified.';
const digest=(text:string)=>createHash('sha256').update(text).digest('hex').slice(0,16);
export const sensitivePath=(path:string)=>/(^|[\/\\])(?:\.env(?:\..*)?|secrets?|auth(?:\.json)?|credentials?)(?:[\/\\]|$)|credential|private.?key/i.test(path);
export function safeText(text:string,limit=768) {
  return text.split('\n').filter(line=>!/(?:api.?key|access.?token|refresh.?token|authorization|bearer\s|password|secret|BEGIN .*PRIVATE KEY)/i.test(line)).join('\n').slice(0,limit);
}
function textOf(value:unknown):string {
  if(typeof value==='string') return value;
  if(!value||typeof value!=='object') return '';
  const v=value as {output?:unknown;content?:Array<{type:string;text?:string}>;result?:unknown};
  if(typeof v.output==='string') return v.output;
  if(Array.isArray(v.content)) return v.content.filter(c=>c.type==='text').map(c=>c.text??'').join('\n');
  return v.result===undefined?'':textOf(v.result);
}
export function shellClass(command:string):'read'|'verify'|'denied' {
  // Deliberately a grammar of a few commands, NOT a general shell effect analyzer.
  if(/[;&|><`$\n\r\\]/.test(command)||command.length>1024) return 'denied';
  if(/^node --test(?: [a-zA-Z0-9_.\/-]+)*$/.test(command)) return 'verify';
  if(/^(?:npm test|npm run (?:test|check|typecheck)|npx tsc --noEmit)$/.test(command)) return 'verify';
  if(/^(?:pwd|ls(?: [-a-zA-Z0-9_.\/'" *]+)?|rg(?: [-a-zA-Z0-9_.\/'" :=()*?]+)?|git (?:status(?: --short)?|diff(?: --stat)?))$/.test(command)) return 'read';
  return 'denied';
}
function validResponse(response:JevResponse,request:JevRequest) {
  if(!response||!response.answers||!response.usage) throw new Error('Invalid semantic response');
  const finite=(n:unknown)=>typeof n==='number'&&Number.isFinite(n)&&n>=0&&n<=1;
  for(const [key,q] of Object.entries(request.questions)) {
    const a=response.answers[key]; if(!a||a.type!==q.type) throw new Error('Invalid semantic head');
    if(a.type==='noul') {if(!finite(a.noul)) throw new Error('Invalid probability');continue;}
    if(!finite(a.confidence)||!a.probabilities) throw new Error('Invalid confidence');
    const expected=q.type==='choice'?Object.keys(q.criteria):q.type==='score'?q.criteria.map((_,i)=>String(i)):[];
    if(Object.keys(a.probabilities).some(k=>!expected.includes(k))||expected.some(k=>!finite(a.probabilities[k]))||Math.abs(Object.values(a.probabilities).reduce((s,p)=>s+p,0)-1)>.02) throw new Error('Invalid distribution');
    if(a.type==='choice'&&!expected.includes(a.choice)) throw new Error('Invalid category');
    if(a.type==='score'&&(!Number.isFinite(a.score)||a.score<0||a.score>=expected.length)) throw new Error('Invalid score');
  }
}
export class SemanticController {
  readonly state=new SemanticState();
  readonly metrics:Metrics={invalidations:0,barriers:0,dirtyHeads:0,semanticUpdates:0,evaluations:0,questions:0,inputTokens:0,outputTokens:0,latencyMs:0,reportedCost:0,costReports:0,cacheHits:0,candidateAdmitted:0,candidateRejected:0,workerAdmitted:0,workerRejected:0,rawEvidenceBytes:0,admittedEvidenceBytes:0,rejectedEvidenceBytes:0,rawEvidenceTokenEstimate:0,admittedEvidenceTokenEstimate:0,codexTurns:0,codexWorkers:0,mutationPermits:0,workerPermits:0,completionPermits:0,permitDenials:0,continuations:0,checks:0,toolCalls:0,fabricExecutions:0,informationGainDecisions:0,informationGainCheaperChoices:0};
  goal=''; evidence:Evidence[]=[];
  verification={commandsRun:0,passed:0,failed:0,mutationRevision:-1,currentPassed:false,lastFailureFingerprint:'',diagnostics:[] as string[]};
  private permits=new Map<string,{action:ActionClass;stamp:string;consumed:boolean}>();
  private queryCounts=new Map<string,number>();
  private admission=new Map<string,{stamp:string;answer:JevAnswer}>();
  private proposal='';
  private tail:Promise<unknown>=Promise.resolve();
  private started=Date.now();
  evaluator:Evaluator;
  constructor(readonly mode:PolicyMode,evaluator:Evaluator,private signal:(signal:Signal)=>void=()=>{}) {this.evaluator=mode==='constant'||mode==='heuristic'?baseline(mode):evaluator;}
  exclusive<T>(work:()=>Promise<T>):Promise<T> { const next=this.tail.then(work,work); this.tail=next.then(()=>undefined,()=>undefined);return next; }
  private invalidate(deps:Dependency[]) {const changed=this.state.change(deps);this.metrics.invalidations+=changed.length;this.signal({kind:'invalidation',count:changed.length,passed:true});}
  input(goal:string) {this.goal=safeText(goal,1024);this.evidence=[];this.queryCounts.clear();this.permits.clear();this.admission.clear();this.verification={commandsRun:0,passed:0,failed:0,mutationRevision:-1,currentPassed:false,lastFailureFingerprint:'',diagnostics:[]};this.state.task();this.metrics.invalidations+=12;}
  facts() {return {hasEvidence:this.evidence.some(e=>e.kind==='candidate'&&e.relationKinds.includes('read')),verified:this.verification.currentPassed&&this.verification.mutationRevision===this.state.revisions.mutation,unresolvedFailure:this.verification.failed>0&&!this.verification.currentPassed};}
  world() {return {goal:this.goal,candidateFiles:this.evidence.filter(e=>e.kind==='candidate').slice(-16),workers:this.evidence.filter(e=>e.kind==='worker').slice(-8),verification:{...this.verification,currentPassed:this.facts().verified},history:{repeatedQueries:[...this.queryCounts.values()].filter(n=>n>1).length,mutationCount:this.state.revisions.mutation},proposal:this.proposal,revisions:this.state.revisions};}
  addEvidence(item:Evidence) {
    if(sensitivePath(item.path)) return;
    const safe={...item,excerpt:safeText(item.excerpt)};
    const existing=this.evidence.find(e=>e.id===safe.id);
    if(existing&&JSON.stringify(existing)===JSON.stringify(safe)) return;
    this.evidence=this.evidence.filter(e=>e.id!==safe.id);this.evidence.push(safe);if(this.evidence.length>24)this.evidence.shift();
    this.invalidate(item.kind==='worker'?['workers','evidence']:['candidates','evidence']);
  }
  async barrier(barrier:Barrier, extra:Record<string,JevQuestion>={}) {
    const relevant=this.state.relevant(barrier);
    const dirty=relevant.filter(k=>!this.state.fresh(k));
    this.metrics.cacheHits+=relevant.length-dirty.length;
    if(!dirty.length&&!Object.keys(extra).length)return true;
    this.metrics.barriers++;this.metrics.dirtyHeads+=dirty.length;
    this.signal({kind:'barrier',count:dirty.length,passed:true});
    const questions:Record<string,JevQuestion>={...extra};
    const stamps=new Map(dirty.map(k=>[k,this.state.stamp(k)]));const epoch=this.state.epoch;
    for(const key of dirty)questions[key]=definitions[key].question;
    if(this.mode==='off')return true;
    if(this.metrics.semanticUpdates>=64||this.metrics.inputTokens>=100000)return false;
    const request:JevRequest={state:this.world(),questions};const start=Date.now();
    this.metrics.semanticUpdates++;if(this.mode==='jev'){this.metrics.evaluations++;this.metrics.questions+=Object.keys(questions).length;}
    this.signal({kind:'control',count:Object.keys(questions).length,passed:true,phase:'start'});
    let succeeded=false;
    try {
      const response=await this.evaluator(request);validResponse(response,request);
      this.metrics.inputTokens+=response.usage.input_tokens;this.metrics.outputTokens+=response.usage.output_tokens;
      // Current Fabric JevResponse does not expose billed cost. Never invent one.
      for(const key of dirty)this.state.update(key,response.answers[key],stamps.get(key)!,epoch);
      for(const key of Object.keys(extra))this.admission.set(key,{stamp:digest(JSON.stringify(this.world())),answer:structuredClone(response.answers[key])});
      succeeded=true;return true;
    } catch {return false;} finally {this.metrics.latencyMs+=Date.now()-start;this.signal({kind:'control',count:Object.keys(questions).length,passed:succeeded,phase:'finish'});}
  }
  private permitStamp() {return `${this.state.epoch}:${this.state.revision}:${JSON.stringify(this.state.revisions)}`;}
  async mint(action:ActionClass):Promise<string> {
    const barrier:Barrier=action==='completion'?'settlement':action;
    const ok=await this.barrier(barrier);
    const granted=this.mode==='off'||(ok&&allow(this.state,action,this.facts()));
    this.signal({kind:'permit',count:1,passed:granted});
    if(!granted){this.metrics.permitDenials++;throw new Error(`Semantic ${action} permit denied; acquire exact evidence or verification`);}
    const id=randomUUID();this.permits.set(id,{action,stamp:this.permitStamp(),consumed:false});
    this.metrics[`${action}Permits`]++;return id;
  }
  consume(id:string,action:ActionClass) {
    const permit=this.permits.get(id);
    if(!permit||permit.action!==action||permit.consumed||permit.stamp!==this.permitStamp())throw new Error('Fabricated, stale, consumed or wrong-class semantic permit');
    permit.consumed=true;this.permits.delete(id);
  }
  mutation() {this.verification.currentPassed=false;this.invalidate(['mutation','evidence']);}
  verify(command:string,passed:boolean,output:string) {
    const fingerprint=digest(`${command}:${passed}:${safeText(output,512)}`);
    const changed=this.verification.lastFailureFingerprint!==fingerprint||this.verification.currentPassed!==passed||this.verification.mutationRevision!==this.state.revisions.mutation;
    this.metrics.checks++;this.verification.commandsRun++;this.verification[passed?'passed':'failed']++;
    this.verification.currentPassed=passed;this.verification.mutationRevision=this.state.revisions.mutation;
    this.verification.lastFailureFingerprint=fingerprint;
    this.verification.diagnostics=passed?[]:safeText(output,512).split('\n').filter(l=>/error|fail|not ok|assert/i.test(l)).slice(0,6);
    if(changed)this.invalidate(['verification']);
  }
  async admit():Promise<Evidence[]> {
    const items=this.evidence.slice(-16);const stamp=digest(JSON.stringify(this.world()));
    const extra:Record<string,JevQuestion>={};
    items.forEach((e,i)=>{const key=`admit_${e.kind}_${i}`;if(this.admission.get(key)?.stamp!==stamp)extra[key]={type:'noul',instructions:`Is evidence item ${e.id} at ${e.path} relevant, novel, and likely to change the next action for the goal, rather than redundant or a distractor?`};});
    const ok=this.mode==='off'||await this.barrier('evidence',extra);
    const ranked=items.map((e,i)=>({e,p:this.mode==='off'?1:ok?this.admission.get(`admit_${e.kind}_${i}`)?.answer:undefined})).map(({e,p})=>({e,p:typeof p==='number'?p:p?.type==='noul'?p.noul:0})).sort((a,b)=>b.p-a.p||a.e.id.localeCompare(b.e.id));
    const selected=ranked.filter(e=>e.p>=thresholds.admission).slice(0,6).map(e=>e.e);
    for(const e of items){const admitted=selected.includes(e);this.metrics[e.kind==='worker'?(admitted?'workerAdmitted':'workerRejected'):(admitted?'candidateAdmitted':'candidateRejected')]++;const bytes=Buffer.byteLength(e.excerpt);this.metrics.rawEvidenceBytes+=bytes;this.metrics[admitted?'admittedEvidenceBytes':'rejectedEvidenceBytes']+=bytes;this.metrics.rawEvidenceTokenEstimate+=Math.ceil(bytes/4);if(admitted)this.metrics.admittedEvidenceTokenEstimate+=Math.ceil(bytes/4);}
    return selected;
  }
  // Separate exploratory finite-action information-gain policy; no commands from Jev.
  async chooseEvidence(actions:Array<{id:string;kind:'read'|'test'|'codex'|'worker';evidenceId:string}>) {
    const finite=actions.slice(0,8);const questions:Record<string,JevQuestion>={};
    finite.forEach((a,i)=>questions[`gain_${i}`]={type:'noul',instructions:`Would the finite action ${a.kind} on evidence ${a.evidenceId} reduce decision-relevant uncertainty and change the next action, rather than repeat evidence?`});
    const ok=await this.barrier('reasoning',questions);this.metrics.informationGainDecisions++;
    const ranked=finite.map((a,i)=>({a,p:ok?this.admission.get(`gain_${i}`)?.answer:undefined})).map(({a,p})=>({a,p:p?.type==='noul'?p.noul:0})).sort((a,b)=>b.p-a.p||['read','test','codex','worker'].indexOf(a.a.kind)-['read','test','codex','worker'].indexOf(b.a.kind));
    const choice=ranked[0]?.p!>=.7?ranked[0]?.a:finite.find(a=>a.kind==='read'||a.kind==='test');
    if(choice&&(choice.kind==='read'||choice.kind==='test'))this.metrics.informationGainCheaperChoices++;
    return choice;
  }
  async settlement() {
    try {const permit=await this.mint('completion');this.consume(permit,'completion');return {ready:true,continue:false,message:''};}
    catch {if(this.metrics.continuations>=2)return {ready:false,continue:false,message:EXHAUSTED};this.metrics.continuations++;return {ready:false,continue:true,message:CONTINUATION};}
  }
  async intercept(ref:string,args:Record<string,unknown>,run:()=>Promise<unknown>, phase:'full'|'prepare'|'observe'='full'):Promise<unknown> {
    this.metrics.toolCalls++;
    const name=ref.replace(/^native\./,'');
    const path=String(args.path??args.file??args.file_path??'');
    const command=String(args.command??args.cmd??args.shell??'');
    const shell=name==='pi.bash'||name==='pi.powershell';
    if(sensitivePath(path)||shell&&sensitivePath(command))throw new Error('Semantic control excludes credential and secret paths');
    const kind=shell?shellClass(command):undefined;
    if(shell&&kind==='denied'&&this.mode!=='off')throw new Error('Experimental semantic shell policy denies this command; use exact read/search/edit/write or an approved check grammar');
    if(this.mode!=='off'&&/^(sessions\.|programs\.|mesh\.|components\.|agents\.(ask|steer|followUp)|rlm\.)/.test(name))throw new Error('Unsupported consequential capability in semantic experiment');
    const mutation=['pi.edit','pi.write','extensions.lsp_rename','extensions.code_rewrite','extensions.lsp_code_actions'].includes(name);
    const worker=/^agents\.(run|spawn|handoff|create)$/.test(name);
    if(mutation&&phase!=='observe'){const proposal=JSON.stringify({path,action:name,summary:safeText(JSON.stringify(args.content??args.contents??args.text??args.edits??{old:args.oldText??args.old,new:args.newText??args.new}),512)});if(proposal!==this.proposal){this.proposal=proposal;this.invalidate(['proposal']);}const permit=await this.mint('mutation');this.consume(permit,'mutation');}
    if(worker&&phase!=='observe'){const permit=await this.mint('worker');this.consume(permit,'worker');this.metrics.codexWorkers++;}
    const investigation=['pi.read','pi.grep','pi.find','pi.ls'].includes(name);
    if(investigation&&phase!=='observe'){const fingerprint=digest(`${name}:${JSON.stringify(args)}`);const count=(this.queryCounts.get(fingerprint)??0)+1;this.queryCounts.set(fingerprint,count);if(count>1)this.invalidate(['history']);}
    if(phase==='prepare')return undefined;
    try {
      const result=await run();const text=textOf(result);
      if(name==='pi.read')this.addEvidence({id:digest(path),path,excerpt:text,kind:'candidate',exactMatchCount:0,relationKinds:['read']});
      if(['pi.grep','pi.find','pi.ls'].includes(name))this.addEvidence({id:digest(`${name}:${JSON.stringify(args)}`),path:path||'.',excerpt:text,kind:'candidate',exactMatchCount:text.split('\n').length,relationKinds:['search']});
      if(mutation)this.mutation();
      if(shell&&kind==='verify'){const r=result as {ok?:boolean;isError?:boolean;exitCode?:number};this.verify(command,r.ok!==false&&r.isError!==true&&(r.exitCode===undefined||r.exitCode===0),text);if(!this.verification.currentPassed)await this.barrier('failure');}
      if(worker)this.addEvidence({id:digest(name+text),path:'worker-report',excerpt:text,kind:'worker',exactMatchCount:0,relationKinds:['report']});
      return result;
    } catch(error) {
      if(mutation)this.mutation(); // partial writes also invalidate
      if(shell&&kind==='verify'){this.verify(command,false,'Exact command failed');await this.barrier('failure');}
      throw error;
    }
  }
  snapshot() {return {epoch:this.state.epoch,revisions:{...this.state.revisions},registers:Object.fromEntries(Object.entries(this.state.cells).map(([k,c])=>[k,{dirty:!this.state.fresh(k as Register),answer:c.answer}])),verification:{...this.verification},metrics:{...this.metrics,wallMs:Date.now()-this.started},generativeEscalationSupported:probability(this.state,'anotherGenerativeTurnValue')!==undefined&&probability(this.state,'anotherGenerativeTurnValue')!>=.8};}
}
