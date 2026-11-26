# Fix the GNOME portal startup delay without regressing session services

## Impact / Priority

High. GNOME login and portal-dependent actions can be delayed by about
25 seconds when the portal waits for the graphical session while GNOME
Shell itself is waiting for portal startup. The latest ordering also
needs a fresh-VM timing check; the user confirmed the Snap Store opens,
but the portal-ordering delay was not timed end to end.

## Goal

Remove the portal-related GNOME startup delay while preserving the
environment-broker behavior and the routed GNOME session services. Fixes
must be in source and verified on a fresh image, not only applied to a
VM.

## Context

The completed `20260927-gnome-session-service-environment-broker.md`
introduced a least-privilege broker for GNOME Session's shared
activation-environment updates. It filters environment values, removes
`SNAP_*` variables, and forces host-visible `XDG_RUNTIME_DIR` and
`XAUTHORITY` paths in the shared user systemd and D-Bus activation
environments. This addressed portal activation failures associated with
snap-private environment values and made a real Snap Store launch
succeed on a fresh VM.

The Stage 2.2 session-service routing work routed remaining GNOME
services through confined session-snap applications using systemd
drop-ins, D-Bus activation files, and autostart entries. It also added
required app plugs, an IBus portal launcher that supplies
`IBUS_ADDRESS`, and gadget connections for NetworkManager and BlueZ. The
source changes were committed as:

- `ubuntu-desktop-session-snap`: `e39e0f3`
- `core-base-desktop`: `73bc174`
- `ubuntu-core-desktop`: `19a71f7`

The core-base change currently orders `xdg-desktop-portal.service` and
the confined GTK portal backend after `graphical-session.target`. That
can conflict with the earlier broker/portal fix: confined GNOME Shell
may need portal interfaces before it can finish starting and reach the
graphical session target, while the portal units wait for that target.
This creates a startup dependency cycle and has previously produced a
roughly 25-second delay. Removing the ordering may expose the opposite
problem: the GTK backend can start before the display is available and
fail with `cannot open display`. Find ordering or activation behavior
that preserves both prompt GNOME startup and a usable portal backend.

## Concrete completion gates

1. Build a fresh GNOME image from the source changes and boot it without
   manual VM-only unit or environment edits.

2. Record timestamps for GNOME Shell startup/readiness,
   `graphical-session.target`, portal frontend activation/name
   ownership, and GTK backend readiness. Require the graphical-session
   target to become active within 5 seconds of GNOME Shell reaching
   ready, with no portal-related 25-second wait or D-Bus activation
   timeout.

3. Verify the host portal owns `org.freedesktop.portal.Desktop` and the
   GTK backend starts with a usable display. Exercise a real FileChooser
   interaction end to end; introspection or a synthetic D-Bus call alone
   is insufficient.

4. Cold-click the Snap Store launcher on the fresh VM and measure until
   its window is visible. Require no more than 2 seconds, matching the
   original broker note's user-visible acceptance target.

5. After login and after Mutter/Xwayland startup, inspect both
   `systemctl --user show-environment` and the D-Bus activation
   environment. Require no `SNAP_*` values, host
   `XDG_RUNTIME_DIR=/run/user/<uid>`, and host-visible `XAUTHORITY`.
   Confirm the broker still rejects unauthorized callers and the portal
   remains activatable.

6. Recheck the Stage 2.2 routed services on that same fresh image,
   including IBus portal activation, GOA, BlueZ/UPower access, keyring,
   GVFS, and LocalSearch. Confirm the expected services work and that no
   new AppArmor denials or service restart loops were introduced.

7. Base completion on the real login, cold launcher click, and
   FileChooser interaction, with journal and unit timestamps supporting
   the results. If any gate fails, keep the note open and record the
   failing unit, timing, and denial or startup error before changing
   the ordering again.

## Latest verification - 2026-09-28

The rebuilt image reaches `graphical-session.target` at monotonic
53.044s; GNOME Shell logs ready at 53.468s. The portal frontend starts
at 51.095s, the document portal at 51.404s, and the GTK backend becomes
active at 54.017s. All three portal units report zero restarts. This
removes the portal-related startup wait on this fresh image.

