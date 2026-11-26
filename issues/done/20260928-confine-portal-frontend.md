# Confine the GNOME desktop portal frontend

## Impact / Priority

Medium. Portal-mediated features currently work in the tested GNOME
session, but the frontend runs on the host rather than under snap
confinement. The user-visible impact is not a known feature failure; the
product does not yet meet its goal of confining the full desktop
session.

## Goal

Run `xdg-desktop-portal` under the intended confined session-snap
application while preserving its D-Bus API, backend dispatch, document
portal access, and permission-store integration. Do not solve the
confinement problem by granting broad access to the session bus or
running a permissive proxy.

## Context

Stage 2.2 routed the portal backends and verified FileChooser selection
and document-portal access. The frontend remains host-run because the
confined `xdg-desktop-portal` app did not acquire
`org.freedesktop.portal.Desktop`. The host frontend and permission store
also have an integration dependency: when the frontend is confined, its
calls to the host permission store are denied.

Relevant source:

- `ubuntu-desktop-session-snap/snap/snapcraft.yaml`: the
  `xdg-desktop-portal` app and its snap plugs.
- `core-base-desktop/static/usr/lib/systemd/user/xdg-desktop-portal.service`:
  the host frontend unit, currently ordered after
  `graphical-session.target`.
- `core-base-desktop/static/usr/share/dbus-1/services/` and
  `static/usr/lib/systemd/user/`: D-Bus activation and unit routing.

The portal ordering has a separate startup-delay investigation in
`20260928-fix-startup-delay-again.md`. Coordinate the solutions: do not
reintroduce the GNOME Shell/portal wait cycle, or make the GTK backend
start before the display is usable.

## Work and verification gates

1. On a fresh image, reproduce which process owns
   `org.freedesktop.portal.Desktop`, which service activation path starts
   it, and why the confined app fails to own the name. Capture the
   relevant D-Bus and AppArmor denial evidence; do not infer the cause
   from a failed name acquisition alone.

2. Identify and implement the narrowest supported D-Bus ownership and
   policy arrangement for the frontend. Verify the snap's declared
   service identity/slot, generated AppArmor policy, bus activation
   file, and user-systemd unit agree. Do not leave a competing host
   service able to claim the Desktop name.

3. Decide and implement how the confined frontend communicates with the
   permission store. Either confine and route the permission store too,
   or provide an explicitly reviewed, narrowly scoped authorization
   path. Confirm normal callers cannot use the change to gain unrelated
   D-Bus access.

4. Build a fresh image from source and verify the frontend process runs
   under its expected enforce profile, owns
   `org.freedesktop.portal.Desktop`, and has no host-run duplicate or
   restart loop. Check logs for new AppArmor denials and startup errors.

5. Exercise real portal flows on that image: request a FileChooser from
   a confined client, select a visible home file, and read it through
   the granted document-portal URI. Also verify a permission-store-backed
   portal operation and one other supported portal call.

6. Recheck cold GNOME login and a real cold Snap Store launcher click.
   Require the graphical session to remain responsive and the store
   window to appear within 2 seconds. Use the startup-delay note's
   timestamp gates; do not count a working portal as a fix if startup
   regresses.

7. Completion requires fresh-image, end-to-end feature tests and
   confirmation that the host frontend is no longer the active owner.
   If Snap's D-Bus policy cannot safely authorize the confined frontend,
   document the specific limitation and leave the frontend host-run
   rather than broadening privileges.

## Latest verification — 2026-09-28

On the rebuilt fresh image, `org.freedesktop.portal.Desktop` is owned by
`/usr/libexec/xdg-desktop-portal` under
`snap.ubuntu-desktop-session.xdg-desktop-portal (enforce)`. The confined
document portal and GTK backend are active with zero restarts.

A FileChooser `OpenFile` request from a GTK client under the real
`snap-store` Snap profile initially returned no URI. The D-Bus trace
showed the frontend's `Documents.AddFull` request failing with `Not
enough permissions`: it requested a writable grant while passing a
read-only file descriptor. The core portal patch now opens selected
files with `O_RDWR` when writable access was requested. The core snap
and fresh GNOME image were rebuilt from source.

After that fix, a user-selected home file returned
`file:///run/user/1000/doc/6bf9009f/portal-grant-test.txt`.
`Documents.Info` showed read/write/grant-permissions for
`snap.snap-store` and the confined frontend permissions ID. A GJS
process under the Snap Store profile read the exact expected contents
through that document URI. The file-selection and read gate now passes.

At that point, the permission-store-backed portal operation, an
additional portal call, broker authorization checks, and the remaining
App Center 2s visual gate were still open. Follow-up verification is
recorded below.

## Follow-up verification — 2026-09-28

On the latest rebuilt image, `org.freedesktop.portal.Desktop` is still
owned by the session-snap frontend under its enforce profile. The portal
frontend, GTK backend, document portal, permission store, broker, and
IBus portal reported zero restarts.

The additional `org.freedesktop.portal.Settings.Read` call from the
Snap Store profile returned the `default` color-scheme value. A confined
Snap Store-profile call to
`org.freedesktop.portal.Background.RequestBackground` returned a request
handle and created the expected `background` permission store entry for
`snap.snap-store`; `PermissionStore.Lookup` confirmed it. The test
permission and its empty record were then deleted and the table
verified empty. This verifies the portal-to-permission-store path, but
it was an API-level call from a shell under the Snap Store profile, not
a user-consent/UI test.

An unconfined environment-broker call was rejected by D-Bus AppArmor
policy; the authorized `gnome-session-service` profile's call succeeded.
The user systemd environment remains free of `SNAP_*` values and has the
required host runtime/Xauthority paths. D-Bus activation values were not
directly queried.

The FileChooser/document-grant/read test remains the real end-to-end
flow recorded above. The later cold App Center launch is positively
reported by the user and has a process-level journal timeline, but no
first-visible-pixel capture; retain the earlier ~3.2-second screenshot
result and leave the 2-second gate open. GNOME Shell/Nautilus and some
routed services still log AppArmor-denied D-Bus calls; no comparable
pre-change baseline was captured, so do not classify them as new or
pre-existing yet.
