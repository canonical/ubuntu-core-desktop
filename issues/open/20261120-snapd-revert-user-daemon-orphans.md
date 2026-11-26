# snap revert: newer-revision user daemons orphaned, user services not restarted

Date: 2026-11-20

Found during the Ubuntu Core Desktop a11y lifecycle testing (the
T41 finding N2 — the full evidence is in the T41 C8 write-up;
also recorded as the a11y spike todo's [2026-11-19] T41 entry).

## Impact / Priority

Revert is the ROLLBACK mechanism — it is invoked precisely when the
new revision is broken. Leaving the running state orphaned (the
old sockets, the mixed revisions, the dangled address resolution)
means the rollback does not actually restore a working state: the
operator must log everyone out or reboot.

## The defect

`snap revert <snap>` returns the snap to the previous revision but
does NOT restart the snap's user services (the apps with
refresh-mode: endure and the socket-activated units). Observed
live with the a11y snap (the bus + speech-dispatcher apps, both
endure, socket-activated):

- After the revert to x1, the NEWER-revision launcher and
  dbus-daemon kept running as orphans BESIDE the fresh x1 launcher
  (two generations of the same daemons, the old ones still bound to
  the x2 sockets).
- The at-spi GetAddress resolution DANGLED: the clients resolving
  through the old process got addresses the fresh profile did not
  grant, until a manual daemon start.
- A FRESH SESSION (logout/login) recovered fully — the workaround
  exists, but the reverted state between the revert and the next
  login is broken for every running client.

## The corollary (the same test)

A non-path-changing refresh (the same content re-sideloaded as a
new revision) behaved correctly — the defect is specific to the
revert path (and the path-changing refresh, which has its own C8
entry).

## Tasks

1. UPSTREAM-FIRST: search snapd's GitLab for the revert + user
   services + endure-mode discussions (the snapd revert handling
   of user services/sockets; the RefreshUsers interrupts?).
2. THE MINIMAL REPRO: the T41 recipe (the a11y snap x1 → x2 →
   revert; the verbatim orphan evidence is in the T41 write-up —
   re-run on the current snapd to confirm it still reproduces).
3. THE FIX PROPOSAL: on revert, snapd should stop the current
   revision's user processes and restart the previous revision's
   (the mirror of the refresh behavior for endure apps), or at
   minimum terminate the orphaned processes so the socket
   activation spawns the fresh ones.
4. SUBMIT upstream with the verbatim evidence.

## Status

[2026-11-20] Issue created. NOT STARTED. The T41 repro recipe +
the verbatim orphan evidence are in the T41 write-up; re-run on
the current snapd before filing.
