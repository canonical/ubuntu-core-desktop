# Stop tracking dangerous model files in Git

Date: 2026-09-17

## Impact / Priority

Every rebuild produced spurious diffs/commits against the generated
`*.model` files: the build re-signs them from the source `*.json`, and
each re-sign produces a new signature/timestamp even when the underlying
model content hasn't changed. Impact derived from the original note's
described symptoms. No priority level was stated in the original note.

## Context

ubuntu-core-desktop-26-amd64-dangerous.model (and its siblings:
ubuntu-core-desktop-22-amd64-dangerous.model,
ubuntu-core-desktop-24-amd64-dangerous.model,
ubuntu-core-desktop-22-pi-dangerous.model) are currently tracked by Git
in canonical/ubuntu-core-desktop, but they are build artifacts: the
Makefile re-signs them from the source *.json via
`snap sign -k $(SNAP_SIGN_KEY)`, and each re-sign produces a new
signature/timestamp even when the underlying model content hasn't
changed. That means every rebuild shows up as a spurious diff/commit
against these files.

"Dangerous" models (grade: dangerous) are explicitly a development-only
signing mode - they exist so images can be tested without proper
brand-store signing. They are not meant to represent a released,
canonical artifact, so there's no real reason to track the generated
.model output in version control at all; only the source *.json should
need to be tracked.

Also noted: stray editor/backup copies of these files already exist in
the working tree (`ubuntu-core-desktop-26-amd64-dangerous.model~`,
`ubuntu-core-desktop-24-amd64-dangerous.model~`, and duplicates under
`old/`), reinforcing that these generated files are noisy to keep
around.

## Work items

- Confirm with the team/maintainers that dangerous models are dev-only
  and safe to stop tracking (sanity check before removing history-
  visible files from a shared repo).
- Add `*.model` (or the specific dangerous-model filenames) to
  .gitignore alongside the existing `*.snap`/`*.img`/`*.xz`/`*~`
  patterns.
- `git rm --cached` the currently tracked dangerous .model files (keep
  them on disk, just untrack) - do NOT rewrite history/purge old
  commits unless that's separately requested.
- Double check the Makefile target that produces %.model from %.json
  still works fine when the .model file is untracked/gitignored (it
  should, since it's just `snap sign ... > $@`).
- Clean up the stray `*~` backup copies while at it.
