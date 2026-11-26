# Route KDE session environment updates through a broker

## Impact / Priority

Medium-High. The KDE desktop starts, but X11 apps from other confined
snaps may fail to connect to Xwayland if they inherit the session snap's
private XAUTHORITY path. This has not yet been reproduced with a real
external app: the inspected KDE VM had no non-session graphical snap
installed. Verify the user-visible impact with a test or real X11 snap.

## Context

The clean-boot KDE VM showed the systemd user manager environment
containing:

    XDG_RUNTIME_DIR=/run/user/1000
    DISPLAY=:0
    WAYLAND_DISPLAY=wayland-0
    XAUTHORITY=/run/user/1000/snap.plasma-desktop-session/xauth_<random>

The manager's XDG_RUNTIME_DIR is the host-visible path, but XAUTHORITY
points inside the Plasma session snap's private runtime directory. That
directory and the xauth file were mode 0700 and 0600 respectively. KWin
itself runs with
XDG_RUNTIME_DIR=/run/user/1000/snap.plasma-desktop-session and starts
Xwayland with an xauth file there.

KWin currently updates the shared D-Bus activation and systemd
user-manager environments directly. `ubuntu-core-desktop-snapd` commit
c675c97fb1 grants the KWin app the `UpdateActivationEnvironment` and
`SetEnvironment` calls needed for KDE startup; there were no denials on
the inspected VM. These permissions do not filter the values KWin
publishes.

The snapd X11 interface allows reading `/run/user/<uid>/.Xauthority`
and `/run/user/<uid>/xauth_*`, but not the nested
`/run/user/<uid>/snap.plasma-desktop-session/xauth_*` path. snapd's
`migrateXauthority` in `cmd/snap/cmd_run.go` only migrates Xauthority
files whose input path is under `/tmp`, so it does not automatically
rewrite this KWin path for another snap. The GNOME environment broker
in `ubuntu-desktop-session-snap` commit
c1f10338f6de7d43955a1b43115b0883a8d7d8be does not cover KDE: it is
integrated with patched `gnome-session-service` and authorizes that
GNOME app specifically.

## Scope and recommendation

Use a KDE source-side integration with the environment broker rather
than building a generic D-Bus proxy by default. Find a narrow KWin
environment export hook and route its shared-environment updates
through a broker that authenticates the KWin app's UID and AppArmor
label, applies an explicit allowlist, and publishes a host-readable
XAUTHORITY containing the valid Xwayland cookie. Keep the shared
XDG_RUNTIME_DIR set to the real `/run/user/<uid>`; do not override the
confined processes' own snap-private runtime directories.

The current broker is packaged in the GNOME session snap and has a
GNOME-specific caller label. Decide whether to generalize/package it
in a component available to both desktops or add a KDE broker adapter;
do not assume the existing GNOME snap is present in KDE images. Once
the broker path works, remove KWin's direct shared-environment write
permissions from `systemd-user-control`. Keep the existing permissions
until then so KWin and KDE startup continue to work.

Do not add a generic D-Bus proxy solely for KDE. Revisit that option
only if another concrete producer cannot be integrated at source or
the number of consumers makes per-desktop adapters unjustifiable.

## Verification

1. Add focused tests for caller authentication, allowed environment
   names and values, forced/rewritten XAUTHORITY, and rejected
   snap-private paths.
2. Build the updated broker and KDE snaps, then boot a fresh KDE VM.
   Confirm KWin, Plasma Shell, KSMServer, and X11 helpers start; the
   user manager retains the real XDG_RUNTIME_DIR and a host-readable
   XAUTHORITY; and no direct KWin writes bypass the broker.
3. Install or seed a separate confined snap with the X11 plug and
   launch it through a real desktop entry. Confirm its Xwayland window
   opens and that its confined process can read the published
   Xauthority path. The inspected VM had no such app, so this
   end-to-end check is still required.
