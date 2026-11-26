# Branch conventions

Which branches to base work on, and how to keep shared branches clean.

## Which branch to use

- Base all work on the project's current shared branch. For most repos
  in this project that is **`desktop/26`**. If a repo has a
  `desktop/26` branch, use it and ignore any other branches — many
  older branches (old per-series names, retired variants, personal
  experiments) still exist but are stale or obsolete.
- Do not assume `desktop/26` is the clone default: some repos have it
  as `HEAD` (most component snaps), but others default to `main`
  (ubuntu-core-desktop itself, the provider snaps). Always clone and
  check out `desktop/26` explicitly — `git clone -b desktop/26` — and
  for the repos whose CI builds from `main`, use `main`.
- Before starting any work, check the branch is up to date: fetch and
  confirm your local checkout matches the remote (e.g. `git pull` /
  `git status` shows no behind-commits). Working on a stale checkout
  wastes the whole effort — the fix may already exist upstream, or the
  code you are changing may have moved.
- Never rebase a branch that has been pushed and shared — other people
  (and other agents) pulling it would hit divergent history.

## Keeping shared branches clean

- Shared branches carry no local-only content: nothing machine-
  specific, no personal convenience scripts, nothing you would not
  hand to another developer as-is. They must be safe to base upstream
  PRs on.
- Local-only build conveniences (private wrapper scripts, cache
  settings, machine paths) live outside the repo, not in commits on
  shared branches. History has repeatedly shown such changes sneaking
  into unrelated commits — check what you are about to commit every
  time.

## Pull-request branches

- Always cut PRs from the shared base branch (e.g. `desktop/26`),
  never from a local-only variant of it, so local tooling never leaks
  upstream.

## Launchpad-style multi-snap monorepos

- Repos that build snaps via Launchpad Snap Recipes use one branch per
  (snap, series) pair, named `snap/<snap-name>/<series>` (e.g.
  `snap/ubuntu-desktop-bootstrap/26.04`), because a recipe builds from
  one repo + branch + path. When starting work in one of these repos,
  base it on the matching `snap/...` branch rather than a bare
  series-named branch.
