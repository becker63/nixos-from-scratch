import type {JevAnswer,JevQuestion,JevRequest,JevResponse} from 'pi-fabric/jev';
import type {Action,Frame} from './state.js';
import {shape,type Evaluator} from '../semantic-policy.js';
export type PurePolicy='jev'|'random'|'heuristic';
export type Decision={action?:Action;needsGeneration:boolean;answers:JevResponse['answers'];narrowed:number};
const noul=(instructions:string):JevQuestion=>({type:'noul',instructions});
export async function choose(frame:Frame,actions:Action[],evaluate:Evaluator):Promise<Decision> {
  const questions:Record<string,JevQuestion>={
    bestAction:{type:'choice',instructions:'Select the legal semantic macro-action most likely to advance the user task using exact evidence. Never invent source text or IDs. unknown means no supported useful move.',criteria:Object.fromEntries([...frame.candidates.map(c=>[c.id,c.facts]),['unknown','No useful supported action in this finite grammar']])},
    evidenceSufficient:noul('Is the bounded evidence sufficient to select a repair action?'),
    likelyProgress:noul('Is a supplied legal action likely to change the relevant behavior in the desired direction?'),
    likelyRegression:noul('Would the most plausible supplied mutation likely regress already verified behavior?'),
    needVerification:noul('Is an exact check now needed for the current mutation revision?'),
    likelyLooping:noul('Is this state repeating an unproductive action/result cycle?'),
    goalSatisfied:noul('Does exact current verification support the user goal? A green test is necessary but not automatically sufficient.'),
    unknownActionRequired:noul('Does the task require new source logic or another semantic operation unavailable in the finite legal grammar?'),
  };
  const response=await evaluate({state:frame as unknown as JevRequest['state'],questions});
  const answer=response.answers.bestAction;
  const unknown=response.answers.unknownActionRequired;
  const sufficient=response.answers.likelyProgress;
  const valid=answer?.type==='choice'&&Number.isFinite(answer.confidence)&&Object.keys(answer.probabilities).every(k=>Object.hasOwn((questions.bestAction as Extract<JevQuestion,{type:'choice'}>).criteria,k));
  const supported=valid&&answer.type==='choice'&&answer.choice!=='unknown'&&shape(answer).top>=.55&&shape(answer).margin>=.10;
  const action=supported?actions.find(a=>a.id===(answer as Extract<JevAnswer,{type:'choice'}>).choice):undefined;
  return {action,needsGeneration:!action&&unknown?.type==='noul'&&unknown.noul>=.75&&sufficient?.type==='noul'&&sufficient.noul<.5,answers:response.answers,narrowed:actions.length};
}
// Reproducible dumb comparisons: no semantic provider, same legality and verification.
export function baselineChoice(mode:'random'|'heuristic',frame:Frame,actions:Action[],seed:number):Action|undefined {
  if(!actions.length)return undefined;
  if(mode==='random')return actions[((seed*1664525+1013904223)>>>0)%actions.length];
  const scored=actions.map(a=>{const facts=frame.candidates.find(c=>c.id===a.id)?.facts??'';let score=0;
    if(a.kind==='InspectFile'&&/subject|parser|range|calculator/i.test(facts))score+=5;
    if(a.kind==='InspectSymbol'&&/export|function (?:pick|run|compute|valid|length|slice)/.test(facts))score+=3;
    if(a.kind==='ApplyEdit') {if(/operator <= with </.test(facts))score+=5;if(/value end instead of start/.test(facts))score+=4;if(/argument end/.test(facts))score+=4;if(/helper add instead of subtract/.test(facts))score+=4;}
    return {a,score};});
  scored.sort((a,b)=>b.score-a.score||a.a.id.localeCompare(b.a.id));return scored[0].a;
}
