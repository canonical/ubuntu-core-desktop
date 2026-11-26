# Merge ubuntu-core-desktop-kde back into ubuntu-core-desktop

Date: 2026-09-18

## Impact / Priority

High. There should be only ONE repo. ubuntu-core-desktop-kde is a
throwaway copy of canonical/ubuntu-core-desktop made so the KDE port
could be worked on without disturbing the main repo. Leaving it as a
separate repo means the KDE work (model, image build target, build/boot
scripts) is invisible to the main repo and will drift/be lost.

What a real user would observe: nothing directly, but the KDE image
cannot be built from the canonical repo, and the KDE work will not be
found unless someone knows to look in the copy.

## Context

ubuntu-core-desktop-kde (branch `kde`) is a copy of
canonical/ubuntu-core-desktop. It contains the KDE-specific additions:

- ubuntu-core-desktop-kde-24-amd64-dangerous.{json,model}
- The `24-kde.img` image build target
- The KDE build/boot scripts (currently UNTRACKED)
- The 4 upstream commits (8736d00, 6463bd1, 8800018, 18a057f) were
  already merged into the kde branch via fast-forward of `26` + merge
  (commit 6a8669a).

## What needs to happen

1. Commit the untracked KDE files in ubuntu-core-desktop-kde: the KDE
   build/boot scripts (and the KDE model files if not already tracked).
   The plasma-core-desktop / plasma-desktop-session repos also have
   UNCOMMITTED forward-port + fix work that should be committed first
   (see the resolution in `20260917-build-kde-neon-core-image.md`).
2. Bring the kde branch (or its KDE-specific commits) into
   canonical/ubuntu-core-desktop. Decide the target branch: the KDE
   work is additive (new model/scripts/build target), so it should
   merge cleanly onto the main 26 branch without touching the GNOME
   scripts.
3. Delete/archive ubuntu-core-desktop-kde once merged, so there is only
   one repo going forward.

Note: the KDE model files are "dangerous" (dev-only) and were gitignored
by upstream commit 8736d00 ("Stop tracking dangerous model files"). The
KDE model files may need to be handled the same way (gitignored, not
committed) — check what the main repo's convention is before committing
them.
