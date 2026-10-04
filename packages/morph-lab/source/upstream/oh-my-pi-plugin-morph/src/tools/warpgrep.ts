import type { WarpGrepResult } from "@morphllm/morphsdk";
import type { Static } from "@oh-my-pi/pi-ai/types";
import type {
  AgentToolResult,
  AgentToolUpdateCallback,
  ExtensionAPI,
  ExtensionContext,
  ToolDefinition,
} from "@oh-my-pi/pi-coding-agent/extensibility/extensions/types";
import { throwIfAborted, ToolAbortError } from "@oh-my-pi/pi-coding-agent/tools/tool-errors";
import { MORPH_API_KEY, MORPH_WARPGREP_ENABLED, MORPH_WARP_GREP_TIMEOUT } from "../config.js";
import { textToolResult } from "../compaction.js";
import {
  fetchGitHubRepoSuggestions,
  formatPublicRepoResolutionFailure,
  type GitHubRepoSuggestion,
  lookupGitHubRepository,
  resolvePublicRepoLocator,
} from "../github.js";
import { formatWarpGrepResult } from "../format.js";
import { warpGrep } from "../morph-clients.js";
import { withToolNote } from "../routing.js";
import { raceAbort } from "../abort.js";
import { nextMorphRetryDelay, transientMorphFailureMessage, waitForMorphRetry } from "../retry.js";

const CODEBASE_DESCRIPTION = `Fast agentic codebase search. Uses ripgrep, file reading, and directory listing across multiple turns to find relevant code contexts.

Prefer this over manual grep-and-read loops for exploratory searches like "Find the authentication flow", "How does error handling work", "Where is the database connection configured". Returns relevant file sections with line numbers.

For exact keyword searches (specific function names, variable names), use grep/ripgrep directly.`;

const GITHUB_DESCRIPTION = `Grounded code context search for public GitHub repositories. Uses Morph's hosted WarpGrep to search indexed public repos without cloning them locally.

PREFER this tool over web search or docs fetching when the question is about how an open-source library or SDK works internally. If the user asks how something works in a library or package from any ecosystem, find its GitHub repo and search it here instead of fetching docs URLs.

Use this when:
- User asks how an external library/SDK works (auth, retries, sessions, internals)
- You need to understand implementation details of any open-source dependency
- Docs URLs are failing or returning 404s — search the source instead
- User asks about a framework or tool they didn't provide a repo for — infer the canonical GitHub repo from the matching ecosystem (npm, crates.io, PyPI, pkg.go.dev, etc.) before guessing owner/repo variants

This tool is for public remote repos.

Provide exactly one repository locator:
- owner_repo: "owner/repo"
- github_url: "https://github.com/owner/repo"`;

