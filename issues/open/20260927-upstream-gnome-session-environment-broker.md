# Prepare the GNOME Session environment broker changes for upstream

## Impact / Priority

Medium. The current patch changes behavior for a regular, unconfined
GNOME Session: it routes Mutter's `Setenv` updates to the snap-only
broker and makes the shared-environment bulk exports no-ops. Without
the broker and host wrapper, ordinary sessions may stop updating
activation environments. The end-user impact outside the confined snap
session has not been verified; test a regular unconfined session to
establish it.

## Goal

Prepare the GNOME Session changes for upstreaming without regressing
regular unconfined sessions. Preserve GNOME Session's existing direct
environment-update behavior when running unconfined, and use the
filtered broker path only for the confined session. Investigate a
confinement-aware guard (for example, checking `$SNAP`) and verify
that the detection is reliable and cannot be confused by inherited
environment values.

## Relevant source

- `ubuntu-desktop-session-snap/patches/gnome-session-environment-broker.patch`
- `ubuntu-desktop-session-snap/snap/snapcraft.yaml`
- `ubuntu-desktop-session-snap/environment-broker/`

Do not make source changes or submit upstream patches as part of
creating this issue.
