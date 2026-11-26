# snapd: "cannot track application process" when the launch env has no bus

Date: 2026-11-20

Root-caused during the Ubuntu Core Desktop a11y gates (the
T34/T44/T48/T49 arc; the T49 live verification is described
below).

## Impact / Priority

Any launch context with a scrubbed/partial environment breaks snap
app launches entirely — the greeter managers with dynamic uids, the
ssh/cron-driven snap runs, the env-scrubbed wrappers. The failure
looks like a broken snap (the rc=1, no explanation to the user).

## The defect

snap run fails with "error: cannot track application process" when
the launch environment does not carry a session bus address. The
tracking (the systemd transient scope snap.<snap>.<app>-<uuid>.scope
that identifies the app's processes) is created over the SESSION
bus for non-root, and the bus address is resolved from the LAUNCH
ENVIRONMENT ONLY ($DBUS_SESSION_BUS_ADDRESS, then
$XDG_RUNTIME_DIR/bus via godbus). Launches from contexts whose env
does not carry the address — a pam session that has closed,
/run/user/<uid> teardown races, env-scrubbed wrappers (runuser,
ssh, cron, a greeter manager with a dynamic uid) — hard-fail on
core26+ bases (upstream 171769f800, SNAPDENG-34299: the tracking
failure is deliberately fatal because device-cgroup enforcement
depends on it).

## Root-cause nuance (the T49 live verification)

godbus's own address discovery ALSO falls back to the canonical
per-user socket — the real difference is that godbus depends on
user.Current(), which FAILS for a dynamic-uid greeter user. The
env-free launch with the socket present fails only because the
address is never exported.

## The draft patch (ready)

dbusutil SessionBus: when the env lacks an address and the
canonical socket /run/user/<uid>/bus exists as a socket, export
DBUS_SESSION_BUS_ADDRESS=unix:path=<socket> so both the presence
check and godbus find the bus (the same fallback systemd-run and
other launchers apply). `git apply --check` clean against
desktop/26; the T49 live verification PASSED: the env-scrubbed
launch flipped FAIL→PASS end-to-end (the transient scope created,
the app executed inside the snap), the control (the env pre-set)
unchanged, and the genuinely-session-less case still fails by the
SNAPDENG-34299 policy (the fallback's boundary, documented).

## Tasks

1. UPSTREAM-FIRST: review the SNAPDENG-34299 discussion (the
   deliberate hard-fail) — the patch must be positioned as the
   address-resolution improvement, NOT the policy relaxation (the
   tracking still fails hard when NO bus exists).
2. THE PATCH SUBMISSION: the draft is apply-checked against
   desktop/26 and live-verified; update it against the current
   upstream master, add the test (the T49 verification recipe is
   the test: the env-scrubbed launch with the socket present), and
   submit to snapd upstream with the SNAPDENG-34299 context.
3. THE A11Y DEPLOYMENT: our fork's lineage carries the fix
   (4835bf2910, pushed); the upstream acceptance removes the
   fork-only delta.

## Status

[2026-11-20] Issue created. NOT STARTED (the draft patch + the
live verification are DONE — only the upstream submission
remains). The fork's lineage (4835bf2910, pushed to
chris-bainbridge/snapd and canonical's desktop/26 via
e01549bbb9) carries the fix; the upstream acceptance removes
the fork-only delta.
