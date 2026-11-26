# Xwayland's XAUTHORITY points at a snap-private runtime dir

## Impact / Priority

Launching a separately-confined snap with a GUI (e.g. App Center /
snap-store, via `snap routine desktop-launch` or clicking its desktop
icon) failed with "cannot open display: :0", because mutter exported an
XAUTHORITY path inside ubuntu-desktop-session's snap-private runtime
directory, which other confined snaps cannot see. Impact derived from
the original note's described symptoms.

## Context

Found: 2026-09-26, while testing an unrelated fix (fuse-broker for
xdg-document-portal). NOT caused by that work — confirmed via git
history that gnome-shell has run confined (as its own snap app inside
ubuntu-desktop-session) since well before that work started (at least
commit cffd9627e8f5, 2026-09-22, "Add wayland/x11 slots to gnome-shell
app for confined Xwayland bind" — and per-app confinement almost
certainly predates even that commit, since that commit only adds
X11-socket-bind slot ownership, not confinement itself). Confirmed via
git diff/commit history that none of the fuse-broker session's changes
(Makefile, fuse-broker, fuse-device interface) touch anything
X11/Xauthority related.

## Symptom and root cause

Launching a separately-confined snap with a GUI (e.g. App Center /
snap-store, via `snap routine desktop-launch` or clicking its desktop
icon) fails with:

    snap-store[NNNN]: cannot open display: :0

Root cause: mutter (running confined as the `gnome-shell` app inside
ubuntu-desktop-session-snap) writes its Xwayland auth file to its own
private, per-snap-instance runtime dir:

    /run/user/<uid>/snap.ubuntu-desktop-session/.mutter-Xwaylandauth.*

and exports that path as XAUTHORITY into the global systemd --user
environment (via systemctl --user set-environment, standard
mutter/gnome-session behaviour). Other, separately-confined snaps (e.g.
snap-store) cannot see into ubuntu-desktop-session's private runtime
dir, so their GTK apps fail to connect to the X11 display via that
XAUTHORITY path.

This is the same *class* of bug as the (separately fixed)
xdg-document-portal global-mount-path issue — a component confined
inside one snap writing state to its own private runtime dir, then
handing out that private path to other, differently-confined consumers
that can't see it — but a different component/mechanism, so tracked
here as its own bug rather than folded into that fix's notes.

## Not yet investigated

- Where exactly XAUTHORITY gets exported into the global systemd user
  environment (likely mutter or gnome-session internals, not something
  this project's own snap packaging currently controls).
- Whether the fix should be: (a) making mutter place the Xwayland auth
  file at the global /run/user/<uid>/ instead of its private runtime
  dir (mirroring the xdg-document-portal fix's XDG_RUNTIME_DIR
  override, if mutter's own runtime-dir need is similarly scoped/safe
  to redirect), (b) bind-mounting/exposing the private path to other
  snaps via a shared interface, or (c) something else.
- Whether this has ever actually worked (i.e. did App Center's GUI ever
  open successfully once gnome-shell became a confined snap app, or has
  this been silently broken since then, just masked by launches failing
  earlier for other reasons like the document-portal issue)? The user
  could not recall for certain; deliberately not bisected further to
  avoid a rabbit hole (out of scope for the fuse-broker work in
  progress at the time this was found).

## Verification once fixed

Click the App Center icon (or any other confined snap with a GUI, e.g.
`snap run gnome-text-editor` after installing it) from a real
logged-in desktop session and confirm its window actually opens, not
just that no document-portal error appears.

## Resolution (2026-09-26)

Fixed. Chose approach (a): pin XDG_RUNTIME_DIR back to the real
/run/user/<uid> for the session's gnome-shell and
ubuntu-desktop-session (gnome-session) apps, mirroring the existing
xdg-document-portal override in snapcraft.yaml.

Root cause confirmed precisely: snap run privatizes XDG_RUNTIME_DIR to
/run/user/<uid>/snap.<name> for every confined app. gnome-session and
mutter re-export that snap-private path (and the Xwayland auth file
mutter writes into it, via g_get_user_runtime_dir()) into the global
systemd --user environment via dbus-update-activation-environment,
overwriting the real /run/user/<uid> values set by
core-desktop-session-wrapper.sh. This leaked:

- XDG_RUNTIME_DIR -> breaks userd's systemd-run --user (can't find the
  user systemd socket) -> every icon-click launch fails with "cannot
  run [...]: exit status 1" (the actual App Store symptom).
- XAUTHORITY -> other confined snaps can't read the auth file ->
  "cannot open display :0".

Fix: commit 89ae093 on ubuntu-desktop-session-snap branch 26-dev adds
`environment: XDG_RUNTIME_DIR: /run/user/$SNAP_UID` to the
`ubuntu-desktop-session` and `gnome-shell` apps.

Verified end-to-end on the desktop26 test VM: rebuilt the snap,
sideloaded it (rev x2), restarted gdm. After the fix the global user
env shows XDG_RUNTIME_DIR=/run/user/1000 and
XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.XXXXXX (real dir), and
snap-store launched via the icon-click desktop-launch path now runs and
connects to the wayland compositor (no more "exit status 1", no
"cannot open display").

Remaining (separate, pre-existing, NOT in scope of this item):

- snap-store still logs "Settings portal not found:
  org.freedesktop.portal.Desktop ... Timeout" — the xdg-desktop-portal
  startup timeout / PermissionStore AppArmor denials (tracked in the
  nautilus/gvfs-tracker portal-denials item) and the portal ordering
  deadlock (`20260924-xdg-desktop-portal-login-delay-ordering-cycle.md`).
- The global user env still leaks SNAP=/snap/ubuntu-desktop-session/x1
  (gnome-session re-exports it too). Harmless for the two bugs fixed
  here, but worth a follow-up if any behaviour keyed off SNAP_* env
  vars is seen in unconfined user services.

## Superseded note (appended on import)

The `environment: XDG_RUNTIME_DIR` override above was later found to be
unsound and was reverted: redirecting XDG_RUNTIME_DIR wholesale caused
AppArmor DENIED errors (gnome-shell writing directly into
/run/user/<uid>/, which its profile does not grant) and broke the
session entirely (Xwayland crashes, sessions bouncing back to GDM). The
underlying leak was fixed afterwards by the filtered session-environment
broker instead — see
`20260926-dbus-proxy-setenv-filter.md` and its "Note on the stale prior
done record" section. Do not repeat the wholesale-override approach.
