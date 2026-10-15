// Fabric async TypeScript body. Replace the synthetic observation, not the policy.
const evidence = await pi.read("fixture.txt");
const observation = { task: "Locate the implementation and assess readiness", evidence,
  candidates: ["implementation", "caller", "unknown"], workerReports: ["none"],
  checks: "No tests have run", history: "First investigation; no patch yet" };
type Action = "proceed" | "inspect_more" | "spawn_worker" | "ask_codex" |
  "retry" | "verify" | "stop";
type Decision = { kind: "decision"; action: Action } |
  { kind: "unknown/provider_failure"; action: "stop" };
const thresholds = { sufficient: 0.90, completion: 0.95, worker: 0.90,
  drift: 0.80, reasoning: 0.80, retry: 0.90, categorical: 0.80, ambiguity: 1.60 };
try {
  const vector = await jev.evaluate({ state: observation, questions: {
    localization: { type: "choice", instructions: "Which candidate owns the implementation rather than an incidental call?",
      criteria: { implementation: "Owns behavior", caller: "Only invokes behavior", unknown: "Evidence insufficient" } },
    sufficient: { type: "noul", instructions: "Is evidence sufficient to edit with a coherent architecture understanding?" },
    ambiguity: { type: "score", instructions: "How much unresolved semantic ambiguity remains?",
      criteria: ["Clear bounded change", "Some missing evidence", "Needs open-ended architecture synthesis"] },
    independence: { type: "noul", instructions: "Is there a bounded worker task meaningfully independent of Main?" },
    informationGain: { type: "noul", instructions: "Is a second Codex worker likely to add enough evidence to justify its cost?" },
    report: { type: "choice", instructions: "Which supplied worker report should enter Main context?",
      criteria: { none: "No useful report supplied", unknown: "Cannot rank supplied reports" } },
    failure: { type: "choice", instructions: "Classify any reported failure; do not infer a failed test when none ran.",
      criteria: { environment: "Host/dependency issue", regression: "Current patch likely caused failure",
        flaky: "Transient failure", compiler: "Compile/type error", test: "Behavior/assertion failure",
        none: "No failure", unknown: "Cannot classify" } },
    retryable: { type: "noul", instructions: "Does evidence support a single affordable retry of a transient failure?" },
    reasoning: { type: "noul", instructions: "Does the failure or ambiguity require generative Codex reasoning rather than deterministic remediation?" },
    drift: { type: "noul", instructions: "Is investigation likely drifting from the stated goal?" },
    redundant: { type: "noul", instructions: "Is investigation repeating a semantic failure or redundant evidence gathering?" },
    complete: { type: "noul", instructions: "Does observed verification evidence support task completion?" },
    verificationDebt: { type: "noul", instructions: "Do relevant checks or verification remain outstanding?" },
    anotherTurn: { type: "noul", instructions: "Is another generative turn likely to materially change the answer?" },
  }});
  const a = vector.answers;
  type NoulKey = { [K in keyof typeof a]: (typeof a)[K] extends { type: "noul" } ? K : never }[keyof typeof a];
  const probability = (key: NoulKey): number | undefined => {
    const value = a[key];
    return value?.type === "noul" ? value.noul : undefined;
  };
  const yes = (key: NoulKey, threshold: number) => {
    const p = probability(key); return p !== undefined && p >= threshold;
  };
  const failure = a.failure;
  const localized = a.localization;
  const ambiguity = a.ambiguity;
  let action: Action = "inspect_more";
  if (yes("drift", thresholds.drift) || yes("redundant", thresholds.drift)) action = "stop";
  else if (yes("reasoning", thresholds.reasoning) || (ambiguity?.type === "score" &&
    ambiguity.confidence >= thresholds.categorical && ambiguity.score >= thresholds.ambiguity)) action = "ask_codex";
  else if (failure?.type !== "choice" || failure.confidence < thresholds.categorical || failure.choice === "unknown") action = "inspect_more";
  else if (failure.choice !== "none") action = yes("retryable", thresholds.retry) ? "retry" : "verify";
  else if (yes("complete", thresholds.completion) && probability("verificationDebt") !== undefined &&
    probability("verificationDebt")! <= 0.05 && probability("anotherTurn") !== undefined && probability("anotherTurn")! <= 0.10) action = "stop";
  else if (yes("independence", thresholds.worker) && yes("informationGain", thresholds.worker)) action = "spawn_worker";
  else if (yes("verificationDebt", thresholds.sufficient)) action = "verify";
  else if (yes("sufficient", thresholds.sufficient) && localized?.type === "choice" &&
    localized.choice !== "unknown" && localized.confidence >= thresholds.categorical) action = "proceed";
  const decision: Decision = { kind: "decision", action };
  return { decision, thresholds, vector };
} catch {
  const decision: Decision = { kind: "unknown/provider_failure", action: "stop" };
  return { decision, thresholds };
}
