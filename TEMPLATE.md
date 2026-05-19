# nixos-from-scratch

Personal NixOS configuration, system modules, packages, and experiments for [{{ USERNAME }}](https://github.com/{{ USERNAME }}).

## Overview

This repository collects machine configuration, reusable Nix modules, package overlays, local tooling, and a custom blog app. It is maintained by {{ NAME }}.

## GitHub Snapshot

- GitHub profile: [@{{ USERNAME }}](https://github.com/{{ USERNAME }})
- Public repositories: {{ TOTAL_REPOSITORIES }}
- Joined GitHub: {{ SIGNUP_DATE2 }}
- Location: {{ LOCATION }}

## Language Analytics

![Weighted language stats](stats/leaderboard_by_weighted.png)

## Recently Updated Repositories

| Repo | Language | Last Push |
| --- | --- | --- |
{{ loop 3_RECENTLY_PUSHED_REPOS }}
| [{{ REPO_FULL_NAME }}]({{ REPO_URL }}) | {{ REPO_LANGUAGE }} | {{ REPO_PUSHED_DATE2 }} |
{{ end 3_RECENTLY_PUSHED_REPOS }}
