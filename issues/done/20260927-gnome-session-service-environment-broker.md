# Add a least-privilege GNOME session environment broker

## Impact / Priority

Priority: High. A real App Center icon click on a fresh GNOME VM took
about 75 seconds for the window to appear. During the wait, Snap Store
logged portal activation timeouts and the host xdg-desktop-portal
service failed to acquire org.freedesktop.portal.Desktop. This is a
reproduced end-to-end user-visible failure, not only a synthetic-call
or journal-based concern.

The shared user systemd and D-Bus activation environments were also
observed to contain SNAP_* values, a snap-private XDG_RUNTIME_DIR, and
Mutter's private XAUTHORITY path. Cleaning those environments and
restarting the portal caused the portal frontend to acquire its bus
name. These changes were applied together, so the responsible variable
or mechanism has not yet been isolated.

## Goal

Prevent confined desktop-session processes from publishing snap-private
or otherwise unsafe values into the shared user systemd and D-Bus
activation environments, without giving every session app that
capability. Restore reliable portal activation and make a real App
Center icon click show its window promptly.

Acceptance target: on a fresh image and real autologin session, the
App Center window is visible within 2 seconds of a cold icon click.
This target is based on an earlier live run where the window appeared
in under one second after cleaning the activation environment and
restarting the portal. Measure from the actual click to a visible
window; process creation or a successful desktop-launch command is not
enough.

## Confirmed call path and current evidence

- Mutter runs as the gnome-shell snap app, not the
  ubuntu-desktop-session launcher app. Mutter reports environment
  changes to GNOME Session; gnome-session-service is the component
  that updates the session D-Bus and user systemd environments.
- GNOME Session makes the D-Bus calls directly in-process; it does not
  exec dbus-update-activation-environment. The subprocess-argv shim
  option is therefore not applicable.
- Source inspection found:

      gsm_util_update_activation_environment() calls
        org.freedesktop.DBus.UpdateActivationEnvironment directly.
      gsm_util_update_user_environment() calls
        org.freedesktop.systemd1.Manager.UnsetAndSetEnvironment directly.
      gsm_util_export_activation_environment() bulk-exports most of the
        session process environment, with only a small blacklist.

- Include SetEnvironment and UnsetEnvironment in the source/policy
  audit as additional write paths, but do not assume they cover the
  observed GNOME Session update path: UnsetAndSetEnvironment is used.
- On a fresh image containing core-base-desktop commit 94c5352, the
  wrapper's initial cleanup did not persist through GNOME startup.
  After login, the user manager again contained SNAP_* values,
  XDG_RUNTIME_DIR=/run/user/<uid>/snap.ubuntu-desktop-session, and
  XAUTHORITY under that private runtime directory.
- A real icon click started Snap Store promptly, but the window took
  about 75 seconds to appear. Logs included portal activation
  timeouts; the host portal unit did not own
  org.freedesktop.portal.Desktop.
- In a live intervention, SNAP_* was cleared and XDG_RUNTIME_DIR and
  XAUTHORITY were set to host paths in both activation environments.
  Restarting xdg-desktop-portal then made it active and it acquired
  the D-Bus name. This is strong evidence that the shared environment
  is relevant, but does not isolate individual variables or prove the
  permanent design.

## Security design

Do not patch Mutter alone as the security fix. Mutter is an input
source, but GNOME Session performs the shared-environment writes and
also has a bulk-export path. A Mutter-only patch would not mediate
those paths or another app with the same capability.

The systemd-user-control interface is used by many apps in
ubuntu-desktop-session. Its AppArmor policy grants shared
user-manager environment writes as well as unit-control operations. A
per-app systemd-user-control plug gives that app the capability even
if the app does not currently use it. Audit the plug assignments and
split environment mutation from the narrower unit-control/inspection
permissions so unrelated apps do not retain an unnecessary way to
change the shared environment.

Preferred first implementation: a separate, user-scoped broker app
inside ubuntu-desktop-session with its own AppArmor profile. Only the
broker receives the environment-writing permission. Initially only
gnome-session-service may call its narrow D-Bus API; Mutter remains
unmodified and GNOME Session forwards Mutter's Setenv updates to the
broker. Do not make every session app a broker client unless the audit
shows it actually publishes session environment.

The broker must:

- Accept only the environment-update operation needed by the session;
  it must not become a general systemd/D-Bus control proxy.
- Authenticate/authorize the caller so only the intended session
  manager can request updates.
- Apply an explicit allowlist and validate values. Never publish SNAP
  or SNAP_* values.
- Force the manager's XDG_RUNTIME_DIR to /run/user/<uid>, regardless
  of the confined caller's value. This is only the shared manager's
  exported value; do not override XDG_RUNTIME_DIR in the confined
  GNOME process itself.
- Set XAUTHORITY to the known host-visible /run/user/<uid>/.Xauthority
  path, not Mutter's private path. Preserve the existing
  Xauthority-copy mechanism until a replacement is proven to supply
  the correct cookie to intended clients.
- Update both the D-Bus activation environment and user systemd
  manager consistently. Define how stale SNAP_* names are removed from
  each environment; empty values in D-Bus and unsetting from systemd
  may require different handling.
- Preserve only required display/session variables. Confirm whether
  values such as DISPLAY, WAYLAND_DISPLAY, XDG_SESSION_TYPE,
  XDG_CURRENT_DESKTOP, XDG_SESSION_DESKTOP, XCURSOR_THEME,
  XCURSOR_SIZE, GNOME_SETUP_DISPLAY, locale, PATH, and XDG_DATA_DIRS
  need to be seeded or updated, and avoid importing arbitrary caller
  environment.

