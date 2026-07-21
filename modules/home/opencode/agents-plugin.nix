{ pkgs }:

let
  opencodeAgentsMdPlugin = pkgs.runCommand "opencode-agents-md-context-plugin-0.1.0" { } ''
    mkdir -p "$out"

    cat > "$out/package.json" <<'EOF'
    {
      "name": "@becker/opencode-agents-md-context",
      "version": "0.1.0",
      "type": "module",
      "main": "./server.js",
      "exports": {
        ".": "./server.js",
        "./server": "./server.js",
        "./tui": "./tui.js"
      },
      "description": "Inject repository AGENTS.md files into OpenCode system and compaction context",
      "keywords": [
        "opencode",
        "plugin",
        "agents"
      ],
      "license": "UNLICENSED"
    }
    EOF

    cat > "$out/server.js" <<'EOF'
    import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
    import { join, relative, resolve } from "node:path";

    const MAX_FILES = 12;
    const MAX_FILE_BYTES = 48 * 1024;
    const MAX_TOTAL_BYTES = 128 * 1024;
    const MAX_DEPTH = 8;
    const IGNORE_DIRS = new Set([
      ".cache",
      ".devenv",
      ".direnv",
      ".git",
      ".hg",
      ".jj",
      ".svn",
      ".zig-cache",
      "build",
      "dist",
      "node_modules",
      "result",
      "target",
      "zig-out",
    ]);

    function safeStat(path) {
      try {
        return statSync(path);
      } catch {
        return undefined;
      }
    }

    function collectAgentsFiles(root) {
      const found = [];

      function walk(dir, depth) {
        if (found.length >= MAX_FILES || depth > MAX_DEPTH) return;

        let entries;
        try {
          entries = readdirSync(dir, { withFileTypes: true }).sort((a, b) =>
            a.name.localeCompare(b.name),
          );
        } catch {
          return;
        }

        for (const entry of entries) {
          if (found.length >= MAX_FILES) return;
          if (entry.isFile() && entry.name === "AGENTS.md") {
            found.push(join(dir, entry.name));
          }
        }

        for (const entry of entries) {
          if (found.length >= MAX_FILES) return;
          if (!entry.isDirectory()) continue;
          if (IGNORE_DIRS.has(entry.name)) continue;
          walk(join(dir, entry.name), depth + 1);
        }
      }

      walk(root, 0);
      return found;
    }

    function readAgentsContext(root) {
      const files = collectAgentsFiles(root);
      if (files.length === 0) return "";

      let totalBytes = 0;
      const chunks = [];

      for (const file of files) {
        const stat = safeStat(file);
        if (!stat || !stat.isFile()) continue;
        if (totalBytes >= MAX_TOTAL_BYTES) break;

        const allowedBytes = Math.min(MAX_FILE_BYTES, MAX_TOTAL_BYTES - totalBytes);
        let content = readFileSync(file, "utf8");
        let truncated = false;

        if (Buffer.byteLength(content, "utf8") > allowedBytes) {
          content = content.slice(0, allowedBytes);
          truncated = true;
        }

        totalBytes += Buffer.byteLength(content, "utf8");
        chunks.push(
          "### " + relative(root, file) + (truncated ? " (truncated)" : "") + "\n\n" + content.trim(),
        );
      }

      if (chunks.length === 0) return "";

      return [
        "## Repository AGENTS.md Instructions",
        "",
        "The following AGENTS.md files were loaded automatically from this repository. Treat them as active project instructions. If multiple files apply, more specific nested AGENTS.md guidance overrides broader guidance for files beneath that directory.",
        "",
        chunks.join("\n\n---\n\n"),
      ].join("\n");
    }

    function appendSystem(output, text) {
      if (!text) return;
      if (Array.isArray(output.system)) {
        output.system.push(text);
        return;
      }
      if (typeof output.system === "string") {
        output.system = output.system + "\n\n" + text;
        return;
      }
      output.system = [text];
    }

    function appendCompactionContext(output, text) {
      if (!text) return;
      if (Array.isArray(output.context)) {
        output.context.push(text);
        return;
      }
      output.context = [text];
    }

    async function writeProbe(root) {
      const probePath = process.env.OPENCODE_AGENTS_MD_CONTEXT_PROBE;
      if (!probePath) return;

      const { appendFileSync } = await import("node:fs");
      appendFileSync(
        probePath,
        JSON.stringify({
          plugin: "agents-md-context",
          event: "initialized",
          root,
          time: new Date().toISOString(),
        }) + "\n",
      );
    }

    export const server = async ({ client, directory, worktree }) => {
      const root = resolve(worktree || directory || process.cwd());

      await writeProbe(root);

      await client?.app?.log?.({
        body: {
          service: "agents-md-context",
          level: "info",
          message: "AGENTS.md context plugin initialized",
          extra: { root },
        },
      }).catch(() => {});

      return {
        "experimental.chat.system.transform": async (_input, output) => {
          if (!existsSync(root)) return;
          appendSystem(output, readAgentsContext(root));
        },

        "experimental.session.compacting": async (_input, output) => {
          if (!existsSync(root)) return;
          appendCompactionContext(output, readAgentsContext(root));
        },
      };
    };

    export default {
      id: "@becker/opencode-agents-md-context",
      server,
    };
    EOF

    cat > "$out/tui.js" <<'EOF'
    export const tui = async () => {};

    export default {
      id: "@becker/opencode-agents-md-context",
      tui,
    };
    EOF
  '';

in
{
  package = opencodeAgentsMdPlugin;
  specifier = "@becker/opencode-agents-md-context@file://${opencodeAgentsMdPlugin}";
}
