# BuildBuddy through OpenAI Secure MCP Tunnel

`default.nix` packages the official `v0.0.16` Linux release for ARM64 and AMD64,
including its Cloudflare companion. Both release archives are pinned by SHA-256
and checked against upstream `SHA256SUMS.txt`. No flake input or system rebuild is
required.

The package exports `tunnel-client` and `buildbuddy-tunnel-configure`. It is also
declared in Home Manager's package list for the next owner-managed activation.

## Local setup

Create a tunnel named `buildbuddy` in
[Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels).
Associate it with the ChatGPT workspace where the plugin will be used. Create a
separate **runtime** key whose principal has **Tunnels Read + Use**. The tunnel
daemon uses this runtime key; it does not need an admin key or an inference token.

Run in a terminal:

```console
buildbuddy-tunnel-configure
tunnel-client doctor --profile buildbuddy --explain
tunnel-client run --profile buildbuddy
```

Setup asks for the tunnel ID, tunnel runtime key, and dedicated BuildBuddy Reader
API key. Key prompts disable echo. It writes these owner-only local files:

- `~/.config/tunnel-client/buildbuddy.yaml`: profile containing file references.
- `~/.config/tunnel-client/buildbuddy-secrets/openai-runtime-key`: runtime key.
- `~/.config/tunnel-client/buildbuddy-secrets/buildbuddy-bearer-header`: full
  `Bearer ...` value for BuildBuddy.

`XDG_CONFIG_HOME` overrides the configuration root when set. The profile and
secret files have mode `0600`; configuration and secret directories have mode
`0700`. Setup refuses to overwrite existing configuration. No secret is an input
to the derivation or stored in the repository or Nix store.

The MCP destination is `https://becker63.buildbuddy.io/mcp`. Its static
Authorization header is injected on the BuildBuddy-facing connection. The local
health/admin listener binds an available loopback port; its URL is written to
`~/.config/tunnel-client/buildbuddy-health-url` while running. Append `/ui` to that
URL to open the client admin page. Keep the daemon running for plugin discovery
and calls. Home Manager declares a `buildbuddy-tunnel.service` user service with
owner-only permissions and the local profile as a startup condition. The service
starts at user login once configured. For an already installed service, use
`systemctl --user status buildbuddy-tunnel` and
`systemctl --user restart buildbuddy-tunnel` after changing the local profile.

In ChatGPT, add a custom MCP server with **Connection: Tunnel**, select the
`buildbuddy` tunnel, and choose **No authentication** for the ChatGPT-facing
connection. BuildBuddy authentication comes from the local header file. Tunnel
and custom MCP access remain subject to the Platform organization and ChatGPT
workspace permissions.

References:

- [Official tunnel client](https://github.com/openai/tunnel-client)
- [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
- [BuildBuddy MCP authentication](https://www.buildbuddy.io/docs/enterprise-mcp/)
