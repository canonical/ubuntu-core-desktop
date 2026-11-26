# GDM autologin never reaches a working confined desktop session

Date: 2026-09-17

## Impact / Priority

With autologin enabled for testing, GDM's autologin PAM session opened
and closed again within ~1s and GDM fell back to a password-prompt
greeter — the confined desktop session never came up, 100%
reproducible. No priority level was stated in the original note; impact
derived from the original note's described symptoms.

## Context

While implementing `--autologin`/`--nouser` flags for the image build
(`build.sh`), the `--autologin` flag's config
(`AutomaticLoginEnable`/`AutomaticLogin = your_username` in
custom.conf) and its build-time `gnome-session` shim (baked per the
technique in `tools/confined-autologin-test.sh`) were both verified
correct and correctly invoked by GDM on a live VM - but the confined
session never actually finishes registering. GDM logs, within ~1s of
the autologin PAM session opening:

    gdm-autologin][NNNNN]: pam_unix(gdm-autologin:session): session
      opened for user your_username(uid=1000) by your_username(uid=0)
    gdm-autologin][NNNNN]: gkr-pam: gnome-keyring-daemon started properly
    gdm-autologin][NNNNN]: pam_unix(gdm-autologin:session): session
      closed for user your_username
    gdm3[NNNNN]: Gdm: GdmDisplay: Session never registered, failing

... and GDM falls back to spawning a normal password-prompt greeter on
the seat. This was 100% reproducible: fresh boot, reused/second boot,
repeated `systemctl restart gdm` cycles - always failed, with or
without the shim's own 5s startup delay (see below).

## What was ruled out (with evidence)

- NOT a settling/AppArmor-profile-reload timing race: adding a 5s
  `sleep` before the shim's `exec core-desktop-session-wrapper.sh` did
  NOT eliminate any denials - the exact same `mknod .hidden` denial
  (already known-harmless, per the confined-session notes) recurred
  unchanged, just 5s later. A genuine manual/password login at ~56s
  post-boot logged 308 similar AppArmor DENIED entries in the same
  window and still succeeded (active seat0/tty2 session). Denials
  clearly occur in both successful and failed sessions - they are not
  themselves the cause.
- NOT a boot-count/first-vs-second-boot issue: confirmed via the raw
  serial console (kernel boot banner "Linux version" appears exactly
  once) that GDM/autologin ran and failed within a single, genuine,
  uninterrupted kernel boot - not during some earlier "install" phase
  that needed a reboot to clear. (Also: with `--nouser`/`auto-import`
  not applying due to the separate model-mismatch bug below,
  `your_username` only ever exists via the cloud-init seed
  (`build-cloud-init.sh`), which runs within that same single boot, not
  via a separate account-creation boot.)
- NOT a PAM-stack gap between `gdm-password` and `gdm-autologin`:
  diffed both files directly on a live VM - their `session` stacks are
  byte-identical (`@include common-session`, containing
  `pam_unix.so`/`pam_systemd.so`); neither stack (nor
  `common-session`/`common-auth`) references any AppArmor-related PAM
  module at all. Snap confinement on this system is attached to the
  executables themselves (via snap-confine at exec time), not driven by
  which PAM stack opened the session, so this theory doesn't match the
  actual config.
- A longer (60s) delay was specifically NOT tried through GDM itself,
  because GDM's registration timeout appears to be counted from PAM
  session-open (fixed, roughly 20-25s in observed tests), not from
  when the confined session actually starts doing work - a longer
  shim-side delay would only eat further into that budget, making
  things worse, not better. (This reasoning, not a live test, is why it
  wasn't attempted - if pursued further, confirm this budget precisely
  first.)

## Leading hypothesis (not yet confirmed)

