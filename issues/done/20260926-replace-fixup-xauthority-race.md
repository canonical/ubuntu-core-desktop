# Replace fixup_xauthority: it loses the race against mutter's Setenv

## Impact / Priority

High. This is the mechanism directly responsible for the XAUTHORITY
leak documented in the App Store launch-failure investigation, which
causes cross-snap GUI launches (e.g. clicking the App Store desktop
icon) to fail with "cannot open display :0" / hard launch failures. A
real user clicking a desktop icon for any snap other than the desktop
session itself can be affected. This is not a minor timing quirk -- the
current design is structurally unable to guarantee correctness, not
just occasionally slow.

## Where

core-base-desktop/static/usr/bin/core-desktop-session-wrapper.sh
(installed as /usr/bin/core-desktop-session-wrapper.sh in the image),
function `fixup_xauthority` plus its call site and the preceding
`dbus-update-activation-environment` line, roughly lines 20-58:

    dbus-update-activation-environment --systemd DISPLAY=:0 \
        WAYLAND_DISPLAY=wayland-0 XAUTHORITY=$XDG_RUNTIME_DIR/.Xauthority

    function fixup_xauthority() {
        while :; do
            sleep 1s
            if [ "$session_type" = "KDE" ]; then
                xauth_file="$(ls -1t $XDG_RUNTIME_DIR/snap.$snap_name/xauth_* | head -n1)"
            else
                xauth_file="$(ls -1t $XDG_RUNTIME_DIR/snap.$snap_name/.mutter-Xwaylandauth.* | head -n1)"
            fi
            if [ -f "$xauth_file" ]; then
                cp "$xauth_file" $XDG_RUNTIME_DIR/.Xauthority
                return
            fi
        done
    }
    ...
    fixup_xauthority &
    ...
    exec "/snap/bin/$snap_cmd"

## What it is trying to do

Avoid the confined mutter/gnome-session ever exporting a snap-private
XAUTHORITY path into the *global* systemd --user / D-Bus activation
environment (which other, separately-confined snaps cannot read). It
tries to do this by:

1. Pre-setting the global XAUTHORITY env var, before mutter starts, to
   a fixed real (unconfined) path: $XDG_RUNTIME_DIR/.Xauthority. At
   this point the file does not exist yet.
2. Backgrounding a poll loop that waits for mutter to create its real
   Xwayland auth cookie inside the snap-private runtime dir, then
   copies the cookie's *contents* into that same fixed real path, and
   exits.
3. Only then execs mutter/gnome-session.

The intent is reasonable (keep the env var's value constant and only
ever update file *contents* at a fixed path, to sidestep having to
"correct" the env var after the fact). It does not work.

## Problem 1: it loses an unordered, unrefereed race against mutter itself

Mutter/gnome-session's own startup path independently calls
org.gnome.SessionManager.Setenv (mutter src/wayland/meta-wayland.c
set_gnome_env), which gnome-session handles by itself invoking
`dbus-update-activation-environment --systemd
XAUTHORITY=<snap-private-path>`. This happens *after* the wrapper
script's line-22 assignment (mutter is only exec'd at the very end of
the script), and unconditionally overwrites whatever was there. There
is no lock, compare-and-swap, or ordering guarantee between two
independent processes calling
`UpdateActivationEnvironment`/`SetEnvironment` on the shared global
environment -- it is simple last-write-wins. In practice, on a clean
boot, mutter's call fires after the wrapper's and wins, which is
exactly the leak that was observed and diagnosed (in the App Store
launch-failure investigation): the global XAUTHORITY ends up pointing
at the snap-private path, not $XDG_RUNTIME_DIR/.Xauthority.

Mutter can also call Setenv more than once over its lifetime (not
provably a single one-shot event at startup), so even a hypothetical
one-time "fix it after mutter's first call" approach would not be safe
either -- there is no final word, only whoever calls last at any given
moment.

## Problem 2: even the file-copy half has its own startup race

