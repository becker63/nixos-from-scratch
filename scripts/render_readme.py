#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import UTC, datetime
from pathlib import Path


GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"
PORTFOLIO_URL = "https://www.becker63.digital"
BLOG_HOME_URL = PORTFOLIO_URL
BLOG_BASE_URL = f"{PORTFOLIO_URL}/Blogs"
HEADLINE = (
    "Infrastructure, security, and AI-infra engineer focused on making complex "
    "systems legible, reproducible, and safer to operate."
)
SHORT_PITCH = (
    "I build tools that move uncertainty out of people's heads and into inspectable "
    "artifacts: static graphs, typed configs, reproducible environments, fuzzing "
    "harnesses, telemetry traces, run bundles, and release-style reports."
)
FLAGSHIP_REPO_NAMES = [
    "searchbench-go",
    "searchbench",
    "designing-for-two",
    "nftables-structure-fuzzer",
    "blog",
    "nixos-from-scratch",
]
REPO_DESCRIPTION_FALLBACKS = {
    "searchbench-go": (
        "Go/Pkl experiment surface for evaluating agentic code-search systems with "
        "bundled artifacts, typed domain models, and promotion-style reports."
    ),
    "searchbench": (
        "Deterministic Python harness for comparing baseline and candidate retrieval "
        "policies with scoring, telemetry, and reproducible run results."
    ),
    "designing-for-two": (
        "Typed control-plane experiments around KCL, Crossplane, Buck2, and Nix to "
        "make infrastructure coordination more legible."
    ),
    "nftables-structure-fuzzer": (
        "Structure-aware Nim/Nix fuzzing harness for Linux firewall semantics, "
        "libnftnl object construction, and Netlink serialization boundaries."
    ),
    "blog": (
        "Custom Next.js + MDX writing system for technical essays, diagrams, search, "
        "and static rendering."
    ),
    "nixos-from-scratch": (
        "Flake-based NixOS and packaging experiments, including an Asahi Linux "
        "workstation on Apple Silicon."
    ),
    "tcp-reassembly-experiments": (
        "Low-level networking experiments around TCP stream reconstruction and packet "
        "boundary behavior."
    ),
    "home_lab": (
        "Home infrastructure experiments around reproducible systems, services, and "
        "local platform ownership."
    ),
    "home_network": (
        "Typed network and infrastructure modeling work with an emphasis on legibility."
    ),
    "iterative-context": (
        "Agent and retrieval experiments centered on structured context gathering and "
        "evaluation."
    ),
    "sat": (
        "Small TypeScript systems experiments used to probe product and interface ideas."
    ),
    "socratic": (
        "TypeScript project exploring structured interaction surfaces and tooling ideas."
    ),
    "Agent-Tldr-Munger": (
        "Tooling experiment for compressing and reshaping agent-facing context."
    ),
    "jaad": "Audio and AI experimentation around a custom DAW-style interaction surface.",
}
REPO_HEROES = {
    "searchbench-go": (
        "It turns agent evaluation into a release-engineering problem: baseline, "
        "candidate, regressions, artifacts, and promotion decisions."
    ),
    "searchbench": (
        "It shows how AI evaluation becomes more useful when scoring, cost, and "
        "failure state are explicit instead of anecdotal."
    ),
    "designing-for-two": (
        "It captures a core belief of mine: less expressive power can be a win when "
        "it buys local reasoning and coordination clarity."
    ),
    "nftables-structure-fuzzer": (
        "It traces security authority across the userland-to-kernel seam rather than "
        "pretending the important behavior starts only at packet time."
    ),
    "blog": (
        "It is both a publishing surface and a technical artifact for communicating "
        "systems work with diagrams, search, and controlled rendering."
    ),
    "nixos-from-scratch": (
        "It is ongoing proof that I like owning the full stack of my tooling, from "
        "packages and wrappers down to hardware-specific configuration."
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render README.md from TEMPLATE.md using GitHub API data."
    )
    parser.add_argument("--template", default="TEMPLATE.md")
    parser.add_argument("--output", default="README.md")
    parser.add_argument(
        "--token",
        default=os.environ.get("README_RENDER_TOKEN") or os.environ.get("GITHUB_TOKEN"),
        help="GitHub token. Defaults to README_RENDER_TOKEN or GITHUB_TOKEN.",
    )
    return parser.parse_args()


def github_graphql(token: str, query: str, variables: dict | None = None) -> dict:
    payload = json.dumps({"query": query, "variables": variables or {}}).encode("utf-8")
    request = urllib.request.Request(
        GITHUB_GRAPHQL_URL,
        data=payload,
        headers={
            "Authorization": f"bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "nixos-from-scratch/readme-renderer",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GitHub API request failed: {exc.code} {detail}") from exc

    if "errors" in body:
        raise RuntimeError(f"GitHub API returned errors: {body['errors']}")
    return body["data"]


def format_date(timestamp: str) -> str:
    return datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").strftime("%Y-%m-%d")


def format_post_date(raw_date: str) -> str:
    return datetime.strptime(raw_date, "%d %B %Y").strftime("%Y-%m-%d")


def clean_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def clean_value_or(value: object, fallback: str) -> str:
    cleaned = clean_value(value)
    return cleaned if cleaned else fallback


def repo_description(name: str, description: object) -> str:
    cleaned = clean_value(description)
    if cleaned:
        return cleaned
    return REPO_DESCRIPTION_FALLBACKS.get(name, "No public description yet.")


def repo_hero(name: str) -> str:
    return REPO_HEROES.get(name, "Active public artifact in my systems/tooling work.")


def fetch_user(token: str) -> dict[str, str]:
    data = github_graphql(
        token,
        """
        query {
          viewer {
            login
            name
            bio
            company
            location
            websiteUrl
            twitterUsername
            createdAt
            followers {
              totalCount
            }
            following {
              totalCount
            }
            starredRepositories {
              totalCount
            }
            repositories(privacy: PUBLIC, ownerAffiliations: OWNER) {
              totalCount
            }
            pinnedItems(first: 6, types: REPOSITORY) {
              nodes {
                ... on Repository {
                  name
                }
              }
            }
          }
        }
        """,
    )["viewer"]

    return {
        "USERNAME": clean_value(data["login"]),
        "NAME": clean_value_or(data["name"], clean_value(data["login"])),
        "BIO": clean_value(data["bio"]),
        "COMPANY": clean_value(data["company"]),
        "LOCATION": clean_value_or(data["location"], "Not listed"),
        "WEBSITE_URL": clean_value(data["websiteUrl"]),
        "TWITTER_USERNAME": clean_value(data["twitterUsername"]),
        "SIGNUP_TIMESTAMP": clean_value(data["createdAt"]),
        "SIGNUP_DATE2": format_date(data["createdAt"]),
        "SIGNUP_YEAR": datetime.strptime(
            data["createdAt"], "%Y-%m-%dT%H:%M:%SZ"
        ).strftime("%Y"),
        "TOTAL_REPOSITORIES": clean_value(data["repositories"]["totalCount"]),
        "FOLLOWERS": clean_value(data["followers"]["totalCount"]),
        "FOLLOWING": clean_value(data["following"]["totalCount"]),
        "STARRED_REPOSITORIES": clean_value(data["starredRepositories"]["totalCount"]),
        "PINNED_REPO_COUNT": clean_value(len(data["pinnedItems"]["nodes"])),
        "HEADLINE": HEADLINE,
        "SHORT_PITCH": SHORT_PITCH,
        "PORTFOLIO_URL": PORTFOLIO_URL,
        "PORTFOLIO_HOST": "becker63.digital",
        "BLOG_HOME_URL": BLOG_HOME_URL,
        "LAST_REFRESHED_DATE": datetime.now(UTC).strftime("%Y-%m-%d"),
    }


def normalize_repo(repo: dict) -> dict[str, str]:
    return {
        "REPO_NAME": clean_value(repo["name"]),
        "REPO_FULL_NAME": clean_value(repo["nameWithOwner"]),
        "REPO_DESCRIPTION": repo_description(repo["name"], repo.get("description")),
        "REPO_URL": clean_value(repo["url"]),
        "REPO_HOMEPAGE_URL": clean_value(repo.get("homepageUrl")),
        "REPO_CREATED_TIMESTAMP": clean_value(repo.get("createdAt")),
        "REPO_PUSHED_TIMESTAMP": clean_value(repo["pushedAt"]),
        "REPO_FORK_COUNT": clean_value(repo.get("forkCount")),
        "REPO_ID": clean_value(repo.get("id")),
        "REPO_CREATED_DATE2": (
            format_date(repo["createdAt"]) if repo.get("createdAt") else ""
        ),
        "REPO_PUSHED_DATE2": format_date(repo["pushedAt"]),
        "REPO_STARS": clean_value(repo.get("stargazerCount", 0)),
        "REPO_LANGUAGE": clean_value(
            repo["primaryLanguage"]["name"] if repo.get("primaryLanguage") else "Mixed"
        ),
        "REPO_OWNER_USERNAME": clean_value(repo["owner"]["login"])
        if repo.get("owner")
        else "",
        "REPO_SIZE_KB": clean_value(repo.get("diskUsage")),
        "REPO_HERO": repo_hero(repo["name"]),
    }


def fetch_repos(token: str, count: int, order_field: str) -> list[dict[str, str]]:
    query = f"""
    query($count: Int!) {{
      viewer {{
        repositories(
          first: $count
          privacy: PUBLIC
          ownerAffiliations: OWNER
          orderBy: {{ field: {order_field}, direction: DESC }}
        ) {{
          nodes {{
            name
            nameWithOwner
            description
            url
            homepageUrl
            createdAt
            pushedAt
            forkCount
            id
            diskUsage
            owner {{
              login
            }}
            stargazerCount
            primaryLanguage {{
              name
            }}
          }}
        }}
      }}
    }}
    """
    nodes = github_graphql(token, query, {"count": count})["viewer"]["repositories"][
        "nodes"
    ]

    repos: list[dict[str, str]] = []
    for repo in nodes:
        repos.append(normalize_repo(repo))
    return repos


def fetch_pinned_repos(token: str) -> list[dict[str, str]]:
    data = github_graphql(
        token,
        """
        query {
          viewer {
            pinnedItems(first: 6, types: REPOSITORY) {
              nodes {
                ... on Repository {
                  name
                  nameWithOwner
                  description
                  url
                  pushedAt
                  stargazerCount
                  primaryLanguage {
                    name
                  }
                }
              }
            }
          }
        }
        """,
    )
    nodes = data["viewer"]["pinnedItems"]["nodes"]
    return [normalize_repo(repo) for repo in nodes]


def fetch_specific_repos(token: str, repo_names: list[str]) -> list[dict[str, str]]:
    aliases: list[str] = []
    variables: dict[str, str] = {}
    for index, name in enumerate(repo_names):
        var_name = f"repo{index}"
        variables[var_name] = name
        aliases.append(
            f"""
            r{index}: repository(owner: "becker63", name: ${var_name}) {{
              name
              nameWithOwner
              description
              url
              homepageUrl
              createdAt
              pushedAt
              forkCount
              id
              diskUsage
              owner {{
                login
              }}
              stargazerCount
              primaryLanguage {{
                name
              }}
            }}
            """
        )

    query = (
        "query("
        + ", ".join(f"${name}: String!" for name in variables)
        + ") { "
        + " ".join(aliases)
        + " }"
    )
    data = github_graphql(token, query, variables)
    repos: list[dict[str, str]] = []
    for index in range(len(repo_names)):
        repo = data.get(f"r{index}")
        if repo:
            repos.append(normalize_repo(repo))
    repo_map = {repo["REPO_NAME"]: repo for repo in repos}
    return [repo_map[name] for name in repo_names if name in repo_map]


def parse_frontmatter(raw_text: str) -> dict[str, str]:
    match = re.match(r"^---\n(.*?)\n---\n", raw_text, re.DOTALL)
    if not match:
        return {}
    frontmatter = match.group(1)
    parsed: dict[str, str] = {}
    for line in frontmatter.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        parsed[key.strip()] = value.strip().strip("'").strip('"')
    return parsed


def read_blog_posts() -> list[dict[str, str]]:
    posts_dir = Path("blog/content/posts")
    if not posts_dir.exists():
        return []

    posts: list[dict[str, str]] = []
    for path in sorted(posts_dir.glob("*.mdx")):
        raw_text = path.read_text(encoding="utf-8")
        metadata = parse_frontmatter(raw_text)
        if not metadata.get("title") or not metadata.get("date"):
            continue
        slug = path.stem
        tags_raw = metadata.get("tags", "")
        tags = [tag.strip() for tag in tags_raw.split(",") if tag.strip()]
        posts.append(
            {
                "POST_TITLE": metadata["title"],
                "POST_DATE": format_post_date(metadata["date"]),
                "POST_DESCRIPTION": metadata.get("description", ""),
                "POST_TAGS": ", ".join(tags) if tags else "untagged",
                "POST_SLUG": slug,
                "POST_URL": f"{BLOG_BASE_URL}/{slug}",
                "POST_TAG_LIST": json.dumps(tags),
            }
        )

    posts.sort(key=lambda post: post["POST_DATE"], reverse=True)
    return posts


def summarize_blog_topics(posts: list[dict[str, str]]) -> str:
    counts: dict[str, int] = {}
    for post in posts:
        tags = json.loads(post["POST_TAG_LIST"])
        for tag in tags:
            if tag == "tech":
                continue
            counts[tag] = counts.get(tag, 0) + 1
    if not counts:
        return "technical writing, systems design, reproducible tooling"
    top = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:4]
    return ", ".join(f"{name} ({count})" for name, count in top)


def replace_vars(text: str, values: dict[str, str]) -> str:
    for key, value in values.items():
        text = text.replace(f"{{{{ {key} }}}}", value)
    return text


def render_loops(text: str, loops: dict[str, list[dict[str, str]]]) -> str:
    pattern = re.compile(
        r"(?P<indent>[ \t]*)\{\{ loop (?P<name>[A-Z0-9_]+) \}\}\n?(?P<body>.*?)\n?[ \t]*\{\{ end (?P=name) \}\}",
        re.DOTALL,
    )

    def repl(match: re.Match[str]) -> str:
        name = match.group("name")
        body = match.group("body")
        items = loops.get(name)
        if items is None:
            raise RuntimeError(f"Unsupported loop in template: {name}")
        return "\n".join(replace_vars(body, item) for item in items)

    return pattern.sub(repl, text)


def main() -> int:
    args = parse_args()
    if not args.token:
        print("Missing GitHub token. Set README_RENDER_TOKEN or GITHUB_TOKEN.", file=sys.stderr)
        return 1

    with open(args.template, "r", encoding="utf-8") as handle:
        template = handle.read()

    user = fetch_user(args.token)
    posts = read_blog_posts()
    loops = {
        "3_MOST_STARRED_REPOS": fetch_repos(args.token, 3, "STARGAZERS"),
        "3_NEWEST_REPOS": fetch_repos(args.token, 3, "CREATED_AT"),
        "3_RECENTLY_PUSHED_REPOS": fetch_repos(args.token, 3, "PUSHED_AT"),
        "PINNED_REPOS": fetch_pinned_repos(args.token),
        "RECENT_REPOS": fetch_repos(args.token, 6, "PUSHED_AT"),
        "FLAGSHIP_REPOS": fetch_specific_repos(args.token, FLAGSHIP_REPO_NAMES),
        "RECENT_POSTS": posts[:4],
    }
    user["BLOG_POST_COUNT"] = clean_value(len(posts))
    user["BLOG_TOPIC_SUMMARY"] = summarize_blog_topics(posts)

    output = render_loops(template, loops)
    output = replace_vars(output, user)

    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(output.rstrip() + "\n")

    print(f"Rendered {args.output} from {args.template}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
