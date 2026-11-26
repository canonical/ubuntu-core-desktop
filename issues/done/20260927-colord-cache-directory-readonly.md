# Investigate colord failing to create its cache directory

## Impact / Priority

Medium. On the running Core Desktop VM, `colord.service` fails during
startup because it cannot create its cache directory under `/var/cache`
on the read-only filesystem. Basic desktop startup may still work, but
color-profile discovery, selection, or calibration could be
unavailable. The actual user-visible impact has not been tested; verify
it with an ICC profile or color-management workflow.

## Context

The VM reported:

    colord.service: Failed to set up special execution directory in /var/cache:
    Read-only file system
    colord.service: Failed at step CACHE_DIRECTORY spawning /usr/libexec/colord:
    Read-only file system
    Failed to start colord.service - Manage, Install and Generate Color Profiles.

This indicates systemd failed while preparing a cache directory before
starting colord. Confirm the service's `CacheDirectory=` setting, any
drop-ins, and the image's writable filesystem layout before choosing a
fix. Do not make `/var/cache` broadly writable or remount the root
filesystem.

## Investigation and verification

1. Inspect the effective `colord.service` unit and drop-ins; identify
   the exact directory systemd tries to create and whether colord needs
   that cache to be persistent or only for the current boot.
2. Check the Core Desktop filesystem layout and existing writable
   locations. Determine whether colord is required for supported
   desktop behavior or can be disabled when color management is not
   provided.
3. If needed, make a narrow source-level change that gives colord only
   the writable cache/state path it requires, following the image's
   existing persistence patterns. Avoid broad writable access to
   `/var/cache`.
4. Build and boot a fresh image. Confirm colord starts, the intended
   path has the expected persistence across reboot, and a real
   color-profile workflow works. Also confirm the service failure no
   longer appears in the boot journal.

## Resolution (2026-09-28)

Added a narrow tmpfs mount at `/var/cache/colord`, leaving the rest of
`/var/cache` read-only. Added a persistent writable bind mount for
`/etc/colord`, and provisioned its factory and writable-system-data
directories. Colord's existing persistent `/var/lib/colord` path is
unchanged.

Rebuilt the Core-base snap and GNOME image, booted the image, and
rebooted the VM. After reboot, `/etc/colord` and `/var/lib/colord` were
writable bind mounts from persistent system data; `/var/cache/colord`
was a writable tmpfs owned by `colord`. `colormgr get-profiles`
successfully enumerated the installed ICC profiles, `colord.service`
started successfully with no restarts, and its boot journal contained
no errors.

The VM exposes no display devices to colord, so assigning a profile to
a display or testing calibration was not possible in this environment.
