# Fix core26 chkpwd via build.sh injection; land the permanent session changes

Date: 2026-11-05

## Impact / Priority

Priority: High. Real end-user impact:

- GNOME lock screen: VERIFIED WORKING (2026-11-05, live VM on store
  core26 646 with both helpers setgid root): wrong password rejected,
  correct password unlocks, journal shows the PAM conversation ran in
  gdm-session-worker (root, subj=gdm) and NO chkpwd helper was exec'd.
  Mechanism: gnome-shell's unlock dialog uses GDM's reauthentication
  channel, so PAM runs as root and the broken helpers are not on its
  path. KDE is the outlier (kscreenlocker_worker runs PAM in-process
  as the confined user). The chisel work's "identical latent bug"
  premise is falsified - nothing to fix on GNOME.
- KDE images currently work only because of two stopgaps, and one of
  them (the chkpwd chown hook) exists ONLY on the local, unpushed
  core-base-desktop branch fix-kde-screen-unlock (3cb217c) - it is
  deliberately NOT on desktop/26 because core26-desktop is being
  retired as a base. Any clean rebuild from committed state
  (desktop/26 + session base core26-desktop) produces a broken lock
  screen. This fragility is real: the core.snap sitting in the
  core-base-desktop tree (built 2026-11-04 from desktop/26) has
  pam_extrausers_chkpwd setgid root again.
- The KDE session still carries the fat core26-desktop base
  dependency (Stage 2.8 of `20260922-split-core26-desktop-base-snap.md`
  is effectively undone until this work lands).

Root cause is fully understood and was verified end-to-end (a VNC
lock/unlock repro, proc-poller catching the helper mid-flight): see
`20261013-fix-kde-screen-unlock.md`. Do not re-derive.

## Context (state as of 2026-11-05)

- chisel discards the uid/gid recorded in package tarballs, so the PAM
  chkpwd helpers are cut setgid ROOT instead of setgid SHADOW and
  cannot read the root:shadow shadow db for a non-root caller. The
  confined session execs the helpers from the BASE snap's /usr - so
  the fix has to be baked into the seeded core26 snap itself. A chown
  in the customized system rootfs does NOT help (the confined session
  never sees its /usr), and a mounted squashfs cannot be chowned at
  runtime.
- Store core26: latest/stable = rev 646 (BOTH helpers broken);
  latest/candidate+beta+edge = rev 750 (published to candidate
  2026-11-05). Rev 750 verified directly from the squashfs metadata:

      usr/sbin/unix_chkpwd            -rwxr-sr-x root/shadow  FIXED
      usr/sbin/pam_extrausers_chkpwd  -rwxr-sr-x root/root    STILL BROKEN

  The unix_chkpwd fix came from upstream canonical/core-base PR #481
  (hook chown, merged 2026-10-21, independent of us). The missing
  pam_extrausers_chkpwd fix is canonical/core-base PR #485 (authored
  by us 2026-11-05, OPEN, no reviewers). Until #485 merges, a new
  rev is published, and that rev promotes to latest/stable (likely
  weeks-to-months), store core26 cannot satisfy the confined session.
- Decision (user-confirmed): do NOT land any chkpwd hook stopgap in
  core-base-desktop desktop/26. The fix belongs upstream in core-base.
- build.sh already has all the machinery needed to inject a fixed
  core26 (this is the workaround that makes the permanent changes
  landable NOW):
  - build.sh re-execs itself under fakeroot so unsquashfs -> edit ->
    mksquashfs bakes root-owned content into repacked snaps as an
    unprivileged user (see the long comment before the ubuntu-image
    call, ~line 1314). A `chown root:shadow` inside that session is
    baked into the squashfs.
  - The model JSON (ubuntu-core-desktop-kde-26-amd64-dangerous.json)
    ALREADY lists core26 (digest-less, dangerous grade) because the
    kf6-core26/plasma-core26-desktop content snaps are core26-based,
    so core26 is already seeded in every image (fetched from store
    stable = 646 today).
  - A snap passed via --snap satisfies a model-listed snap by name -
    that is exactly how custom-core.snap satisfies the core26-desktop
    model entry. So a locally-fixed core26 passed via --snap wins
    over the store fetch. --validation=ignore + dangerous grade
    accept the unasserted repack (same as custom-core.snap).

## What's left (do in order; the build.sh block gates everything else)

