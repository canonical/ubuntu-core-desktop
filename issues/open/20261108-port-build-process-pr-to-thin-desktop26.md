# Port the stalled core-base-desktop build-process PR to the thin desktop/26

## Impact / Priority

PRIORITY: Medium — the PR carries build-process changes someone
considered worth submitting; leaving it unlanded means whatever problem
it set out to fix remains unfixed on our side too. No direct end-user
impact is known (the PR predates the thin variant and targets the fat
base's build), so the honest statement is: impact unknown until the
PR's intent is re-read against the new build — the work item below
includes that classification step. If the PR fixed a real
build-process gap that the thin machinery inherited, users would see it
as whatever build failure/inconsistency it addressed.

## Background

There is an existing open PR against canonical/core-base-desktop's old
(fat) desktop/26 branch modifying the build process. It stalled
because: (a) the fat branch's build.sh diverged after the PR was made;
(b) on review it did not obviously cover everything build.sh does, so
landing it needed regression consideration that never happened. The
thin-variant work has now replaced the fat branch entirely (old
desktop/26 renamed desktop/26-fat; the new desktop/26 is the
core-base-derived thin variant). When the branch was renamed, GitHub
retargeted the PR to desktop/26-fat automatically.

## Work items

0. The open PRs against the old desktop/26 (verified 2026-11-08 via
   gh):
   - #92 "fix: add gdm3 configuration to fstab and core-writable.conf"
     [fix-autologin -> desktop/26] — the build-process PR. NOTE: its
     content (gdm3 writable mounts in fstab + core-writable.conf) is
     exactly what the thin variant's fstab wave already ships
     (commit "Add the desktop rootfs and GNOME runtime integration"
     in the 8-commit series) — evaluate it as LIKELY SUBSUMED, but
     verify nothing extra rides in its diff.
   - #91 "feat: add ubuntu-wallpapers to stage-packages" [fix-wallpaper
     -> desktop/26] — wallpaper data; the thin design routes wallpaper
     data to content snaps (build.sh symlinks SDDM's Next wallpaper to
     plasma-core26-desktop's Altai). Evaluate intent vs that design.
   Both retarget to desktop/26-fat automatically when the branch is
   renamed (the admin step pending in the upstreaming work item).
1. Re-read each PR's INTENT (not its diff — the machinery changed
   completely: the fat Makefile/hooks build vs the core-base variant
   machinery, tools/build-variant.sh). Identify what build-process
   problem it solves.
2. Audit the new desktop/26 machinery against that intent: does the
   thin build still have the problem? (Parts of the PR may be obsolete;
   parts may be as applicable as ever.)
3. Implement whatever still applies — a rewrite into the variant
   machinery, NOT a direct merge (the diff will not apply meaningfully
   across the machinery change). Verify with a clean variant build +
   the standard content-identity checks.
4. Close the PR referencing the landing commit(s) with a short
   explanation of what was ported and what became moot.

## Notes

- The PR lives against desktop/26-fat after the rename; do not delete
  the fat branch while the PR is open.
- If the PR's intent turns out to be fully obsolete, close it with
  that explanation instead of porting — but verify obsolescence, don't
  assume it.
