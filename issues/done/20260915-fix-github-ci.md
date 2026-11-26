# Fix GitHub Actions CI for branch 26

Date: 2026-09-15

## Impact / Priority

No end-user impact; the gap was process-level: the workflow's push
trigger only listed branches main, 22 and 24, so as carried over it
would not actually run CI for this branch — snap builds for the branch
went unverified by CI until the workflow was fixed.

Impact derived from the original note's symptoms.

## Context

While cleaning up pc-amd64-gadget-desktop branch 26 and rebasing it onto
upstream canonical/pc-gadget branch 26 (new branch: 26-rebase), I removed
the .github/workflows/build-snap.yml addition from the rebased commits.

Reason for removal: the workflow's push trigger only lists branches
main, 22, and 24 - it does not build on push to 26 (or any future
release branch), so as carried over it wouldn't actually run CI for
this branch. Rather than commit a workflow that silently doesn't apply,
it was dropped from the 26-rebase commit set pending a fix.

Original workflow (from commit 33eae03 "Rebase Ubuntu Core Desktop
changes on top of core24:"):

    name: build-snap
    on:
      pull_request:
      push:
        branches:
          - main
          - 22
          - 24

    jobs:
      snap:
        runs-on: ubuntu-latest
        steps:
        - uses: actions/checkout@v4
        - uses: snapcore/action-build@v1
          id: snapcraft
          with:
            # Switch back to stable once
            # https://github.com/canonical/snapcraft/pull/4850 is released.
            snapcraft-channel: edge
        - uses: actions/upload-artifact@v4
          with:
            name: 'snap'
            path: ${{ steps.snapcraft.outputs.snap}}

## Work items

- Add .github/workflows/build-snap.yml back to branch 26 (and 26-rebase),
  with "26" added to the push.branches list (and consider adding future
  branches / using a wildcard instead of hardcoding branch numbers).
- Check whether snapcraft-channel: edge / the linked snapcraft PR
  (#4850) has since shipped to stable; switch back to stable if so.
- Once fixed, re-add the workflow as its own commit rather than bundling
  it into the "Rebase Ubuntu Core Desktop changes" commit.

Resolution 2026-11-03: DONE (in substance, branch naming superseded).
The workflow was re-added as its own commit - b8d01a9 "github: build the
desktop/26 snap in CI and publish to the desktop-26-latest release" on
pc-amd64-gadget-desktop - with the working branch in push.branches plus
pull_request/workflow_dispatch triggers, and it publishes to the rolling
desktop-26-latest GitHub release (live on canonical/pc-amd64-gadget-
desktop since 2026-10-09). The literal "branch 26 / 26-rebase" ask was
superseded when the repo standardized on desktop/26 (26-rebase no longer
exists; the `20261008-gnome-github-ci.md` plan, now done, made desktop/26
the canonical CI branch for all six repos). Leftover: the workflow still
uses snapcraft-channel: edge rather than switching back to stable - deliberate,
since snapcraft 9.x/edge is required for the core26-based repos (see
`20261008-gnome-github-ci.md`); revisit only if edge breaks.
