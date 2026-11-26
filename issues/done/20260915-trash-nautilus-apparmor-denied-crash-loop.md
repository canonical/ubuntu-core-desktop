# Trash and Home desktop icons fail: Nautilus AppArmor-denied, crash-loops

Date: 2026-09-15

## Impact / Priority

Clicking the desktop Trash icon (or the Home icon, or any other action
that routes through Nautilus) shows an on-screen error and no file
manager window ever appears: Nautilus is AppArmor-denied on its
display-connection path, crash-loops, and systemd gives up, so the
file manager/Trash is completely broken, not just cosmetically
degraded. No priority level was stated in the original note; impact
derived from the original note's described symptoms.

Image: Ubuntu Core Desktop 26 amd64 dangerous (desktop26)

## Summary

Clicking the Trash icon on the desktop showed an on-screen error.
Decoded from the journal (no screenshot tool/VNC was available in this
setup -- see "How this was diagnosed" below), the error text is:

    Error: while opening file trash:///: An AppArmor policy prevents this
    sender from sending this message to this recipient; type="method_call",
    sender=... comm="gjs /usr/share/gnome-shell/extensions/ding@rasters"
    label="unconfined" interface="org.freedesktop.Application" member="Open"
    destination="org.gnome.Nautilus" (comm="/usr/bin/nautilus
    --gapplication-service" label="snap.ubuntu-desktop-session.nautilus-service
    (enforce)")

Confirmed not Trash-specific: clicking the Home desktop icon a few
minutes later reproduced the identical failure signature, just for a
different URI:

    Error: while opening file file:///home/your_username: An AppArmor policy
    prevents this sender from sending this message to this recipient;
    ... interface="org.freedesktop.Application" member="Open"
    destination="org.gnome.Nautilus" (... label=
    "snap.ubuntu-desktop-session.nautilus-service (enforce)")

Same root cause, same AppArmor denials, same crash-loop-then-give-up
pattern (see below) -- only the requested URI differs. Any desktop icon
or action that asks Nautilus to open a location will fail the same way,
since the failure is in Nautilus's own startup/display-connection path,
not in anything specific to Trash or Home.

## Root cause

Clicking the desktop Trash icon makes the (unconfined) gnome-shell
"Desktop Icons NG" (DING) extension call
`org.freedesktop.Application.Open` on `org.gnome.Nautilus`, which is
provided by the confined
`snap.ubuntu-desktop-session.nautilus-service`. That service is denied
by AppArmor on every path it needs to actually come up and show a
window:

- `dbus_bind` on `org.freedesktop.FileManager1` (needed for Nautilus to
  register itself as the file manager) -- DENIED.
- `org.gnome.Mutter.ServiceChannel` / `OpenWaylandServiceConnection`
  (Nautilus's private channel to get a Wayland connection from
  gnome-shell) -- DENIED ("Failed to initialize display server
  connection").
- Direct fallback `connect` to the X11 abstract socket
  `@/tmp/.X11-unix/X0` -- DENIED (`class="net" family="unix"`).
- `org.gtk.vfs.Daemon`/`ListMonitorImplementations` and
  `org.gtk.vfs.mounttracker`/`ListMountableInfo` -- DENIED.
- `org.freedesktop.portal.Registry`/`Register` -- DENIED.

With both its Wayland and X11 paths denied, Nautilus logs "Failed to
open display" and exits (status 1). systemd (`user@1000.service`,
PID 1770) restarts
`snap.ubuntu-desktop-session.nautilus-service.service` five times in
well under a second, hits "Start request repeated too quickly", and
gives up ("Failed to start
snap.ubuntu-desktop-session.nautilus-service.service"). The net effect:
Trash (and, by the same code path, any other Nautilus/Files action --
double-clicking a folder, "Open" from a right-click menu, etc.) is
completely broken, not just cosmetically degraded.

This is the same underlying AppArmor gap already noted as an
open/narrow issue in the project's confinement notes
("org.gtk.vfs.Daemon / ListMonitorImplementations ... denied", "X11
abstract-socket connect to @/tmp/.X11-unix/X0 denied"), but those notes
did not previously record that the impact is a fully non-functional
file manager/Trash, nor the `org.freedesktop.FileManager1` bind denial
or the `org.gnome.Mutter.ServiceChannel` denial. Update the notes once
this is fixed.

## How this was diagnosed (no screenshot needed)

No VNC port is exposed by this test VM's qemu invocation (it uses
`-display sdl,gl=on`, no `-vnc`), there is no screenshot binary in the
guest (`gnome-screenshot`/`grim`/`scrot`/`import` all absent), and
`org.gnome.Shell.Screenshot` returned `AccessDenied` when called
out-of-band over D-Bus (not a trusted caller), and gnome-shell's `Eval`
RPC is disabled (returns `(false, '')`) so no scripted screenshot via
Looking Glass either. Instead, the exact user-facing error text and its
full causal chain were read directly out of `journalctl -b 0 --since
...` on the VM -- this is more precise than a screenshot/OCR would have
been anyway, and is the preferred method for any future "the screen
shows an error" report on this project: grep the journal around the
time of the click for the app's `comm=`/AppArmor `DENIED` lines rather
than trying to capture the framebuffer.

## Why this works on Ubuntu 24 but not here (root cause of the mismatch)

Compared directly against the working desktop24 reference VM
(`ubuntu-desktop-session` 24/stable rev 40):

- On desktop24, `gnome-shell` itself (PID from `ps`, confirmed via
  `aa-status`) runs CONFINED as
  `snap.ubuntu-desktop-session.ubuntu-desktop-session` -- the entire
  session (gnome-shell/mutter, gsd-*, Xwayland, ibus, etc.) is one
  confined snap, same label prefix as `nautilus-service`.
- On this Core 26 image (desktop26), `gnome-shell` runs UNCONFINED
  (`ps -p <pid> -o label` -> `unconfined`; `aa-status` shows it outside
  any snap profile), while only satellite apps like `nautilus-service`
  and `xdg-desktop-portal-gnome` run confined under the
  `ubuntu-desktop-session` snap.
- On desktop24, the `org.freedesktop.FileManager1` bind is ALSO denied
  (confirmed in its journal) -- so that specific denial is harmless
  there and evidently not required for Nautilus to function.
- The difference that actually matters is
  `org.gnome.Mutter.ServiceChannel`/`OpenWaylandServiceConnection` (and
  the X11 socket fallback): the AppArmor policy allowing
  `nautilus-service` to reach Mutter's private service channel appears
  to require the peer to be the confined `ubuntu-desktop-session` snap
  (peer label matching). On desktop24 that's true (gnome-shell is that
  same snap), so the call is allowed and Nautilus gets a working
  display connection. On desktop26 gnome-shell is unconfined, the peer
  label doesn't match, and the call -- and the X11 fallback -- are both
  denied, so Nautilus can never get a display connection at all and
  crash-loops.

This points to a deeper architectural difference from the working
Ubuntu 24 reference, not just a missing AppArmor rule: desktop26 needs
either (a) gnome-shell/mutter to run confined as part of the
`ubuntu-desktop-session` snap here too (matching desktop24's model), or
(b) the AppArmor policy for `nautilus-service`'s access to
`OpenWaylandServiceConnection`/the X11 socket to be relaxed to also
allow an unconfined peer, if running gnome-shell unconfined on Core 26
is intentional/required. Confirm which of these is the intended design
for Core 26 before picking a fix -- treat the desktop24 comparison as a
strong lead, not a mandate to blindly copy its confinement model (the
project documentation cautions that desktop24 is a non-systemd
reference and not fully like-for-like).

## Work items

Add the missing AppArmor allow rules (or interface connections, if
these are meant to come from a proper interface rather than a bare
allow) for the confined `ubuntu-desktop-session` snap's
`nautilus-service` app:

- Allow the `org.freedesktop.FileManager1` D-Bus name bind on the
  session bus (or determine why it's currently disallowed --
  `desktop`/`desktop-legacy` interfaces normally cover this on a
  regular Ubuntu Desktop).
- Allow
  `org.gnome.Mutter.ServiceChannel`/`OpenWaylandServiceConnection` from
  confined apps that plug `wayland` -- this looks like it should
  already be covered by the `wayland` interface; check whether
  Nautilus's snap declares/plugs it, or whether the interface's
  AppArmor template is missing this specific method on this image.
- Allow (or explicitly deny-and-avoid) the X11 fallback socket connect
  if X11 is not meant to be used at all in this confined session -- if
  `wayland` is fixed, the X11 fallback may become moot.
- Allow the `org.gtk.vfs.Daemon`/`org.gtk.vfs.mounttracker` calls
  (needed for Trash and network locations to enumerate correctly).

## Validation

1. Click the desktop Trash icon and the desktop Home icon (or open
   Files/Nautilus any other way) and confirm a normal window appears
   with no error, for every entry point, not just one.
2. `journalctl -b 0 -u snap.ubuntu-desktop-session.nautilus-service.service
   --since <test time>` shows no `AVC apparmor="DENIED"` entries and no
   restart-loop/"Start request repeated too quickly".
3. Confirm ordinary Nautilus operations (open a folder, empty Trash,
   restore a file from Trash) work end-to-end, not just that the window
   opens.
4. Update the confinement documentation's AppArmor-gaps bullet list to
   reflect the fix (or, if only partially fixed, to correct the
   still-open subset).
