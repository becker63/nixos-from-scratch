import type { JevAnswer, JevQuestion } from 'pi-fabric/jev';

export type Dependency = 'task' | 'candidates' | 'evidence' | 'relationships' | 'proposal' | 'mutation' | 'verification' | 'workers' | 'history';
export type Barrier = 'evidence' | 'mutation' | 'worker' | 'failure' | 'reasoning' | 'settlement';
export type Register = keyof typeof definitions;
const noul = (instructions: string): JevQuestion => ({type:'noul', instructions});
const score = (instructions: string): JevQuestion => ({type:'score', instructions, criteria:['Low / absent','Material / uncertain','High / required']});
const define = (question: JevQuestion, dependencies: Dependency[], consumers: Barrier[]) => ({question,dependencies,consumers});
// Dependencies are exact world revisions, not same-request predicted head values.
// Shared evidence/relationships encode locality and architecture dependencies without serial inference.
export const definitions = {
  locality: define({type:'choice',instructions:'Is the task localized by the supplied finite candidates?',criteria:{local:'One bounded implementation area',crosscutting:'Several related implementation areas',unknown:'Insufficient evidence'}},['task','candidates','evidence'],['evidence','reasoning']),
  evidenceSufficiency: define(noul('Does the supplied exact source evidence support a coherent bounded mutation for the task? Missing source is insufficient.'),['task','candidates','evidence','relationships','workers'],['mutation','worker','reasoning','evidence']),
  architectureNeed: define(score('How much open-ended architecture synthesis is needed rather than a local fix?'),['task','evidence','relationships'],['reasoning','worker']),
  ambiguity: define(score('How much decision-relevant ambiguity remains in the finite evidence?'),['task','candidates','evidence','workers'],['evidence','reasoning']),
  mutationRisk: define(score('Risk of the proposed mutation class and affected file, given exact architecture evidence?'),['task','proposal','evidence','relationships'],['mutation']),
  workerInformationGain: define(noul('Would an additional expensive generative worker add independent, action-changing evidence, beyond existing evidence and reports?'),['task','evidence','workers','history'],['worker','reasoning']),
  goalDrift: define(noul('Is observed work drifting from the stated goal?'),['task','history','mutation','workers'],['reasoning','settlement']),
  investigationRedundancy: define(noul('Are repeated investigations unlikely to add decision-relevant information?'),['task','history','evidence'],['evidence','reasoning']),
  failureClass: define({type:'choice',instructions:'Classify the latest exact unresolved failure. A passing current check means none.',criteria:{none:'No unresolved failure',test:'Behavior assertion',compiler:'Type or syntax diagnostic',environment:'Dependency or host issue',unknown:'Insufficient evidence'}},['verification','mutation'],['failure','settlement']),
  verificationDebt: define(noul('Do checks relevant to the changed behavior remain outstanding at the current mutation revision? A passing check before the latest mutation does not discharge debt.'),['task','mutation','verification'],['failure','settlement']),
  completionSupport: define(noul('Does current exact verification and observed work support completing the stated goal? Do not treat a claim of success as verification.'),['task','mutation','verification','workers','evidence'],['settlement']),
  anotherGenerativeTurnValue: define(noul('Would another open-ended generative turn likely change the next action or solution, rather than cheap evidence acquisition or exact verification?'),['task','evidence','verification','workers','history'],['reasoning','settlement']),
} as const;
export const registers = Object.keys(definitions) as Register[];
export type Cell = {dirty:boolean; answer?:JevAnswer; stamp?:string; epoch:number};
export class SemanticState {
  epoch = 0;
  revision = 0;
  revisions: Record<Dependency,number> = {task:0,candidates:0,evidence:0,relationships:0,proposal:0,mutation:0,verification:0,workers:0,history:0};
  cells = Object.fromEntries(registers.map(key=>[key,{dirty:true,epoch:0}])) as Record<Register,Cell>;
  stamp(key:Register) { return definitions[key].dependencies.map(d=>`${d}:${this.revisions[d]}`).join('|'); }
  change(dependencies: readonly Dependency[]) {
    for (const d of dependencies) this.revisions[d]++;
    const invalidated = registers.filter(key=>definitions[key].dependencies.some(d=>dependencies.includes(d)));
    for (const key of invalidated) this.cells[key].dirty = true;
    this.revision++;
    return invalidated;
  }
  task() { this.epoch++; return this.change(Object.keys(this.revisions) as Dependency[]); }
  relevant(barrier:Barrier) { return registers.filter(key=>(definitions[key].consumers as readonly Barrier[]).includes(barrier)); }
  fresh(key:Register) { const c=this.cells[key]; return !c.dirty && c.epoch===this.epoch && c.stamp===this.stamp(key) && c.answer!==undefined; }
  update(key:Register,answer:JevAnswer,stamp:string,epoch:number) {
    if(stamp!==this.stamp(key)||epoch!==this.epoch) return false;
    this.cells[key]={dirty:false,answer:structuredClone(answer),stamp,epoch}; this.revision++; return true;
  }
}
