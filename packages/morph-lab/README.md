# Morph lab with Jev

Local source snapshot from `~/projects/morph-bot`, checkpoint `8635c2a`. Stanley's bounded-decision ideas were adapted; its implementation was not copied. The unchanged MIT Morph plugin is included under `source/upstream/oh-my-pi-plugin-morph`, with its license. This remains a single bounded `FindRelevantCode` workflow plus a Morph-enabled Pi fallback.

```sh
nix build .#packages.aarch64-linux.morph-lab --no-link --print-out-paths
morph-lab --no-agent 'Find function printCandidateLadder'
morph-lab 'Find where tree reuse candidates are ranked'
```

The package is exported on Linux ARM64 and x64 and added to Home Manager's package list. Only the standalone package was built and installed in the user profile; no system closure was built or activated. Existing kernel pins and the Factory credential launcher are unchanged.

## Runtime configuration

Defaults:

- Decision provider: OpenRouter `typesafe/jev-1.13`, `POST https://openrouter.ai/api/alpha/decisions`.
- Repository: `$HOME/projects/attuneflix-tree-reuse`; override with `--repo PATH` or `MORPH_LAB_DEFAULT_REPO`.
- Credential file: `$HOME/nixos-from-scratch/.env`; override with `MORPH_LAB_ENV_FILE`.
- Specialists and Pi generation: Morph, using `MORPH_API_KEY`. Pi retains `morph-dsv41flash`.
- Mutable Pi state: `$XDG_STATE_HOME/morph-lab/omp`, or `$HOME/.local/state/morph-lab/omp`.

`MORPH_LAB_DECISION_PROVIDER=morph` explicitly selects the original System One provider. Provider errors never switch models. Jev responses accept only the requested model or its dated 1.13 snapshot and retain returned probabilities, confidence, and `usage.cost`.

The ignored `.env` contains only the copied named `MORPH_API_KEY` and `OPENROUTER_API_KEY` entries (the latter from `~/projects/attune/.env`), permissions `0600`. Keys are parsed at runtime, never interpolated by Nix, logged, put in command arguments, or included in build inputs. Each key is sent only to its provider. This is a copy: rotation in the original file does not automatically update the installed configuration.

The source fileset is explicit; neither the lab's `.env`, dependencies, receipts, nor temporary directories are copied as source. Dependencies are installed separately from the frozen Bun lockfile into a fixed-output derivation, with scripts disabled and no credentials. All Linux CPU optional packages are included so the dependency hash is independent of the target architecture. Bun 1.3.14 is pinned and patched to the Nix loader.

## Observed live checks

Jev's three-type public fixture smoke succeeded. A read-only localization in Attuneflix found `src/TreeReuse.flix` with two decisions, native search, no specialists or general generation, and returned billing data. Installed-package receipts are retained in the original lab's `receipts/` directory. Localization does not prove code correctness or modify the repository.

To refresh this snapshot, copy only the lab's source files and `scripts/plugin-host.ts`, the two dependency manifests, and the plugin's source/license/manifest. Never copy the full workspace or `.env`. If dependencies change, recompute the fixed-output dependency hash. Build only this package; repository safeguards prohibit system builds and pin changes.

## Pi chat default

`morph-lab` now opens Pi's interactive terminal UI in Attuneflix with GPT-6.1 Sol medium over the existing Codex subscription login. `morph-find` retains the previous bounded CLI. `/morph-status` shows the three Morph worker models and four roles. Jev decisions and the unchanged specialist plugin are available in chat and workers.

Runtime-only Codex access is read from `~/.codex/auth.json` (or CODEX_HOME); no login credential is copied into this package, persisted by the extension, or refreshed behind the active Codex CLI. Relaunch after refreshing an expired login. Runtime keys remain in the ignored root `.env`. Native Pi task fan-out is capped at 32, five minutes per worker, and workers do not spawn nested tasks. Kimi is excluded after an incoherent full-context smoke response. No system closure build/switch is needed.
