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

## Open questions

1. The error text itself. The next parked run will show
   `snap change 1`; until then candidates include a transient
   apparmor_parser failure under runner I/O pressure and a pipewire
   interface-setup error. Note the gate fix is what surfaces it.
2. Does the resume reboot actually recover (the theory behind the
   Wait mechanism), or does seeding error again deterministically?
   The first parked run after 47d16d5 answers this from the log.
3. Is "park in Wait after a seed error" intended snapd behaviour? If
   the reboot resume works, it is defensible (matches classic
   install-mode recovery); if it re-errors every boot, the error text
   decides where to fix. Our snapd fork lives in
   ubuntu-core-desktop-snapd; upstreaming path in
   docs/upstream-contributions.md.
4. Real-hardware impact (see Impact above): needs a reproduced first
   boot, or the snapd journal from an affected machine.

## Notes

- Do not shrink the 30-minute seeding budget over this: a parked seed
  now fails in ~10 min on its own, and the budget still covers slow
  (not parked) seeding, which is the case
  `20261125-apparmor-profile-setup-slow-single-threaded.md` documents.
- Do not retry the workflow run in a loop as a workaround: the same
  transient error can recur, and each failed attempt costs 35 min.
  The gate's one reboot is the cheap, targeted retry.
