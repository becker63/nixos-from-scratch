import { CompactClient, MorphClient, WarpGrepClient } from "@morphllm/morphsdk";
import {
  MORPH_API_KEY,
  MORPH_API_URL,
  MORPH_COMPACT_TIMEOUT,
  MORPH_TIMEOUT,
  MORPH_WARP_GREP_TIMEOUT,
} from "./config.js";

export let morph: MorphClient | null = null;
export let warpGrep: WarpGrepClient | null = null;
export let compactClient: CompactClient | null = null;

export function initMorphClients(): void {
  if (!MORPH_API_KEY) {
    morph = null;
    warpGrep = null;
    compactClient = null;
    return;
  }
  morph = new MorphClient({ apiKey: MORPH_API_KEY, timeout: MORPH_TIMEOUT });
  warpGrep = new WarpGrepClient({
    morphApiKey: MORPH_API_KEY,
    morphApiUrl: MORPH_API_URL,
    timeout: MORPH_WARP_GREP_TIMEOUT,
  });
  compactClient = new CompactClient({
    morphApiKey: MORPH_API_KEY,
    morphApiUrl: MORPH_API_URL,
    timeout: MORPH_COMPACT_TIMEOUT,
  });
}

export function morphReady(): boolean {
  return Boolean(MORPH_API_KEY && morph && warpGrep && compactClient);
}

initMorphClients();
