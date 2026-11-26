# Nautilus: gvfs/Tracker AppArmor denials slow open, break features

## Impact / Priority

PRIORITY: Medium (user-visible annoyance, not a hard breakage; no data
loss or crash).

What a real user actually sees: clicking the "Home" or "Trash" desktop
icon (or opening Files/Nautilus any other way) shows a spinner for
roughly 60-90 seconds before the window finally appears. This was
directly reproduced by clicking the desktop icon on the live VM, not
just inferred from logs -- the window DOES eventually open and works
normally afterwards, it is just badly delayed. A user unfamiliar with
the cause would likely think the desktop has hung or the app crashed,
and may click the icon again (spawning a second, redundant attempt) or
give up before it resolves.

Beyond the slow open, several Nautilus features are silently broken for
the lifetime of that Nautilus session (no error dialog, they just don't
work):
  - No file search/indexing (Tracker/localsearch miner connection is
    denied), so Nautilus's built-in search will not find file contents
    and may be slower/less useful for filename search too.
  - No removable-media/device detection in the Nautilus sidebar --
    plugging in a USB drive, phone (MTP), camera (GPhoto2), or a
    GNOME-Online-Accounts-backed remote (Goa) will not show up, because
    every gvfs volume-monitor backend (UDisks2/Afc/Goa/GPhoto2/MTP) is
    denied. This is a real, noticeable "my USB stick doesn't show up in
    Files" bug for an end user, not a cosmetic one.
  - "Connect to network location" / `network:///` fails ("Could not
    mount 'network:///': volume doesn't implement mount").
  - The desktop-icons (DING) extension itself repeatedly retries the
    same denied gvfs calls roughly every 3 seconds indefinitely in the
    background (harmless CPU/log noise, but never stops on its own),
    and was observed to hit a GLib-GIO assertion/"Bail out!" in its
    open-URI-portal retry handling in the journal around the same time
    -- worth a closer look in case it's contributing to the slow open.

Not affected: once the window is open, ordinary file operations (open a
folder, move/copy/delete a file, empty Trash) work fine -- this is a
functionality-loss/slowness issue in a specific set of side features and
in first-open latency, not a fully broken file manager.

## Context

This supersedes/re-confirms
`20260915-trash-nautilus-apparmor-denied-crash-loop.md` and item 3's
"Nautilus" angle in
`20260915-followup-confined-session-apparmor-gaps.md`. That earlier
investigation found gnome-shell itself running unconfined, causing
Nautilus to fail outright to get a display connection. That root cause
IS now fixed (see `20260916-confine-gnome-session-user-units.md` --
`nautilus-service` now runs correctly labeled
`snap.ubuntu-desktop-session.nautilus-service (enforce)`, confirmed live
on the test VM), but a distinct, narrower set of denials remains and was
not previously verified end-to-end with an actual UI click -- only via
journal reading and synthetic D-Bus calls from an unconfined SSH shell,
which the project documentation cautions is not a valid test.

Denials confirmed live (via `sudo journalctl -b 0`) during a real
desktop-icon-triggered Nautilus startup on the test VM
(`nautilus-service` running confined, pid varies per boot):
  - `org.gtk.vfs.Daemon`/`ListMonitorImplementations` (peer unconfined,
    pid of `/usr/libexec/gvfs-udisks2-volume-monitor` and similar) --
    denied.
  - `org.gtk.vfs.mounttracker`/`ListMountableInfo` -- denied.
  - `org.gtk.Private.RemoteVolumeMonitor`/`IsSupported` against each of:
    `org.gtk.vfs.UDisks2VolumeMonitor`, `AfcVolumeMonitor`,
    `GoaVolumeMonitor`, `GPhoto2VolumeMonitor`, `MTPVolumeMonitor` --
    all denied (peers are the corresponding unconfined
    `/usr/libexec/gvfs-*-volume-monitor` daemons).
  - `org.freedesktop.DBus.Peer`/`Ping` to
    `org.freedesktop.Tracker3.Miner.Files` (unconfined
    `/usr/libexec/localsearch-3`) -- denied, logged by Nautilus as
    "Unable to create connection for session-wide Tracker indexer" /
    "Could not start local Tracker indexer".
  - `org.freedesktop.DBus`/`NameHasOwner` and
    `org.freedesktop.DBus.Properties`/`GetAll` on the bus itself
    (peer_label unconfined) -- denied, logged by Nautilus's own
    `unity-inspector.vala` code as "Unable to connect to session bus".
  - File reads under `/etc/vulkan/{icd,implicit_layer,explicit_layer}.d/`
    -- denied (likely benign GPU-layer-discovery noise, but adds to
    startup latency/log volume; worth confirming harmless before
    deprioritizing further).
  - File reads of `$HOME/.bash_logout`, `.bashrc`, `.profile`,
    `.bash_history` from a nautilus worker thread (`comm="pool-8"`) --
    denied; likely a `home` interface dotfile exclusion, same family as
    the already-resolved `.hidden` issue, probably from a
    recently-used/shell-integration feature trying to read shell
    dotfiles. Low priority on its own, but worth checking whether it's
    contributing to the startup delay.
  - Separately, gnome-shell's own DING extension (label
    `snap.ubuntu-desktop-session.ubuntu-desktop-session//&unconfined`)
    independently and repeatedly (~every 3s) hits the same
    `ListMonitorImplementations`/`ListMountableInfo` denials against the
    same unconfined gvfs daemon peer -- this looks like a background
    polling loop that never stops retrying rather than a one-time
    startup check.

