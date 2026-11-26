# xdg-desktop-portal startup waits for GTK backend before the display is ready

## Impact / Priority

Medium-High. A real user waits roughly 85 seconds (not the ~25-27s
already tracked in `20260925-autologin-portal-login-delay.md`) for
anything that depends on `org.freedesktop.portal.Desktop` to become
usable. This was observed to correlate with several separately-reported
symptoms on the same image: the Home folder desktop icon not appearing
until long after login, and snap-store's window/portal-dependent
features stalling after being launched. The portal does eventually
succeed (this is a severe startup delay, not a permanent hang), but
~85s is a very visible, every-boot problem for any real user.

## Reproduction

VM: the core-desktop test VM (freshly built GNOME image).

    sudo -u your_username env XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      systemctl --user reset-failed xdg-desktop-portal.service
    time sudo -u your_username env XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      systemctl --user restart xdg-desktop-portal.service

Result: `real 1m24.528s` before the restart command returns. The
service's own journal for that start shows:

    Starting xdg-desktop-portal.service - Portal service...
    (~85s gap)
    Failed to load RealtimeKit property: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown:
        The name org.freedesktop.RealtimeKit1 was not provided by any .service files
    (repeated 3x)
    Failed to connect to PipeWire: Couldn't create PipeWire context
    Started xdg-desktop-portal.service - Portal service.

## Root cause

The long wait is not caused by retries for RealtimeKit or PipeWire. On
the fresh boot, `/usr/libexec/xdg-desktop-portal` logged the missing
RealtimeKit service immediately. The PipeWire connection failure was
also logged without a delay once portal initialization reached the
camera portal. A manual portal restart after the desktop was up took
0.216 seconds even though both services were still unavailable.

The blocking path is startup of the GTK portal implementation:

1. The portal frontend is activated before GNOME Shell has created its
   display. It starts the GTK backend, which exits with
   `cannot open display: :0`. Snapd restarts that D-Bus service rapidly
   until systemd's start limit is reached.
2. Portal initialization creates proxies for GTK's Settings, Inhibit,
   and Email implementations using ordinary `GDBusProxy` construction.
   Those constructions auto-activate the unavailable service and each
   waits for the D-Bus call timeout (~25 seconds). The frontend does
   not acquire `org.freedesktop.portal.Desktop` until initialization
   finishes, so callers wait for the sequential timeouts.

The relevant `xdg-desktop-portal` 1.21.1 source is `src/settings.c`,
`src/inhibit.c`, and `src/email.c`. Constructing these optional backend
proxies with `G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START_AT_CONSTRUCTION`
should let the frontend register first while retaining service
auto-activation on a later portal method call. Upstream already uses
this flag for the optional GameMode backend.

## What was ruled out

Initially suspected `gnome-keyring-daemon.socket`/`.service` being
`disabled` (found via `systemctl --user is-enabled` returning
`disabled` for both, despite `WantedBy=graphical-session-pre.target`)
as the cause, on the theory that the portal was blocked waiting for the
`org.freedesktop.secrets` Secret Service backend
(`/usr/share/xdg-desktop-portal/portals/gnome-keyring.portal` expects
it). Tested live:

    systemctl --user enable --now gnome-keyring-daemon.socket

`org.freedesktop.secrets` / `org.freedesktop.impl.portal.Secret` were
STILL shown as `(activatable)` with no owner after this, and the portal
restart still took the same ~85s — so the disabled keyring socket is a
real, separate issue (see "related open item" below) but is NOT the
cause of this particular delay. The earlier attribution to RealtimeKit/
PipeWire retries was also incorrect: those failures are logged promptly
and do not explain the wait. The GTK backend's early activation and
subsequent proxy timeouts are the cause, as described above.

## Related open item (separate, smaller bug)

