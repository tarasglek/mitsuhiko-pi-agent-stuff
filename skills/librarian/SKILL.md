---
name: librarian
description: "Cache and refresh remote git repositories under ~/.cache/checkouts/<host>/<org>/<repo> so future references can reuse a local copy. Use this skill when the user points you to a remote git repository as reference or you encountered a remote git repo through other means."
---

Use this skill when the user points you to a remote git repository (GitHub/GitLab/Bitbucket URLs, `git@...`, or `owner/repo` shorthand).

The goal is to keep a reusable local checkout that is:
- **stable** (predictable path)
- **up to date** (periodic fetch + fast-forward when safe)
- **efficient** (partial clone with `--filter=blob:none`, no repeated full clones)

## Cache location

Repositories are stored at:

`~/.cache/checkouts/<host>/<org>/<repo>`

Example:

`github.com/mitsuhiko/minijinja` → `~/.cache/checkouts/github.com/mitsuhiko/minijinja`

A best-effort shared-object pantry is kept at:

`~/.cache/checkouts/.object-pool`

It reuses Git objects by hash only; refs remain private to each checkout. The exact canonical checkout path always wins, and both ordinary `.git` directories and linked-worktree `.git` files are supported. Missing repositories use a filtered clone with the pantry as an optional reference, falling back to a plain filtered clone if the pantry is unavailable.

Alternates are persistent dependencies: do not move or delete donor checkouts or the pantry, and do not aggressively prune unreachable objects from them. The pantry is not an offline mirror.

## Command

```bash
bash checkout.sh <repo> --path-only
```

Examples:

```bash
bash checkout.sh mitsuhiko/minijinja --path-only
bash checkout.sh github.com/mitsuhiko/minijinja --path-only
bash checkout.sh https://github.com/mitsuhiko/minijinja --path-only
```

The script will:
1. Parse the repo reference into host/org/repo.
2. Reuse the exact canonical checkout if it is valid; invalid existing destinations are not deleted.
3. Register its common Git object directory with the optional shared pantry.
4. Clone if missing using a filtered, optionally reference-assisted clone.
5. Fetch from `origin` when stale (default interval: 300s).
6. Attempt a fast-forward merge if the checkout is clean and has an upstream.

A failed refresh of an existing checkout is reported as `fetch-failed` but remains usable and is returned. Shared objects do not share refs, and the script does not scan, migrate, repack, or prune cached repositories.

## Update strategy

- Default behavior is **throttled refresh** (every 5 minutes) to avoid unnecessary network calls.
- Force immediate refresh with:

```bash
bash checkout.sh <repo> --force-update --path-only
```

## Recommended workflow

1. Resolve repository path via `checkout.sh --path-only`.
2. Use that path for searching, reading, and analysis.
3. On later references to the same repo, call `checkout.sh` again; it will find and update the cached checkout.

## If edits are needed

Prefer not to edit directly in the shared cache. Create a separate worktree or copy from the cached checkout for task-specific modifications.

## Notes

- `owner/repo` defaults to `github.com`.
