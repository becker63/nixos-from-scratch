{
  config,
  inputs',
  lib,
  pkgs,
  ...
}:

let
  upstreamDroid = inputs'.llm-agents.packages.droid;
  jevMcp = pkgs.callPackage ../../../packages/jev-mcp { };
  droid = pkgs.callPackage ../../../packages/factory-droid {
    droid = upstreamDroid;
  };
  factoryConfig = pkgs.callPackage ../../../packages/factory-config { };
  factoryInstructions = ''
    ## Jev semantic coprocessor

    `jev_decide` is available globally. Use it freely for useful bounded semantic choice, noul, or score judgments, and batch related questions with shared state. Do deterministic work deterministically; do not use Jev for generation, arithmetic, or Factory model selection. Never send secrets. Treat probabilities and confidence as evidence, not proof; for consequential ambiguity, verify or escalate rather than blindly trusting a score.

    ## Delegation preference

    Prefer Factory's native worker, explorer, and subagent mechanisms for focused delegated work. Keep delegated tasks bounded and machine-verifiable where possible. Do not make the user manually choose models unless necessary.

    ## Flash-first execution

    Assume GLM-5.3 Flash can do ordinary engineering. Stay on Flash through multi-file work and normal machine-verifiable iteration: build/test/compiler failures, retries, long tasks, and large repositories are not escalation triggers. Use deterministic tools and Jev to reduce generative reasoning.

    Escalate with `Task(... complexity="heavy")` when two genuinely distinct semantic approaches fail, the mental model contradicts machine evidence, a stable invariant is repeatedly violated, a focused reread still leaves the specification misunderstood, consequential architecture choices require synthesis, accepted compacted state conflicts with live artifacts, evidence is contradictory, or the next decision is difficult to verify cheaply. Send compact evidence, not raw log dumps. Repeated identical commands, flaky infrastructure, dependency failures, and ordinary build/test failures are not distinct semantic failures.

    After Heavy/full GLM resolves the blocker, record the decision durably and return implementation to Flash. Do not permanently upgrade a long trajectory because of one hard episode. Use `conceptual-escalator` only when benchmark evidence invalidates the governing hypothesis, a major architecture pivot has weak verification, full GLM cannot resolve two distinct semantic failures, or compacted state cannot be reconciled from artifacts. It reviews; it does not implement routine work.
  '';
  conceptualEscalator = ''
    ---
    name: conceptual-escalator
    description: Rare conceptual escalation for contradictory evidence, architecture pivots, or unresolved semantic failures
    model: gpt-5.6-sol
    reasoningEffort: max
    tools: read-only
    mcpServers: ["jev"]
    ---

    Act as a rare, read-oriented conceptual reviewer. Do not implement routine work or continue into bulk implementation. Inspect only the supplied compact evidence, identify the conceptual blocker, and resolve architecture, hypothesis, or state contradictions. Return a concise decision packet that explicitly separates facts, hypotheses, the recommended decision, and the next cheapest discriminating experiment or change. Use Jev only for bounded semantic judgments; never use it to select a model tier.
  '';
in
{
  home.packages = [
    droid
    jevMcp
    pkgs.xdg-utils
  ];

  home.file.".factory/AGENTS.md".text = factoryInstructions;
  home.file.".factory/droids/conceptual-escalator.md".text = conceptualEscalator;

  home.activation.configureFactory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${factoryConfig}/bin/factory-config-merge \
      --factory-dir ${lib.escapeShellArg "${config.home.homeDirectory}/.factory"} \
      --jev-command ${lib.escapeShellArg "${jevMcp}/bin/jev-mcp"}
  '';
}
