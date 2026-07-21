{ pkgs }:

let
  opencodeOpenSpecCommands = [
    "opsx-apply"
    "opsx-archive"
    "opsx-explore"
    "opsx-import"
    "opsx-propose"
    "opsx-sync"
  ];

  opencodeOpenSpecSkills = [
    "openspec-apply-change"
    "openspec-archive-change"
    "openspec-explore"
    "openspec-propose"
    "openspec-sync-specs"
  ];

  opencodeOpenSpecFiles = pkgs.runCommand "opencode-openspec-files-1.5.0"
    {
      nativeBuildInputs = [
        pkgs.nodejs
        pkgs.gnutar
        pkgs.gzip
      ];
      openspecSrc = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@fission-ai/openspec/-/openspec-1.5.0.tgz";
        hash = "sha512-SLZkyF51gFYkISufZKaka0X04z4y/WCjPOcCB+EC7tALd0TC+7V76BOIzWOSIOhdhBWwh5EMIBhrgLnugIh1DA==";
      };
    }
    ''
    mkdir -p "$out"
    mkdir -p src
    tar -xzf "$openspecSrc" -C src

    OUT="$out" node --input-type=module <<'EOF'
    import fs from "node:fs";
    import path from "node:path";
    import { opencodeAdapter } from "./src/package/dist/core/command-generation/adapters/opencode.js";
    import {
      generateSkillContent,
      getCommandContents,
      getSkillTemplates,
    } from "./src/package/dist/core/shared/skill-generation.js";

    const out = process.env.OUT;
    const version = JSON.parse(fs.readFileSync("./src/package/package.json", "utf8")).version;
    const workflows = ["explore", "apply", "sync", "archive", "propose"];

    fs.mkdirSync(path.join(out, "commands"), { recursive: true });
    fs.mkdirSync(path.join(out, "skills"), { recursive: true });

    for (const command of getCommandContents(workflows)) {
      const file = path.basename(opencodeAdapter.getFilePath(command.id));
      fs.writeFileSync(path.join(out, "commands", file), opencodeAdapter.formatFile(command));
    }

    fs.writeFileSync(
      path.join(out, "commands", "opsx-import.md"),
      [
        "---",
        "description: Import a pasted OpenSpec dump into the correct local change files",
        "---",
        "",
        "Import a pasted OpenSpec-style dump from ChatGPT, Codex, Claude, notes, or another assistant into proper local OpenSpec files.",
        "",
        "This command is intentionally optimized for dumping. The user may paste a large raw block after `/opsx-import` with little or no setup.",
        "",
        "**Input:** Everything after `/opsx-import` is the source dump. It may include a change name, proposal, design, tasks, delta specs, requirements, scenarios, or mixed prose. If the dump is missing, ask the user to paste it.",
        "",
        "**Required behavior:** Use the `openspec-import-dump` skill. Treat the pasted dump as source evidence, not authoritative structure. Preserve every concrete detail from the dump unless it is an exact duplicate or pure assistant boilerplate.",
        "",
        "**Workflow:**",
        "",
        "1. Preserve every minute detail: constraints, examples, edge cases, filenames, commands, domain names, rationale, alternatives, uncertainties, acceptance criteria, and caveats.",
        "2. Infer the change name when it is obvious. Ask one focused question only when ambiguity would create the wrong change or capability.",
        "3. Discover the local OpenSpec store and paths with the OpenSpec CLI instead of guessing.",
        "4. If the change does not exist, create it with `openspec new change <change-name>`.",
        "5. Use `openspec status --change <change-name> --json` and `openspec instructions <artifact-id> --change <change-name> --json` to resolve output files.",
        "6. Normalize the dump into proposal, design, tasks, and/or delta specs according to local OpenSpec conventions without summarizing away facts or collapsing distinct details.",
        "7. Prefer full-file writes for generated OpenSpec artifacts when clearer and faster.",
        "8. Remove only generic assistant boilerplate, exact duplicates, and meta commentary; preserve uncertainty notes, tradeoffs, and hedging when they carry product or implementation meaning.",
        "9. Do not implement app/source code in this command; only import planning/spec artifacts.",
        "10. After writing, audit with `jj status` and `jj diff --stat` when the repo uses jj.",
        "11. Validate only when the dump or user asks for validation, or when structure is uncertain.",
        "",
        "**Output:** Briefly report the change name, files written, assumptions, and suggested next command, usually `/opsx-apply <change-name>`.",
      ].join("\\n"),
    );

    for (const { template, dirName } of getSkillTemplates(workflows)) {
      const dir = path.join(out, "skills", dirName);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, "SKILL.md"), generateSkillContent(template, version));
    }
    EOF

        import_skill="$out/skills/openspec-import-dump"
        mkdir -p "$import_skill"

        cat > "$import_skill/SKILL.md" <<'EOF'
    ---
    name: openspec-import-dump
    description: Import a pasted OpenSpec-style dump from ChatGPT or another assistant into the correct local OpenSpec change files. Use when the user pastes proposal/design/tasks/spec text and wants it normalized, split into files, written to resolved OpenSpec paths, or prepared for OpenSpec validation.
    ---

    # OpenSpec Dump Import

    Use this skill when the user pastes a large OpenSpec-ish draft from ChatGPT/Codex/Claude and wants it turned into proper local OpenSpec files.

    The pasted dump is source evidence, not authoritative structure. Preserve every concrete detail, but follow the local OpenSpec CLI, schema instructions, and resolved paths.

    ## Detail preservation

    Do not summarize away useful information. Preserve every minute detail from the dump unless it is an exact duplicate or pure assistant wrapper text.

    Preserve:

    - concrete constraints, limits, defaults, thresholds, and configuration values
    - filenames, paths, commands, flags, package names, protocol names, model names, and domain-specific identifiers
    - examples, counterexamples, edge cases, acceptance criteria, scenarios, and failure modes
    - rationale, tradeoffs, alternatives considered, risks, caveats, open questions, and uncertainty notes
    - sequencing notes, migration notes, compatibility notes, validation notes, and operational requirements
    - subtle distinctions between similar requirements; do not collapse them unless they are truly identical

    When the local OpenSpec format needs shorter sections, move detail to the most appropriate artifact instead of deleting it. For example, put operational nuance in design, observable behavior in specs, implementation sequencing in tasks, and product framing in proposal.

    ## Routing

    - Use `@fast` or AFT tools to inspect the existing `openspec/` structure and find nearby examples.
    - Use `@medium` for writing or updating OpenSpec files.
    - Use `@heavy` only if the dump contains conflicting requirements, unclear architecture, or irreversible scope decisions.

    ## Intake

    1. Identify the likely change name, schema, and artifacts in the paste:
       - proposal
       - design
       - tasks
       - delta specs
       - requirements/scenarios
       - capability names
       - migration notes or acceptance criteria
    2. If the change name is missing, infer a kebab-case name from the user-visible goal.
    3. Ask one focused question only when ambiguity would create the wrong capability or wrong change name. Otherwise proceed and state the assumption.

    ## Source-of-truth commands

    Before writing files, use the OpenSpec CLI to discover local paths and artifact rules. Do not guess file locations from memory.

    Useful commands:

    ```bash
    openspec list --json
    openspec store list --json
    openspec new change <change-name>
    openspec status --change <change-name> --json
    openspec instructions <artifact-id> --change <change-name> --json
    openspec validate --change <change-name>
    ```

    If the repo uses a standalone OpenSpec store, discover it with `openspec store list --json` and pass `--store <id>` to commands that accept it.

    ## Import workflow

    1. Check whether the change already exists.
       - If it exists, read `openspec status --change <name> --json`.
       - If it does not exist, run `openspec new change <name>`.
    2. Run `openspec status --change <name> --json`.
    3. For each artifact you need to create or update, run:

       ```bash
       openspec instructions <artifact-id> --change <name> --json
       ```

    4. Read any dependency/context files listed by the instructions output.
    5. Write the resolved output files from the instructions output. Never write to a guessed path when the CLI provides `resolvedOutputPath`, `existingOutputPaths`, `changeRoot`, or `artifactPaths`.
    6. Normalize the pasted content into local OpenSpec conventions without losing detail:
       - proposal: concise problem, goal, scope, non-goals, impact
       - design: architecture, data flow, tradeoffs, risks, validation plan
       - tasks: actionable checklist items using `- [ ]`
       - specs: `ADDED`, `MODIFIED`, `REMOVED`, or `RENAMED Requirements`
       - scenarios: `WHEN`/`THEN` style where appropriate
    7. Remove only generic ChatGPT boilerplate, exact duplicate sections, and meta commentary.
    8. Preserve user intent, domain-specific names, intentional phrasing, and meaningful uncertainty notes exactly when they look intentional.
    9. If a detail does not fit cleanly in one artifact, preserve it in another artifact rather than dropping it.
    10. If validation is expected for this import, run `openspec validate --change <name>` and fix structural errors. If validation uncovers product ambiguity, pause with the smallest useful question.

    ## Delta spec rules

    - Put new capabilities under `## ADDED Requirements`.
    - Put changes to existing capabilities under `## MODIFIED Requirements`.
    - Use `## REMOVED Requirements` only when the dump clearly asks to delete behavior.
    - Use `## RENAMED Requirements` only when there is an explicit old/new requirement name.
    - Do not invent compatibility requirements unless the dump or local architecture requires them.

    ## Output style

    After import, report:

    - change name
    - files written
    - assumptions made
    - validation result, if run
    - any unresolved ambiguities
    - suggested next command, usually `/opsx-apply <change-name>` or `/opsx-explore <topic>`

    Keep the final summary short; the files are the source of truth.

    ## Guardrails

    - Do not treat pasted formatting as authoritative.
    - Do not create app/source-code changes; this skill only imports planning/spec artifacts.
    - Do not silently overwrite a meaningful existing artifact with a weaker pasted version. Merge intentionally.
    - Do not expand scope beyond the pasted intent unless the local OpenSpec instructions require missing structure.
    - Do not compress distinct requirements into a vague umbrella requirement just to make the artifact shorter.
    - Do not discard caveats, alternatives, examples, or edge cases because they seem small; small details often encode the user's real intent.
    - Prefer one good import with clear assumptions over a long back-and-forth.
    EOF
  '';

in
{
  inherit opencodeOpenSpecFiles;

  xdgConfigFiles =
    (builtins.listToAttrs (map (name: {
      name = "opencode/commands/${name}.md";
      value.source = "${opencodeOpenSpecFiles}/commands/${name}.md";
    }) opencodeOpenSpecCommands))
    // (builtins.listToAttrs (map (name: {
      name = "opencode/skills/${name}";
      value.source = "${opencodeOpenSpecFiles}/skills/${name}";
    }) opencodeOpenSpecSkills))
    // {
      "opencode/skills/openspec-import-dump".source =
        "${opencodeOpenSpecFiles}/skills/openspec-import-dump";
    };
}
