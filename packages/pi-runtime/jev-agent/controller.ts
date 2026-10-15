import type {JevQuestion,JevRequest,JevResponse} from 'pi-fabric/jev';
import {RepositoryWorld,fingerprint} from './actions.js';
import {choose,baselineChoice,type PurePolicy} from './policy.js';
import {defaults,type Action,type Budgets,type Frame,type Grammar,type Metrics,type Phase,type Terminal,type Trace} from './state.js';
import {safeText} from '../semantic-controller.js';
import {classifyTask,navigate} from './tasks.js';
import {ExactVerificationUnavailable,type ExactVerifier,type TaskKind,type NavigationResult} from './state.js';
import type {Evaluator} from '../semantic-policy.js';

export async function runJevAgent(options:{root:string;task:string;exactVerifier?:ExactVerifier;protocolTaskKind?:'Repair';boundedExploration?:boolean;verificationAware?:boolean;patchDepth?:1|2|3;retrieval?:'conventional';grammar?:Grammar;policy?:PurePolicy;seed?:number;evaluate:Evaluator;budgets?:Partial<Budgets>;signal?:AbortSignal;trace?:(event:Trace)=>void}):Promise<Terminal> {
  const start=Date.now(),budget={...defaults,...options.budgets},policy=options.policy??'jev';
  const metrics:Metrics={steps:0,jevEvaluations:0,jevHeads:0,jevInputTokens:0,jevOutputTokens:0,jevLatencyMs:0,reportedCost:null,deterministicMs:0,phaseTransitions:0,candidatesBefore:0,candidatesAfter:0,candidatesNarrowed:0,reads:0,searchExpansions:0,transformAttempts:0,mutations:0,reverts:0,checks:0,failures:0,repeatedStates:0,codexCalls:0,workerCalls:0,wallMs:0,actionFamilies:{},narrowingStages:0};
  const world=new RepositoryWorld(options.root,options.grammar??'J2',options.exactVerifier,{retrieval:options.retrieval,patchDepth:options.patchDepth,verificationAware:options.verificationAware,boundedExploration:options.boundedExploration});
  let taskKind:TaskKind='Unsupported',result:NavigationResult|undefined;let shadowClassification:Terminal['shadowClassification'];
  const trajectory:NonNullable<Terminal['trajectory']>=[];
  world.prioritize(options.task);
  let phase:Phase='Localize',previousAction:string|undefined,previousResult:Frame['previousResult'];
  const distributions:JevResponse['answers'][]=[];const repetitions=new Map<string,number>();let flat=0;
  const emit=(kind:Trace['kind'],eventPhase:Trace['phase'],count=1,passed=true)=>options.trace?.({kind,phase:eventPhase,count,passed});
  const terminal=(kind:Terminal['kind'],missingCapability?:string):Terminal=>{if(kind!=='Success'&&kind!=='Submitted'&&world.original){try{const count=world.patch.length;world.rollbackPatch();metrics.reverts+=count;}catch{missingCapability='External mutation prevented exact rollback';}}metrics.wallMs=Date.now()-start;return {kind,taskKind,patchState:world.patchState,retrieval:world.retrieval?{generated:world.retrieval.generated.map(({id,path,signals,score})=>({id,path,signals,score})),compressed:world.retrieval.compressed.map(f=>f.path),ranked:world.rankedFiles,rankStages:world.rankStages,ms:world.retrieval.ms}:undefined,shadowClassification,result,trajectory,phase,focusedTargets:world.focus?[world.focus.file,...(world.focus.symbol?[world.focus.symbol]:[])]:[],evidenceCollected:world.evidence.length,attemptedActionFamilies:Object.keys(metrics.actionFamilies),missingCapability,metrics,verification:{...world.verification},distributions};};
  let verificationWaitMs=0;const elapsed=()=>Date.now()-start-(options.verificationAware?verificationWaitMs:0);
  const evaluate:Evaluator=async request=>{
    if(metrics.jevEvaluations>=budget.maxEvaluations||elapsed()>=budget.maxWallMs)throw new Error('Jev budget exhausted');
    metrics.jevEvaluations++;metrics.jevHeads+=Object.keys(request.questions).length;const then=Date.now();emit('jev-policy','start',Object.keys(request.questions).length);
    let passed=false;
    try {const finiteRequest=JSON.parse(JSON.stringify(request)) as JevRequest;
      const response=await options.evaluate(finiteRequest);metrics.jevInputTokens+=response.usage.input_tokens;metrics.jevOutputTokens+=response.usage.output_tokens;passed=true;return response;}
    finally {metrics.jevLatencyMs+=Date.now()-then;emit('jev-policy','finish',Object.keys(request.questions).length,passed);}
  };
  const timed=async<T>(work:()=>T|Promise<T>):Promise<T>=>{const then=Date.now();try{return await work();}finally{metrics.deterministicMs+=Date.now()-then;}};
  const verify=async(broad=false)=>{emit('verification','start',world.checks.length);const began=Date.now();const result=await timed(()=>world.verify(budget.maxWallMs-elapsed(),broad));if(world.exactVerifier?.verificationScope==='canonical')verificationWaitMs+=Date.now()-began;metrics.checks++;if(!result.passed)metrics.failures++;emit('verification','finish',world.checks.length,result.passed);return result;};
  try {
    if(budget.maxSteps<=0)return terminal('Exhausted','Step budget');
    const classification=await classifyTask(options.task,world,policy,evaluate);taskKind=options.protocolTaskKind??classification.kind;if(options.protocolTaskKind)shadowClassification=classification;
    if(classification.answers)distributions.push(classification.answers);
    if(taskKind==='Unsupported')return terminal('Unsupported','Task outside finite task grammars');
    if(taskKind==='Locate'||taskKind==='Inspect') {
      emit('candidate-generation','start');
      const navigation=await timed(()=>navigate(options.task,taskKind as 'Locate'|'Inspect',classification.relation,world,policy,evaluate));
      distributions.push(...navigation.answers);metrics.candidatesBefore=world.objects.length;metrics.candidatesAfter=navigation.candidates;metrics.candidatesNarrowed=navigation.candidates;metrics.steps=1;result=navigation.result;
      emit('candidate-generation','finish',navigation.candidates);emit('action-selected','finish');
      return terminal(result?'Success':'NotFound',result?undefined:'No supported existing repository object');
    }
    if(!world.exactVerifier&&!world.checks.length)return terminal('NotFound','No enumerated exact check target');
    if(taskKind==='Verify'){let checked=await verify();if(checked.passed&&!world.exactVerifier&&world.checks.length>1)checked=await verify(true);return terminal(checked.passed?'Success':'NeedsGeneration',checked.passed?undefined:'Exact checks fail; Verify cannot mutate');}
    // Reproduction is now reachable only after Repair classification.
    await verify();
    if(options.retrieval==='conventional'){
      {
       await timed(()=>world.prioritize(options.task));
       let files=world.files.slice();
       for(const limit of [64,16,8]){
        if(files.length<=limit)continue;
        const scores=new Map<string,number>();
        for(let start=0;start<files.length;start+=(options.verificationAware?8:16)){
         const batch=files.slice(start,start+(options.verificationAware?8:16));
         const response=await evaluate({state:{task:safeText(options.task,options.verificationAware?4096:2048),failures:world.verification.failures,candidates:batch.map(f=>({id:f.id,path:f.path,signals:world.retrieval!.generated.find(c=>c.id===f.id)?.signals.slice(0,4)??[],definitions:options.verificationAware?(world.retrieval!.generated.find(c=>c.id===f.id)?.definitions.slice(0,12)??[]):[],excerpt:world.matchingExcerpt(f,options.task,options.verificationAware?384:128)}))},questions:Object.fromEntries(batch.map(f=>[f.id,{type:'noul',instructions:'Is this existing file likely to own the reported faulty behavior? Use its supplied deterministic signals; do not invent paths.'}]))});
         distributions.push(response.answers);for(const file of batch){const answer=response.answers[file.id];scores.set(file.id,answer?.type==='noul'?answer.noul:0);}
        }
        files.sort((a,b)=>(scores.get(b.id)??0)-(scores.get(a.id)??0)||world.rank(b,options.task)-world.rank(a,options.task)||a.path.localeCompare(b.path));files=files.slice(0,limit);metrics.narrowingStages++;
        world.rankedFiles=files.map(f=>f.path);world.rankStages.push({limit,paths:world.rankedFiles.slice(),scores:[...scores].map(([id,score])=>({id,score}))});
       }
       if(options.verificationAware){files=[...new Map([...files,...world.retrieval!.compressed.slice(0,8)].map(f=>[f.id,f])).values()];world.rankedFiles=files.map(f=>f.path);world.rankStages.push({limit:files.length,paths:world.rankedFiles.slice(),scores:[]});}
       world.files=files;
      }
    }
    for(;metrics.steps<budget.maxSteps;metrics.steps++) {
      if(options.boundedExploration&&metrics.searchExpansions>=6&&phase==='Localize')return terminal('Exhausted','Six-file exploration budget');
      if(options.signal?.aborted)return terminal('Cancelled');
      if(elapsed()>=budget.maxWallMs||metrics.jevEvaluations>=budget.maxEvaluations||metrics.transformAttempts>=budget.maxTransforms||(metrics.checks>=budget.maxTests&&phase!=='Stop'&&phase!=='Recover'))return terminal('Exhausted','Explicit task budget');
      emit('candidate-generation','start');
      let actions=await timed(()=>world.legal(phase));
      if(phase==='Stop'&&world.verification.passed&&world.verification.revision===world.revision)actions=world.exactVerifier?.verificationScope==='cheap'?[{id:'ASubmit',kind:'SubmitPatch'}]:[{id:'ASuccess',kind:'StopSuccess'}];
      const stop:Action={id:'ANeedsGeneration',kind:'NeedsGeneration',reason:'No supported useful finite action or transform remains'};
      const rawCount=phase==='Transform'?world.before:actions.length;
      metrics.candidatesBefore+=rawCount;metrics.candidatesAfter+=actions.length;emit('candidate-generation','finish',actions.length);
      const frame:Frame={task:safeText(options.task,options.verificationAware?4096:1024),phase,grammar:world.grammar,focus:world.focus,patchState:world.patchState,candidates:actions.map(a=>({id:a.id,kind:a.kind,facts:a.kind==='StopSuccess'?'Exact current checks passed; finish':world.description(a)})),evidence:world.evidence,diagnostics:world.diagnostics,previousAction,previousResult,mutations:world.mutations.slice(-6),verification:world.verification,budget:{stepsRemaining:budget.maxSteps-metrics.steps,jevCallsRemaining:budget.maxEvaluations-metrics.jevEvaluations,wallClockRemainingMs:Math.max(0,budget.maxWallMs-elapsed())},loopDetected:metrics.repeatedStates>0};
      const stateFingerprint=fingerprint({phase,focus:world.focus,candidates:actions.map(a=>a.id),verification:world.verification.fingerprint,rejected:[...world.rejected].sort()});
      const repeated=(repetitions.get(stateFingerprint)??0)+1;repetitions.set(stateFingerprint,repeated);if(repeated>1)metrics.repeatedStates++;
      if(repeated>budget.maxRepeated)return terminal('Exhausted','LoopDetected');
      const localityEscape=actions.find(a=>a.kind==='Relocalize');
      if(policy==='jev'&&actions.length>8) {
        // One relevance vector then one Choice over the narrowed finite set.
        const scores=new Map<string,number>(),batchSize=options.verificationAware?8:64;
        for(let i=0;i<Math.min(actions.length,64);i+=batchSize){const batch=actions.slice(i,i+batchSize),questions:Record<string,JevQuestion>={};batch.forEach(a=>questions[a.id]={type:'noul',instructions:'Does this finite action address the original reported behavior or expose its owning location? Compiler diagnostics alone do not establish issue relevance.'});
         const state=options.verificationAware?{...frame,candidates:frame.candidates.filter(c=>batch.some(a=>a.id===c.id)),evidence:frame.evidence.slice(-3).map(e=>({...e,excerpt:e.excerpt.slice(0,256)})),diagnostics:frame.diagnostics.slice(0,4)}:frame;
         const response=await evaluate({state:state as unknown as JevRequest['state'],questions});distributions.push(response.answers);for(const a of batch){const answer=response.answers[a.id];scores.set(a.id,answer?.type==='noul'?answer.noul:0);}
        }
        actions=actions.slice(0,64).sort((a,b)=>(scores.get(b.id)??0)-(scores.get(a.id)??0)||a.id.localeCompare(b.id)).slice(0,8);metrics.narrowingStages++;
        frame.candidates=frame.candidates.filter(c=>actions.some(a=>a.id===c.id));
      } else if(actions.length>8)actions=actions.slice(0,8);
      if(localityEscape&&!actions.some(a=>a.id===localityEscape.id)){actions.push(localityEscape);frame.candidates.push({id:localityEscape.id,kind:localityEscape.kind,facts:world.description(localityEscape)}); }
      metrics.candidatesNarrowed+=actions.length;
      actions=[...actions,stop];frame.candidates.push({id:stop.id,kind:stop.kind,facts:stop.reason});
      let action:Action|undefined;
      if(policy==='jev') {
        let scheduling:Action|undefined;
        if(options.verificationAware&&world.patch.length&&(phase==='Compose'||phase==='Verify')){
         const response=await evaluate({state:frame as unknown as JevRequest['state'],questions:Object.fromEntries(['patchPlausiblyComplete','anotherEditLikelyUseful','verificationLikelyInformative','currentPatchLikelyRegression','rollbackPreferred'].map(key=>[key,{type:'noul' as const,instructions:key+' given the existing finite patch, original issue, and bounded exact evidence. This estimate cannot establish correctness.'}]))});distributions.push(response.answers);
         const p=(key:string)=>{const a=response.answers[key];return a?.type==='noul'?a.noul:0;};
         if(p('rollbackPreferred')>.8&&p('currentPatchLikelyRegression')>.7)scheduling=actions.find(a=>a.kind==='RollbackPatch');
         else if(p('anotherEditLikelyUseful')>.5&&p('patchPlausiblyComplete')<.7)scheduling=actions.find(a=>a.kind==='ContinuePatch');
         else if(p('verificationLikelyInformative')>.5&&p('patchPlausiblyComplete')>.5)scheduling=actions.find(a=>a.kind==='VerifyPatch'||a.kind==='VerifyAffectedRegion');
        }
        const decision=await choose(frame,actions,evaluate);distributions.push(decision.answers);action=scheduling??decision.action;
        // Exact lifecycle obligations outrank an uncertain semantic action choice.
        // A mutation always gets its enumerated check; confidence cannot discharge it.
        if(phase==='Verify'&&world.verification.revision!==world.revision)action=actions.find(a=>a.kind==='VerifyAffectedRegion');
        const goal=decision.answers.goalSatisfied;
        if(phase==='Stop'&&world.verification.passed&&world.verification.revision===world.revision&&goal?.type==='noul'&&goal.noul>=.90)action=actions.find(a=>a.kind===(world.exactVerifier?.verificationScope==='cheap'?'SubmitPatch':'StopSuccess'));
        if(actions.length===1&&actions[0].kind==='NeedsGeneration')action=actions[0];
        if(options.boundedExploration&&!world.patch.length&&(phase==='Transform'||phase==='Inspect')&&(!action||action.kind==='NeedsGeneration'))action=actions.find(a=>a.kind==='Relocalize');
        if(options.boundedExploration&&action)flat=0;
        if(!action){flat++;if(decision.needsGeneration||flat>=2){emit('NeedsGeneration','finish');return terminal('NeedsGeneration','Flat/unknown action distribution after bounded evidence');}action=actions.find(a=>a.kind==='InspectFile'||a.kind==='InspectSymbol'||a.kind==='Revert'||a.kind==='RollbackLast'||a.kind==='Relocalize');if(!action)return terminal('NeedsGeneration','No supported legal semantic move');}
        if(action.kind==='SubmitPatch'){if(!world.patch.length)return terminal('NeedsGeneration','No candidate patch to submit');trajectory.push({action:'SubmitPatch',file:world.focus?world.file(world.focus.file).path:undefined,edits:world.patch.length});metrics.actionFamilies.SubmitPatch=(metrics.actionFamilies.SubmitPatch??0)+1;return terminal('Submitted');}
        if(action.kind==='StopSuccess'){
          const support=decision.answers.goalSatisfied;
          const choice=decision.answers.bestAction;
          // Provisional reconciliation of two independent semantic signals, NOT
          // statistical calibration: concentrated finish choice plus positive goal
          // support, or strong goal support. Exact checks remain mandatory.
          const concentrated=choice?.type==='choice'&&choice.choice==='ASuccess'&&(choice.probabilities.ASuccess??0)>=.90&&(choice.probabilities.unknown??0)<=.05;
          if(support?.type!=='noul'||!(support.noul>=.90||support.noul>=.50&&concentrated))return terminal('NeedsGeneration','Exact checks green but semantic goal support remains uncertain');
        }
      } else action=baselineChoice(policy,frame,actions.filter(a=>a.kind!=='NeedsGeneration'),metrics.steps+1+(options.seed??0))??stop;
      if(!action)return terminal('NeedsGeneration','No finite action');
      const nextAction=action;
      const selectedEdit=nextAction.kind==='ApplyEdit'?world.edits.find(e=>e.id===nextAction.edit):undefined;
      const selectedSymbol=nextAction.kind==='InspectSymbol'?world.symbols.find(s=>s.id===nextAction.symbol):undefined;
      trajectory.push({action:nextAction.kind,file:nextAction.kind==='InspectFile'?world.file(nextAction.file).path:world.focus?world.file(world.focus.file).path:undefined,symbol:selectedSymbol?.name,edits:world.edits.length,selectedEdit:selectedEdit?{family:selectedEdit.family,from:selectedEdit.from,to:selectedEdit.to,description:selectedEdit.description}:undefined});
      previousAction=nextAction.id;metrics.actionFamilies[nextAction.kind]=(metrics.actionFamilies[nextAction.kind]??0)+1;emit('action-selected','finish');
      if(nextAction.kind==='NeedsGeneration'){emit('NeedsGeneration','finish');return terminal('NeedsGeneration',world.edits.length?'Unsupported semantic operation or inadequate finite candidates':'No legal type-filtered repair in current grammar');}
      if(nextAction.kind==='StopSuccess'){if(!world.verification.passed||world.verification.revision!==world.revision)throw new Error('Stale verification cannot finish');emit('success','finish');return terminal('Success');}
      const before:Phase=phase;
      if((nextAction.kind==='VerifyAffectedRegion'||nextAction.kind==='VerifyPatch')){let checked=await verify();if(checked.passed&&!world.exactVerifier&&world.checks.length>1)checked=await verify(true);phase=checked.passed?'Stop':'Recover';previousResult={kind:'verification',passed:checked.passed};}
      else {
        if(nextAction.kind==='ApplyEdit')emit('mutation','start');
        phase=await timed(()=>world.execute(nextAction));previousResult={kind:nextAction.kind};
        if(nextAction.kind==='InspectFile') {metrics.reads++;metrics.searchExpansions++;world.rejected.add(`inspect:${nextAction.file}`);}
        if(nextAction.kind==='InspectFamily')metrics.searchExpansions++;
        if(nextAction.kind==='InspectSymbol') {metrics.reads++;world.rejected.add(`symbol:${nextAction.symbol}`);}
        if(nextAction.kind==='ApplyEdit'){metrics.transformAttempts++;metrics.mutations++;const family=world.original!.edit.family;metrics.actionFamilies[family]=(metrics.actionFamilies[family]??0)+1;emit('mutation','finish');}
        if(nextAction.kind==='Revert'||nextAction.kind==='RollbackLast')metrics.reverts++;
        if(nextAction.kind==='RollbackPatch')metrics.reverts+=frame.patchState?.edits.length??0;
      }
      if(phase!==before)metrics.phaseTransitions++;
      if(phase==='Transform'&&!world.edits.length){
        if(world.symbols.some(s=>!world.rejected.has(`symbol:${s.id}`)))phase='Inspect';
        else {world.advanceRegion();if(world.legal('Localize').length)phase='Localize';}
      }
    }
    return terminal('Exhausted','Step budget');
  } catch(error) {
    if(error instanceof Error&&error.message==='Jev budget exhausted')return terminal('Exhausted','Jev budget exhausted');
    if(error instanceof ExactVerificationUnavailable)return terminal('BenchmarkBootstrapFailure','Host-owned canonical verifier unavailable');
    if(options.signal?.aborted)return terminal('Cancelled');
    // Do not substitute a generative model, emit raw provider error, or manufacture success.
    return terminal('ProviderFailure',error instanceof Error&&/^(TypeSafe|Jev|No Fabric)/.test(error.message)?safeText(error.message,160):'Provider or deterministic action unavailable');
  }
}
