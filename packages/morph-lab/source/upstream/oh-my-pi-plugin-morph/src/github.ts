import {
  GITHUB_REPO_API_URL,
  GITHUB_REPO_SEARCH_URL,
  GITHUB_REPO_SUGGESTION_LIMIT,
  GITHUB_RESOLVER_TIMEOUT,
} from "./config.js";

export type PublicRepoContextSearchArgs = {
  search_term: string;
  owner_repo?: string;
  github_url?: string;
  branch?: string;
};

export type GitHubRepo = string;

export type GitHubRepoSuggestion = {
  fullName: string;
  htmlUrl: string;
  description?: string;
  stars: number;
  ownerLogin: string;
  name: string;
};

export type GitHubRepoLookupResult =
  | {
      status: "found";
      fullName: string;
      defaultBranch?: string;
      htmlUrl?: string;
    }
  | {
      status: "not_found";
      detail: string;
    }
  | {
      status: "unavailable";
      detail: string;
    };

export const GITHUB_OWNER_REPO_PATTERN = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

export function tokenizeSuggestionQuery(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length >= 2);
}

export function buildGitHubSuggestionQueries(
  repo: GitHubRepo,
  searchTerm: string,
): string[] {
  const [owner, repoName] = repo.split("/");
  const searchTokens = tokenizeSuggestionQuery(searchTerm).slice(0, 3);
  const queries = new Set<string>();

  if (owner) queries.add(`user:${owner}`);
  if (owner && repoName) queries.add(`${repoName} user:${owner}`);
  if (repoName) queries.add(repoName);
  if (searchTokens.length > 0 && repoName) {
    queries.add(`${repoName} ${searchTokens.join(" ")}`);
  }

  return Array.from(queries).slice(0, 4);
}

export function formatPublicRepoResolutionFailure(
  repo: GitHubRepo,
  _detail?: string,
  suggestions: GitHubRepoSuggestion[] = [],
): string {
  const parts: string[] = [
    `Repository not found: ${repo}\n\nThis repository does not exist or is private. Do NOT keep guessing other repo names.`,
  ];
  if (suggestions.length > 0) {
    const list = suggestions.map((s) => `- ${s.fullName}${s.description ? ` - ${s.description}` : ""}`).join("\n");
    parts.push(`Public repos found under this org:\n${list}\n\nIf one of these looks right, retry with that owner_repo.`);
  }
  parts.push(`If the package or SDK is closed-source or private:\n- Check the ecosystem registry or package page for repository metadata before guessing more names\n- Use the registry that matches the environment: npm for Node/TypeScript, crates.io for Rust, PyPI for Python, pkg.go.dev for Go, etc.\n- The real source repo may be under a different org or name\n- Stop trying variations and report that the source is not publicly available`);
  return parts.join("\n\n");
}

export function resolvePublicRepoLocator(
  args: PublicRepoContextSearchArgs,
): { repo: GitHubRepo } | { error: string } {
  const ownerRepo = args.owner_repo?.trim();
  const githubUrl = args.github_url?.trim();

  if (ownerRepo && githubUrl) {
    return {
      error: `Error: Provide either owner_repo or github_url, not both.

Use owner_repo for values like "owner/repo" or github_url for full URLs like "https://github.com/owner/repo".`,
    };
  }

  if (!ownerRepo && !githubUrl) {
    return {
      error: `Error: Missing repository target.

Provide exactly one of:
- owner_repo: "owner/repo"
- github_url: "https://github.com/owner/repo"`,
    };
  }

  if (ownerRepo) {
    if (!GITHUB_OWNER_REPO_PATTERN.test(ownerRepo)) {
      return {
        error: `Error: owner_repo must be a GitHub repository in "owner/repo" format.

Received: "${ownerRepo}"

Examples:
- "owner/repo"
- "org/project"
- "team/package"

If you have a full URL, use github_url instead.`,
      };
    }

    return { repo: ownerRepo };
  }

  let parsed: URL;
  try {
    parsed = new URL(githubUrl!);
  } catch {
    return {
      error: `Error: github_url must be a valid GitHub repository URL.

Received: "${githubUrl}"

Example:
- "https://github.com/owner/repo"`,
    };
  }

  if (!["github.com", "www.github.com"].includes(parsed.hostname)) {
    return {
      error: `Error: github_url must point to github.com.

Received host: "${parsed.hostname}"

Example:
- "https://github.com/owner/repo"`,
    };
  }

  const pathParts = parsed.pathname
    .split("/")
    .map((part) => part.trim())
    .filter(Boolean);

  if (pathParts.length < 2) {
    return {
      error: `Error: github_url must include both owner and repository name.

Received: "${githubUrl}"

Example:
- "https://github.com/owner/repo"`,
    };
  }

  const owner = pathParts[0]!;
  const repoName = pathParts[1]!.replace(/\.git$/, "");
  const canonicalRepo = `${owner}/${repoName}`;

  if (!GITHUB_OWNER_REPO_PATTERN.test(canonicalRepo)) {
    return {
      error: `Error: github_url did not resolve to a valid GitHub owner/repo locator.

Received: "${githubUrl}"`,
    };
  }

  return { repo: canonicalRepo };
}

