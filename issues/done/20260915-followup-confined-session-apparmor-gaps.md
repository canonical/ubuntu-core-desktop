# Follow-up work after fixing the Core 26 confined desktop session

Date: 2026-09-15

## Impact / Priority

This follow-up tracked the remaining gaps after the confined-session
fix; the most serious finding was that the session's process tree
silently lost confinement partway through startup — gnome-shell and
everything it launched ended up running unconfined — which was the real
cause of "the terminal spinner never resolves" and very likely of
most/all of the as-yet-unexplained AppArmor denials logged during a
real login.

Impact derived from the original note's symptoms.

## Context

See `20260915-fix-confined-session.md` for the original symptom/report.
The confined session on Core 26 is now fixed and verified end-to-end.
This file tracks what's left.

## Already fixed this session (uncommitted -- see item 1 below)

- `ubuntu-desktop-session-snap/snap/snapcraft.yaml`: `base: core26-desktop`
  (Stage 1 of `proposed-plan.md`) -- was written earlier but never
  built+deployed to the test VM. Now built and confirmed working.
- `ubuntu-desktop-session-snap/scripts/run-session.sh`: removed the
  obsolete `--builtin` flag passed to `gnome-session` (upstream removed
  support for it; was causing an immediate SIGABRT/coredump on every
  confined-session launch attempt).
- ubuntu-core-desktop (image build): added a first-boot systemd
  oneshot unit that runs `snap connect
  ubuntu-desktop-session:systemd-user-control` unconditionally, since the
  gadget's static connection is keyed to the store snap-id and never
  applies to our locally-sideloaded/dangerous snap.

## Work items

- Commit the above three changes (in ubuntu-desktop-session-snap and
  ubuntu-core-desktop).
- Fix the AppArmor denial on `run-session.sh`'s `mknod`/create of
  `$HOME/.hidden` (currently non-fatal, but the file never gets created).
  Likely needs a small `home` interface AppArmor rule addition (the
  interface excludes dotfiles by default), or move the file to
  `$SNAP_USER_DATA`, or confirm the step is obsolete and remove it.
- Investigate and, if appropriate, fix the following AppArmor denials
  seen once the confined session's D-Bus-activated services actually
  start (narrower gaps, not architectural blockers):

    - org.gtk.vfs.Daemon / ListMonitorImplementations
    - org.gtk.vfs.mounttracker / ListMountableInfo
    - org.freedesktop.DBus / ListActivatableNames
    - X11 abstract-socket connect to @/tmp/.X11-unix/X0
    - bwrap / userns_create ("failed to find unprivileged_userns profile")

- [DONE 2026-09-15, see below] Test a genuine manual/greeter password
  login -- completed via the AccountsService D-Bus fix, no VNC needed.
- [DONE 2026-09-15, see below] Gadget/snap-id-mismatch connections gap
  -- extended from just `systemd-user-control` to all ~24 affected
  interfaces, hardened against boot-time races, verified on a clean
  reboot.
- Re-test after a reboot (not just `systemctl restart gdm`) to make sure
  the fixes are robust across a full VM restart, not just a live session
  restart. [Partially done 2026-09-15: the interface-connections fix was
  verified this way. The systemd-user-delegation confinement bug below
  was found via a real login, but hasn't itself been re-tested after a
  fix, since no fix exists yet.]

## Update 2026-09-15 (later the same day): real login enabled, connections
   gap fully closed, and a second, more serious, architectural bug found

1. Real password login now works and is the supported path.
   GDM reads the user's session choice via `act_user_get_session`
   (accountsservice). If `AccountsService`'s `Session=`/`XSession=` for a
   user has never been set (true for any never-before-selected user),
   GDM silently falls back to plain unconfined `gnome-session` -- same as
   autologin. This greeter build also has **no visible session-chooser
   gear icon**, so there is currently no UI path for a user to pick the
   confined session themselves.
   Fix applied: set it explicitly via the proper D-Bus API (editing
   `/var/lib/AccountsService/users/<user>` directly does NOT reliably
   take effect -- accounts-daemon caches in memory):

       sudo busctl call org.freedesktop.Accounts \
         /org/freedesktop/Accounts/User<uid> \
         org.freedesktop.Accounts.User SetSession s "ubuntu-desktop-session"
       sudo busctl call org.freedesktop.Accounts \
         /org/freedesktop/Accounts/User<uid> \
         org.freedesktop.Accounts.User SetXSession s "ubuntu-desktop-session"

   This is real, user-visible product/UX gap worth its own follow-up:
   either add a session-chooser gear icon to the greeter, or make
   `ubuntu-desktop-session` the accounts-service default for new users so
   this manual D-Bus step isn't required.

