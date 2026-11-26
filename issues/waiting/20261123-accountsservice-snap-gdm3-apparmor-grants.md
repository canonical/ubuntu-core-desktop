---
upstream: https://github.com/canonical/ubuntu-desktop-provision/pull/1634
waiting_since: 2026-11-23
---

# accountsservice snap: AppArmor lacks grants for the GDM autologin write

## Impact / Priority

Priority: Medium (narrowed 2026-11-23 — see below) — the wizard wedges
when the user opts into automatic login on current images.

What a real user sees (reproduced live 2026-11-23 on the test VM,
nouser image, PR core-base-desktop#92's /etc/gdm3 mount in place): the
identity page's control is the "Require my password to log in"
checkbox. With it CHECKED (the default) the wizard COMPLETES — provd
calls SetAutomaticLogin(false) and accountsservice early-returns in
daemon_local_set_automatic_login without touching custom.conf, so the
flow finishes, the handoff runs and the created user's session starts.
With it UNCHECKED (automatic login opted in) provd calls
SetAutomaticLogin(true) → save → `failed to set autologin: failed to
change automatic login: Permission denied` → rollback (now fixed by
the provd DeleteUser patch, see
`20261123-provd-deleteuser-rollback-signature.md`) → wizard spins
forever. So the wedge is the automatic-login opt-in path only, not
every wizard run.

SEPARATE, A/B-PROVEN GAP (2026-11-23): the wizard→user ACCESSIBILITY
handover does not work on the published-image shape at all. A/B on the
0.1.5-provd image (byte-equivalent to the CI artifact): screen reader
enabled on the wizard's a11y page → flow completes → user session
starts → the created user's dconf contains NO a11y keys and orca is
NOT running in their session. Reason: the handover writer (provd
internal/services/user/handover.go) exists ONLY on the local
test/upstream-main branch — no published artifact ever carried it:
provd-snap has only ever packed the deb binary (no side branches, no
source build in its CI; even the fat-era t/ tree's baked provd md5
equals the deb's 462a0a1f...), and the fork's desktop/26 branch (which
builds the CI wizard artifact) doesn't contain the pair either. The
designed chain (provd writes /etc/dconf/channel/handover at CreateUser
→ ucd-a11y-handover-live.path triggers the live-read → the global user
unit ucd-a11y-handover applies the allowlisted keys at the target
user's first login) has therefore only ever worked on locally-built
images. The in-wizard a11y itself (chord, a11y page, orca in the
wizard session) works everywhere — that is what a downloaded-image
test exercises.

## Root cause

accounts-daemon runs SNAP-CONFINED on current images
(snap.accountsservice.accounts-daemon — the accountsservice snap is in
the image model; older base trees' unconfined /usr/libexec/
accounts-daemon is stale evidence). Its generated AppArmor profile:
- grants only `r` on the literal `/etc/gdm3/custom.conf` — but that
  path is a SYMLINK to /etc/writable/gdm3/custom.conf, and AppArmor
  mediates the RESOLVED path for symlink reads, so the read rule never
  matches;
- has no write grants at all, while accountsservice's autologin save
  is `g_file_set_contents("/etc/gdm3/custom.conf", ...)` — a temp file
  created IN /etc/gdm3 and renamed over the target (replacing the
  symlink).

core-base-desktop#92 (merged, ab3c09a) provides the writable /etc/gdm3
mount; without it the write would fail EROFS even with grants. With
the mount in place, only the AppArmor grants are missing.

## Fix (verified live with apparmor_parser -r, then reverted)

Add to the accounts-daemon profile (accountsservice-snap repo — the
generated profile comes from the snap's declaration, so the fix lands
in the snap's packaging, not in accountsservice's C source):

    /etc/writable/gdm3/custom.conf r,   # read current config through the symlink
    /etc/gdm3/ rw,                      # g_file_set_contents temp-file directory
    /etc/gdm3/custom.conf rw,           # rename target
    /etc/gdm3/custom.conf.* rw,         # g_file_set_contents temp file

With these, SetAutomaticLogin succeeds, the symlink is replaced by a
real merged config inside the writable mount, it persists across
reboot, and GDM autologins the created user straight into the confined
session (verified: wayland-0 -> snap.ubuntu-desktop-session/wayland-0
after reboot).

## Second gate (found 2026-11-23 while verifying the provd rollback fix)

Even with the grants and the fixed provd call, CreateUser's ROLLBACK
(the DeleteUser path) still cannot clean up: the PPA accountsservice
daemon passes --extrausers to its CreateUser-path helpers (useradd/
groupadd/usermod/gpasswd — the user lands in extrausers) but runs
PLAIN `/usr/sbin/userdel` in DeleteUser, and the PPA shadow build
(debian/patches/1013_extrausers_deluser.patch in the PPA's
shadow-4.17.4 source) makes extrausers OPT-IN for userdel — so userdel
exits 6 ("not found" in /etc/passwd) and the half-created user remains
(observed live: journal `running '/usr/sbin/userdel' failed: Child
process exited with code 6` right after the now-working delete
request). Fix options, in the accountsservice-snap repo:
- the chpasswd-guard pattern: stage a tiny userdel wrapper that
  injects --extrausers (plus -r for a fresh account's cleanup) and
  execs the base's real userdel, bound over the daemon's resolved
  helper path — needs its slot-policy exec rule checked; or
- fix the PPA accountsservice source's DeleteUser argv (heavier: PPA
  rebuild).
Verified `/usr/sbin/userdel --extrausers -r <user>` removes the
extrausers user, group entry and home cleanly (mail-spool warning is
cosmetic).

## Steps

1. Find where the accountsservice snap declares its AppArmor rules
   (the accountsservice-snap repo: snapcraft.yaml apparmor snippet,
   staged profile file, or interface slots) and add the four rules.
2. Rebuild the snap, rebuild a nouser image, drive the wizard
   end-to-end: identity page with autologin -> wizard completes
   (or at least passes SetAutomaticLogin), custom.conf carries the
   keys, reboot autologins the user.
3. Check the fat-base-era fallback path: the /etc/writable/gdm3/
   custom.conf copy goes stale once the wizard's write lands (GDM reads
   /etc/gdm3/custom.conf, which is authoritative) — confirm nothing in
   the image still treats the /etc/writable copy as live state.

## Delivery of the handover provd (fixed 2026-11-23 evening)

The a11y carry-over gap was DELIVERY, not code: the handover writer
exists in the provd source (test/upstream-main) but every published
provd.snap staged the resolute deb binary (provd-snap's CI had no
source build; provd-src-built was a hand-placed untracked file), so
the A/B on a deb-binary image showed the created user's dconf carrying
NO a11y keys (owner-confirmed on the downloaded rolling image). Fixed
in canonical/provd-snap (ad86406, on top of the concurrently-pushed
26.04-runner/arm64-suffix/Node24 CI commits): build-provd-from-source.sh
clones the pinned source stream (defaults: the fork's core26-provd
integration branch = DeleteUser fix + the handover pair, commit
fb2d845b2; flip the defaults to canonical/ubuntu-desktop-provision@main
when both PRs merge), builds cmd/provd, writes provd-src-built +
provd-src-built.provenance (repo/ref/commit/go/built). build-github.sh
and the local build wrapper call it and clean the provd part every
run (snapcraft caches the override-build scriptlet - a replaced
provd-src-built is never re-staged without the clean; hit twice). CI
workflow gains setup-go (v7 = the Node-24 release; v6 is still node20)
for the module's go 1.26.11. The fork's core26-provd integration
branch is pushed (fb2d845b2). DONE: CI green on both arches and the
published desktop-26-latest provd.snap is 0.1.5+t26handover (verified
by downloading the asset) - the next build-image.yaml run embeds it
and the published image regains the wizard->user a11y handover.
Remaining: the upstream PRs (DeleteUser = #1634 filed; the handover
pair = needs the receiver design conversation), then flip the pin.
