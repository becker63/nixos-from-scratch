import { readFile } from "node:fs/promises";
/** Parse one allowlisted credential. No shell evaluation, dotenv export, or logging. */
export async function loadNamedKey(
  name: "MORPH_API_KEY" | "OPENROUTER_API_KEY",
  path: string | URL = process.env.MORPH_LAB_ENV_FILE ??
    new URL("../.env", import.meta.url),
): Promise<string | undefined> {
  let key = process.env[name];
  if (!key) {
    let text: string;
    try {
      text = await readFile(path, "utf8");
    } catch {
      return undefined;
    }
    const matches = text
      .split(/\r?\n/)
      .filter((line) =>
        new RegExp(`^\\s*(?:export\\s+)?${name}\\s*=`).test(line),
      );
    if (matches.length > 1) throw new Error(`Duplicate ${name}`);
    key = matches[0]
      ?.replace(new RegExp(`^\\s*(?:export\\s+)?${name}\\s*=\\s*`), "")
      .trim();
    if (key?.startsWith('"') || key?.startsWith("'")) {
      const quote = key[0];
      if (!key.endsWith(quote)) throw new Error(`Invalid ${name} quoting`);
      key = key.slice(1, -1);
    } else key = key?.replace(/\s+#.*$/, "").trim();
  }
  if (key && !/\s/.test(key)) {
    process.env[name] = key;
    return key;
  }
  return undefined;
}

export const loadMorphKey = (path?: string | URL) =>
  loadNamedKey("MORPH_API_KEY", path);
export const loadOpenRouterKey = (path?: string | URL) =>
  loadNamedKey("OPENROUTER_API_KEY", path);
