import type {JevResponse} from 'pi-fabric/jev';
export type Id=string;
export type TaskKind='Locate'|'Inspect'|'Repair'|'Verify'|'Unsupported';
export type NavigationResult={kind:'LocatedFile'|'LocatedSymbol'|'RepositoryFacts';path:string;symbol?:string;facts?:Array<{path:string;line?:number;text?:string}>};
export type Phase='Localize'|'Inspect'|'Transform'|'Verify'|'Compose'|'Recover'|'Stop';
export type Grammar='J0'|'J1'|'J2'|'J3'|'J4';
export type FileTarget={id:Id;path:string;family:Id;bytes:number};
export type SymbolTarget={id:Id;file:Id;name:string;start:number;end:number;excerpt:string;references?:string[]};
export type Edit={id:Id;file:Id;node:Id;family:'CompilerFix'|'ReplaceOperator'|'ReplaceVariable'|'ReplaceCallable'|'InsertArgument'|'ReplaceLiteral'|'NegateExpression'|'ReplaceMember'|'ReplaceArgument'|'RemoveArgument'|'PermuteArguments'|'ReplaceReturn'|'ReplaceCondition';provenance?:{kind:'ASTDonor'|'TypeChecker'|'Compiler';file:string;start:number;end:number};start:number;end:number;from:string;to:string;description:string;typeValid:true};
export type Action=
 | {id:Id;kind:'InspectFamily';family:Id}
 | {id:Id;kind:'InspectFile';file:Id}
 | {id:Id;kind:'InspectSymbol';symbol:Id}
 | {id:Id;kind:'ApplyEdit';edit:Id}
 | {id:Id;kind:'VerifyAffectedRegion';target:Id}
 | {id:Id;kind:'Revert';edit:Id}
 | {id:Id;kind:'ContinuePatch'}
 | {id:Id;kind:'Relocalize'}
 | {id:Id;kind:'VerifyPatch';target:Id}
 | {id:Id;kind:'RollbackLast'}
 | {id:Id;kind:'RollbackPatch'}
 | {id:Id;kind:'StopSuccess'}
 | {id:Id;kind:'SubmitPatch'}
 | {id:Id;kind:'NeedsGeneration';reason:string};
export type PatchState={baseRevision:number;edits:Array<{id:Id;family:Edit['family'];file:Id}>;changedFiles:Id[];depthLimit:number};
export type Check={id:Id;path:string};
export type Verification={checked?:Array<{path:string;passed:boolean}>;scope?:'canonical'|'cheap';revision:number;passed:boolean;testsRun:number;failures:string[];exitStatus:number|null;fingerprint:string};
// Trusted host supplies bounded exact results; the policy never selects commands.
export type ExactVerifier={verificationScope:'canonical'|'cheap';verify(workspace:string):Promise<{passed:boolean;failures:string[];fingerprint:string}>};
export class ExactVerificationUnavailable extends Error {}
export type Budgets={maxSteps:number;maxEvaluations:number;maxWallMs:number;maxTransforms:number;maxTests:number;maxRepeated:number};
export const defaults:Budgets={maxSteps:24,maxEvaluations:32,maxWallMs:120000,maxTransforms:6,maxTests:10,maxRepeated:2};
export type Metrics={steps:number;jevEvaluations:number;jevHeads:number;jevInputTokens:number;jevOutputTokens:number;jevLatencyMs:number;reportedCost:number|null;deterministicMs:number;phaseTransitions:number;candidatesBefore:number;candidatesAfter:number;candidatesNarrowed:number;reads:number;searchExpansions:number;transformAttempts:number;mutations:number;reverts:number;checks:number;failures:number;repeatedStates:number;codexCalls:number;workerCalls:number;wallMs:number;actionFamilies:Record<string,number>;narrowingStages:number};
export type Frame={task:string;phase:Phase;grammar:Grammar;focus?:{file:Id;symbol?:Id;node?:Id};patchState?:PatchState;candidates:Array<{id:Id;kind:string;facts:string}>;evidence:Array<{id:Id;excerpt:string}>;diagnostics:string[];previousAction?:Id;previousResult?:{passed?:boolean;kind:string};mutations:Array<{id:Id;family:string;revision:number}>;verification:Verification;budget:{stepsRemaining:number;jevCallsRemaining:number;wallClockRemainingMs:number};loopDetected:boolean};
export type Terminal={kind:'Success'|'Submitted'|'NeedsGeneration'|'Exhausted'|'ProviderFailure'|'Cancelled'|'NotFound'|'Unsupported'|'BenchmarkBootstrapFailure';taskKind:TaskKind;patchState?:PatchState;retrieval?:{generated:Array<{id:string;path:string;signals:unknown[];score:number}>;compressed:string[];ranked:string[];rankStages:Array<{limit:number;paths:string[];scores:Array<{id:string;score:number}>}>;ms:number};shadowClassification?:{kind:TaskKind;relation:string;answers?:JevResponse['answers']};result?:NavigationResult;trajectory?:Array<{action:string;file?:string;symbol?:string;edits?:number;selectedEdit?:{family:string;from:string;to:string;description:string}}>;phase:Phase;focusedTargets:Id[];evidenceCollected:number;attemptedActionFamilies:string[];missingCapability?:string;metrics:Metrics;verification:Verification;distributions:JevResponse['answers'][]};
export type Trace={kind:'candidate-generation'|'jev-policy'|'action-selected'|'mutation'|'verification'|'NeedsGeneration'|'success';phase:'start'|'finish';count:number;passed:boolean};
