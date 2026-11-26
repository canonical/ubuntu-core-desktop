# Fix GDM/nsswitch "systemd" requirement without forking the core26 base

## Impact / Priority

No current user impact: the original GDM greeter bug is already fixed
by patching nsswitch.conf in our chroot hooks. This is a follow-up
design question so a future switch to the stock upstream core26 base
does not reintroduce a broken greeter session. Impact derived from the
original note's described symptoms.

## Background

See `20260911-fix-gdm-needs-systemd-in-_etc_nsswitch.conf.md` for the
full root-cause writeup: stock resolute/Ubuntu-26.04 gdm3 auto-enables
HAVE_USERDB against libsystemd >= 257 and relies on nss_systemd (via
gdm's dynamic-user-store varlink socket) to resolve the "gdm-greeter"
account. Real Ubuntu Desktop .debs wire "systemd" into
/etc/nsswitch.conf via postinst maintainer scripts; our chisel-based
core-base-desktop build skips maintainer scripts, so that wiring never
happens - hence pam_unix's getpwnam("gdm-greeter") fails and gdm never
gets a working greeter session.

That issue has *already been fixed* by patching nsswitch.conf inside
our own chroot hooks (hooks/013-setup-extrausers.chroot) as part of
building our custom core snap. This issue is about a *different*
question raised afterwards:

    If we ever want to switch to the unmodified, upstream Canonical
    core26 base snap (i.e. stop maintaining our own chisel-built base),
    is there any way to still get "systemd" wired into
    /etc/nsswitch.conf, given that file lives inside the base snap's
    read-only squashfs and isn't part of any writable-paths overlay?

## Goal

Determine (and, if promising, prototype) a supported, non-base-snap-fork
mechanism to get nss_systemd wired in ahead of gdm.service starting, so
that a future switch to a fully-stock upstream core26 base remains
possible without reintroducing this bug.

## Candidate approaches to evaluate (in priority order)

1. `system-files` interface, `write: true`, plug targeting
   /etc/nsswitch.conf. Ship a corrected nsswitch.conf inside a small
   snap (or the gdm-providing snap itself); on connect, snapd
   bind-mounts it over the real path. Need to check:
   - Does this require store-side auto-connect approval, or can a
     manual `snap connect` be done at image-build/seeding time?
   - Timing: is the bind-mount established early enough (i.e. before
     gdm.service's first getpwnam) during boot?

2. `mount-control` interface - more general/newer mechanism, snap's own
   oneshot systemd unit does an explicit `mount --bind` of its own file
   onto the host path. Gives explicit control over unit ordering
   (Before=gdm.service, WantedBy=sysinit.target) to guarantee it lands
   before GDM needs it. More setup than (1) but more control.

3. Confirm whether core26's own writable-paths list (baked into the
   base snap, consulted by snap-bootstrap/initramfs to decide what gets
   overlaid from ubuntu-data vs served read-only from squashfs) happens
   to already include /etc/nsswitch.conf for some unrelated reason - if
   so, a first-boot/gadget script could edit it directly without any
   interface plumbing at all. (Believed unlikely, but cheap to check by
   inspecting the stock core26 snap's writable-paths definition.)

Not viable, ruled out already (see prior investigation):
- gadget.yaml `defaults`/`write-files` - can't touch base-snap-owned
  system paths.
- Per-snap `configure` hooks - run inside snap confinement, can't
  write arbitrary host /etc files.
- Pre-creating a static gdm-greeter account instead of nsswitch wiring
  - already tried and reverted (dual-identity UID mismatch bug, see
  `20260911-fix-gdm-needs-systemd-in-_etc_nsswitch.conf.md` for
  details). Don't repeat this dead end.

## Suggested next steps

- [ ] Pull down the actual unmodified core26 base snap and inspect its
      writable-paths definition to settle approach (3) definitively.
- [ ] Prototype approach (1) (system-files interface) in a throwaway
      snap against a stock core26 image; confirm bind-mount timing
      relative to gdm.service.
- [ ] If (1) proves too late/unreliable, prototype approach (2)
      (mount-control + explicit oneshot ordering).
- [ ] Document findings and, if a working approach is found, decide
      whether to actually pursue dropping the chisel-built base in
      favor of it, or just keep this as a validated fallback option.

## Status

Investigation only so far. Nothing implemented yet - no code/hook
changes needed unless/until we decide to pursue this.