export function makeWarpgrepCodebase(pi: ExtensionAPI) {
  const { z } = pi.zod;
  const parameters = z.object({
    search_term: z.string().describe(
      "Natural language search query describing what to find in the codebase",
    ),
  });

  return {
    name: "codebase_warpsearch",
    label: "Codebase Warpsearch",
    description: withToolNote(DESCRIPTION_OVERRIDE.CODEBASE, "codebase_warpsearch"),
    parameters,
    approval: "read",
    async execute(
      _toolCallId: string,
      params: Static<typeof parameters>,
      signal: AbortSignal | undefined,
      onUpdate: AgentToolUpdateCallback | undefined,
      ctx: ExtensionContext,
    ): Promise<AgentToolResult> {
      if (!MORPH_API_KEY || !warpGrep) {
        return textToolResult(`Error: MORPH_API_KEY not configured.

To use codebase_warpsearch, set the MORPH_API_KEY environment variable.
Get your API key at: https://morphllm.com/dashboard/api-keys`);
      }
      const client = warpGrep;

      const startTime = Date.now();

      // Drains one fresh WarpGrep generator to completion, forwarding turn
      // updates as they stream in. Invoked again for each retry attempt.
      async function runAttempt(): Promise<{ result: WarpGrepResult; turnCount: number }> {
        const generator = client.execute({
          searchTerm: params.search_term,
          repoRoot: ctx.cwd,
          streamSteps: true,
        });
        let turnCount = 0;
        for (;;) {
          throwIfAborted(signal);
          const { value, done } = await raceAbort(generator.next(), signal);
          if (done) {
            return { result: await Promise.resolve(value), turnCount };
          }
          turnCount = value.turn;
          onUpdate?.(
            textToolResult(`WarpGrep turn ${value.turn}: ${value.toolCalls?.map((tc) => tc.name).join(", ") ?? "..."}`),
          );
          pi.logger.debug(
            `WarpGrep turn ${value.turn}: ${value.toolCalls?.map((tc) => tc.name).join(", ") ?? "..."}`,
          );
        }
      }

      const retryStartTime = Date.now();
      let attemptIndex = 0;
      try {
        for (;;) {
          throwIfAborted(signal);
          let attempt: { result: WarpGrepResult; turnCount: number };
          try {
            attempt = await runAttempt();
          } catch (error) {
            const transientMessage = transientMorphFailureMessage(error);
            if (transientMessage === undefined) throw error;
            const delayMs = nextMorphRetryDelay(attemptIndex, retryStartTime, MORPH_WARP_GREP_TIMEOUT);
            if (delayMs === undefined) throw error;
            pi.logger.warn(
              `WarpGrep transient overload on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
            );
            await waitForMorphRetry(delayMs, signal);
            attemptIndex++;
            continue;
          }

          const { result, turnCount } = attempt;
          const transientMessage = transientMorphFailureMessage(result);
          const delayMs =
            transientMessage === undefined ? undefined : nextMorphRetryDelay(attemptIndex, retryStartTime, MORPH_WARP_GREP_TIMEOUT);
          if (delayMs !== undefined) {
            pi.logger.warn(
              `WarpGrep transient overload on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
            );
            await waitForMorphRetry(delayMs, signal);
            attemptIndex++;
            continue;
          }

          const duration = Date.now() - startTime;
          const contextCount = result.contexts?.length ?? 0;

          pi.logger.info(
            `WarpGrep: ${contextCount} contexts in ${turnCount} turns (${duration}ms)`,
          );

          return textToolResult(formatWarpGrepResult(result));
        }
      } catch (error) {
        if (
          error instanceof ToolAbortError ||
          (error instanceof Error && error.name === "AbortError") ||
          signal?.aborted
        ) {
          throw error instanceof Error ? error : new ToolAbortError();
        }
        const message = error instanceof Error ? error.message : String(error);
        const duration = Date.now() - startTime;
        pi.logger.error(
          `WarpGrep failed after ${duration}ms: ${message}`,
        );
        return textToolResult(`WarpGrep search failed: ${message}

Try rephrasing your search term or using grep for exact keyword searches.`);
      }
    },
  } satisfies ToolDefinition<typeof parameters>;
}

function formatPublicRepoSearchFailure(
  repo: string,
  branch: string | undefined,
  detail?: string,
): string {
  const target = branch ? `${repo}@${branch}` : repo;
  return `WarpGrep search failed for ${target}: ${detail || "no error details were provided."}

The repository was reachable, so this is a search failure, not a missing repository.
- Retry the search, optionally with a more specific search term
- If you supplied a branch, confirm it exists on ${repo}
- If failures persist, fetch the repository's docs or source another way`;
}

