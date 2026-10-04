import { lstatSync, realpathSync, type Stats } from "node:fs";
import {
  basename,
  isAbsolute,
  relative as relativePath,
  resolve as resolvePath,
  sep,
} from "node:path";
import type { WarpGrepResult } from "@morphllm/morphsdk";
import { EXISTING_CODE_MARKER } from "./config.js";

export { EXISTING_CODE_MARKER };

export function normalizeCodeEditInput(codeEdit: string): string {
  const trimmed = codeEdit.trim();
  const lines = trimmed.split("\n");

  if (lines.length < 3) return codeEdit;

  const firstLine = lines[0];
  const lastLine = lines[lines.length - 1];

  if (/^```[\w-]*$/.test(firstLine) && /^```$/.test(lastLine)) {
    return lines.slice(1, -1).join("\n");
  }

  return codeEdit;
}

function tryRealpath(p: string): string | null {
  try {
    return realpathSync(p);
  } catch {
    return null;
  }
}

function tryLstat(p: string): Stats | null {
  try {
    return lstatSync(p);
  } catch {
    return null;
  }
}

// Walk each path component of `resolved` (already proven lexically contained in
// `cwd` by the caller) starting from the real workspace root. For any component
// that is a symlink, resolve it: reject dangling symlinks (their target cannot
// be verified) and reject any symlink whose resolved real target escapes the
// real workspace root. Returns true when following the path would escape the
// workspace, so a write cannot create or truncate a file outside it.
function symlinkEscapesRoot(realRoot: string, cwd: string, resolved: string): boolean {
  const rel = relativePath(cwd, resolved);
  const components = rel.split(sep).filter((c) => c.length > 0 && c !== ".");
  let current = realRoot;
  for (const component of components) {
    current = resolvePath(current, component);
    const stat = tryLstat(current);
    if (stat === null) {
      // This component does not exist yet; the remaining suffix is new and
      // anchored inside the workspace, so no symlink can be traversed.
      return false;
    }
    if (stat.isSymbolicLink()) {
      const real = tryRealpath(current);
      // Dangling symlink (null) or a target outside the workspace escapes.
      if (real === null || escapesRoot(realRoot, real)) {
        return true;
      }
      current = real;
    }
  }
  return false;
}

function escapesRoot(root: string, target: string): boolean {
  const rel = relativePath(root, target);
  return rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel);
}

// Basename-matched secret files a read-only tool must not egress to Morph.
// A read ships the file's bytes to a remote API, so err broad: native `read`
// still works on anything refused here. Case-sensitive per the pinned contract.
const SECRET_FILE_PATTERNS: readonly RegExp[] = [
  /^\.env(\..*)?$/, // .env, .env.local, .env.production, ...
  /\.(pem|key|p12|pfx)$/, // private keys / PKCS#12 key stores
  /^id_(rsa|dsa|ecdsa|ed25519)$/, // SSH private keys
  /^\.(npmrc|netrc|pgpass|htpasswd)$/, // credential config dotfiles
  /^credentials(\.(json|ya?ml))?$/, // credentials[.json|.yaml|.yml]
];

function isSecretFile(base: string): boolean {
  return SECRET_FILE_PATTERNS.some((re) => re.test(base));
}

export function resolveReadPath(targetFilepath: string, cwd: string): string {
  const resolved = resolvePath(cwd, targetFilepath);
  if (isSecretFile(basename(resolved))) {
    throw new Error(`Refusing to read secret file: ${targetFilepath} (may contain credentials).`);
  }

  // Absolute / ../ out-of-tree reads are allowed outright and skip symlink
  // inspection entirely (pinned). For a path lexically inside the workspace,
  // refuse a symlink that aliases a secret behind an innocent name
  // (public.txt -> .env) or whose real target escapes the root.
  if (!escapesRoot(cwd, resolved)) {
    const real = tryRealpath(resolved);
    if (real !== null && isSecretFile(basename(real))) {
      throw new Error(`Refusing to read secret file: ${targetFilepath} (may contain credentials).`);
    }
    const realRoot = tryRealpath(cwd);
    if (realRoot !== null && symlinkEscapesRoot(realRoot, cwd, resolved)) {
      throw new Error(
        `Refusing to read through a symlink escaping the workspace root: ${targetFilepath}.`,
      );
    }
  }

  return resolved;
}

export function detectMarkerLeakage(
  originalCode: string,
  mergedCode: string,
  hasMarkers: boolean,
): boolean {
  return (
    hasMarkers &&
    !originalCode.includes(EXISTING_CODE_MARKER) &&
    mergedCode.includes(EXISTING_CODE_MARKER)
  );
}

export type TruncationCheck = {
  triggered: boolean;
  charLoss: number;
  lineLoss: number;
};

export function detectCatastrophicTruncation(
  originalCode: string,
  mergedCode: string,
  hasMarkers: boolean,
): TruncationCheck {
  const originalLineCount = originalCode.split("\n").length;
  const mergedLineCount = mergedCode.split("\n").length;
  const charLoss =
    (originalCode.length - mergedCode.length) / originalCode.length;
  const lineLoss = (originalLineCount - mergedLineCount) / originalLineCount;

  return {
    triggered: hasMarkers && charLoss > 0.6 && lineLoss > 0.5,
    charLoss,
    lineLoss,
  };
}

export const PLAUSIBLE_PATH_RE = /[/\\]|\.[\w]+$/;

export function isValidContext(ctx: { file: string; content: string }): boolean {
  return Boolean(ctx.file) && PLAUSIBLE_PATH_RE.test(ctx.file) && ctx.content.length > 0;
}

// Escape XML metacharacters so repository-controlled file paths and content
// cannot break out of the <file> envelope with closing tags or injected markup.
function escapeXmlText(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function escapeXmlAttr(value: string): string {
  return escapeXmlText(value).replace(/"/g, "&quot;");
}

export function formatWarpGrepResult(result: WarpGrepResult): string {
  if (!result.success) {
    return `Search failed: ${result.error || "search returned no error details."}`;
  }

  if (!result.contexts || result.contexts.length === 0) {
    return "No relevant code found. Try rephrasing your search term.";
  }

  const valid = result.contexts.filter(isValidContext);

  if (valid.length === 0) {
    const sample = result.contexts.slice(0, 3).map((c) => c.file);
    return `Search returned malformed file contexts (file values: ${JSON.stringify(sample)}).
Fallback: use \`grep\` + \`read\` for local code search.`;
  }

  const parts: string[] = [];
  parts.push("Relevant context found:");

  for (const ctx of valid) {
    const rangeStr =
      !ctx.lines || ctx.lines === "*"
        ? "*"
        : ctx.lines.map(([s, e]) => `${s}-${e}`).join(",");
    parts.push(`- ${escapeXmlText(ctx.file)}:${rangeStr}`);
  }

  parts.push("\nFile contents:\n");

  for (const ctx of valid) {
    const rangeStr =
      !ctx.lines || ctx.lines === "*"
        ? ""
        : ` lines="${ctx.lines.map(([s, e]) => `${s}-${e}`).join(",")}"`;
    parts.push(`<file path="${escapeXmlAttr(ctx.file)}"${rangeStr}>`);
    parts.push(escapeXmlText(ctx.content));
    parts.push("</file>\n");
  }

  return parts.join("\n");
}