Keep the broker in the session snap for the first consumer. Give it a
narrow D-Bus service identity/slot and connect only
gnome-session-service (prefer a custom, narrowly-scoped interface if
the generic dbus interface grants too much access). Consider a
separate broker snap only after a second real consumer establishes a
need for independent release and reuse.

An unmodified-client alternative is a transparent D-Bus proxy reached
by gnome-session-service through DBUS_SESSION_BUS_ADDRESS. This avoids
patching GNOME Session but proxies all of that process's bus traffic,
not just environment updates. The upstream bus sees the proxy's
connection and AppArmor identity, not the original client identity. An
unconfined byte-forwarding proxy could therefore become a confused
deputy and bypass the client's D-Bus restrictions. Do not use a broad
pass-through proxy unless its profile and forwarding policy preserve
the original confinement boundary, direct bypasses are denied, and
this has been demonstrated by negative security tests. The existing
`20260926-dbus-proxy-setenv-filter.md` design should be revised before
following its raw-relay or generic-unconfined-service steps.

## Implementation gates

1. Audit all systemd-user-control plug assignments in
   ubuntu-desktop-session/snap/snapcraft.yaml. Record which apps need
   which Manager methods. Design the split so apps that still need
   unit control cannot call SetEnvironment, UnsetEnvironment, or
   UnsetAndSetEnvironment. Confirm the D-Bus activation update method
   is also restricted to the broker.

2. Implement the broker and the smallest GNOME Session integration.
   Patch gnome-session-service's direct update and bulk-export paths
   to use the broker; do not patch every app or Mutter unless source
   tracing reveals another writer. The broker, not the caller, must
   enforce the allowlist and host-path rewrites.

3. Unit-test allowed, rejected, rewritten, and removed variables;
   malformed input; repeated updates; and consistent outcomes in both
   activation environments. Include deliberately bad SNAP_*,
   XDG_RUNTIME_DIR, and XAUTHORITY values. Verify unrelated D-Bus
   session traffic continues normally.

4. Add confinement tests. From an ordinary app profile, attempt direct
   systemd and D-Bus activation-environment writes and confirm they
   are denied and do not alter either environment. Confirm only the
   broker can perform the filtered updates and only the intended
   session manager can call the broker. Inspect AppArmor denials and
   broker identity rather than relying only on successful calls.

5. Build a fresh GNOME image and boot it from scratch with real
   autologin. Poll both global activation environments throughout
   session startup and after Mutter/Xwayland starts; no SNAP_* or
   snap-private XDG_RUNTIME_DIR/XAUTHORITY may appear there. Confirm
   the host portal acquires org.freedesktop.portal.Desktop and its
   backend is usable.

6. Perform a real cold App Center icon click and time until the window
   is visible. Require <=2 seconds, confirm there is no retry storm,
   and check the rest of the desktop remains functional. Synthetic
   launcher calls are supplementary only; they do not satisfy this
   gate.

7. Keep the separate X11 socket bind-mount issue out of scope; this
   work must not mask or be credited with fixing it. Do not remove the
   wrapper's initial allowlist or Xauthority-copy behavior until the
   broker is proven to replace each behavior safely.

## Implementation and verification update (2026-09-27)

Implemented the scoped session environment broker, GNOME Session
forwarding, the snapd systemd environment policy split, caller
authentication, and wrapper cleanup. Source changes are in the
ubuntu-desktop-session-snap, ubuntu-core-desktop-snapd,
core-base-desktop, and ubuntu-core-desktop worktrees. The session
environment broker race tests and focused snapd interface/AppArmor
tests pass. The GNOME Session patch compiled and the session snap and
two fresh GNOME images were built with the image build.

On the latest clean image, systemd's shared environment had no SNAP
variables and showed host paths for XDG_RUNTIME_DIR and XAUTHORITY.
The host portal frontend acquired its D-Bus name during session
startup; the GNOME portal backend started. Tests also confirmed the
broker rejects ordinary app callers, accepts the authenticated
gnome-session-service identity, and leaves the shared environment
unchanged for rejected calls.

The cold App Center click acceptance gate is NOT met: the 1.5-second
capture was still the desktop, while a later capture (about five
seconds after the click) showed the App Center window. The GTK portal
backend initially logged `cannot open display: :0` and required later
activation after the desktop was up. The separate missing X11 socket
bind mount remains unresolved and was not changed or used to mask this
result. Empty GNOME_SETUP_DISPLAY Setenv values were also found to
need explicit broker removal handling; this is now covered by a broker
regression test and rebuilt into the latest session snap, but that
last broker-only change has not yet been tested in a newly rebuilt
image. These findings were superseded by the user's subsequent
fresh-VM verification recorded below.

## Resolution (2026-09-27)

Implemented and committed the least-privilege session environment
broker, GNOME Session integration, snapd policy split, host wrapper
cleanup, and the GTK portal's D-Bus activation. The user rebuilt the
latest snap and a fresh VM, waited for the desktop and Home launcher
to appear, then clicked the Snap Store launcher and confirmed that the
window opened. Their subsequent `systemctl --user show-environment`
output contained no SNAP variables and showed host-visible
XDG_RUNTIME_DIR and XAUTHORITY paths. The user considers the real
fresh-VM launch and clean-environment check verified; the launch was
not independently stopwatch-timed in that final run.

Commits:

- ubuntu-desktop-session-snap: c1f1033
- ubuntu-core-desktop-snapd: cea0366d3d
- core-base-desktop: 0fd1ab5
- ubuntu-core-desktop: e10a5f6

The separate X11 socket bind-mount issue was not changed or credited
to this work.
