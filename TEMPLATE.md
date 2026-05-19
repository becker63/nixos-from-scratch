# Taylor Johnson / `becker63`

> {{ HEADLINE }}

{{ SHORT_PITCH }}

- Portfolio: [{{ PORTFOLIO_HOST }}]({{ PORTFOLIO_URL }})
- Writing: [essays and project notes]({{ BLOG_HOME_URL }})
- GitHub: [@{{ USERNAME }}](https://github.com/{{ USERNAME }})
- Last refreshed: {{ LAST_REFRESHED_DATE }}

## What I Build

- Platform, infrastructure, and security systems that are easier to reason about under pressure.
- AI evaluation tooling that treats agent changes like release candidates instead of vibes.
- Developer interfaces that compress operational ambiguity into explicit, inspectable entrypoints.
- Technical writing that makes low-level behavior and system tradeoffs legible without flattening them.

## Flagship Work

{{ loop FLAGSHIP_REPOS }}
### [{{ REPO_NAME }}]({{ REPO_URL }})

{{ REPO_DESCRIPTION }}

- Why it matters: {{ REPO_HERO }}
- Stack: {{ REPO_LANGUAGE }}
- Last push: {{ REPO_PUSHED_DATE2 }}
- GitHub: `{{ REPO_FULL_NAME }}`

{{ end FLAGSHIP_REPOS }}

## Recent Writing

{{ loop RECENT_POSTS }}
- [{{ POST_TITLE }}]({{ POST_URL }}) — {{ POST_DESCRIPTION }}  
  Published: {{ POST_DATE }} · Tags: {{ POST_TAGS }}
{{ end RECENT_POSTS }}

Writing snapshot: {{ BLOG_POST_COUNT }} published posts. Current themes: {{ BLOG_TOPIC_SUMMARY }}.

## GitHub Snapshot

| Public repos | Followers | Following | Stars given | Pinned repos |
| --- | --- | --- | --- | --- |
| {{ TOTAL_REPOSITORIES }} | {{ FOLLOWERS }} | {{ FOLLOWING }} | {{ STARRED_REPOSITORIES }} | {{ PINNED_REPO_COUNT }} |

## Current Surface Area

{{ loop PINNED_REPOS }}
- [{{ REPO_FULL_NAME }}]({{ REPO_URL }}) — {{ REPO_DESCRIPTION }}  
  {{ REPO_LANGUAGE }} · {{ REPO_STARS }} stars · updated {{ REPO_PUSHED_DATE2 }}
{{ end PINNED_REPOS }}

## Recently Active Repos

{{ loop RECENT_REPOS }}
- [{{ REPO_FULL_NAME }}]({{ REPO_URL }}) — {{ REPO_DESCRIPTION }}  
  {{ REPO_LANGUAGE }} · updated {{ REPO_PUSHED_DATE2 }}
{{ end RECENT_REPOS }}

## Language Analytics

![Weighted language stats](stats/leaderboard_by_weighted.png)

The chart above is generated automatically from my GitHub repositories on a schedule. It is useful as a rough signal for where time is going, not as a proxy for importance.
