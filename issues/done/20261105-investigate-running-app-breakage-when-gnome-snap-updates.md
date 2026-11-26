# Running snap apps break when a gnome/mesa content snap refreshes

Date: 2026-11-05

## Impact / Priority

A running snap app (e.g. firefox) can break mid-session when its
gnome/mesa content provider snap refreshes underneath it: the running
process's cloned mount namespace does not get the re-established
content mounts, so pages fail to load and journal errors appear until
the app is relaunched. New processes started after the refresh are
fine -- only the already-running instance is affected. Priority: Low
(not blocking the core26 migration - monitoring/verification task).
Impact derived from the original note's symptoms.

## The bug

LP#2016358 - "Running firefox instance malfunctions after refresh of
gnome-42-2204 snap"
https://bugs.launchpad.net/ubuntu/+source/snapd/+bug/2016358
Status: In Progress, High, assignee James Henstridge (NOT fixed as of
2026-11-05; last public activity 2024-10 asking for progress).

What happens (2023 report, firefox on core22):
- gnome-42-2204 (content provider) auto-refreshed overnight while firefox
  was RUNNING.
- The running firefox's cloned mount namespace (the desktop interface sets
  up a private namespace for the $XDG_RUNTIME_DIR/doc bind) did NOT get the
  re-established content mounts propagated: /proc/<pid>/root/snap/firefox/
  <rev>/gnome-platform was EMPTY for the running process.
- Symptoms in journal: LD_PRELOAD .../gnome-platform/$LIB/bindtextdomain.so
  cannot be preloaded; libgtk-3.so.0 cannot open shared object file;
  XPCOMGlueLoad error; firefox unable to load new pages.
- New processes started after the refresh were fine - only the already-
  running instance was affected.
- Ken VanDine: reproduced with firefox built for core22, NOT with core20.
- Duplicate: LP#2023344.

History in firefox-snap (context for our core26 migration):
- 00059b6a "Add workaround for LP: #2016358" primed the gpu mountpoint dirs.
- 2026-11-04: core26 landed (PR #184), then f274e0c REVERTED the workaround
  (no explanation in the commit) - the core26 gnome extension now creates
  the gpu-2604 mountpoint itself. The revert silently re-bets that this
  refresh-while-running failure mode no longer applies. Nobody has verified
  that on core26.
- Tracker context: `20261104-desktop-snaps-core26-migration-list.md`,
  "(correction)" block, 2026-11-05.

## Upstream bug tracking

- The LP bug is filed against the Ubuntu snapd package, but snapd upstream
  is github.com/canonical/snapd. The LP bug page showed NO remote watches
  and I could not find a corresponding upstream GitHub issue from the page.
- TODO: search canonical/snapd issues for the failure mode ("content
  interface" + "refresh" + "mount namespace" / "propagation" / "desktop
  interface" doc bind); if none exists, file one upstream and cross-link
  both ways (upstream is where a fix would land; the LP bug tracks the
  Ubuntu packaging side).

## What we need to reproduce

Goal: determine whether the failure mode still exists on core26 + current
snapd (2.78+ as of 2026-10-31), with the post-revert firefox recipe (no
primed gpu dirs) and the core26 gnome extension.

Environment:
- A snap-based desktop (NOT our headless core26-build VM as-is - we need a
  real X/Wayland session because the failure lives in the desktop-interface
  cloned namespace). Options: 26.04 desktop VM with the snap GNOME session,
  or the core26-build VM + snap desktop session bits.
- firefox-snap current beta/stable (core26, post-f274e0c - no primed dirs).
- gnome-core26 + mesa-2604 as content providers. For an aggressive test use
  mesa-2604 latest/edge (26.2.3-snap281) so a refresh has real content
  delta; stable deltas are small, edge changes often.

Repro attempt (per variant):
1. Start the desktop session; launch firefox via its .desktop (so it runs
   under the desktop interface, i.e. WITH the cloned namespace - launching
   via `snap run` in a terminal may NOT hit the bug).
2. Record the running firefox pid(s); save
      grep -E 'gnome-platform|gpu-2604' /proc/<pid>/mountinfo
   as the baseline.
3. While firefox stays open and is actively used:
      sudo snap refresh gnome-core26   (and/or mesa-2604)
   If no new revision is available, sideload a trivially-different rebuild
   of the provider snap (--dangerous) to force a real refresh.
4. Immediately and after ~5 min of use, check firefox still loads pages and
   renders; compare mountinfo with the baseline:
      grep -E 'gnome-platform|gpu-2604' /proc/<pid>/mountinfo
   Failure signature = mounts for the NEW revision absent/empty under the
   OLD snap root in the running process's namespace + journal lines:
   LD_PRELOAD bindtextdomain.so preload failure, libgtk-3.so.0 missing,
   XPCOMGlueLoad error.
5. Repeat with snapd from different channels (stable/candidate) if
   reproducing, to bracket whether a snapd fix landed unnoticed.

Variants worth testing (matrix):
- provider refreshed: gnome-core26 (runtime content) vs mesa-2604 (gpu
  content) - the original bug was the runtime provider.
- firefox WITH primed gpu dirs (rebuild with the 00059b6a workaround
  re-applied) vs WITHOUT (current post-revert recipe) - tells us whether
  f274e0c actually changed anything for this failure mode.
- core26 vs core24 firefox (VanDine saw core22 affected, core20 not - find
  out what the actual gating condition is).

## If reproduced

- Comment on LP#2016358 with the core26 results (it is In Progress, assigned
  to jamesh - he will care), file/link the upstream canonical/snapd issue,
  and flag to nteodosio: if the failure mode still exists on core26, the
  f274e0c revert removed the only mitigation and the workaround (or a real
  snapd fix) needs to come back.
- If NOT reproduced: note it on the LP bug (valuable data point either way:
  "cannot reproduce on core26 + snapd 2.78 with post-revert recipe") and
  close out this issue.

## Related files

- Tracker: `20261104-desktop-snaps-core26-migration-list.md`
  (see the "(correction)" block, 2026-11-05)
- Bug: https://bugs.launchpad.net/ubuntu/+source/snapd/+bug/2016358
- Duplicate: https://bugs.launchpad.net/ubuntu/+source/snapd/+bug/2023344
- firefox-snap commits: 00059b6a (workaround), f274e0c (revert), 09a9552
  (core26 move); PRs #184 (merged via cherry-pick), #185 (ours, closed)
- Test rig: a multipass VM (core26-build) with a GUI test script.

## Conclusion (2026-11-14): superseded

This is the same family as `20261112-firefox-fails-after-upgrade.md`,
which now carries the authoritative analysis: snapd patches preserved
namespaces in place instead of discarding and rebuilding them. LP#2016358
is the "torn update into a running app's cloned namespace" variant of the
same flaw; the 2026-11-14 discard-first conclusion in that note fixes it
as a corollary (the running app keeps its coherent old mounts; the next
launch gets a fresh bootstrap).

The unique material from this note - the LP links, firefox-snap history
(00059b6a workaround, f274e0c revert, 09a9552, PRs #184/#185) and the
running-app repro matrix - has been folded into
`20261112-firefox-fails-after-upgrade.md` ("Related failure mode:
LP#2016358"). No separate work remains here; verify the running-app shape
during that issue's prototype validation.
