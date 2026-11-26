# Fix GNOME login delay from portal/Mutter startup cycle

## Impact / Priority

GNOME login paused for roughly 25 seconds: GNOME Shell waited for the
portal name while the portal backend waited for Shell's Mutter service
channel, until the portal proxy's ~25-second timeout broke the cycle.
The pause was a regression from the screenshot-portal startup-order
change, so every login on affected images hit it. Impact derived from
the original note's described symptoms.

## Cause

During GNOME Shell initialization, GLib's g_memory_monitor_dup_default()
selected its portal-backed memory monitor. Creating that monitor
synchronously waited for org.freedesktop.portal.Desktop.

The screenshot-portal work added a command-chain wait before launching
xdg-desktop-portal-gnome: it waited for org.gnome.Mutter.ServiceChannel
so the backend would not initialize before Mutter was ready. Mutter only
exports that channel after GNOME Shell completes its early
initialization. This formed a startup cycle: Shell waited for the portal
name while the portal backend waited for Shell's Mutter channel. The
portal proxy's roughly 25-second timeout eventually broke the cycle,
producing the observed login pause.

This was a regression from the screenshot-portal startup-order change,
not a failure in the GNOME content snap itself. The wait was introduced
with the screenshot portal work in ubuntu-desktop-session-snap commit
1a45863 ("Enable portal screenshots in GNOME session").

## Fix

In scripts/run.sh, set GIO_USE_MEMORY_MONITOR=poll for GNOME Shell and
the GNOME portal backend. This selects GLib's local polling fallback for
memory warnings during startup, so neither process synchronously
activates the portal while the Mutter wait is in effect. Keep the
Mutter-channel wait: removing it made the backend start too early and
expose settings-only portals.

GIO_USE_PORTAL=0 is not sufficient for these confined snap processes:
GLib determines portal use from the connected Snap desktop plug.

## Verification

The live VM reached "Running GNOME Shell" about 0.12 seconds after
service start, with the unit active in about 0.47 seconds. In the
rebuilt image the Shell process had GIO_USE_MEMORY_MONITOR=poll, Mutter's
service channel had an owner, and ScreenCast.AvailableSourceTypes
returned 7. The Screenshot and ScreenCast portal interfaces were
exposed.

## Commits

- ubuntu-desktop-session-snap: 0e9e944 Avoid portal memory monitor
  startup cycle
- core-base-desktop: ad83f92 Remove GNOME session payload from core base
- gnome-desktop-content: 03c29de Trim host-only packages from GNOME
  content snap
