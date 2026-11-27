# Seed change errors early, then parks in Wait; only a reboot resumes it

## Impact / Priority

High for CI reliability: two PR builds failed at ~35 min each
(2026-11-26, 2026-11-27) and the failure mode is transient - the same
content had a green run two minutes after the red one. The user-facing
side is suspected but not yet reproduced: GDM is ordered behind
`snapd.seeded`, so a first boot that hits this error would sit on the
boot splash indefinitely, and the only recovery is a reboot. Pinning
down the real-hardware impact needs the error text (open question 1).

What is observed, precisely (from the CI gate dump f81fb81 added):

- ~3 min into first-boot seeding, the "Initialize system state" change
  goes to Error; its last undone tasks are the pipewire cluster
  ("Setup snap "pipewire" security profiles" and its interface
  connects). The task log was not captured by that dump, so the error
  text is still unknown.
- snapd immediately spawns a second "Initialize system state" change
  in Wait status, and nothing further happens: no apparmor_parser
  running, `snapd.seeded` activating forever.
- WaitStatus means "task accomplished but some external event needs to
  happen" - in practice "resume after a reboot"
  (overlord/state/change.go in the snapd fork). The gate used to just
  watch that park for the remaining 27 minutes, which is why the
  timeout fired at 30 min with nothing running.

Runs (canonical/ubuntu-core-desktop, build-image.yaml):

- 45990228770 (2026-11-27, PR "Workshop image environment"): change 1
  Error 11:29->11:32, change 3 Wait from 11:32, gate failed 12:00.
- 45834432211 (2026-11-26, same PR, earlier head): identical
  signature, errored 14:02->14:05, then parked to the 30-min limit.
- 45990450048 (2026-11-27, started 2 min after the failure, same
  content): seeded in ~110 s, whole gate green in ~6.5 min. So the
  seed error is transient, not content-dependent.

This is NOT the slow-apparmor-parsing case that commit f81fb81
addressed: in both dumps no apparmor_parser was running at all. That
commit's `-smp 4` fix stands (green runs seed in ~2-3 min), but the
30-minute timeouts since then all belong to this issue. See
`20261125-apparmor-profile-setup-slow-single-threaded.md` for the
correction and `20261123-simplify-image-build-workflow.md` for the
gate's history. The arm64 "snapd.seeded sat running for 13 min, twice"
note in `20261124-fix-broken-installer.md` may be the same failure
mode on different hardware.

## Done (2026-11-27): the gate now detects the park and reboots once

Commit 47d16d5 (both image workflows): during the cold-boot wait, every
2 minutes, check for "a change in Error status while no change is
Doing" - that is exactly the parked state (during snapd's own
undo/retry the change shows Doing/Undoing, so those don't trigger).
On detection:

1. dump the evidence while the guest is still up;
2. reboot the guest once (`sudo systemctl reboot`, clean reset - the
   qemu process stays up and the wait loop keeps polling, printing
   "unreachable" while the guest is down). snapd resumes the parked
   change on the new boot; a resumed boot seeds in ~2-3 min;
3. if it parks again (or the park is found after iteration 150/180,
   too late for a reboot), fail immediately with the evidence - a
   deterministic failure now costs ~10 min instead of 35.

The dump was upgraded at the same time: it prints each Error/Wait
change in full (`snap change <id>`, i.e. the actual task log with the
error text), the snapd journal tail, an OOM check, and the
apparmor_parser check; the misleading "(diagnostics ssh failed)" line
is gone (it was `systemctl is-active` exiting 1 while seeding
activates).

## Done (2026-11-27 later): mechanism verified, CI capture + experiments

The first post-fix CI park (run 46008820280) triggered the dump and
answered open questions 1-3:

1. The seed error is NOT an apparmor_parser kill. `snap change 1`
   shows: `ERROR Post "http://1000/v1/service-control": read unix
   @->/run/user/1000/snapd-session-agent.socket: read: connection
   reset by peer` (task "Make snap "ubuntu-desktop-a11y" available"),
   and the resumed change re-failed the same family: `Start snap
   "ubuntu-desktop-a11y" services failed: ... connect: connection
   refused`. Earlier field failures had their undone clusters next to
   pipewire's user services - same trigger, previously invisible.
2. The reboot resume works: change 3 flipped Wait->Do and ran, but
   re-errored (agent socket unavailable again) and was queued for
   undo; the gate failed fast with evidence. Detector refinement:
   queued states (Do/Undo) must count as busy.
3. The park mechanism: the retry change is built by the normal
   install machinery, whose gadget link-snap is a Do restart boundary
   (`setDefaultRestartBoundaries`, snapstate/reboot.go); when it
   completes, doLinkSnap requests a system restart, and CoreDesktop
   snapd never reboots itself - processRestartForChange
   (overlord/restart/restart.go) notifies the desktop session instead
   and logs "Postponing restart until a manual system restart allows
   to continue". No session exists mid-seed, so the park is permanent.
   First-seed changes are built by populateStateFromSeedImpl with no
   such boundary, which is why healthy seeds never park.

