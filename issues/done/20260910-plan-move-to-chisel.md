# Plan: rebase core-base-desktop's 26 branch onto upstream main (chisel)

## Impact / Priority

No user-facing impact stated in the original note: this is a work plan
for rebasing the base-snap build (core-base-desktop) onto upstream
core-base's chisel build process, i.e. keeping the image's boot base
close to stock Core instead of fixing a reproducible defect. Impact
derived from the original note's described symptoms.

Audience: a coding agent picking this up as a standalone task. Read
this whole document before making any changes. Do not skip ahead - each
step below must be verified before the next one is attempted, and the
verification instructions (including how to build a test image and boot
a VM) are given in full.

## 0. Background / why this is hard

Repo: core-base-desktop. Remotes:
  origin   -> https://github.com/canonical/core-base-desktop.git (our fork)
  upstream -> https://github.com/canonical/core-base.git (Canonical's base)

Current state (verify with `git log --oneline --all`, `git branch -a`,
`git merge-base 26 upstream/main` before doing anything, in case this
plan document is stale by the time you run it):

- Branch "26" is our current working branch. It contains 18 desktop-
  specific commits on top of commit da9ad97 ("tests/lib/prepare-utils.sh:
  ensure 4KiB alignment for the image"), which is the immediate PARENT of
  upstream commit 254c901 ("many: switch to chisel build process (#225)").
- `git merge-base 26 upstream/main` should return da9ad97 - confirm this
  is still true before starting.
- upstream/main has since moved on: as of this writing there are 57
  commits between da9ad97 and upstream/main (`git log --oneline
  da9ad97..upstream/main | wc -l`), the first of which, 254c901, is a
  single massive squashed PR that rewrites the ENTIRE package-
  installation mechanism from apt-get-in-chroot-hooks to chisel slices,
  and also renumbers/renames/removes/splits a large fraction of the
  hooks/*.chroot scripts (verify: `git diff --stat da9ad97 254c901` and
  `git diff --stat da9ad97 upstream/main -- hooks/` - expect on the
  order of 100+ files touched).

Why a plain `git rebase 26 --onto upstream/main da9ad97` is NOT a good
first move: git's rename/conflict detection cannot reliably match our
desktop commits' edits to hooks/001-extra-packages.chroot,
hooks/002.1-add-gdm.chroot, etc. against a target tree where those files
have been renamed, renumbered, split, or replaced by a completely
different package-selection mechanism (chisel slice manifests referenced
from snapcraft.yaml, not apt-get calls in a hook script). A naive
rebase will produce large, confusing conflicts in files that no longer
exist in the same form, and resolving them "in the merge conflict
markers" risks silently dropping or corrupting behaviour.

Instead, this plan treats our 18 commits as a SPECIFICATION of desktop
behaviour to be re-implemented against the new chisel-based tree, one
commit's worth of behaviour at a time, verifying a real build+boot after
each one. Where a commit turns out to still apply cleanly (a few of the
smaller ones might), a straight cherry-pick is fine - but check the
result carefully anyway.

This will likely be significantly more work than a normal rebase.
Budget accordingly, and do not try to shortcut by batching multiple
commits' worth of change into one un-verified step.

## 1. The 18 commits to re-apply, in order, with a first-pass category

Get the authoritative list yourself with:
    git log --oneline da9ad97..26

As of this writing (oldest first - this is the order to re-apply them
in):

1. acda220 hooks,tools: add generate-connections.py to auto-connect snap
   plugs during installation
   -> new files only (hooks/993-connect-snaps.chroot, tools/generate-
   connections.py, README.md addition). Likely a clean cherry-pick;
   check whether hook-numbering convention/hook-runner behaviour changed
   upstream (hooks now go up to 992-... in some areas - check the number
   993 doesn't collide and still runs at the right point in the new
   sequence).

2. 5a2ca7d hooks: add desktop system users/groups and NSS/extrausers
   config
   -> edits hooks/002-setup_user.chroot, hooks/300-remove-pkgs-late.chroot,
   hooks/606-cleanup-perl.chroot. ALL THREE of these files have been
   renamed/renumbered upstream (e.g. setup_user -> 013-setup-extrausers,
   cleanup-perl -> 601-cleanup-perl). Needs manual re-implementation:
   find the new equivalent file for each, re-apply the same *intent*
   (add desktop-specific users/groups, keep them out of the "late
   package removal" cleanup, don't strip perl bits we need), not the
   literal diff.

3. 1d67fde snapcraft,hooks: add desktop-snappers PPA and GDM/GNOME
   session packages
   -> snapcraft.yaml only, but the whole point of this commit (adding a
   PPA and a package list for apt to install GDM/GNOME) is exactly the
   thing chisel replaces. Needs a genuine redesign: figure out whether
   the desktop packages needed here are available as chisel slices
   already (check chisel-releases repo / existing slice defs used by
   upstream/main's snapcraft.yaml for similar packages), and if not,
   decide whether to keep an apt-based part for just the desktop-
   specific extra packages (likely needed, since GDM/GNOME won't have
   upstream core slices) alongside the new chisel-based core packages.
   This is probably the single most involved step in the whole task -
   flag it for extra scrutiny/testing.

4. 3a32b74 hooks,static: add GDM, confined GNOME session, and session
   wrapper
   -> hooks/050-snap-symlink.chroot (still exists upstream, check diff
   still applies), hooks/500-create-xdg.chroot (renamed to
   hooks/ed4431e.../500-create-xdg.chroot - same name in the listing
   above, good sign, diff the content to be sure logic is compatible),
   plus two brand-new static/ files (session wrapper script, .desktop
   file) which should be clean adds.

5. db82d0a hooks: replace gnome-initial-setup with ubuntu-core-desktop-init
   -> one new hook file, likely a clean add; double check the hook
   number (002.4) doesn't collide with a new upstream hook in that
   range.

6. e27efb4 hooks: add admin-console helper for local shell access
   -> one new file, should be a clean add.

7. f5685e0 hooks: install GNOME locale packs instead of generating
   minimal C.<encoding> locales
   -> touches hooks/002.2-add-locales.chroot (new) and removes
   hooks/009-locale-archive.chroot. Upstream's locale handling has been
   restructured too (002-initialize-locales.chroot now exists with a
   different number/possibly different content, and 010-locale-
   vconsole-symlinks.test in hook-tests was also touched by the chisel
   switch). Re-derive against the new locale hook rather than blindly
   reapplying.

8. 47fe455 hooks: set VARIANT_ID=desktop in os-release
   -> tiny one-line-ish change to whatever hook now sets os-release
   (018-set-os-release.chroot upstream, was a different name/number
   before). Should be trivial once you find the new file.

9. 408ee39 hooks: make im-config configuration writable
   -> check whether the writable-paths mechanism (011-etc-writable /
   static/usr/lib/tmpfiles.d) changed shape upstream; likely still
   applies with minor adaptation.

10. cbe1159 static,hooks: add writable paths required for desktop packages
    -> static/etc/fstab, static/usr/lib/tmpfiles.d/core-writable.conf -
    check upstream/main's own static/ tree for an fstab/tmpfiles.d of
    the same name that may already exist post-chisel-switch and need
    merging rather than overwriting.

11. 510f4e8 snapcraft,static: add dconf defaults and default desktop
    wallpapers
    -> snapcraft.yaml (one line, probably still a clean context match) +
    new static binary/data files (dconf-init-data, wallpaper images).
    Should be low-risk.

12. 892b04b hooks: misc adjustments needed for the desktop session
    -> hooks/607-cleanup-xkb.chroot and hooks/900-cleanup-etc-var.chroot -
    both renamed/renumbered upstream (602-cleanup-xkb.chroot now,
    900-cleanup-etc-var.chroot may or may not still exist by that name -
    check). Re-derive.

13. c0cdda2 static,hooks: add KDE Plasma session support and snapped
    PipeWire adaptation
    -> touches hooks/002.1-add-gdm.chroot (careful: this is the file with
    our root-cause GDM fix from earlier in this project - make sure that
    fix, described below, survives however this file is restructured),
    hooks/599-cleanup-packages.chroot, plus new static/ desktop files.
    Non-trivial; this also affects KDE which you confirmed is in scope
    for the project generally - keep the Plasma .desktop file working.

14. 9b8ea09 snapcraft.yaml: make core26 stable
    9b8ea09 and
15. 339fd7f snapcraft.yaml: fix moved ubuntu-base resolute daily-build URL
    -> both tiny, single-purpose snapcraft.yaml edits. Check whether
    upstream/main's own snapcraft.yaml already has equivalent/superseding
    logic (it likely has its own, newer URL-fetching logic entirely -
    see the "build-env" part shown in upstream/main's snapcraft.yaml,
    which is quite different from ours already). May turn out to be
    entirely moot / already fixed upstream - verify rather than blindly
    reapplying.

16. 1e46337 hooks: streamline desktop packages and GDM setup
    -> large deletion (204 lines) from hooks/001-extra-packages.chroot,
    which no longer exists upstream at all (it was chisel's primary
    casualty). This commit's *content* needs to be reconciled with
    whatever commit 3 (1d67fde) above ends up looking like once
    redesigned for chisel - they may effectively collapse into one
    redesigned "desktop packages via chisel + supplementary apt" part.

17. 9d7664e hooks: add desktop identity and locale defaults
    -> hooks/000-provide-uids-gids.chroot (still exists upstream, diff
    should mostly still apply) and hooks/010-locale-vconsole-symlinks.chroot
    (renamed/restructured per the chisel switch's hook-tests changes
    noted above - re-derive).

18. b52ccc6 wip
    -> this is THE fix from earlier in this project: it restores
    hooks/002.1-add-gdm.chroot's org.gnome.Shell@.service unit file
    (previously wrongly deleted, causing GDM to fail to register a
    graphical seat0 session - this was the original bug this whole
    project started from). This must not be lost. Re-verify explicitly,
    after re-deriving hooks/002.1-add-gdm.chroot for chisel (needed
    already for step 13 above), that `org.gnome.Shell@.service` (or
    whatever unit gnome-session needs at the point GDM hands off) is
    NOT deleted by the new hook. This should probably be folded into the
    same re-derivation work as step 13, not treated as a fully separate
    step, but keep it as an explicit, separately-verified checklist item
    regardless of how the commits get squashed/reordered.

This numbering/categorization is a best-effort first pass from reading
the diffs, not gospel - re-verify each file's upstream fate with
`git log --oneline --follow -- <path>` and `git diff da9ad97
upstream/main -- <path>` before assuming a rename target above is
correct.

## 2. Safety / setup steps (do this before touching anything)

2.1 Confirm current branch state matches this document's assumptions
    (in the core-base-desktop repo):
      git status                      # should be clean of tracked changes
      git branch -a                   # confirm 26, 26-pre-chisel exist
      git merge-base 26 upstream/main # should print da9ad97...
    If anything differs materially, stop and re-assess before proceeding
    with the rest of this plan - the commit list in section 1 may be
    stale.

2.2 Tag the current tip of 26 before starting, so there is an
    unambiguous rollback point independent of any branch that gets
    rewritten:
      git tag pre-chisel-rebase-backup 26
    (branch "26-pre-chisel" already exists per `git branch -a` - confirm
    it points at the same commit; if not, investigate why before
    proceeding, don't assume this plan's premise is correct.)

2.3 Create the working branch for this task from upstream/main's
    current tip (NOT from 26, and NOT with `git rebase` as the first
    move):
      git fetch upstream
      git checkout -b 26-chisel upstream/main

2.4 Do NOT force-push, delete, or rewrite the existing "26" branch at
    any point during this task. It stays as-is, untouched, as the
    reference/fallback until 26-chisel is fully verified and the user
    has reviewed it. Only once the user explicitly says so should "26"
    be replaced or fast-forwarded.

## 3. Baseline sanity check: does plain upstream/main build and boot at all?

We have never built the post-chisel-switch upstream/main tree in this
environment. Before layering any desktop changes on top, confirm the
baseline itself works, so that any future build failure can be
attributed to a desktop-specific change rather than an
environment/tooling issue.

3.1 On branch 26-chisel (plain upstream/main, no desktop changes yet),
    build the base snap in core-base-desktop (the build packs via
    `snapcraft pack` and renames the output to core.snap - see the
    build script for exact behaviour). If it fails outright due to
    e.g. a "name: core26" vs "name: core26-desktop" mismatch, or
    missing something environment-specific, resolve that narrowly -
    do NOT start adding desktop content yet.
    NOTE: at this point the produced snap's `name:` in snapcraft.yaml
    is still "core26" (Canonical's own base), not "core26-desktop".
    Leave it as "core26" for this baseline check only - do not rename
    yet.

3.2 This baseline core.snap cannot usefully boot a full desktop (it
    has none of our desktop hooks yet), so "verification" at this
    stage just means: the build completes and produces a core.snap of
    a sane size (compare to today's ~485MB - a plain core26 without
    desktop extras should be substantially SMALLER, likely 100-250MB;
    if it's wildly different investigate why before proceeding).
    Optionally, for extra confidence, you can plug this bare snap into
    the existing "26" VM boot pipeline (see section 4 below for the
    full procedure) just to confirm it boots to a console at all (no
    GUI expected) - this is optional but recommended if time allows,
    since it catches fundamental chisel/build problems before they get
    tangled up with desktop-specific debugging later.

3.3 Record the result (build succeeded, snap size, boot-to-console
    result if tested) before moving on. If this step fails, STOP and
    resolve the baseline problem first - everything after this assumes
    a working, un-modified upstream/main baseline.

## 4. How to build and test the full desktop image (repeat after each step)

This is the verification procedure to repeat after each commit/step in
section 5. Read it once now, then just refer back to it.

4.1 Build core-base-desktop itself (snapcraft pack; the output is
    renamed to core.snap). Confirm it exists and check build.log for
    unexpected warnings/errors even on "success" (chisel slice
    resolution failures sometimes warn rather than hard fail).

    IMPORTANT naming caveat (historical context from the image repo's
    build notes): snapcraft currently refuses to build an app/gadget
    snap declaring a custom `base:` value, but a `type: base` snap
    (which is what this is) can be named anything - so snapcraft.yaml's
    `name:` field can stay as whatever it currently is on the 26-chisel
    branch (check: it may say "core26" if you haven't changed it, or
    "core26-desktop" if a later step in this plan renames it back -
    follow whatever the current snapcraft.yaml says, and keep it
    CONSISTENT with what the gadget snap / model assertion expect -
    see 4.2 and 4.3).

4.2 Build the full desktop VM image using the existing "26" pipeline
    in ubuntu-core-desktop, which is already wired to consume
    core-base-desktop's core.snap directly: it downloads/reuses a
    pc-desktop gadget snap, downloads/reuses a reference core24-desktop
    snap (used only for comparison/base assets, not for booting),
    unsquashes our core.snap, injects SSH keys/host keys and a
    passwordless-sudo sudoers entry for your own user for test access,
    and finally runs `make 26.img`.
    If snapcraft.yaml's `name:` was changed away from whatever the
    build currently expects, you may need to adjust the image build
    (or the Makefile target it calls) to match - check for any place
    that hardcodes "core26" or "core26-desktop" as a snap name and
    keep it consistent. Do not silently change unrelated behaviour in
    this script beyond what's needed for the name to match.

4.3 Boot the image (the qemu run): qemu with a bridged network device,
    serial console on stdio, and virtio-vga-gl for a real GPU/display
    device. The run holds a lock file so it refuses to start a second
    instance - if a previous test run is still up, either use it
    directly or shut it down (state cleanly if possible, e.g. `sudo
    poweroff` over ssh, or as a last resort `kill <qemu-pid>`) before
    starting a fresh one for a from-scratch boot test.
    Give it time to boot fully (watch the serial console output in the
    terminal, or tail boot logs) before trying to SSH in - first boot
    performs snap seeding, which can take a couple of minutes.

4.4 Connect and verify, over SSH: `ssh your_username@<vm-ip>`
    (passwordless sudo is configured by the image build - see step
    4.2). If the IP has changed, check the bridge's DHCP leases on the
    host, or check the qemu serial console output directly for a login
    prompt / IP address.

    Minimum verification checklist to run after EVERY step in section
    5 (do all of these, every time - do not skip any once GDM starts
    coming up, to avoid an earlier regression going unnoticed):
      a) The machine boots to a login screen at all (serial console
         and/or actually connecting a display shows GDM's greeter, not
         a crash/reboot loop). This alone is the main check for early
         steps in section 5, before GDM-related hooks land.
      b) Once logged in over SSH:
           sudo loginctl list-sessions
         confirms a graphical seat0 session appears once GDM is present
         and configured (this is the ORIGINAL bug this whole project
         started from - do not regress it). Cross-reference against the
         working "24" reference VM if in doubt about what "correct"
         looks like.
      c) Check no AppArmor denials related to systemd-user-control or
         general desktop operation appeared during boot/login:
           sudo dmesg | grep -i apparmor | grep -i DENIED
         (some denials may be expected/known - compare against the
         "24" reference VM's dmesg output for the same boot sequence
         to see if a new denial is actually new, or already present in
         the known-good baseline).
      d) Once the full desktop hooks are back (i.e. from around step
         13 / step 18's re-derivation onward), attempt an actual
         graphical login (either via the qemu SDL display window if
         running with a display, or `-display egl-headless,gl=on` mode
         plus a VNC/screenshot mechanism if headless) and confirm the
         confined ubuntu-desktop-session snap starts and a usable
         GNOME session comes up - check confinement specifically:
           ps aux | grep gnome-shell
           sudo cat /proc/<gnome-shell-pid>/attr/current
         should show a confined AppArmor profile, not "unconfined".
    Record pass/fail for each of a-d at every checkpoint in section 5.
    If any check regresses versus the previous checkpoint, stop and
    fix it before moving to the next commit - do not accumulate
    multiple unverified changes.

4.5 Between test iterations, re-run the image build and boot fresh
    each time (don't try to hot-patch a running VM's disk image) -
    this keeps every checkpoint an honest from-scratch build+boot,
    matching the "small, independently verified steps" requirement for
    this whole project.

## 5. Step-by-step re-application sequence

For EACH of the 18 items in section 1, in the order listed:

a) Re-derive/re-apply just that one item's change against the current
   tip of 26-chisel (find the new location of any renamed/renumbered
   file per the notes in section 1; use `git log --follow` and diffing
   against da9ad97/254c901/upstream/main as needed to locate the right
   target; do not guess blindly).
b) Commit it on 26-chisel with a clear message referencing the
   original commit hash it replaces/re-derives from, e.g.:
     "hooks: add desktop identity and locale defaults (chisel
      re-derive of 9d7664e)"
   Keep commits small and single-purpose, same granularity as the
   original 18, even if the underlying files changed shape - don't
   batch multiple original commits into one just because they touch
   related areas, unless (as flagged for items 3/16 above) the
   upstream restructuring genuinely makes them inseparable, in which
   case say so explicitly in the commit message.
c) Run the FULL build+boot+verify procedure in section 4.
d) Only proceed to the next item once section 4's checklist passes
   (or you've explicitly confirmed with the user that a particular
   regression is expected/acceptable at this intermediate step - e.g.
   the desktop won't come up at all until several GDM-related items
   have landed, which is fine, but say so and check the simpler parts
   of the checklist - like "does it boot to a console/login screen at
   all" - even in early steps).
e) If a step turns out to be a no-op (upstream/main already does the
   equivalent thing - this is plausible for items 8, 14, 15 per the
   notes above), commit an empty/documentation commit noting this
   explicitly (or fold the note into the next real commit's message) -
   don't just silently skip it without a record.

After all 18 items are re-applied and the final full verification
(step 4.4's checklist, especially item d, a full confined GNOME
desktop login) passes, do a side-by-side comparison against the "24"
reference VM and the previous working "26" branch's own
last-known-good boot (if still bootable via a leftover core.snap/build
- otherwise this plan's own section 4 records serve as the comparison
baseline) to confirm no functional regressions.

## 6. Wrap-up

- Do not merge/replace the "26" branch automatically. Leave 26-chisel
  ready for review, summarize what changed per original commit (a
  short table: original commit -> new commit(s) -> any notable
  redesign) and report back to the user.
- Note explicitly for the user any places where chisel's package
  selection turned out to be insufficient for desktop needs and you
  had to keep/introduce an apt-based part (this is expected for at
  least the GDM/GNOME package set per item 3 in section 1) - this is
  useful input for the broader "reduce base snap bloat" work already
  described in `proposed-plan.md`, since it tells us which packages
  chisel doesn't have slices for yet.
- Leave the pre-chisel-rebase-backup tag and 26-pre-chisel branch in
  place; do not delete either without being asked.
