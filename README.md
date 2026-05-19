# Taylor Johnson / `becker63`

> Infrastructure, security, and AI-infra engineer focused on making complex systems legible, reproducible, and safer to operate.

I build tools that move uncertainty out of people's heads and into inspectable artifacts: static graphs, typed configs, reproducible environments, fuzzing harnesses, telemetry traces, run bundles, and release-style reports.

- Portfolio: [becker63.digital](https://www.becker63.digital)
- Writing: [essays and project notes](https://www.becker63.digital)
- GitHub: [@becker63](https://github.com/becker63)
- Last refreshed: 2026-05-19

## What I Build

- Platform, infrastructure, and security systems that are easier to reason about under pressure.
- AI evaluation tooling that treats agent changes like release candidates instead of vibes.
- Developer interfaces that compress operational ambiguity into explicit, inspectable entrypoints.
- Technical writing that makes low-level behavior and system tradeoffs legible without flattening them.

## Flagship Work

### [searchbench-go](https://github.com/becker63/searchbench-go)

Go/Pkl experiment surface for evaluating agentic code-search systems with bundled artifacts, typed domain models, and promotion-style reports.

- Why it matters: It turns agent evaluation into a release-engineering problem: baseline, candidate, regressions, artifacts, and promotion decisions.
- Stack: Go
- Last push: 2026-05-19
- GitHub: `becker63/searchbench-go`

### [searchbench](https://github.com/becker63/searchbench)

Deterministic Python harness for comparing baseline and candidate retrieval policies with scoring, telemetry, and reproducible run results.

- Why it matters: It shows how AI evaluation becomes more useful when scoring, cost, and failure state are explicit instead of anecdotal.
- Stack: Python
- Last push: 2026-04-21
- GitHub: `becker63/searchbench`

### [designing-for-two](https://github.com/becker63/designing-for-two)

Typed control-plane experiments around KCL, Crossplane, Buck2, and Nix to make infrastructure coordination more legible.

- Why it matters: It captures a core belief of mine: less expressive power can be a win when it buys local reasoning and coordination clarity.
- Stack: Python
- Last push: 2026-02-15
- GitHub: `becker63/designing-for-two`

### [nftables-structure-fuzzer](https://github.com/becker63/nftables-structure-fuzzer)

Structure-aware Nim/Nix fuzzing harness for Linux firewall semantics, libnftnl object construction, and Netlink serialization boundaries.

- Why it matters: It traces security authority across the userland-to-kernel seam rather than pretending the important behavior starts only at packet time.
- Stack: Nim
- Last push: 2026-02-15
- GitHub: `becker63/nftables-structure-fuzzer`

### [blog](https://github.com/becker63/blog)

Custom Next.js + MDX writing system for technical essays, diagrams, search, and static rendering.

- Why it matters: It is both a publishing surface and a technical artifact for communicating systems work with diagrams, search, and controlled rendering.
- Stack: TypeScript
- Last push: 2026-05-19
- GitHub: `becker63/blog`

### [nixos-from-scratch](https://github.com/becker63/nixos-from-scratch)

Flake-based NixOS and packaging experiments, including an Asahi Linux workstation on Apple Silicon.

- Why it matters: It is ongoing proof that I like owning the full stack of my tooling, from packages and wrappers down to hardware-specific configuration.
- Stack: Nix
- Last push: 2026-05-19
- GitHub: `becker63/nixos-from-scratch`


## Recent Writing

- [Derivations Are Better Than Skills](https://www.becker63.digital/Blogs/derivations-are-better-than-skills) — Skills tell an agent what to try. Derivations encode what exists. When I want durable capability, I trust the second one more.  
  Published: 2026-05-18 · Tags: tech, nix, ai
- [I Installed OpenCode So I Could Run Nx](https://www.becker63.digital/Blogs/i-installed-opencode-so-i-could-run-nx) — Packaging Cursor Agent, open-cursor, and an OpenCode provider stack as Nix artifacts because I wanted an agent surface as legible and forceful as Nx.  
  Published: 2026-05-18 · Tags: tech, nix, ai, nx
- [You Are Giving Your AI Cognitive Overload](https://www.becker63.digital/Blogs/ai-cognitive-overload) — Using Buck2 and Nix to turn repository operations into a small graph of sanctioned actions instead of a pile of debugging commands.  
  Published: 2026-05-14 · Tags: tech, ai, build-systems
- [Running the Latest Zed on a Platform That Hates Me](https://www.becker63.digital/Blogs/zed) — Getting bleeding-edge Zed running on NixOS, Asahi Linux, Wayland, and Apple Silicon because I wanted to try the new agent features before my package set caught up.  
  Published: 2026-05-09 · Tags: tech, nix, linux

Writing snapshot: 9 published posts. Current themes: ai (3), nix (3), build-systems (1), linux (1).

## GitHub Snapshot

| Public repos | Followers | Following | Stars given | Pinned repos |
| --- | --- | --- | --- | --- |
| 106 | 21 | 7 | 644 | 6 |

## Current Surface Area

- [becker63/tcp-reassembly-experiments](https://github.com/becker63/tcp-reassembly-experiments) — Low-level networking experiments around TCP stream reconstruction and packet boundary behavior.  
  C · 0 stars · updated 2024-07-06
- [becker63/designing-for-two](https://github.com/becker63/designing-for-two) — Typed control-plane experiments around KCL, Crossplane, Buck2, and Nix to make infrastructure coordination more legible.  
  Python · 1 stars · updated 2026-02-15
- [becker63/blog](https://github.com/becker63/blog) — Custom Next.js + MDX writing system for technical essays, diagrams, search, and static rendering.  
  TypeScript · 0 stars · updated 2026-05-19
- [becker63/home_lab](https://github.com/becker63/home_lab) — Home infrastructure experiments around reproducible systems, services, and local platform ownership.  
  Nix · 0 stars · updated 2026-02-15
- [becker63/home_network](https://github.com/becker63/home_network) — Typed network and infrastructure modeling work with an emphasis on legibility.  
  KCL · 0 stars · updated 2026-02-15
- [becker63/nftables-structure-fuzzer](https://github.com/becker63/nftables-structure-fuzzer) — Structure-aware Nim/Nix fuzzing harness for Linux firewall semantics, libnftnl object construction, and Netlink serialization boundaries.  
  Nim · 0 stars · updated 2026-02-15

## Recently Active Repos

- [becker63/nixos-from-scratch](https://github.com/becker63/nixos-from-scratch) — Flake-based NixOS and packaging experiments, including an Asahi Linux workstation on Apple Silicon.  
  Nix · updated 2026-05-19
- [becker63/blog](https://github.com/becker63/blog) — Custom Next.js + MDX writing system for technical essays, diagrams, search, and static rendering.  
  TypeScript · updated 2026-05-19
- [becker63/searchbench-go](https://github.com/becker63/searchbench-go) — Go/Pkl experiment surface for evaluating agentic code-search systems with bundled artifacts, typed domain models, and promotion-style reports.  
  Go · updated 2026-05-19
- [becker63/iterative-context](https://github.com/becker63/iterative-context) — Agent and retrieval experiments centered on structured context gathering and evaluation.  
  Python · updated 2026-05-18
- [becker63/jaad](https://github.com/becker63/jaad) — Just Another AI DAW  
  TypeScript · updated 2026-05-13
- [becker63/searchbench](https://github.com/becker63/searchbench) — Deterministic Python harness for comparing baseline and candidate retrieval policies with scoring, telemetry, and reproducible run results.  
  Python · updated 2026-04-21

## Language Analytics

![Weighted language stats](stats/leaderboard_by_weighted.png)

The chart above is generated automatically from my GitHub repositories on a schedule. It is useful as a rough signal for where time is going, not as a proxy for importance.
