# Fuse broker Step 4: wiring the fusermount3 shim in (final design + gotcha)

## Impact / Priority

Medium. Without this, any GTK/portal-based file-open dialog in a
confined app that uses xdg-document-portal cannot browse the filesystem
at all (the portal service crash-loops at startup); this is a core
piece of desktop file-picker functionality, but does not block
boot/login/other apps.

## Context

xdg-document-portal (confined snap) needs to FUSE-mount its doc dir but
has no real CAP_SYS_ADMIN. Steps 1-3 built a privileged root broker
(xdg-fuse-broker) + a fusermount3-replacing shim that hands the
confined process a live FUSE fd via SCM_RIGHTS. This note covers
Step 4: wiring that shim into the actual xdg-document-portal snap app,
and the blocker hit doing so.

## Root cause of the two blockers hit (in order)

1. libfuse's `fuse_mount_sys()` (mount.c) only falls back to invoking
   fusermount3 (replaced, for this app, by the shim) on mount(2) errno
   EPERM specifically — any other errno gives up with no fallback.
   AppArmor's mount mediation is default-deny, so simply deleting the
   mount rule (as an earlier plan draft assumed) makes AppArmor itself
   deny with EACCES, and libfuse never invokes the shim at all. Fix:
   the new `fuse-device` interface (interfaces/builtin/fuse_device.go in
   ubuntu-core-desktop-snapd) DOES include this scoped mount-allow
   AppArmor rule — this is not a capability grant, it only makes
   AppArmor *permit* the attempt so the kernel's own capability check
   is what then denies it, with the specific errno (EPERM) libfuse's
   fallback path is looking for. No `capability sys_admin` is granted
   anywhere in this interface:

       mount fstype=fuse.* ... -> /run/user/[0-9]*/snap.@{SNAP_INSTANCE_NAME}/doc{,/**},

2. Once the interface/plug/gadget-connection wiring was all correct and
   the image rebuilt, a fresh boot still failed with `fuse: failed to
   open /dev/fuse: Operation not permitted` (an EPERM on open(2),
   before even reaching mount(2)) and `snap connections` showed the
   `fuse-device` plug listed but unconnected (`-` in the Slot column).
   Cause: this project's local/dangerous dev builds resolve gadget.yaml
   static `connections:` entries by snap-id only — these never apply
   for locally-built, `--dangerous`-installed snaps, so there's a
   dev-only boot-time workaround loop in `ubuntu-core-desktop/build.sh`
   that explicitly runs `snap connect ubuntu-desktop-session:<plug>`
   for a hardcoded list of interface names (baked into a systemd unit,
   ensure-desktop-session-connections.service). This list was never
   taught about the new `fuse-device` interface when fuse-support was
   replaced by it — it needed `fuse-device` added alongside the other
   ~30 entries already there (e.g. network-control, hardware-observe).
   Confirmed via fast VM iteration: manually running
   `snap connect ubuntu-desktop-session:fuse-device snapd:fuse-device`
   on an already-booted VM immediately fixed both the /dev/fuse open
   and the subsequent mount, with the broker log showing the shim's
   mount request being serviced (`cmd=M ... mounted fuse filesystem`) —
   then added `fuse-device` to build.sh's list and reran just the final
   image-assembly stage (no need to rebuild snapd/gadget/session snaps,
   only build.sh itself changed) and confirmed a second, fully clean
   fresh boot (no manual `snap connect`) also worked end-to-end.

## Final design (as actually shipped)

- New snapd interface `fuse-device` (ubuntu-core-desktop-snapd,
  interfaces/builtin/fuse_device.go): implicitOnCore, udev
  `KERNEL=="fuse"`, AppArmor grants `/dev/fuse rw,`, the broker socket
  `/run/xdg-fuse-broker.sock rw,`, the scoped doc-dir mount-allow rule
  described above, and `/sys/fs/fuse/** r,`. No sys_admin capability,
  no seccomp additions needed (snapd's seccomp default-implicit-denial
  errno is already EPERM; network-control's existing seccomp mount
  grant is what lets the syscall reach AppArmor mediation at all on
  this profile).
- `fuse-support` fully reverted/removed from this app's plugs
  (ubuntu-desktop-session-snap), the gadget's auto-connection
  (pc-amd64-gadget-desktop), and fuse_support.go itself (byte-identical
  revert in ubuntu-core-desktop-snapd) — replaced by `fuse-device` in
  the same 2 non-snapd locations, plus the fuse_device.go interface.
- ubuntu-desktop-session-snap/snap/snapcraft.yaml gained a `layout:`
  stanza bind-mounting the shim onto `/usr/bin/fusermount3` snap-wide
  (libfuse tries the absolute path first, falling back to $PATH only on
  failure, so PATH-only redirection is insufficient).
- `ubuntu-core-desktop/build.sh`'s dev-only
  ensure-desktop-session-connections workaround list needed
  `fuse-device` added (see gotcha 2 above) — this workaround is purely
  a local/--dangerous-build convenience; once/if
  ubuntu-desktop-session is ever installed with a real store snap-id,
  the gadget.yaml connection alone is sufficient and this list becomes
  unnecessary for this interface too, same as for its other ~30
  entries.

## Verification performed (on a genuinely fresh VM boot, not a live-patched one)

- `systemctl --user show
  snap.ubuntu-desktop-session.xdg-document-portal.service`:
  ActiveState=active, SubState=running, NRestarts=0.
- `mount | grep doc`: FUSE mount present at
  /run/user/1000/snap.ubuntu-desktop-session/doc.
- `snap connections ubuntu-desktop-session | grep fuse`: fuse-device
  connected (fuse-support absent).
- xdg-fuse-broker's own journal log shows the shim's mount request
  being serviced (`cmd=M ... mounted fuse filesystem`) — confirms the
  shim path is actually exercised, not bypassed.
- No new AppArmor DENIED entries for fuse/mount (remaining DENIED noise
  in the journal, e.g. PermissionStore dbus GetAll and gvfs
  MountTracker.ListMountableInfo, are pre-existing/unrelated — present
  identically before and after this change).
- `/proc/<portal-pid>/status`: CapPrm/CapEff both
  0000000000000000 — no capability leak.