## Likely fix direction (not yet investigated in depth)

The common thread is that `nautilus-service` (and gnome-shell's DING
extension) are confined, but the various `gvfs-*-volume-monitor`
daemons, `localsearch-3` (Tracker), and possibly xdg-desktop-portal
components they talk to are NOT -- so every D-Bus call to them hits an
AppArmor peer-label check that fails. Two possible directions, mirroring
the item-3 fix pattern:
  a. Give the relevant gvfs volume-monitor / Tracker systemd --user
     units the same kind of `AppArmorProfile=` drop-in treatment used
     for gnome-session/gnome-shell/SettingsDaemon, so they run
     confined under the same snap label and the peer-label checks
     pass.
  b. Or, if these daemons are meant to stay unconfined/shared system
     services (check whether that's intentional upstream GNOME/gvfs
     architecture), relax the specific AppArmor interface(s) that cover
     `gvfs`/`tracker`/D-Bus peer discovery to explicitly allow a
     confined peer talking to these particular unconfined, well-known
     system services, rather than blanket-denying cross-confinement
     D-Bus traffic.

Confirm which of these matches the intended Core 26 design (same caveat
as the original Nautilus investigation) before picking a fix.

## Validation

1. From a fresh confined-session login, click Home/Trash and time how
   long the window takes to appear -- target: no worse than a normal
   Ubuntu Desktop (a couple seconds), not 60-90s.
2. Plug in (or simulate) a USB storage device and confirm it appears in
   the Nautilus sidebar / desktop.
3. Confirm Nautilus's search box actually finds file contents, not just
   filenames.
4. `journalctl -b 0` around a Nautilus startup shows no
   `apparmor="DENIED"` lines for the gvfs/Tracker/DBus calls listed
   above.
5. Re-test after a full reboot (not just a live retry), per the
   project's standing "test across a full VM restart" convention.

## Follow-up verification — 2026-09-28

The UDisks2 volume-monitor peer denials are fixed in a freshly rebuilt
and rebooted image. The host `gvfs-udisks2-volume-monitor.service` is
routed to
`/snap/bin/ubuntu-desktop-session.gvfs-udisks2-volume-monitor`; the
process runs under
`snap.ubuntu-desktop-session.gvfs-udisks2-volume-monitor (enforce)`,
owns `org.gtk.vfs.UDisks2VolumeMonitor`, and has zero restarts. The
gadget connects only the session snap's UDisks2 plug. Snapd now exposes
the Core system slot for this interface, while its base declaration
still denies automatic connections.

From a shell under the confined GNOME Shell profile, `gio mount -l`
enumerated the VM's UDisks-backed virtual drives, GVFS
`ListMonitorImplementations` listed `GProxyVolumeMonitorUDisks2` as
supported, and `IsSupported()` returned true. The fresh boot had no
confined GVFS/Tracker denials for `RemoteVolumeMonitor`,
`ListMountableInfo`, or `ListMonitorImplementations`.

There are still distinct Nautilus/DING messages. Nautilus's
`unity-inspector.vala` is denied `org.freedesktop.DBus.NameHasOwner` and
`Properties.GetAll` on the session bus; DING nevertheless logged its
Nautilus interfaces available immediately afterward. DING also runs
`nautilus --version` from the GNOME Shell profile, producing denied
attempts by that helper to own `org.freedesktop.FileManager1` and
`org.gnome.Nautilus`; the separately systemd-activated Nautilus service
starts under its correct enforce profile. These remaining denials have
not been compared with a pre-change baseline or shown to delay the
actual window.

One final `gio mount -l` probe was accidentally run unconfined over SSH.
That synthetic host caller was correctly denied by the confined GVFS
services; those messages are not from GNOME Shell, Nautilus, or DING.
The confined-profile enumeration above succeeded.

The UDisks routing and Core-slot changes are committed as
`core-base-desktop` `0adc567`, `ubuntu-desktop-session-snap` `35e6d18`,
`ubuntu-core-desktop` `77e4ab8`, and `ubuntu-core-desktop-snapd`
`e43a14dfe7`. Keep this todo open: a real post-fix Home/Trash
first-open timing, removable USB test, Nautilus content-search test,
`network:///` test, and the remaining denial classification are still
outstanding.
