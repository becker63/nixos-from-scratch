import type { JevAnswer, JevRequest, JevResponse } from 'pi-fabric/jev';
import { SemanticState, type Register } from './semantic-state.js';
export type PolicyMode = 'jev' | 'constant' | 'heuristic' | 'off';
export type ActionClass = 'mutation' | 'worker' | 'completion';
export const thresholds = {sufficient:.80,risk:.80,worker:.90,completion:.90,debt:.10,drift:.10,anotherTurn:.15,admission:.70}; // Provisional, NOT calibrated.
export function shape(answer: JevAnswer) {
  const probabilities = answer.type==='noul' ? {yes:answer.noul,no:1-answer.noul} : answer.probabilities;
  const sorted=Object.entries(probabilities).sort((a,b)=>b[1]-a[1]);
  return {top:sorted[0]?.[1]??0,runnerUp:sorted[1]?.[1]??0,margin:(sorted[0]?.[1]??0)-(sorted[1]?.[1]??0),unknown:probabilities.unknown??0,confidence:answer.type==='noul'?undefined:answer.confidence};
}
export function probability(state:SemanticState,key:Register) { const a=state.fresh(key)?state.cells[key].answer:undefined; return a?.type==='noul'?a.noul:undefined; }
export function allow(state:SemanticState,action:ActionClass,exact:{verified:boolean;hasEvidence:boolean;unresolvedFailure:boolean}) {
  const p=(key:Register)=>probability(state,key);
  const high=(key:Register,t:number)=>p(key)!==undefined&&p(key)!>=t;
  const low=(key:Register,t:number)=>p(key)!==undefined&&p(key)!<=t;
  if(action==='mutation') {
    const risk=state.fresh('mutationRisk')?state.cells.mutationRisk.answer:undefined;
    return exact.hasEvidence&&high('evidenceSufficiency',thresholds.sufficient)&&risk?.type==='score'&&(risk.probabilities['0']??0)>=thresholds.risk;
  }
  if(action==='worker') return high('evidenceSufficiency',thresholds.sufficient)&&high('workerInformationGain',thresholds.worker);
  const failure=state.fresh('failureClass')?state.cells.failureClass.answer:undefined;
  return exact.verified&&!exact.unresolvedFailure&&failure?.type==='choice'&&failure.choice==='none'&&shape(failure).margin>=.5&&high('completionSupport',thresholds.completion)&&low('verificationDebt',thresholds.debt)&&low('goalDrift',thresholds.drift)&&low('anotherGenerativeTurnValue',thresholds.anotherTurn);
}
export type Evaluator = (request:JevRequest)=>Promise<JevResponse>;
// Same controller and exact-fact policy, interchangeable semantic estimator.
export function baseline(mode:'constant'|'heuristic'):Evaluator { return async request=>{
  const world=request.state as Record<string,unknown>;
  const verification=world.verification as {currentPassed?:boolean};
  const verified=verification?.currentPassed===true;
  const answers:Record<string,JevAnswer>={};
  for(const [key,q] of Object.entries(request.questions)) {
    if(q.type==='noul') {
      let yes=['evidenceSufficiency','completionSupport'].includes(key);
      if(key==='verificationDebt') yes=!verified;
      if(key==='completionSupport') yes=verified;
      if(key.startsWith('admit_')) yes=mode==='constant'||key.endsWith('_0')||key.endsWith('_1')||key.endsWith('_2');
      answers[key]={type:'noul',noul:yes?.99:.01};
    } else if(q.type==='choice') { const choice=key==='failureClass'?(verified?'none':'unknown'):Object.keys(q.criteria)[0]; answers[key]={type:'choice',choice,confidence:.99,probabilities:Object.fromEntries(Object.keys(q.criteria).map(k=>[k,k===choice?1:0]))}; }
    else answers[key]={type:'score',score:0,confidence:1,probabilities:{'0':1,'1':0,'2':0},legend:{'0':q.criteria[0],'1':q.criteria[1],'2':q.criteria[2]}};
  }
  return {model:`baseline-${mode}`,answers,usage:{input_tokens:0,output_tokens:0}};
}; }