`systemctl --user show-environment` has no `SNAP_*` entries and shows
the host `XDG_RUNTIME_DIR=/run/user/1000` and
`XAUTHORITY=/run/user/1000/.Xauthority`. At that time, the D-Bus
activation environment and broker caller authorization had not been
rechecked.

The cold App Center screenshot test on the preceding fresh image showed
no App Center pixels at 2s, a blank window at about 3.2s, and full
content at about 7.2s, so the 2s user-visible target failed. The
current image's desktop-entry launch began at 19:01:28.296; GNOME Shell
emitted window-change signals at about 0.545s and 1.257s afterward.
These are not pixel-level first-frame measurements, so do not count them
as a pass. App Center logged PackageKit service-unavailable errors and
ratings.ubuntu.com timeouts while loading, then remained running.

Other findings at that time: `xdg-user-dirs.service` exited with status
1, and DING failed because `~/Desktop` was absent. GNOME Shell and
Nautilus also logged session-bus AppArmor denials.

## Follow-up verification — 2026-09-28

The VM journal resolves the user's later cold launch to this
process-level timeline: the prior Snap Store scope exited at 19:25:16;
the graphical session stopped at 19:25:21; the next login began at
19:25:24 and `graphical-session.target` was active at 19:25:26. The
desktop-launch activation was logged at 19:25:31.191, the Snap Store
scope started at 19:25:31.278, and its first startup log appeared at
19:25:31.388. The scope exited successfully at 19:25:39.051 after 7.773
seconds. The user reported that the window appeared straight away. This
confirms a cold launch and startup within 87 ms of the desktop
activation, but does not measure the first visible pixel. Retain the
earlier ~3.2-second screenshot observation and leave the strict
2-second first-frame gate open pending a timed capture.

The latest rebuilt image, including the user-directory fix below,
reached `graphical-session.target` at monotonic 54.179s; GNOME Shell
logged started at 54.590s (target active 0.411s earlier). The document
portal, permission store, and frontend became active at 52.570s,
52.507s, and 52.813s; the GTK backend was active at 55.162s. All portal
and broker units reported zero restarts.

The environment broker was exercised from both sides. An unconfined
`UpdateEnvironment` call was rejected by session-bus AppArmor policy.
The authorized `gnome-session-service` profile's call returned
successfully. The user systemd environment has no `SNAP_*` values and
has `XDG_RUNTIME_DIR=/run/user/1000` and
`XAUTHORITY=/run/user/1000/.Xauthority`. The D-Bus activation
environment has no read/query method and was not independently
observed.

IBus engine enumeration succeeded after supplying the session's
published `IBUS_ADDRESS`. GOA `GetManagedObjects`, BlueZ
`GetManagedObjects`, and UPower `EnumerateDevices` returned
successfully (no accounts or power devices were present in the VM).
Confined GNOME Shell-profile calls to the keyring, GVFS, and LocalSearch
services also returned successfully. Their names were owned and the
routed services were active.

The `xdg-user-dirs.service` failure was traced to confinement denying
reads of `/etc/xdg/user-dirs.conf` and `/etc/xdg/user-dirs.defaults`. A
dedicated read-only `system-files` plug for just those files was added
to the session, user-directory, and GTK user-directory updater apps and
seeded by the GNOME gadget. On the rebuilt image, the unit completed
with status 0, `~/Desktop` was created, and the DING missing-Desktop
errors stopped. The generated AppArmor rules name only those two files.
The fix is committed as `ubuntu-desktop-session-snap` `0d0a2d5` and
`ubuntu-core-desktop` `89bf34e`.

GNOME Shell/Nautilus and other confined session services still log
AppArmor-denied D-Bus calls (including GeoClue/GDM registration, UDisks
volume-monitor queries, and some systemd user-unit controls). A
matching pre-change denial baseline was not captured, so whether these
are new is still unresolved. Keep this note open for that comparison
and the first-visible-frame timing.
