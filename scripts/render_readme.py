#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime


GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"


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


def clean_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def clean_value_or(value: object, fallback: str) -> str:
    cleaned = clean_value(value)
    return cleaned if cleaned else fallback


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
            repositories(privacy: PUBLIC, ownerAffiliations: OWNER) {
              totalCount
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
        repos.append(
            {
                "REPO_NAME": clean_value(repo["name"]),
                "REPO_FULL_NAME": clean_value(repo["nameWithOwner"]),
                "REPO_DESCRIPTION": clean_value(repo["description"]),
                "REPO_URL": clean_value(repo["url"]),
                "REPO_HOMEPAGE_URL": clean_value(repo["homepageUrl"]),
                "REPO_CREATED_TIMESTAMP": clean_value(repo["createdAt"]),
                "REPO_PUSHED_TIMESTAMP": clean_value(repo["pushedAt"]),
                "REPO_FORK_COUNT": clean_value(repo["forkCount"]),
                "REPO_ID": clean_value(repo["id"]),
                "REPO_CREATED_DATE2": format_date(repo["createdAt"]),
                "REPO_PUSHED_DATE2": format_date(repo["pushedAt"]),
                "REPO_STARS": clean_value(repo["stargazerCount"]),
                "REPO_LANGUAGE": clean_value(
                    repo["primaryLanguage"]["name"] if repo["primaryLanguage"] else ""
                ),
                "REPO_OWNER_USERNAME": clean_value(repo["owner"]["login"]),
                "REPO_SIZE_KB": clean_value(repo["diskUsage"]),
            }
        )
    return repos


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
    loops = {
        "3_MOST_STARRED_REPOS": fetch_repos(args.token, 3, "STARGAZERS"),
        "3_NEWEST_REPOS": fetch_repos(args.token, 3, "CREATED_AT"),
        "3_RECENTLY_PUSHED_REPOS": fetch_repos(args.token, 3, "PUSHED_AT"),
    }

    output = render_loops(template, loops)
    output = replace_vars(output, user)

    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(output.rstrip() + "\n")

    print(f"Rendered {args.output} from {args.template}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