2. The snap-id/gadget-connections gap was much bigger than first
   thought, and is now fully fixed and persisted (not just
   `systemd-user-control`).
   Diffing `snap connections ubuntu-desktop-session` between the working
   Core 24 reference and Core 26 showed ~24 interfaces the gadget
   auto-connects via snap-id matching on Core 24 that silently never
   connect on Core 26, because our snap is locally sideloaded
   (`--dangerous`) and has no real snap-id for the gadget's static
   `connections:` list to match. The image build has now been
   extended (see the `ensure-desktop-session-connections.sh` oneshot
   unit) to connect all of: account-control, bluetooth-control,
   desktop-launch, hardware-observe, home, hostname-control,
   locale-control, login-session-control, login-session-observe,
   mount-observe, network-control, network-observe, personal-files (x3
   plugs), polkit-agent, process-control, shutdown, system-files,
   system-observe, systemd-user-control, time-control,
   timeserver-control, timezone-control, upower-observe.
   (avahi-control/bluez/cups-control/network-manager were left out --
   their provider snaps aren't installed on this test image.)
   Boot-time race: snapd only processes one `connect-snap` change at a
   time and can still be busy with its own seeding/auto-connect tasks
   when this oneshot fires, so a bare loop of `snap connect` calls
   intermittently fails several/all of them with `error: snap
   "ubuntu-desktop-session" has "connect-snap" change in progress`. The
   script now retries each plug up to 5 times with a short sleep; this
   was verified to reliably connect everything on a from-scratch
   image rebuild + fresh boot with zero manual
   intervention.
   Longer-term real fix (not yet done): give the locally-built snap a
   matching snap-id (self-signed snap-declaration) so the gadget's own
   `connections:` mechanism just works, or wait until
   ubuntu-desktop-session has a real published snap-id -- either would
   make this whole workaround unit unnecessary.

3. NEW, more serious finding: the confined session's process tree loses
   confinement partway through startup, and this -- not any single
   missing AppArmor rule -- is the real cause of "the terminal spinner
   never resolves" and is very likely at the root of most/all of the
   as-yet-unexplained AppArmor denials logged during a real login.
   On the working Core 24 reference, `gnome-session-binary` and
   everything it forks (gnome-shell, gsd-*, and every app the user
   launches, including gnome-terminal-server) stays labeled
   `snap.ubuntu-desktop-session.ubuntu-desktop-session (enforce)` the
   whole way down, because gnome-session directly fork+execs its
   children (confinement is inherited automatically) and its attempts to
   delegate to `systemd --user` unit activation are themselves *denied*
   by AppArmor, so it falls back to the old direct-fork behavior.
   On Core 26, gnome-session's startup sequence has been rearchitected to
   delegate session start-up to `systemd --user` targets/units
   (`gnome-session@gnome-login.target`,
   `gnome-session-manager@gnome-login.service`, etc.) -- and this time
   the systemd-unit-activation calls *succeed* (that's exactly what the
   `systemd-user-control` interface fix from earlier this session
   enabled). But every unit `systemd --user` spawns is a **direct child
   of `systemd --user` itself**, which runs completely unconfined -- so
   `gnome-session-ctl`, `gnome-session-service`, and **gnome-shell
   itself** all end up unconfined, and everything gnome-shell
   subsequently launches (terminal, apps, etc.) inherits *that*
   unconfined label instead of the snap's confinement.
   Confirmed directly on the Core 26 test VM via `ps -o pid,ppid,cmd` +
   reading `/proc/<pid>/attr/current` for every process owned by
   your_username: only the
   very first `gnome-session-init-worker` process (launched by our
   wrapper script) is confined; `gnome-session-ctl`, `gnome-session-service`,
   and `gnome-shell` (PPID = systemd --user's PID) are all `unconfined`.
   This directly answers the user's question about whether the
   systemd-user-session migration is the cause: **yes**, confirmed with
   process-tree evidence, distinct from (and more serious than) the
   `--builtin` flag crash and the interface-connections gap already
   fixed.
   This is NOT a quick AppArmor-rule fix. Two possible real fixes,
   neither implemented yet:
     a. Make `systemd --user` apply
        `AppArmorProfile=snap.ubuntu-desktop-session.ubuntu-desktop-session`
        to the session-related units it starts (systemd has supported
        the `AppArmorProfile=` unit directive since v250). This would
        need a systemd drop-in/override generated for the relevant
        units (`gnome-session-manager@.service` and whatever unit(s)
        gnome-shell itself runs under), installed in a way that survives
        being regenerated across GNOME/systemd version bumps.
     b. Prevent the systemd-user-activation path from succeeding at all
        (mirror Core 24's "denied -> falls back to fork+exec" behavior)
        -- but this fights new upstream behavior rather than working
        with it and would likely need re-doing on every future rebase.
   Also worth double-checking: my own earlier reproduction of the
   `org.gnome.Terminal.Factory0`/`CreateInstance` AppArmor denial by
   directly `gio launch`-ing `admin-console.desktop` over SSH (as an
   unconfined process) is **not** a valid test of the real bug --
   launching a confined app from an unconfined shell was never going to
   stay confined on *either* system. The correct way to test this
   properly is from within a live, real-login confined session (once
   fix (a) above makes gnome-shell itself confined again), by using
   whatever the actual dash/Activities-invoked launch path is.
   Remember to revert `[debug] Enable=true` in
   `/etc/writable/gdm3/custom.conf` on the Core 26 test VM once this
   investigation concludes -- it's still on from earlier debugging this
   session.

## Update 2026-09-18: closed out and split into focused follow-ups

Re-verified every item in this file directly against the live Core 26
test VM (currently running a real confined session). Status per item:

- Item 3 (architectural confinement-loss bug): CONFIRMED FIXED. Live
  check: `gnome-session-service` and `gnome-shell` (pid 2232) both run
  labeled `snap.ubuntu-desktop-session.ubuntu-desktop-session//
  &unconfined (enforce)`, matching the fix landed in
  `20260916-confine-gnome-session-user-units.md`.
  `[debug] Enable=true` was confirmed already reverted (never left on).
- `run-session.sh`'s `$HOME/.hidden` step: no longer denied/relevant --
  the script only appends to the file with `>>` (not `mknod`), and the
  file already exists from a prior run. No AppArmor denial for it
  appears in the current boot's journal. Considered resolved/moot, no
  new work item filed.
- `org.gtk.vfs.Daemon`/`ListMonitorImplementations`,
  `org.gtk.vfs.mounttracker`/`ListMountableInfo`, and a wider set of
  sibling denials (gvfs volume monitors, Tracker/localsearch indexer,
  xdg-desktop-portal) confirmed STILL DENIED live, and directly verified
  (via an actual desktop icon click, not just journal-reading) to cause
  a real, user-visible slow/janky Nautilus/Files startup (~60-90s
  spinner before the window appears) plus silently-broken removable-
  media detection and search indexing. Split out to
  `20260918-nautilus-gvfs-tracker-portal-denials-slow-degraded-file-manager.md`
  with full impact detail -- this supersedes/re-confirms
  `20260915-trash-nautilus-apparmor-denied-crash-loop.md`'s
  finding (that file's "gnome-shell unconfined" root cause is fixed,
  but a related-but-distinct denial set remains and was previously
  under-tested — it does NOT fully hang forever, it just takes a long
  time, contrary to what a quick read of the older file would suggest).
- `bwrap`/`userns_create` denied ("failed to find unprivileged_userns
  profile"): CONFIRMED STILL DENIED live. Split out to
  `20260918-bwrap-userns-create-denied.md`.
- Item 1 (AccountsService session-selection UX gap): CONFIRMED STILL
  OPEN. Live check: `/var/lib/AccountsService/users/your_username` has
  `Session=` empty even though the manual `busctl ... SetSession` fix
  was applied earlier this project (doesn't persist across reboot,
  as already suspected), and there is still no greeter session-chooser
  UI. Split out to
  `20260918-accountsservice-default-session-ux-gap.md`.
- X11 abstract-socket connect denial and `org.freedesktop.DBus`/
  `ListActivatableNames` denial: NOT reproduced in the current boot's
  journal at all. Likely already-resolved side effects of the item-3
  fix (X11 fallback probably only mattered when Wayland/Mutter
  peer-label checks failed, which no longer happens for gnome-shell
  itself), or simply not triggered by anything in this session. Not
  carried forward as their own work item; re-open if seen again.

This file is now fully superseded by the three new focused work items
above (each has its own real-world impact/priority assessment).