This is very likely the SAME already-open, already-assigned bug as
`20260917-post-login-grey-screen-gnome-session-timeout.md`:
`gnome-session-manager@ubuntu.service` intermittently fails to complete
its startup handshake under confinement (that note's evidence includes
AppArmor DENIED events on D-Bus method calls carrying a stacked
`snap.ubuntu-desktop-session.ubuntu-desktop-session//&unconfined` label
- the exact same stacked-label pattern was also observed during this
autologin investigation). That note describes the failure as
"intermittent" on manual logins (sometimes grey-screens, sometimes
works) with a 90s `StartupTimeoutSec`. Autologin likely just has much
less timing slack before GDM's OWN (separate, shorter) registration
timeout than a manual login does, so it hits the same underlying
confined-session-startup flakiness far more reliably/consistently (100%
in this investigation) instead of intermittently.

## Goal

Confirm whether fixing the root cause in the (already assigned, still
open) post-login-grey-screen investigation also fixes autologin's
100%-reproducible failure. If they turn out to be unrelated after all,
come back to this note and investigate the confined session's startup
path specifically under `gdm-autologin` vs `gdm-password`/normal login
(e.g. differences in session type, VT/seat assignment timing, or
whatever environment/arguments GDM's autologin path passes vs. what a
normal `.desktop`-session launch provides - manual login never goes
through `/usr/bin/gnome-session` at all, so isn't a perfectly clean
comparison).

## Suggested investigation approach

- Start from whatever progress exists on
  `20260917-post-login-grey-screen-gnome-session-timeout.md` rather
  than re-deriving from scratch.
- Once that root cause is fixed/understood, retest `--autologin` on the
  Core 26 image (rebuild with `--autologin`, boot with a seed.iso or
  after the `system-user.json` model-mismatch bug is fixed) and update
  this item and the `--autologin` caveat in the project's build
  documentation accordingly.
- If the fix does NOT resolve autologin specifically, capture a full,
  uninterrupted journal (`journalctl -b --no-pager`, not filtered) for
  one fresh autologin failure cycle and compare line-by-line against a
  successful manual login's journal from the same boot, focusing on
  what `gnome-session-manager@gnome-login.target` / `ubuntu.target`
  services and D-Bus activity happen (or don't) in each case.

## Fix (2026-09-17, later same day)

This turned out to be a THIRD, separate bug from both of the two
theories above (not the AppArmor-profile-timing race, and not the same
root cause as the grey-screen `gnome-session-manager` timeout).

Root cause: `/tmp/snap-private-tmp/snap.ubuntu-desktop-session` was
getting corrupted to mode `01777` (instead of the required `0700`) by a
bug in `cmd/snap-update-ns`'s `MkPrefix` (applies a single mode
uniformly to every directory segment it creates along a missing path,
rather than consulting a per-segment mode hint - see `f3169086dc`/2020,
present since the mode-hints feature's inception, not a regression).
Once corrupted, `snap-confine`'s `setup_private_tmp()` reliably
`die()`s with "unexpected ownership / permissions: File exists" on
EVERY subsequent launch attempt (it only fixes permissions on
directories it creates itself, never on ones that already exist) - this
is exactly the "session opened -> closed within ~1s/~226ms -> Session
never registered, failing" signature described above. It affects manual
login identically, not just autologin; autologin's tight registration
timeout window just made the underlying corruption manifest as a
100%-reproducible failure instead of an intermittent one.

Fixed upstream in `cmd/snap-update-ns`: `MkPrefix`
(`MkdirAll`/`MkfileAll`/`MksymlinkAll`) now looks up each directory
segment's own mode via `Assumptions.ModeForPath()` instead of reusing
the leaf's flat mode. Verified end-to-end on the VM: with this fix,
`snap.ubuntu-desktop-session` stays `0700`, `--autologin` succeeds
(confined `gnome-shell --mode=ubuntu` running on seat0/tty2, zero
`die()`/ownership errors in the journal), and manual login (built
without `--autologin`) also succeeds. No further workaround is required
in `ubuntu-core-desktop`.

Fix submitted upstream as canonical/snapd#17665 (branch
`fix-tmpdir-permissions-bug` in `ubuntu-core-desktop-snapd`,
cherry-picked onto `upstream/master`). Check whether that PR has merged
before assuming a local workaround is still needed.

This item is complete.
