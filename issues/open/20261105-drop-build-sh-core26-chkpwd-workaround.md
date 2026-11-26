# Drop the build.sh core26 chkpwd workaround once core26 stable is fully fixed

Date: 2026-11-05

## Impact / Priority

Priority: Medium - mostly hygiene, but with one real silent-regression
window. If this is NOT done:

- Dev images keep running a locally-modified, unasserted core26 base
  snap indefinitely (divergent from store, repacked every build).
- REAL HAZARD: the injected core26 keeps its store revision, and once
  a NEWER rev promotes to latest/stable, snapd auto-refresh (on
  networked images) replaces the fixed copy with the store rev. The
  current candidate 750 fixes only unix_chkpwd - pam_extrausers_chkpwd
  is still setgid root there - so a refreshing image can SILENTLY
  regress to "Unlocking failed" with the correct password, then
  self-heal when the post-#485 rev reaches stable. Anyone hitting that
  window burns hours re-deriving October's investigation (the exact
  failure the notes warn about). If the refresh check in
  `20261105-fix-core26-chkpwd-via-build-sh-and-revert-session-base.md`
  (its step 6) showed snapd does NOT auto-refresh sideloaded snaps,
  this hazard does not apply - verify, don't assume.
- Nothing is user-visible otherwise until the trigger below is met;
  the workaround keeps images working in the meantime.

## Trigger (do NOT start until this is true)

core26 latest/stable contains a rev where BOTH helpers are correct:

    snap download core26 --channel=latest/stable
    unsquashfs -ll core26_*.snap | grep chkpwd
      required for BOTH:
        -rwxr-sr-x root/shadow  usr/sbin/unix_chkpwd
        -rwxr-sr-x root/shadow  usr/sbin/pam_extrausers_chkpwd

(or, on a booted VM: stat -c "%A %U:%G" /snap/core26/current/usr/sbin/
{unix_chkpwd,pam_extrausers_chkpwd}).

Check the CONTENT, not the PR states - Canonical may ship the fix by
any route (hook, chisel, package change).

Status at writing (2026-11-05): stable=646 (both broken);
candidate/beta/edge=750 (unix_chkpwd fixed, pam_extrausers_chkpwd
broken). The gating change is canonical/core-base PR #485 (extends the
#481 hook chown to pam_extrausers_chkpwd; open, authored by us, no
reviewers yet) -> merge -> new core26 rev published -> promoted to
latest/stable. Expect weeks-to-months. Nudging #485 review is the
shortest path.

## Steps

1. Confirm the trigger (above).
2. Delete the "TEMPORARY WORKAROUND" block from build.sh (grep for the
   marker): the download/cache, unsquashfs/chown/mksquashfs of
   fixed-core26.snap, the unsquashfs -ll assert, and the
   --snap fixed-core26.snap argument. If a per-snap refresh hold for
   core26 was added (the previous work item's step 6), remove that
   unit too. After removal, ubuntu-image goes back to fetching core26
   from the store stable channel on its own - the model JSON already
   lists core26 (needed by the kf6/plasma content snaps), and the
   store fetch is how the GNOME images have been seeded all along, so
   no model or session change is needed.
3. Rebuild the KDE image; verify the seeded core26 is the STORE rev
   (asserted, revision matches latest/stable) with both helpers
   root:shadow; re-run the lock/unlock gate end-to-end (wizard
   account -> login -> logout -> Super+L -> wrong password rejected ->
   correct password unlocks; zero chkpwd errors in the journal).
4. GNOME regression check only (near-trivial): GNOME unlock is
   helper-independent - VERIFIED 2026-11-05 on the live VM running
   store core26 646 (wrong password rejected, correct unlocks; PAM
   ran as root in gdm-session-worker, no chkpwd helper exec). Just
   repeat the wrong-password/correct-password check once on the
   rebuilt image to guard against fail-open regressions.
5. Optional but valuable: on an already-flashed NETWORKED image, let
   core26 auto-refresh to the new stable rev and re-verify lock/unlock
   - this validates the self-heal path that existing images in the
   field will take, and closes the refresh-behaviour question from
   `20261105-fix-core26-chkpwd-via-build-sh-and-revert-session-base.md`
   for good.
6. Cleanup once verified:
   - Retire the core-base-desktop local branch fix-kde-screen-unlock
     (3cb217c, the chkpwd chown stopgap). Nothing needs it any more:
     the session base is core26 (fixed upstream), so neither the
     session nor interim core26-desktop builds depend on it. Also
     delete stale downloaded/repacked core26 caches from build dirs.
   - Bookkeeping: append resolution notes and move BOTH this file and
     `20261105-fix-core26-chkpwd-via-build-sh-and-revert-session-base.md`
     into done/; update `20261013-fix-kde-screen-unlock.md` (the
     base-switch stopgap story is superseded - the chisel
     file-ownership work's step 6 asks for exactly this); tick step 4
     of the chisel file-ownership work.
7. chisel PR #338: NOT gating anything for us any more - do not block
   this item on it. Still worth landing upstream as general-purpose
   correctness (container/server images; chage/expiry flattening
   remains latent there), so keep responding to review when pinged.

## References

- `20261105-fix-core26-chkpwd-via-build-sh-and-revert-session-base.md`
  (the workaround itself; step numbers above refer to it)
- `20261013-fix-kde-screen-unlock.md` (root cause, helper behaviour,
  journal signatures)
- the chisel file-ownership work item (parent; its step 4 completes
  when this item lands)
- the proc-poller method from the KDE session confinement work (if
  any re-verification needs helper forensics)
- upstream: canonical/core-base PR #485 (gating), #481 (landed),
  canonical/chisel PR #338 (courtesy)
