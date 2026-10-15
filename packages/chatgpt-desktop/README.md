# ChatGPT desktop

Packages OpenAI's official Linux ARM64 desktop app for this Asahi host. The
versioned Debian artifact is checked against a fixed SHA-256 hash. The package
patches the ELF interpreter and library paths for NixOS, including the bundled
Codex, Node runtime, and native modules. The `chatgpt` launcher uses the system
graphics drivers and registers the upstream desktop entry.

Build and install just this package without building or switching a system:

```sh
nix build --no-write-lock-file --no-link path:.#chatgpt-desktop
nix profile add --no-write-lock-file path:.#chatgpt-desktop
chatgpt
```

Home Manager also includes the package for future user environment deployments.
The separate Codex CLI remains managed by npm; this app retains its own bundled
Codex executable.

To update, select a versioned ARM64 artifact from OpenAI's Debian package index,
update `version` and `src.hash`, and rebuild only this package. No flake input
changes are needed. NixOS is outside OpenAI's formally supported distributions;
native Wayland support is experimental, so the launcher leaves upstream's
XWayland default intact. To try native Wayland, run
`chatgpt --ozone-platform=wayland`.

Source: <https://learn.chatgpt.com/docs/linux/linux-app>.
