# Secret portal backend activation is GNOME-specific on a shared base

## Impact / Priority

Medium, but on-the-ground impact not yet pinned down. The
xdg-desktop-portal Secret backend (org.freedesktop.impl.portal.Secret)
lets portal-based apps (flatpaks, portal-aware snaps) store and
retrieve secrets. What a real user would observe if it is broken: apps
that store credentials via the Secret portal fail to save/retrieve
logins and tokens, typically with "portal backend unavailable"-style
errors. Whether ANY current app on the GNOME image actually hits this
is unknown - it needs a real end-to-end test (a portal client storing
a secret) rather than log reading.

## Context

core-base-desktop's tree vendors
static/usr/share/dbus-1/services/org.freedesktop.impl.portal.Secret.service
(Exec=/snap/bin/ubuntu-desktop-session.gnome-keyring-daemon ..., added
in a02e727 "Fix confined portal activation") but the 002.1-add-gdm
greeter-trim hook deletes it along with the apt-staged copies, so no
built snap has ever shipped it. The 2026-11-04 review of the Settings
activation fix (59690db) deliberately did NOT restore it: the same
base snap feeds the KDE image, whose model
(ubuntu-core-desktop-kde-26-amd64-dangerous.json) has
plasma-desktop-session, not ubuntu-desktop-session - a GNOME-keyring
activation file in the shared base would dangle on KDE.
hook-tests/024-vendored-dbus-services.test asserts its absence; that
assertion must be updated together with any fix here.

## Next steps

1. Test on the GNOME image whether the Secret portal actually works
   today (does the running gnome-keyring-daemon own
   org.freedesktop.impl.portal.Secret, or does the portal fail to
   activate the backend?);
2. decide placement for desktop-specific activation files:
   per-desktop restore after the trim (like the Settings files in the
   Makefile, driven from ubuntu-core-desktop's build.sh which knows
   which desktop is being built) vs keeping them in the shared base
   with desktop-neutral Exec= paths;
3. check what KDE uses for the Secret portal backend at all.
