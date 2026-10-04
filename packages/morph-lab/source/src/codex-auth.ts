import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
export function decodeCodexAccess(value: unknown, now = Date.now()): string {
  const data = value as { auth_mode?: string; tokens?: { access_token?: unknown } };
  const token = data?.tokens?.access_token;
  if (data?.auth_mode !== "chatgpt" || typeof token !== "string")
    throw Error("Codex subscription login required: run codex login");
  try {
    const claims = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
    if (typeof claims.exp !== "number" || claims.exp * 1000 <= now + 60000)
      throw Error();
  } catch { throw Error("Codex subscription token expired or invalid: refresh your Codex login"); }
  return token;
}
/** Read access token only; never persist or rotate the active Codex refresh grant. */
export async function codexAccess(): Promise<string> {
  const path = join(process.env.CODEX_HOME ?? join(homedir(), ".codex"), "auth.json");
  let value: unknown;
  try { value = JSON.parse(await readFile(path, "utf8")); }
  catch { throw Error("Cannot read Codex subscription login: run codex login"); }
  return decodeCodexAccess(value);
}