1. build.sh: add a clearly-marked "TEMPORARY WORKAROUND (remove once
   core26 stable ships the chkpwd ownership fix - see
   `20261105-drop-build-sh-core26-chkpwd-workaround.md`)" block,
   immediately after the custom-core.snap mksquashfs (~line 1281),
   still inside the fakeroot re-exec:
   - Source snap: use a cached core26_*.snap in BUILD_DIR if present,
     else `snap download core26 --channel=latest/stable` (the build
     machine has network; fail loudly if download fails). Keep the
     store revision number - the repack preserves meta/snap.yaml, and
     keeping the rev keeps snapd's refresh logic predictable.
   - unsquashfs -> chown root:shadow + chmod 2755 on
     usr/sbin/unix_chkpwd AND usr/sbin/pam_extrausers_chkpwd ->
     mksquashfs (comp zstd, mirroring custom-core.snap) ->
     BUILD_DIR/fixed-core26.snap.
   - Assert before continuing: `unsquashfs -ll` the repacked snap and
     require BOTH helpers to be `-rwxr-sr-x root/shadow`, else exit 1
     (fakeroot faked-ownership failures would otherwise ship silently).
   - Add `--snap "${BUILD_DIR}/fixed-core26.snap"` to snap_args.
   - SCOPE: fix ONLY the two chkpwd helpers. Upstream's hook fix
     (#481 + #485) covers exactly those two - chage/expiry stay
     flattened upstream - so fixing only these keeps the dev images
     faithful to the future fixed stable rev. Do not "helpfully"
     chown chage/expiry/crontab here. (crontab/plocate are not even
     in core26; ssh-agent/gpasswd need nothing on resolute.)
2. plasma-desktop-session permanent changes (this is the chisel work's
   step 4 / Stage 2.8, landing early behind the build.sh workaround):
   - snap/snapcraft.yaml: base: core26 (snapcraft accepts it
     natively - no placeholder games).
   - Restore the four layouts dropped in fe296ef, EXACTLY as they
     were before that commit (git show fe296ef^:snap/snapcraft.yaml):

        /usr/share/X11/xkb:                        symlink $SNAP/kf6/usr/share/X11/xkb
        /usr/share/glvnd/egl_vendor.d:             symlink $SNAP/plasma/usr/share/glvnd/egl_vendor.d
        /usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/gbm: symlink $SNAP/plasma/usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/gbm
        /usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/dri: symlink $SNAP/plasma/usr/lib/$CRAFT_ARCH_TRIPLET_BUILD_FOR/dri

     Note the xkb one points at $SNAP/kf6, not $SNAP/plasma. Rewrite
     the NOTE comments that currently explain the layouts' ABSENCE
     ("the core26-desktop base ships xkb-data...") - with base: core26
     the base ships none of that content (verified absent in rev 750;
     646/750 share the same chisel content train, but re-verify
     against the actual stable rev with unsquashfs -ll - it's cheap).
   - KEEP the LD_LIBRARY_PATH content-first reorder (base /usr,/lib
     paths LAST). Stock core26 ships no libwayland-server/libEGL/
     libglapi at all (verified), so it is harmless now, but
     content-first is the correct invariant and the chisel work's
     step 4 explicitly keeps it.
   - KEEP XKB_CONFIG_ROOT/XLOCALEDIR ($SNAP/kf6/...) and every other
     env var - none of them reference the base.
3. Delete the base-swap hacks (they exist only because the base was
   core26-desktop):
   - plasma-desktop-session/build-github.sh: remove the sed swap
     (~line 23), the restore_base trap (~lines 24-27), and the
     post-pack meta/snap.yaml patch-back (~lines 41-51); update the
     header comment.
   - The local dev build wrapper (which performs the same base swap
     for local builds): remove the swap-in and the meta/snap.yaml
     patch-back there too.
4. Rebuild + verify KDE (the gate): rebuild the image and boot, then:
   - stat -c "%A %U:%G" /snap/core26/current/usr/sbin/{unix_chkpwd,
     pam_extrausers_chkpwd} inside the VM -> both -rwxr-sr-x
     root:shadow (proves the injected base is the one mounted).
   - End-to-end, real user flow: create an account via the
     plasma-setup wizard -> login -> logout -> login -> Super+L lock
     -> WRONG password rejected -> CORRECT password unlocks. (Simplest
     reproducer first is fine: autologin account via cloud-init, then
     lock/unlock - but the wizard account exercises pam_extrausers,
     which is the helper this whole bug is about; do that path too.)
   - journalctl: zero chkpwd errors during unlock (silent success
     path). If it fails, catch the helper with the static proc-poller
     method (egid should be 42) - do NOT re-derive October's
     investigation.
5. GNOME verification: DONE 2026-11-05 on the live VM (before any of
   this work) - wrong password rejected, correct password unlocks;
   journal shows gdm-session-worker (root, subj=gdm) ran the PAM
   conversation and no chkpwd helper was exec'd. GNOME unlock is
   helper-independent (GDM reauthentication channel), so it was never
   affected by the core26 bug and needs nothing from the build.sh
   injection. Keep one cheap line in the standard image test bar:
   lock -> wrong password must be REJECTED (guards against fail-open
   regressions - the kwin precedent in
   `20261013-fix-kde-screen-unlock.md`).
6. Refresh-behaviour check (needs a NETWORKED VM): check whether snapd
   wants to replace the sideloaded core26 with the store rev
   (`snap refresh --list`; or wait for an actual refresh attempt).
   If yes: accept it (disposable dev images; it self-heals once the
   post-#485 rev is stable) or seed a per-snap refresh hold for
   core26 (needs snapd >= 2.63 - check our snapd) as part of the same
   marked block. KNOWN INTERIM HAZARD either way: candidate 750 can
   promote to stable at any time; if a refreshing image then regresses
   to "Unlocking failed", check the core26 rev + helper ownership
   FIRST before re-running October's investigation.
7. Land: commit build.sh + the session-repo changes; the CI image
   build inherits the fix automatically (same build.sh).
8. Tick step 4 (partially) + step 5 of the chisel file-ownership work;
   this work supersedes that item's step 4 ordering (the revert
   happens BEFORE the store fix reaches stable, behind the build.sh
   injection).

## Do NOT change

- core-base-desktop desktop/26 stays hook-less (deliberate). The local
  fix-kde-screen-unlock branch (3cb217c) is still needed for interim
  builds made BEFORE this work lands (session base is core26-desktop
  until step 2/4 are done); once this lands it is fully obsolete -
  retire it in the follow-up work
  (`20261105-drop-build-sh-core26-chkpwd-workaround.md` step 6).
- The model base stays core26-desktop (system rootfs) - that is the
  endgame tracked separately in
  `20261105-replace-model-base-core26-desktop-with-stock-core26.md`
  (which supersedes the Stage 3 framing in
  `20260922-split-core26-desktop-base-snap.md`). When THAT switch
  happens, revisit the apparmor profile gap below (it becomes live
  then).
- core-base-desktop static/etc/apparmor.d/unix-chkpwd override stays
  (the system rootfs is still core26-desktop). KNOWN LATENT GAP for
  the future: upstream core26's own profile grants
  /var/lib/extrausers/shadow but NOT /var/lib/extrausers/passwd or
  /group (verified in rev 750). Functionally harmless once core26
  becomes the system base (pam_extrausers_chkpwd runs Ux unconfined
  and does the real work), but unix_chkpwd will again log
  "check pass; user unknown" for every extrausers unlock - exactly
  the journal noise that made October's investigation expensive.
  Consider upstreaming those two rules (Ubuntu apparmor package /
  apparmor.d project) or verifying a clean silent unlock on stock
  core26 once the helpers are fixed.
- pam-unix-chkpwd / kde-kauth snapd interfaces and build.sh
  simple_plugs: unchanged, base-independent.

## References

- `20261013-fix-kde-screen-unlock.md` (root cause + resolution)
- the chisel file-ownership work item (parent; tick its steps as this
  lands)
- `20260922-split-core26-desktop-base-snap.md` (Stage 2.8)
- the proc-poller method from the KDE session confinement work (helper
  forensics, if any re-verification needs it)
- plasma-desktop-session fe296ef (commit being partially reverted: base
  + layouts revert, LD_LIBRARY_PATH reorder stays)
- upstream: canonical/core-base PR #481 (landed), #485 (open, gating),
  canonical/chisel PR #338 (open, courtesy only - see the impact
  discussion in the 2026-11-05 session: only chage/expiry are real
  losses, both latent; crontab/plocate absent from core26, ssh-agent/
  gpasswd need nothing)
## Resolution (established in later work; note appended on import)

The permanent fix landed on `core-base-desktop` `desktop/26`: commits
`c70408d` (set correct group and setgid on unix_chkpwd, PR #481) and
`6bd4383` (the same for pam_extrausers_chkpwd, PR #485) restore the
helpers' group/setgid in the base build itself. The temporary
build-side injection this issue described was made unnecessary; the
session snap's core26-desktop base dependency could then be handled by
the ordinary base-swap work.