Root cause (why the agent socket dies): snapd manages user-scope snap
services through per-user session agents, discovered by globbing
/run/user/*/snapd-session-agent.socket (clientutil/session.go). The
agent is a systemd --user unit that exists only while the user has a
session. During first-boot seeding the gate's own SSH poll loop
creates the only sessions: a <1 s login every 10 s. When a
service-control POST lands while the last poll session closes, the
user manager stops (logind GCs it; KillUserProcesses only governs
session scopes, not this) and the socket dies mid-request (reset), or
a stale socket file answers nothing (refused).

Verified by a three-phase experiment on a local image (only the SSH
pattern varied):

- no SSH at all: seeds clean (empty glob -> snapd skips user ops);
- SSH storm, overlapping logins every ~1 s: seeds clean (a session
  always exists, the agent never goes away);
- one held-open ControlMaster session: seeds clean;
- sparse poll (one short login every ~10 s, the CI rhythm): fails
  with exactly the captured reset/refused errors.

So the trigger is not load or memory (systemd-oomd is not in the
image; snapd's parser call has no timeout; snapd.service has
KillMode=process and no memcg limits; no kernel OOM anywhere) - it is
the agentless GAP between sparse SSH polls.

Fix (landed): core-base-desktop now ships drop-ins ordering
ssh.service, ssh.socket and sshd@.service after snapd.seeded
(static/etc/systemd/system/*.d/10-seed-order.conf), so port 22 only
answers once seeding is done; dev and wizard images keep SSH fully
enabled, and "ssh connects" becomes a truthful readiness signal. The
CI gate SSH-wait budget was raised to 30 min to absorb seeding, the
park detector treats queued changes as busy, and the dump gained the
logind/user@1000 journal tails (the teardown actor's own record).

Upstream: stock Ubuntu Core with a system-user assertion (SSH keys)
is exposed the same way - assertions are auto-imported during seeding
by design, with ssh.socket already listening - and any agent-driven
first boot (Workshop: enable SSH, connect the moment the host
answers) hits this. The daemon-level race (a user-scope service error
failing the whole change, and the refresh-flavour of the same race on
running systems, where a transient session dying mid-refresh rolls
the refresh back) is filed separately for snapd maintainers; see
`20261127-snapd-user-service-session-agent-race.md`.

## Open questions

## Notes

- Do not shrink the 30-minute seeding budget over this: a parked seed
  now fails in ~10 min on its own, and the budget still covers slow
  (not parked) seeding, which is the case
  `20261125-apparmor-profile-setup-slow-single-threaded.md` documents.
- Do not retry the workflow run in a loop as a workaround: the same
  transient error can recur, and each failed attempt costs 35 min.
  The gate's one reboot is the cheap, targeted retry.

## Resolution (2026-11-27)

Fixed at the base level, verified in a real boot, and shipped upstream
as a proposal:

- canonical/core-base-desktop commit `baac940` (desktop/26): drop-ins
  ordering `ssh.service` and `sshd@.service` after
  `snapd.seeded.service`, so no sshd session can exist during
  seeding - the race door is closed structurally. `ssh.socket` is
  deliberately NOT ordered the same way: that creates an ordering
  cycle (basic.target -> sockets.target -> ssh.socket ->
  snapd.seeded -> basic.target) which systemd resolves by dropping
  the snapd.seeded edge, killing ssh.socket for the whole boot -
  caught and verified in the first validation boot. Also pins chisel
  and bypasses pkgproxy for the `go install` (its Go module cache
  only covers module roots; the subpath @latest resolution 403s on a
  cold cache).
- canonical/core-base-desktop CI rebuilt and published the fixed
  desktop-variant base to `desktop-26-latest` (16:42Z).
- `ubuntu-core-desktop` commits `47d16d5` (gate: park detection +
  reboot-resume + full `snap change`/journal dumps) and `474ece6`
  (SSH-wait budget 10->30 min since the SSH wait now absorbs seeding;
  detector treats queued Do/Undo as busy; dump adds logind and
  user@1000 journals).
- Validation: image rebuilt on the fixed base, booted with an SSH
  storm (~1 login/3 s) across the whole seed window - 0 ordering
  cycles, 0 service-control errors, seeding Done, post-seed SSH OK.
  The unpatched image under the same storm reproduced the captured
  seed errors.
- Upstream proposal: canonical/core-base#494 (closes #493); the
  daemon-level race is filed for snapd maintainers as Launchpad bug
  #2178247 (GitHub issues are disabled on canonical/snapd) - tracked
  in `20261127-snapd-user-service-session-agent-race.md` (waiting).

End-to-end CI confirmation is the only residual: the first
build-image run consuming the fixed base (published 16:42Z) is the
final check; the gate's reboot-resume path keeps CI green even if
some other transient error recurs.