`gnome-keyring-daemon.socket` and `gnome-keyring-daemon.service` are
`disabled`/`inactive` despite being
`WantedBy=graphical-session-pre.target`, and
`graphical-session-pre.target` reaches "active" without ever starting
them. A different, PAM-based gnome-keyring-daemon instance
(`pam_gnome_keyring`, logged as "gkr-pam: gnome-keyring-daemon started
properly and unlocked keyring") does run and unlock the login keyring,
but is a distinct process from the systemd-managed one and does not
register the D-Bus Secret Service
(`org.freedesktop.secrets`/`org.freedesktop.impl.portal.Secret` remain
unowned/`(activatable)` even after manually enabling the socket). This
means any app that actually needs the Secret Service portal (not just
`org.freedesktop.portal.Desktop` itself) will fail/stall separately.
This separate issue is tracked as its own item (GNOME Keyring Secret
Service activation) and is out of scope for the GTK-backend startup
delay documented here.

## Related work still open

The separate autologin delay in
`20260925-autologin-portal-login-delay.md` was not reproduced on the
post-fix autologin boot below, but its planned manual-login/autologin
comparison is still outstanding. The Secret Service activation issue is
tracked separately as its own item. The previously fixed
`After=graphical-session.target` ordering behavior also remained
non-blocking in this test.

## Implementation status

The `core-base-desktop` source now contains a patch that constructs the
Settings, Inhibit, and Email implementation proxies with
`G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START_AT_CONSTRUCTION`. Its Snapcraft
configuration builds the frontend from the exact Ubuntu source version
staged in the image, retaining the distro source patches and package
data while replacing only `/usr/libexec/xdg-desktop-portal`. The
patched core snap and a fresh GNOME image have now been built, and the
runtime verification below confirms the frontend starts promptly, the
GTK backend starts after the display is available, and Settings
requests still complete.

## Fresh-boot confirmation (2026-09-27)

On the active GNOME VM, the systemd user journal shows the same
user-visible startup stall and narrows its timing:

- `xdg-desktop-portal.service` began at monotonic 223.221 and acquired
  its D-Bus name / reached `Started` at 298.641, a 75.4-second
  activation interval.
- The portal logged missing RealtimeKit at 223.538. The GTK backend
  started at 223.540, then exited at 223.606 with `cannot open display:
  :0`; it retried five times and hit the systemd start limit at
  229.731.
- The portal frontend timed out starting the GTK implementation while
  creating Settings, Inhibit, and Email proxies at 248.564, 273.595,
  and 298.631. These are 25-second intervals. It acquired its D-Bus
  name at 298.641, 75.4 seconds after startup.
- PipeWire failure was logged at 273.602, adjacent to the Inhibit
  timeout. RealtimeKit was missing from the start. Neither explains
  the three GTK activation timeouts: after the desktop was fully up, a
  measured portal start with PipeWire and RealtimeKit still absent
  completed in 0.216 seconds.
- GNOME Shell logged `Launching DING process` every three seconds from
  monotonic 250.351 through 298.522; the DING process started at
  298.721, immediately after the portal became available. This matches
  the delayed Home desktop icon.
- The first Snap Store `desktop-launch` request was logged at about
  255.5, while the portal was still starting. Snap Store then logged a
  portal/settings activation timeout around 281.3; its window appeared
  around 298.9. Another launch was recorded at 308.673, after the
  portal had started.

This reproduces the user's observation that launching Snap Store during
the Home-icon delay stalls, and identifies early GTK backend activation
as the portal-startup blocker. Keep this distinct from the separate
`20260926-desktop-launch-retry-storm.md` issue; these logs show only
two launcher invocations, not the runaway transient-unit storm.

## Post-fix verification (2026-09-27)

Built the updated core snap, built a fresh GNOME image with the image
build, and booted it on the test VM. The VM's
`/usr/libexec/xdg-desktop-portal` SHA-256 matched the executable in the
rebuilt core snap.

- On the fresh boot, the frontend started at monotonic 232.995 and
  reached `Started` at 233.419 (0.424 seconds). RealtimeKit and
  PipeWire errors were logged immediately and did not delay startup.
- The autologin session opened at 232.255; GNOME Shell started at
  232.797 and reached `Started` at 234.554. The previous
  25-27-second black-screen delay was not reproduced; DING launched at
  236.348.
- The confined GTK backend started at 235.578 and reached `Started` at
  235.865, after the frontend was available and the display existed.
  There was no `cannot open display` error or proxy-construction
  timeout.
- GNOME Shell launched DING at 236.348; the process remained running,
  `show-home` was true, and DING processed the `/home/your_username`
  desktop entry by 237.060.
- Launched App Center through its installed desktop entry. Its
  `io.snapcraft.Store` D-Bus name was acquired and the process remained
  running. A `Settings.ReadOne` portal request for
  `org.gnome.desktop.interface/color-scheme` completed and returned
  `<default>`, confirming that GTK-backed Settings still works.
- Systemd later logged a duplicate base/snap GTK unit activation
  attempt, but the confined snap backend was already active and owned
  the implementation bus name; the Settings request succeeded.

## Resolution

Deferring optional backend activation reduced portal startup from the
75.4-second baseline to 0.424 seconds on a fresh boot. The GTK-backed
Settings request and App Center launch were verified. Source changes
remain uncommitted; no commit reference is available.
