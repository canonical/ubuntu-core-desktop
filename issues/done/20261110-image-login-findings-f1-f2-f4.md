# Image login/session findings from the a11y E2E (F1/F2/F4) — NOT a11y scope

## Impact / Priority

F1 (P0): no normal user login on the affected image variant — logging
in as any non-GDM account fails with "Session never registered",
while the wizard path works. F2 (P1, security): password checks are
not enforced — PAM rejects the hash and pam_permit then grants
authentication without any password check. F4 (P1): after the
workaround, the dispatched session stalls before gnome-shell, so the
desktop does not come up via the normal dispatch path. Triage order
from the note: F2 first (security), then F1 (blocks all login
testing), then F4. 2026-11-11 update: all three are FAT-image
findings — on the thin (core26-desktop desktop/26) image F1 does not
manifest, F2 is absent (fail-closed, also tested on the greeter
path), and F4 is fixed/verified.

Impact derived from the original note's symptoms.

## Context

Written 2026-11-10, spun out of the accessibility E2E
(`20261109-bring-accessibility-up-to-regular-ubuntu-desktop-levels.md`,
task T7b, full evidence in the T7b session-E2E report). These are
image-level login/session bugs discovered while trying to reach the
desktop session for the a11y matrix. They block normal login on the
current main-repo base image but are owned here, not by the a11y
todo. The a11y agent used a documented, revertible desktop-file
dispatch edit on the T7b VM to run a degraded session; that edit is
NOT a fix and must not be treated as one.

### F1 (P0) — content-launcher guard refuses every non-GDM account

Symptom: logging in as any non-GDM account (the seeded t7b user)
fails with "Session never registered" — the content-launcher guard
rejects the account, so the session never starts.

Impact: no normal user login on this image variant.

Note: the wizard (gnome-initial-setup) path works; only real-user
login is broken.

### F2 (P1, SECURITY) — PAM fail-open: password checks are not enforced

Symptom: pam_extrausers REJECTS the YESCRYPT-style hash, and
pam_permit then grants authentication WITHOUT any password check —
i.e. any password (or none?) authenticates.

Impact: password auth is broken-open on this image. Root/x ssh is
by design (test image), but this affects the greeter/login path.

Possible relation:
`20261108-investigate-accountsservice-security-issue.md`
(reconcile before fixing).

### F4 (P1) — dispatched session stalls before gnome-shell

Symptom: after the F1 workaround (desktop-file dispatch edit), the
dispatched session stalls before gnome-shell starts; the session
definition appears invisible to the confined service.

Impact: desktop session does not come up via the normal dispatch
path even when the account is accepted.

Also recorded from the same run (backlog classes, see the a11y
todo's denial backlog + T7b sweep section):

- provd (snap-routed daemon) crash-loops on gdm OpenSession /
  accounts Ping / keyring RequestName — 852 denials (the raw-exec
  unconfined provd is what actually runs; see the base-variant
  decision in the a11y todo's T7a-fix entry).
- registryd RegisterClient, SetIdleHint, wayland runtime-dir
  mismatch denials.

Verification/ownership: each of F1/F2/F4 needs its own root-cause
pass on a fresh image (the T7b VM retains the documented workaround
state). Priority: F2 first (security), then F1 (blocks all login
testing), then F4.

## Update 2026-11-11 (T22, thin line only)

F-class outcomes on the THIN (core26-desktop desktop/26) image; full
evidence in the T22 thin-login report; prior thin boot in T21:

- F1: NOT-MANIFESTING on thin, live-PROVEN (wizard-continued session
  AND greeter password login as a wizard-created real user reach a
  confined desktop; 0 "refusing content runtime" / "Session never
  registered" lines). The gnome-content-launch alias allowlist
  (gdm*/initial-setup*) is off the real-user path on thin by design:
  the static /usr/bin/gnome-session wrapper routes real users to
  core-desktop-session-wrapper.sh, and the content snap's user-unit
  core-overrides dispatch gnome-shell/gnome-session-service via
  `gnome-content-launch --session-dispatch` to the confined session
  snap. Guard left UNTOUCHED (load-bearing); NO fix, NO commit. F1
  remains FAT-ONLY.
- F2: absent on thin, now fail-closed-tested on the GREETER path too
  ($y$ wizard-set hash; wrong password REJECTED verbatim:
  pam_extrausers(gdm-password:auth) authentication failure /
  res=failed; right password accepted). Stays FAT-ONLY. Caveat
  recorded: on this PAM build, audit grantors= for a SUCCESSFUL auth
  shows pam_permit-only shape even when the password was checked
  (same shape for root sshd) — do not diagnose fail-open from
  grantors alone.
- F4: FIXED/VERIFIED LIVE on thin — the dispatched session reaches
  gnome-shell confined (exe=/snap/ubuntu-desktop-session/x1/gnome/
  usr/bin/gnome-shell --mode=ubuntu, label
  snap.ubuntu-desktop-session.gnome-shell enforce). Fat's stall does
  not reproduce; the thin dispatch wiring (content-snap user units
  via user.control + core-override dispatch) is the fix that already
  ships.

## Resolution (appended on import)

All three findings were FAT-variant issues, closed by the thin-base
line: on thin (core26-desktop desktop/26), F1 does not manifest (the
wrapper routes real users around the content-launch guard), F2 is
absent and fail-closed (verified on the greeter path too), and F4 is
fixed/verified live (the thin dispatch wiring ships). No thin-side fix
was needed; nothing committed against this file.
