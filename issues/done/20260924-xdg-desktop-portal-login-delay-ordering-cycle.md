# xdg-desktop-portal login delay (~25-27s): circular D-Bus activation deadlock

## Impact / Priority

High. Every GDM login on core26-desktop (GNOME session) shows a
blank/black screen for ~25-27 seconds after entering the password
before the desktop appears. This is a first-impression/every-login
regression for the default Ubuntu (GNOME) session, not a crash — the
session does eventually come up.

## Context

Full original investigation, timeline and journal evidence were
recorded in the original investigation notes.

Confirmed root cause (corrected; it supersedes an earlier "stale
package" theory that was based on a misread and is now retracted):

`xdg-desktop-portal.service` carries `After=graphical-session.target` in
its shipped unit (present identically on core26-desktop AND on a plain
Ubuntu 26.04 host — this is not a stale package, not a core-base-desktop
modification, not a chisel-vs-apt issue). `graphical-session.target`
only becomes active once `org.gnome.Shell@.service` (Type=notify)
reports READY. But gnome-shell's own startup path makes a synchronous
D-Bus call requiring `org.freedesktop.portal.Desktop` before it can
call sd_notify(READY=1). This is a genuine ordering cycle mediated
through D-Bus activation (not visible to systemd's own job-dependency
cycle detection), broken only when dbus-daemon's default 25s
`service_start_timeout` fires.

Confirmed live via strace: gnome-shell's D-Bus I/O thread goes
completely silent for the entire stall right after requesting the
portal activation — a genuine blocking wait. `ibus-daemon`
independently hits the identical stuck-portal timeout at the same
moment ("portal is not running: Timeout was reached"), confirming the
portal's own activation is genuinely stuck during the window, not
something specific to one caller.

AppArmor and colord were both ruled out as the cause — colord's
read-only-/var/cache failure is a real, separate bug but its timing does
not match the stall.

Still open: why this identical unit graph deadlocks on core26-desktop
but not on a plain Ubuntu host. Leading (unproven) hypothesis:
gnome-shell running as a confined snap app here routes more of its
startup path through portal-mediated D-Bus calls than an unconfined
session needs.

## Next steps

1. This is very likely an upstream-reportable bug (xdg-desktop-portal
   and/or gnome-shell/mutter): a service ordered After= a target that
   itself cannot become active without a synchronous call succeeding
   against that service is a real ordering-cycle defect, independent of
   core26-desktop. Worth confirming whether upstream is already aware
   (this looks related in spirit to the previously-fixed LP#2144855,
   though that fix apparently only addressed part of the ordering,
   since the current package still has `After=graphical-session.target`
   and still deadlocks).
2. Do NOT hand-patch the packaged xdg-desktop-portal.service file in
   core-base-desktop (explicit instruction from the reporting user — we
   should be using upstream/updated packages, not hacking the shipped
   unit).
3. A drop-in `After=` reset was tested and does NOT clear the inherited
   ordering on this image (systemd 259.5-0ubuntu3.4, confirmed) — a
   full replacement unit file would be needed to override at all, which
   is exactly the kind of packaging divergence to avoid without a
   stronger reason.
4. Realistic remediation options to evaluate:

   a. Report/track upstream (xdg-desktop-portal and/or gnome-shell) —
      the real fix belongs there since the unit files are unmodified
      stock packages.
   b. Investigate whether gnome-shell's confined-snap startup path can
      avoid or defer the specific synchronous portal call (would need a
      full backtrace/gdb session on gnome-shell to identify the exact
      call site — strace alone only proved *that* it blocks
      synchronously on the portal, not *which* internal call triggers
      it).
   c. As a last-resort stopgap only, consider whether a supported
      override (not a static file edit) could relax dbus's
      service_start_timeout or the portal's ordering for this specific
      deployment — but this masks rather than fixes the underlying
      cycle and should be avoided if (a) or (b) are viable.
5. Separately: colord.service fails on this image ("Failed to set up
   special execution directory in /var/cache: Read-only file system",
   ProtectSystem=strict + CacheDirectory=colord on a read-only
   /var/cache) — a real bug but NOT the cause of the login delay above.
   Track/fix separately (point CacheDirectory at a writable path or
   adjust ProtectSystem=strict).

## Resolution (2026-09-24)

Root cause fully confirmed and fixed. The "why does this deadlock
happen here but not on a plain Ubuntu host with identical unit files"
open question is answered: it's glib/gio's built-in sandbox detection.
A confined snap process (SNAP=/SNAP_NAME=/etc. present in its
environment) is detected by glib as sandboxed, which makes
gnome-shell/GTK route Settings/theme queries through
org.freedesktop.portal.Desktop synchronously at startup. An unconfined
process has none of those env vars, so glib never touches the portal at
all during startup and the (unmodified, identical-everywhere) ordering
cycle is simply never exercised. The fix also surfaced a systemd
drop-in gotcha: a `.d/override.conf` resetting `After=` does NOT
reliably clear an inherited `After=graphical-session.target`; a full
replacement unit file does.

Fix shipped in core-base-desktop as commit 034d42a on branch `26`
(cherry-picked from 4c646d2 on `26-dev`, which itself replaced an
earlier, non-working drop-in-based attempt, fceceb8, removed from
history rather than reverted): full-file replacements for
static/usr/lib/systemd/user/xdg-desktop-portal.service and
static/usr/lib/systemd/user/xdg-desktop-portal-gtk.service, both
dropping `After=graphical-session.target` (keeping `After=dbus.service`
and `PartOf=graphical-session.target`). Verified live on the
bug-reproducing VM after a full core-base-desktop + ubuntu-core-desktop
image rebuild: gnome-shell reaches ready in ~1.2s (down from ~26s),
portal starts concurrently, and gnome-shell remains genuinely
AppArmor-confined (`snap.ubuntu-desktop-session.gnome-shell (enforce)`)
— no regression on confinement. User-confirmed working via a fresh
login on the rebuilt image.
