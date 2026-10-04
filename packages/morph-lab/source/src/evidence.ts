import {
  lstat,
  readFile,
  realpath,
  mkdtemp,
  mkdir,
  writeFile,
  rm,
} from "node:fs/promises";
import { join, relative, resolve, dirname, isAbsolute } from "node:path";
import { tmpdir } from "node:os";
export interface Candidate {
  id: string;
  path: string;
  start: number;
  end: number;
  text: string;
  source: "native" | "warpgrep";
}
export interface Inspection {
  files: string[];
  native: Candidate[];
  limits: string[];
}
export interface AtlasSearchProvider {
  search(task: string, repo: string): Promise<Candidate[]>;
} // Later structural alternative. No Atlas implementation in v1.
export function secretPath(path: string): boolean {
  return path
    .split(/[\\/]/)
    .some(
      (part) =>
        /^\.env(?:\..*)?$/i.test(part) ||
        /^\.(?:aws|ssh|gnupg|npmrc|netrc|pgpass|htpasswd|git|omp|pi|codex|config)$/i.test(
          part,
        ) ||
        /^(?:credentials|auth|secrets?)(?:\.(?:json|ya?ml|toml|ini))?$/i.test(
          part,
        ) ||
        /^id_(?:rsa|dsa|ecdsa|ed25519)$/i.test(part) ||
        /\.(?:pem|key|p12|pfx)$/i.test(part),
    );
}
export async function safePath(repo: string, path: string): Promise<string> {
  const root = await realpath(repo),
    target = resolve(root, path);
  if (secretPath(path) || secretPath(target))
    throw Error("Secret path refused");
  const rel = relative(root, target);
  if (rel === ".." || rel.startsWith("../") || isAbsolute(rel))
    throw Error("Path escapes repository");
  let existing = target,
    actual: string | null = null;
  for (;;) {
    const info = await lstat(existing).catch(() => null);
    if (info) {
      actual = await realpath(existing).catch(() => null);
      if (!actual) throw Error("Unsafe dangling symlink");
      break;
    }
    if (existing === root) throw Error("Repository unavailable");
    existing = dirname(existing);
  }
  if (actual) {
    const relActual = relative(root, actual);
    if (
      secretPath(actual) ||
      relActual === ".." ||
      relActual.startsWith("../") ||
      isAbsolute(relActual)
    )
      throw Error("Unsafe symlink");
  }
  return target;
}
function command(args: string[], repo: string) {
  const p = Bun.spawnSync(args, {
    cwd: repo,
    stdout: "pipe",
    stderr: "pipe",
    timeout: 3000,
    env: { PATH: process.env.PATH!, HOME: process.env.HOME! },
    maxBuffer: 512000,
  });
  if (p.exitCode !== 0) throw Error("Repository inspection failed");
  return p.stdout.toString();
}
/** Git supplies an allowlist. Only small regular source/test files become evidence. */
export async function inspect(task: string, repo: string): Promise<Inspection> {
  const paths = command(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
    repo,
  )
    .split("\0")
    .filter(Boolean);
  const files: string[] = [],
    native: Candidate[] = [],
    limits: string[] = [];
  const symbols = [
    ...task.matchAll(
      /`([A-Za-z_$][\w$]*)`|\b(?:function|symbol|class|method)\s+([A-Za-z_$][\w$]*)|\b([a-z]+[A-Z][A-Za-z0-9_$]*|[a-z]+_[a-z_]+)\b/g,
    ),
  ].map((m) => m[1] ?? m[2] ?? m[3]);
  const tokens = [...new Set(symbols)].slice(0, 4);
  for (const path of [...new Set(paths)].sort()) {
    if (files.length >= 128) {
      limits.push("Only first 128 eligible source files inspected");
      break;
    }
    if (
      secretPath(path) ||
      !/\.(?:[cm]?[jt]sx?|py|go|rs|zig|java|rb|c|h|cpp|md|json|toml|flix|nix)$/.test(
        path,
      ) ||
      /^(?:node_modules|upstream|\.git|\.tmp)\//.test(path)
    )
      continue;
    let full: string;
    try {
      full = await safePath(repo, path);
    } catch {
      continue;
    }
    const info = await lstat(full);
    if (!info.isFile() || info.size > 64000) {
      limits.push(`Skipped large/nonregular file: ${path}`);
      continue;
    }
    files.push(path);
    if (!tokens.length) continue;
    // Exact rg lookup, argv array, no shell interpolation and no secret files.
    const p = Bun.spawnSync(
      ["rg", "-n", "-F", ...tokens.flatMap((t) => ["-e", t]), "--", full],
      {
        stdout: "pipe",
        stderr: "pipe",
        timeout: 1000,
        maxBuffer: 32000,
        env: { PATH: process.env.PATH! },
      },
    );
    if (p.exitCode !== 0 && p.exitCode !== 1)
      throw Error("Native search failed");
    const lineNumbers = p.stdout
      .toString()
      .split("\n")
      .filter(Boolean)
      .map((line) => Number(line.split(":")[0]))
      .filter(Number.isFinite);
    if (!lineNumbers.length) continue;
    const lines = (await readFile(full, "utf8")).split("\n");
    const start = Math.max(1, lineNumbers[0] - 4),
      end = Math.min(lines.length, start + 30);
    native.push({
      id: "",
      path,
      start,
      end,
      text: lines
        .slice(start - 1, end)
        .join("\n")
        .slice(0, 4000),
      source: "native",
    });
  }
  return {
    files,
    native: native.slice(0, 3).map((c, i) => ({ ...c, id: `candidate_${i}` })),
    limits,
  };
}
/** WarpGrep explores a bounded mirror with no credentials, symlinks, or unrelated files. */
export async function publicMirror(
  repo: string,
  files: string[],
): Promise<{ root: string; dispose: () => Promise<void> }> {
  const root = await mkdtemp(join(tmpdir(), "morph-evidence-"));
  try {
    for (const path of files) {
      const src = await safePath(repo, path);
      const text = await readFile(src, "utf8");
      if (Buffer.byteLength(text) > 64000) continue;
      const dest = join(root, path);
      await mkdir(dirname(dest), { recursive: true });
      await writeFile(dest, text);
    }
  } catch (error) {
    await rm(root, { recursive: true, force: true });
    throw error;
  }
  return { root, dispose: () => rm(root, { recursive: true, force: true }) };
}
