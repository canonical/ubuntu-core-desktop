# snapd: user-scope service ops race the session agent; failures error whole changes

Filed for snapd maintainers to evaluate; we are not working on this.
Impact on our project and reproduction evidence below - the fix choice
is theirs.

## The mechanism

snapd manages user-scope snap services (start/stop on install,
refresh, connect/disconnect) through per-user "session agents". Which
users get these operations is decided by globbing
`/run/user/*/snapd-session-agent.socket`:

- `client/clientutil/session.go`: `AvailableUserSessions()` returns
  the uids that currently have a `snapd-session-agent.socket`.
- The session agent is a systemd --user unit
  (`data/systemd-user/snapd.session-agent.socket`), so the socket
  exists only while the user's systemd --user manager runs, i.e. only
  while the user has a session.
- The code explicitly knows this is racy - overlord/servicestate/
  helpers.go, `affectedUids()`:

      // This is inherently racy, i. e this can easily become
      // out of sync by the time we actually invoke the user-session
      // agents, where a user may have logged out, or one logged in
      // (i. e worst case we may miss a user, if someone logged out
      // the user is ignored).

The tolerance described in that comment ("a user who logged out is
ignored") is only implemented for one direction of the race. The other
direction - the socket was seen by the glob, but the user's session
ends while the service-control request is in flight - is a hard task
error:

- agent killed mid-request -> `Post "http://<uid>/v1/service-control":
  read unix @->/run/user/<uid>/snapd-session-agent.socket: read:
  connection reset by peer`
- stale socket file (user manager stopped between glob and connect) ->
  `... connect: connection refused`

In both cases the task fails, which on a seed change triggers lane
undo and a change Error; on a refresh change it triggers a rollback of
the refresh.

## Reproduction (our CI, 2026-11-26/27)

Ubuntu Core Desktop image boot gate: the gate image is built with a
baked user + SSH keys, and the gate polls SSH readiness once every
10 s while first-boot seeding runs. Each poll creates a transient
logind session; when the last one closes, logind stops user@1000 and
the agent socket dies. Three runs failed with exactly the errors
above (one captured after we added full `snap change` dumps:

- canonical/ubuntu-core-desktop run 46008820280, `snap change 1`:
  `ERROR Post "http://1000/v1/service-control": ... connection reset
  by peer` in "Make snap "ubuntu-desktop-a11y" (x1) available to the
  system"; after a reboot-resume, `Change 3 task (Start snap
  "ubuntu-desktop-a11y" (x1) services) failed: ... connect:
  connection refused` in the snapd journal.
- On CoreDesktop the retry change then parked permanently in Wait:
  the retry is built by the normal install machinery, whose gadget
  link-snap is a Do restart boundary; when it completes, snapd
  requests a system restart, but on CoreDesktop
  `processRestartForChange` (overlord/restart/restart.go) instead
  notifies the desktop session and logs "Postponing restart until a
  manual system restart allows to continue". Mid-seed there is no
  session and nobody to reboot manually, so first boot never
  completes. On stock UC the same sequence auto-reboots (ugly but
  self-healing).

Controlled experiment (only the SSH pattern varied, image fixed):

- no SSH during seeding: clean (empty glob -> the user-op phase is
  skipped entirely);
- overlapping SSH logins every ~1 s: clean (a session always exists);
- one held-open session: clean;
- one short login every ~10 s (the CI poll rhythm): fails with the
  captured reset/refused errors.

So the trigger is the agentless *gap* between sparse polls, not load
or memory: the image has no systemd-oomd, snapd's apparmor_parser
invocation has no timeout, snapd.service has KillMode=process, no
memcg limits, and no kernel OOM appears anywhere.

Exposure beyond our gate: any system where a user with valid
credentials exists before seeding completes - Ubuntu Core images with
SSH keys in a system-user assertion (assertions are auto-imported
*during* seeding by design), and agent-driven workflows that enable
SSH and connect the moment the host answers. The refresh flavour also
affects ordinary running systems: a user logging out while a refresh
starts their user-scope services can fail and roll back the refresh.

## Options we can see (for maintainers to weigh)

1. Fail-soft: treat agent-gone (ECONNRESET/ECONNREFUSED on the
   session-agent socket) like the already-designed "user logged out,
   ignore them" case - log, skip, let the services start at the next
   login. Smallest change; makes the race non-fatal everywhere.
2. Defer user-scope service operations while the system is not yet
   seeded (`seeded == false`): there is no real session to serve
   mid-seed; socket-activated/first-login starts make the skip
   invisible.
3. Bounded retry with backoff on those two errnos in the usersession
   client.
4. CoreDesktop restart policy during seeding: gate the
   "Postponing restart until a manual system restart" path on
   `seeded == false` so a failed seed can self-heal by reboot like
   stock UC instead of parking forever.

1 + 2 together cover the severe case (seeding park) and the mild case
(refresh rollback on running systems).