export function makeWarpgrepGithub(pi: ExtensionAPI) {
  const { z } = pi.zod;
  const parameters = z.object({
    search_term: z.string().describe(
      "Natural language query describing what to find or understand in the public repository",
    ),
    owner_repo: z.string().optional().describe(
      'GitHub repository in "owner/repo" format, for example "owner/repo"',
    ),
    github_url: z.string().optional().describe(
      'Full GitHub repository URL, for example "https://github.com/owner/repo"',
    ),
    branch: z.string().optional().describe(
      "Optional branch name to search instead of the repository default branch",
    ),
  });

  const workspaceRedirect = MORPH_WARPGREP_ENABLED
    ? "\n\nFor the current checked-out workspace, use codebase_warpsearch instead."
    : "";

  return {
    name: "github_warpsearch",
    label: "GitHub Warpsearch",
    description: withToolNote(GITHUB_DESCRIPTION + workspaceRedirect, "github_warpsearch"),
    parameters,
    approval: "read",
    async execute(
      _toolCallId: string,
      params: Static<typeof parameters>,
      signal: AbortSignal | undefined,
      _onUpdate: AgentToolUpdateCallback | undefined,
      _ctx: ExtensionContext,
    ): Promise<AgentToolResult> {
      if (!MORPH_API_KEY || !warpGrep) {
        return textToolResult(`Error: MORPH_API_KEY not configured.

To use github_warpsearch, set the MORPH_API_KEY environment variable.
Get your API key at: https://morphllm.com/dashboard/api-keys`);
      }

      const locator = resolvePublicRepoLocator(params);
      if ("error" in locator) {
        return textToolResult(locator.error);
      }
      const repo = locator.repo;

      const startTime = Date.now();
      throwIfAborted(signal);
      const repoLookup = await raceAbort(lookupGitHubRepository(repo, signal), signal);

      if (repoLookup.status === "not_found") {
        const suggestions = await raceAbort(
          fetchGitHubRepoSuggestions(repo, params.search_term, signal),
          signal,
        ).catch((): GitHubRepoSuggestion[] => []);
        throwIfAborted(signal);
        return textToolResult(formatPublicRepoResolutionFailure(repo, repoLookup.detail, suggestions));
      }

      if (repoLookup.status === "unavailable") {
        pi.logger.warn(`GitHub repo lookup unavailable for ${repo}: ${repoLookup.detail}`);
      }

      const retryStartTime = Date.now();
      let attemptIndex = 0;
      try {
        for (;;) {
          throwIfAborted(signal);
          let result: WarpGrepResult;
          try {
            result = await raceAbort(
              warpGrep.searchGitHub({
                searchTerm: params.search_term,
                github: repo,
                branch: params.branch,
              }),
              signal,
            );
          } catch (error) {
            const transientMessage = transientMorphFailureMessage(error);
            if (transientMessage === undefined) throw error;
            const delayMs = nextMorphRetryDelay(attemptIndex, retryStartTime, MORPH_WARP_GREP_TIMEOUT);
            if (delayMs === undefined) throw error;
            pi.logger.warn(
              `Public repo WarpGrep transient overload for ${repo} on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
            );
            await waitForMorphRetry(delayMs, signal);
            attemptIndex++;
            continue;
          }
          throwIfAborted(signal);

          const transientMessage = transientMorphFailureMessage(result);
          const delayMs =
            transientMessage === undefined ? undefined : nextMorphRetryDelay(attemptIndex, retryStartTime, MORPH_WARP_GREP_TIMEOUT);
          if (delayMs !== undefined) {
            pi.logger.warn(
              `Public repo WarpGrep transient overload for ${repo} on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
            );
            await waitForMorphRetry(delayMs, signal);
            attemptIndex++;
            continue;
          }

          const duration = Date.now() - startTime;
          const contextCount = result.contexts?.length ?? 0;

          pi.logger.info(`Public repo context: ${repo} → ${contextCount} contexts (${duration}ms)`);

          if (!result.success) {
            return textToolResult(formatPublicRepoSearchFailure(repo, params.branch, result.error));
          }

          return textToolResult(`Repository: ${repo}\n\n${formatWarpGrepResult(result)}`);
        }
      } catch (error) {
        if (
          error instanceof ToolAbortError ||
          (error instanceof Error && error.name === "AbortError") ||
          signal?.aborted
        ) {
          throw error instanceof Error ? error : new ToolAbortError();
        }
        const message = error instanceof Error ? error.message : String(error);
        const duration = Date.now() - startTime;
        pi.logger.error(`Public repo context search failed for ${repo} after ${duration}ms: ${message}`);
        return textToolResult(formatPublicRepoSearchFailure(repo, params.branch, message));
      }
    },
  } satisfies ToolDefinition<typeof parameters>;
}

const DESCRIPTION_OVERRIDE = {
  CODEBASE: CODEBASE_DESCRIPTION,
} as const;