Independently of problem 1, there is a window between the wrapper
setting the (correct-valued) global env var and the background loop
actually copying real cookie content into
$XDG_RUNTIME_DIR/.Xauthority (the loop polls only once per second and
only starts once mutter has created the source file). Any process that
tries to use XAUTHORITY=$XDG_RUNTIME_DIR/.Xauthority to authenticate to
X11 during that window finds a missing or stale file. This is a
secondary, smaller issue compared to problem 1, but should not be
reintroduced by whatever replaces this function.

Conclusion: no "fire and forget" / "fix it afterward" design can be
correct here, because the global activation environment has no
ordering or locking semantics between independent writers. The only
race-free fix is to intercept and filter the value *at the point mutter
hands it off* (i.e. the Setenv call / the dbus-update-activation-
environment invocation it triggers), so the bad value is never written
in the first place, rather than trying to win a race against it
afterward.

## Design directions considered (not yet decided/implemented)

1. Determine whether gnome-session's handling of Setenv actually execs
   a separate `dbus-update-activation-environment` process (a
   subprocess boundary we could intercept/shim with a filtering wrapper
   that only allows a var whitelist through -- e.g. WAYLAND_DISPLAY,
   DISPLAY, XDG_SESSION_TYPE, XDG_CURRENT_DESKTOP,
   XDG_SESSION_DESKTOP, XCURSOR_THEME, XCURSOR_SIZE,
   GNOME_SETUP_DISPLAY, etc., always forcing
   XAUTHORITY/XDG_RUNTIME_DIR to the fixed real values) or calls the
   D-Bus methods directly in-process (no subprocess boundary to
   intercept cheaply).
2. If there is no subprocess boundary, a proper D-Bus-level
   interception is needed instead (originally proposed by the user as
   a systemd --user-managed proxy sidecar sitting between mutter and
   the real session bus, whitelisting which env vars
   `UpdateActivationEnvironment` is allowed to set before forwarding).
   This is a bigger piece of work (needs to correctly forward all
   other D-Bus traffic mutter needs, not just this one method) and
   should only be pursued if (1) is not viable.
3. Either way, the fix needs to also keep working for the KDE session
   variant (session_type = KDE), which currently uses the analogous
   xauth_* file pattern in the same function.

## Next steps

1. Determine exactly how gnome-session invokes
   `dbus-update-activation-environment` for the Setenv it receives
   from mutter (strace/ps during a live session, or read gnome-session
   source) to decide between design (1) and (2) above.
2. Prototype the chosen interception point and verify, on a fresh VM
   boot after an image rebuild (`build.sh`), that the global
   XAUTHORITY never contains a snap-private path at any point after
   login (not just "eventually corrects itself").
3. Re-run the end-to-end App Store desktop-icon click test (from the
   earlier app-store investigation) to confirm this alone is
   sufficient for part 1 of that bug (part 2, the X11 socket
   bind-mount issue in snapd's x11 interface, is separate and still
   unresolved).
4. Remove/replace the old `fixup_xauthority` function and its call
   site once the new mechanism is in place and verified.

Update 2026-11-03 (status, not a fix): the replacement mechanism this
issue's design direction (2) pointed at has since LANDED - the GNOME
session environment broker (ubuntu-desktop-session-snap; see
`20260927-gnome-session-service-environment-broker.md`):
gnome-session-service forwards Mutter's Setenv updates to the broker,
which authenticates the caller, strips SNAP*/SNAP_* variables, and
forces host-visible XDG_RUNTIME_DIR and XAUTHORITY before applying
them to the shared environments. So for GNOME the XAUTHORITY leak is
fixed at the write path and the race is unwinnable-by-design rather
than won. What remains from this issue:
- step 4 (cleanup): the old fixup_xauthority poll loop is STILL
  present, dead, in
  core-base-desktop/static/usr/bin/core-desktop-session-wrapper.sh
  (function at line 138, backgrounded call at line 175) - remove it
  and its call site;
- the KDE equivalent is still open -
  `20260927-kde-session-environment-broker.md`: KWin's direct
  UpdateActivationEnvironment/SetEnvironment writes are unfiltered, so
  KDE retains the same class of leak (XAUTHORITY pointing into
  snap.plasma-desktop-session's private runtime dir).
