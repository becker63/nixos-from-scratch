# DeepSeek Harness

DSH is packaged from the published `@deepseek-ai/dsh` 0.2.0-rc.2 artifacts with
`dsh-codex` 0.3.2. Required DSH peer services are explicitly pinned in
`package.json`; `package-lock.json` and `npmDepsHash` fix the complete dependency
graph. The build checks both CLI startup and the default Web composition.

Build or install only this package; no system rebuild is needed:

```sh
nix build .#dsh --no-link --no-update-lock-file
nix profile add .#dsh --no-update-lock-file
dsh web
```

The existing `~/.bun/bin/dsh` launcher points to `~/.nix-profile/bin/dsh` so
the interactive shell's Bun-first PATH also selects the Nix package.

Profiles and sessions remain mutable under `~/.dsh`. Install the provider in each
profile you use:

```sh
dsh plugin --profile web add --save-exact dsh-codex@0.3.2
```

To use the existing Codex subscription login, merge this row into that profile's
`cordis.patch.yml`, keeping its other rows:

```yaml
- id: llm-openai-codex
  config:
    credentialFile: /home/becker/.codex/auth.json
    searchMode: live
```

Set `agent-default-model` in `~/.dsh/settings.yaml` to provider `openai-codex`
and your selected Codex model. The current setup uses `gpt-6.1-sol`. The provider
reads the CLI model catalog and refreshes the selected OAuth file in place; no
credentials belong in this repository. Avoid simultaneous token refreshes in
DSH and Codex. Logging out through the provider also affects the shared login.

Use Settings → OpenAI Codex to verify this shared login. The standalone provider
CLI's `status` checks its separate default credential file instead.

Research Graph must match the installed DSH host. For this package's
`0.2.0-rc.2` host, stop the running `dsh web`, then install the matching release:

```sh
dsh plugin --profile web add --save-exact @benz-ai-x/dsh-research-graph@0.2.0-rc.2.1
dsh web
```

Open the authenticated URL printed by DSH, enter a non-blank Session, and select
**Research Graph**. Do not use npm's unversioned `latest` or `next` tags here;
check the [upstream compatibility table](https://github.com/benz-ai-x/dsh-research-graph#installable-versions)
when changing the host version. Remove any old exact-version compatibility
exemption after replacing an incompatible release:

```sh
dsh plugin --profile web revoke-version @benz-ai-x/dsh-research-graph@0.1.5-rc.1 --dsh-version 0.2.0-rc.2
```

Published plugins may lag DSH's preview releases. Let DSH's compatibility check
skip incompatible plugins instead of forcing them to load.