function githubHeaders(): Record<string, string> {
  return {
    Accept: "application/vnd.github+json",
    "User-Agent": "oh-my-pi-plugin-morph",
  };
}

async function withGitHubTimeout<T>(
  fn: (signal: AbortSignal) => Promise<T>,
  upstream?: AbortSignal,
): Promise<T> {
  const ctrl = new AbortController();
  const abort = () => ctrl.abort();
  const timer = setTimeout(abort, GITHUB_RESOLVER_TIMEOUT);
  if (upstream?.aborted) abort();
  upstream?.addEventListener("abort", abort, { once: true });
  try {
    return await fn(ctrl.signal);
  } finally {
    clearTimeout(timer);
    upstream?.removeEventListener("abort", abort);
  }
}

export async function lookupGitHubRepository(
  repo: GitHubRepo,
  signal?: AbortSignal,
): Promise<GitHubRepoLookupResult> {
  return withGitHubTimeout(async (signal) => {
    try {
      const response = await fetch(`${GITHUB_REPO_API_URL}/${repo}`, {
        headers: githubHeaders(),
        signal,
      });

      if (response.status === 404) return { status: "not_found", detail: "GitHub repository not found" };
      if (!response.ok) return { status: "unavailable", detail: `GitHub repo lookup failed with status ${response.status}` };

      const body = (await response.json()) as {
        full_name?: string;
        default_branch?: string;
        html_url?: string;
      };

      return {
        status: "found",
        fullName: body.full_name || repo,
        defaultBranch: body.default_branch,
        htmlUrl: body.html_url,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown GitHub repo lookup error";
      return { status: "unavailable", detail: message };
    }
  }, signal);
}

export async function fetchGitHubRepoSuggestions(
  repo: GitHubRepo,
  searchTerm: string,
  signal?: AbortSignal,
): Promise<GitHubRepoSuggestion[]> {
  return withGitHubTimeout(async (signal) => {
    const queries = buildGitHubSuggestionQueries(repo, searchTerm);

    const results = await Promise.all(
      queries.map(async (query) => {
        const url = new URL(GITHUB_REPO_SEARCH_URL);
        url.searchParams.set("q", query);
        url.searchParams.set("sort", "stars");
        url.searchParams.set("order", "desc");
        url.searchParams.set("per_page", String(GITHUB_REPO_SUGGESTION_LIMIT));

        const response = await fetch(url.toString(), { headers: githubHeaders(), signal });
        if (!response.ok) return [];

        const body = (await response.json()) as {
          items?: Array<{
            full_name?: string;
            html_url?: string;
            description?: string | null;
            stargazers_count?: number;
            name?: string;
            owner?: { login?: string };
          }>;
        };

        return (body.items || []).filter(
          (item) => item.full_name && item.html_url && item.name && item.owner?.login,
        );
      }),
    );

    const candidates = new Map<string, GitHubRepoSuggestion>();
    for (const items of results) {
      for (const item of items) {
        if (!candidates.has(item.full_name!)) {
          candidates.set(item.full_name!, {
            fullName: item.full_name!,
            htmlUrl: item.html_url!,
            description: item.description || undefined,
            stars: item.stargazers_count || 0,
            ownerLogin: item.owner!.login!,
            name: item.name!,
          });
        }
      }
    }

    return Array.from(candidates.values()).slice(0, GITHUB_REPO_SUGGESTION_LIMIT);
  }, signal);
}
