# Ensure the Ubuntu Core 26 confined desktop session starts correctly

Date: 2026-09-15

## Impact / Priority

High. The confined desktop session — this project's core feature — did
not work at all: app launches (e.g. the terminal icon) showed a spinner
forever, and the session came up unconfined, bypassing the wrapper that
creates the confined Wayland socket.

## Context

The terminal icon on the Core 26 test VM only shows a spinner and does
not open a window. The terminal works on the Core 24 test VM.

On the working Core 24 VM, the graphical session is started through:

    core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME

On the failing Core 26 VM, the session is instead started as:

    /usr/libexec/gdm-wayland-session gnome-session

The wrapper is required for the confined desktop session. Among other
things, it creates the Wayland socket link:

    /run/user/1000/wayland-0
        -> snap.ubuntu-desktop-session/wayland-0

That link and the corresponding socket under the snap runtime directory
exist on Core 24 but are missing on Core 26.

As a result, activating the terminal starts the confined
ubuntu-desktop-session.gnome-terminal-server service, but it exits with:

    Failed to parse arguments: Cannot open display

The D-Bus activation then times out, leaving the terminal launcher
spinner running indefinitely.

Relevant session files are present on both systems:

    /usr/share/wayland-sessions/ubuntu-desktop-session.desktop

with:

    Exec=core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME

## Work items

- Ensure GDM selects and launches the `ubuntu-desktop-session.desktop`
  session on Ubuntu Core 26, rather than falling back to plain
  `gnome-session`.
- Verify that the resulting session has `XDG_CURRENT_DESKTOP=ubuntu:GNOME`
  and that `core-desktop-session-wrapper.sh` creates the confined
  Wayland socket and related PipeWire socket links.
- Confirm that `/run/user/1000/snap.ubuntu-desktop-session/wayland-0`
  exists and that the `snap.ubuntu-desktop-session.gnome-terminal-server`
  service remains active after launching the terminal.
- Check why GDM/session selection chose plain GNOME on Core 26
  (including the default-session configuration and any stale remembered
  session selection), and make the fix persistent for new logins.
- Re-test the terminal icon and direct terminal launch after logging out
  and back in, and after a reboot.

## Resolution (2026-09-15)

Root cause found and fixed: the Stage 1 fix (base: core26-desktop) had
been written but never built+deployed to the test VM, and a separate bug
in `run-session.sh` (obsolete `--builtin` flag to gnome-session) caused
an immediate crash once the Stage 1 fix was deployed. Both fixed; the
confined session (including the terminal) now works end-to-end. See
`20260915-followup-confined-session-apparmor-gaps.md` for remaining
follow-up work.
