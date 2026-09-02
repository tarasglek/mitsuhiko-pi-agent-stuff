---
name: github
description: "Interact with GitHub using the `gh` CLI. Use `gh issue`, `gh pr`, `gh run`, and `gh api` for issues, PRs, CI runs, and advanced queries."
---

# GitHub Skill

Use the `gh` CLI to interact with GitHub. Always specify `--repo owner/repo` when not in a git directory, or use URLs directly.

## Selecting Projects

Before recommend/install/adopt. Never judge from README/features alone.

```bash
gh api repos/OWNER/REPO --jq \
  '{stars:.stargazers_count,forks:.forks_count,issues:.open_issues_count,archived,created_at,updated_at,pushed_at}'
gh api repos/OWNER/REPO/releases/latest --jq '{tag_name,published_at}'
```

Compare:
- Fit, compatibility, alternatives.
- Health: exact stars, dates, releases, commits, issue response. Flag new/stale/archived.
- Code: tests, CI, structure, permissions, data ownership, graceful failure.
- Footprint: artifact size, LOC, runtime deps, external APIs, failure domains, deploy steps.
- Supply chain: locks, pins, checksums, reproducible build, one-step rollback.

Deployment rank: vendored static binary/file > self-contained package > runtime environment > extra service. Sprawling unlocked deps lose; Python no exception. Penalize unused machinery. Prefer simple, observable, replaceable, pinned.

Popularity = signal, not verdict. Verify registry claims against registry metadata, not badges.

Report bone-dry: ≤80 words unless asked. Fragments. Compact table, decision, risks, unknowns. No praise, filler, or repeated conclusion.

## Pull Requests

Check CI status on a PR:
```bash
gh pr checks 55 --repo owner/repo
```

List recent workflow runs:
```bash
gh run list --repo owner/repo --limit 10
```

View a run and see which steps failed:
```bash
gh run view <run-id> --repo owner/repo
```

View logs for failed steps only:
```bash
gh run view <run-id> --repo owner/repo --log-failed
```

## API for Advanced Queries

The `gh api` command is useful for accessing data not available through other subcommands.

Get PR with specific fields:
```bash
gh api repos/owner/repo/pulls/55 --jq '.title, .state, .user.login'
```

## JSON Output

Most commands support `--json` for structured output.  You can use `--jq` to filter:

```bash
gh issue list --repo owner/repo --json number,title --jq '.[] | "\(.number): \(.title)"'
```
