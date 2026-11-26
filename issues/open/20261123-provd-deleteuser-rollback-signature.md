# provd CreateUser rollback calls DeleteUser with the wrong D-Bus signature

## Impact / Priority

Priority: Medium (masked today by a bigger bug, but structural).

What a real user sees, grounded in the 2026-11-23 live wizard run on
the test VM (PR core-base-desktop#92 verification): whenever provd's
CreateUser flow fails after the account was already created
(useradd ran), provd tries to roll the user back, the rollback's
DeleteUser call is rejected by accounts-daemon, the user stays behind,
and the wizard UI hangs on the identity page with a spinner forever
(the Flutter app takes the gRPC error as an unhandled exception; no
error page). Recovery is a hard reboot, after which the leftover
account still logs in with the chosen password (SetPassword ran before
the failure).

Today the rollback path fires on the wizard's AUTOLOGIN-ON flow (the
"require my password" checkbox UNCHECKED): provd calls
SetAutomaticLogin(true), and accountsservice's save path fails on the
accountsservice snap's AppArmor gap (see
`20261123-accountsservice-snap-gdm3-apparmor-grants.md`). The DEFAULT
(checkbox CHECKED) flow completes: SetAutomaticLogin(false) hits the
early-return in daemon_local_set_automatic_login
(`priv->autologin != user && !enabled -> TRUE`) and never touches
custom.conf — verified live 2026-11-23 (flow completed, handoff ran,
user session started on the 0.1.5-provd image). Once the AA gap is
fixed the autologin path stops reaching the rollback too, but it stays
reachable on any genuine mid-flow failure (disk full, hostname service
failure, ...), where the same orphan-user + wedged-wizard behaviour
returns.

## Evidence (live run + source)

- provd journal: `WARN error encountered when rolling back CreateUser:
  Type of message, "(t)", does not match expected type "(xb)"`;
  the user remained in /var/lib/extrausers/passwd and
  ubuntu_init logged `Unhandled exception GrpcError ... failed to set
  autologin: failed to change automatic login: Permission denied`.
- provd/internal/services/user/user.go:127 calls
  `s.accounts.Call(...+".DeleteUser", 0, userID)` with userID a
  uint64 — one argument. AccountsService's real signature is
  `DeleteUser(id x, remove_files b)` (gint64 + gboolean; confirmed in
  the accountsservice source). godbus marshals a lone uint64 as "(t)".
- Why tests never caught it: the test mock
  (provd/internal/testutils/accounts_mock.go) implements
  `DeleteUser(userID uint32)` and its introspection XML declares a
  single `u` argument — the mock encodes provd's own bug instead of
  the real signature, so unit tests validate the broken call.

## Fix

- user.go:127: pass `int64(userID), true` (D-Bus "x" + the
  remove_files bool; the rollback should remove the just-created
  account's files).
- accounts_mock.go: handler signature `DeleteUser(userID int64,
  removeFiles bool)`, XML args `x` + `b`, action string updated
  (the mock fix is the regression guard: with the real signature
  exported, a wrong-arity call fails the tests instead of production).
- Regenerate the affected goldens (`go test -update`): e.g.
  error_when_setting_hostname_rolls_back_user records
  `Accounts.DeleteUser(userID: 1001)` today.

## Upstream

canonical/ubuntu-desktop-provision is the upstream (public repo; the
local clone has origin=chris-bainbridge fork + upstream=canonical).
Plan: branch off upstream/main, land the fix + mock fix there, open a
PR. The owner wants to review the diff before the PR is filed.

## Verification (2026-11-23 — done, fix awaiting owner review)

- Unit: provd test suite green with the corrected mock (12 packages ok;
  the affected golden regenerated to
  `Accounts.DeleteUser(userID: 1001, removeFiles: true)`).
- E2E on a fresh nouser image with the source-built fixed provd
  (provd-src-built flow): wizard run → SetAutomaticLogin fails (the
  accountsservice AppArmor gap, deliberately still present) → the
  rollback now REACHES the daemon: journal shows
  `accounts-daemon: request ...: delete user 'wizard-test' (1000)` and
  the "(t)/(xb)" mismatch warning is GONE.
- Residual failure found one layer deeper (see
  `20261123-accountsservice-snap-gdm3-apparmor-grants.md`): the daemon's
  DeleteUser runs PLAIN `/usr/sbin/userdel` — the PPA shadow build
  (patch 1013_extrausers_deluser) makes extrausers an OPT-IN flag
  (`--extrausers`), and the PPA accountsservice daemon passes
  --extrausers on its CreateUser-path helpers but NOT on DeleteUser's
  userdel → userdel exits 6 (not found in /etc/passwd) and the user
  remains. Verified `/usr/sbin/userdel --extrausers -r <user>` removes
  the extrausers user + home cleanly, so the rollback completes once
  the daemon-side argv (or a snap-side wrapper, the chpasswd-guard
  pattern) adds the flag.
- Toolchain gotcha hit on the way (go1.26.8): `go test -update PKG`
  with the flag BEFORE the package list silently ran the WRONG package
  ("[no test files]", exit 0) — the test-binary flag must go AFTER the
  package list (`go test PKG -update`).
- Upstream PR: FILED 2026-11-23 after the owner reviewed the diff
  (requested dropping the explanatory comment — the fix is a one-liner,
  the explanation lives in the commit message) and the local
  test/upstream-main cherry-pick was refreshed to match:
  canonical/ubuntu-desktop-provision#1634, from the fork branch
  fix/deleteuser-signature (upstream/main + the one-liner).
- Related delivery work (same provd source stream): the a11y handover
  writer reached no published provd.snap until
  canonical/provd-snap gained the pinned-source build — see
  `20261123-accountsservice-snap-gdm3-apparmor-grants.md`'s DELIVERY
  section for the branch/pin ladder (fork core26-provd integration
  branch @ fb2d845b2 until the PRs merge, then canonical:main).
