# GDM greeter needs "systemd" in /etc/nsswitch.conf (and a related theme bug)

Date: 2026-09-11

## Impact / Priority

A fresh image booted with no graphical login screen at all: gdm.service
showed "active (running)" but no gnome-shell/Xorg/Xwayland ever appeared
on seat0, so the image was unusable for login until fixed. A second bug
(missing gdm-theme.gresource) then crashed gnome-shell in the greeter,
producing the same no-greeter symptom.

Impact derived from the original note's symptoms.

## Symptom

Fresh 24.img boots, gdm.service shows "active (running)", but no gnome-shell/
Xorg/Xwayland ever appears on seat0 - no graphical login screen. `ps auxw`
shows only the `gdm3` daemon itself, nothing else.

Journal (`sudo journalctl -u gdm`) originally showed:

    Gdm: Failed to lock passwd database, ignoring: Read-only file system
    pam_unix(gdm-launch-environment:account): could not identify user
        (from getpwnam(gdm-greeter))

## Root cause

This gdm3 build (regular resolute/Ubuntu-26.04 archive package, NOT the
disabled desktop-snappers PPA mentioned near the top of snapcraft.yaml -
that PPA is explicitly not enabled here) auto-compiles with GNOME's
"HAVE_USERDB" feature whenever built against libsystemd >= 257
(see gdm's meson.build: `have_userdb = libsystemd_dep.version()
.version_compare('>= 257')`). Resolute ships systemd 259, so this is
just what any stock resolute gdm3 does now - it's not a packaging bug.

With HAVE_USERDB, gdm3 no longer needs (or uses) a real, pre-provisioned
"gdm-greeter" system account. Instead (daemon/gdm-dynamic-user-store.c),
it dynamically allocates a UID on the fly and advertises the account via
a systemd "userdb" varlink multiplexer socket it registers itself at
/run/systemd/userdb/org.gnome.DisplayManager. That socket is only ever
consulted by the `nss_systemd` NSS module - and it isn't wired into
/etc/nsswitch.conf by default, so classic NSS consumers like pam_unix's
getpwnam("gdm-greeter") (used by the gdm-launch-environment PAM service)
can't see it and fail outright, so the greeter's PAM session never opens.

Confirmed by reading the real gdm3 source on GNOME/gdm (GitHub mirror):
- daemon/gdm-display.c: gdm_launch_environment_ensure_uid() call and the
  "Failed to allocate UID for greeter" warning.
- daemon/gdm-dynamic-user-store.c: gdm_dynamic_user_store_create(),
  pick_uid()/pick_username() (this is where the "gdm-greeter",
  "gdm-greeter-2", ... naming and the GREETER_UID_MIN/MAX range come
  from), and the `lckpwdf()`-based passwd lock (source of the
  "Failed to lock passwd database, ignoring: Read-only file system"
  warning - that lock is just to serialize allocation against races
  with real /etc/passwd writes; it's expected to always fail/no-op on
  Ubuntu Core's read-only /etc, and gdm3 tolerates that fine).
- meson.build: have_userdb auto-detection based on libsystemd version.

Note this differs from a real (non-Core) Ubuntu Desktop resolute
install only in *how* nsswitch.conf gets updated: on a real Ubuntu
Desktop, gdm3's .deb postinst (or dependency chain) does this wiring
via normal `dpkg`/maintainer-script mechanisms. Our base is built with
chisel, which deliberately skips maintainer scripts, so nothing ever
replicated that one bit of the real .deb's postinst - hence the gap.

Regular headless Ubuntu Core does NOT have "systemd" in nsswitch.conf,
and that's correct for it - it doesn't ship gdm3 at all, so there's no
userdb multiplexer for nss_systemd to ever need to find. This is a
new requirement specific to bolting a modern (systemd>=257-linked) GDM
onto Core, not a deviation from Core's normal design.

## Fix applied (already committed to core-base-desktop)

Did NOT go with pre-creating a static "gdm-greeter" account (tried this
first - it "fixed" pam_unix's lookup, but gdm3's own dynamic allocator
doesn't check for an existing static account of the same name, so it
happily created a *second*, different-UID identity for the same
username via its varlink multiplexer, and whichever of the two the
XDG_RUNTIME_DIR/session code paths picked disagreed with whichever
pam_unix had opened the session for - actual observed symptom:
"XDG_RUNTIME_DIR /run/user/60578 is owned by uid 60578, not our uid 208").

Reverted that, and instead wired `nss_systemd` into nsswitch.conf so
there is a single, consistent source of truth (gdm3's own dynamic
allocation) for the whole system:

hooks/000-provide-uids-gids.chroot
  - reverted; no static gdm-greeter account.

hooks/002.1-add-gdm.chroot
  - comment only, pointing at 013 for the real nsswitch fix (order:
    002.1 runs before 013, so doing the sed here would just get
    partially re-mangled by 013's own later nsswitch edits).

hooks/013-setup-extrausers.chroot
  - after the existing extrausers sed lines, add:

        sed -i 's/^passwd:\(.*\)files/passwd:\1files systemd/' /etc/nsswitch.conf
        sed -i 's/^group:\(.*\)extrausers/group:\1extrausers systemd/' /etc/nsswitch.conf
        sed -i 's/^shadow:\(.*\)files/shadow:\1files systemd/' /etc/nsswitch.conf

  - passwd/shadow: "systemd" placed right after "files" (before
    "extrausers") - real accounts and Core's human users still take
    priority; only unresolved names (the dynamic greeter accounts)
    fall through to nss_systemd.
  - group: deliberately placed at the very END (after "extrausers"),
    NOT between "files" and "extrausers" - the existing
    "[SUCCESS=merge]" action modifier must stay immediately after
    "files" (it's what makes Core's supplementary/extrausers group
    merging work at all); inserting "systemd" there would have
    re-attached that modifier to "systemd" instead and broken group
    merging.

Result after rebuilding core.snap -> custom-core.snap -> 24.img and
booting: pam_unix now correctly resolves "gdm-greeter"/"gdm-greeter-2"/
etc. to the *same* dynamically-allocated UID gdm3 itself is using
(confirmed matching UIDs each retry, e.g. 60578, 60579, 60580, ...) -
the PAM session opens, and gnome-shell (--mode=gdm) actually starts,
initializes the GPU (/dev/dri/card1, virtio_gpu, atomic mode setting)
and gets as far as creating its Wayland/X11 displays. So this specific
bug (nsswitch/userdb) is fully fixed and confirmed.

## Second bug found and fixed: missing gdm-theme.gresource

gnome-shell was crashing immediately after starting, before it could
register the session with GDM, so GDM cycled through greeter attempts
and eventually gave up ("GdmLocalDisplayFactory: maximum number of
display failures reached"). Journal:

    gnome-shell[9536]: JS ERROR: Gio.IOErrorEnum: GLib.FileError:
      Failed to open file "/usr/share/gnome-shell/gdm-theme.gresource":
      open() failed: No such file or directory
    gnome-shell[9536]: Execution of main.js threw exception: Module
      resource:///org/gnome/shell/ui/init.js threw an exception
    gnome-shell[9536]: free(): invalid pointer
    audit: ANOM_ABEND ... pid=9536 comm="gnome-shell" sig=6 res=1
    systemd-coredump: Process 9536 (gnome-shell) ... terminated
      abnormally with signal 6/ABRT

Root cause (confirmed by fetching the real Ubuntu resolute gnome-shell
and yaru-theme sources with `apt-get source`):

- gnome-shell-common's own postinst registers
  /usr/share/gnome-shell/gdm-theme.gresource (and gdm-icons.gresource)
  as `update-alternatives` symlinks - see debian/gnome-shell-common
  .alternatives in the gnome-shell source package:

    Name: gdm-theme.gresource
    Link: /usr/share/gnome-shell/gdm-theme.gresource
    Alternative: /usr/share/gnome-shell/gnome-shell-theme.gresource
    Priority: 10

- yaru-theme-gnome-shell's postinst registers a *higher*-priority (15)
  alternative for the same name, pointing at the Yaru-themed variants
  instead - debian/yaru-theme-gnome-shell.alternatives:

    Name: gdm-theme.gresource
    Link: /usr/share/gnome-shell/gdm-theme.gresource
    Alternative: /usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource
    Priority: 15

  (and the same pattern for gdm-icons.gresource ->
  theme/Yaru/gnome-shell-icons.gresource).
- On a real .deb install, whichever package's postinst runs last with
  the highest priority wins, so gdm-theme.gresource ends up a symlink
  to the Yaru variant. Chisel never runs any package's postinst/
  maintainer scripts, so this symlink (and the underlying
  /etc/alternatives/gdm-theme.gresource indirection) is never created
  at all - hence gnome-shell's greeter-mode init.js can't open the
  file and aborts.
- /usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource and
  .../gnome-shell-icons.gresource *are* already staged in core.snap
  (from the yaru-theme-gnome-shell stage-package), so nothing extra
  needed to be added to snapcraft.yaml - only the missing symlinks.

Fix applied in hooks/002.1-add-gdm.chroot (right after the nsswitch/
HAVE_USERDB comment block):

    ln -sf theme/Yaru/gnome-shell-theme.gresource \
        /usr/share/gnome-shell/gdm-theme.gresource
    ln -sf theme/Yaru/gnome-shell-icons.gresource \
        /usr/share/gnome-shell/gdm-icons.gresource

Rebuilt core.snap -> custom-core.snap -> 24.img and booted fresh:
gnome-shell --mode=gdm now starts and stays running (no crash, no
coredump - `coredumpctl list` clean), and `loginctl list-sessions`
shows a session registered on seat0/tty1 with class "greeter":

    SESSION   UID USER        SEAT  LEADER CLASS         TTY  IDLE SINCE
          c1 60578 gdm-greeter seat0 9049   greeter       tty1 no   -

Both this bug and the nsswitch/HAVE_USERDB bug above are now fully
fixed and verified end-to-end: GDM boots to a working graphical
greeter session.

## On the externally-sourced "answer" provided

The pasted answer (unclear source) claimed Canonical prototyped
Ubuntu Core Desktop for core24 by baking libnss-systemd/systemd
nsswitch entries directly into an experimental core24 base snap at
compile time ("Base Snap Compile" method) - i.e. the same approach
this fix takes - and separately describing a snap `layouts:` bind-file
trick for *individual confined snaps* that need nss_systemd access to
query /run/systemd/userdb/* sockets, backed by an AppArmor abstraction
snapd ships for that purpose.

I could not independently verify the specific claim about an
experimental Canonical core24-desktop base snap doing this (no solid
citation found), and the answer's "NVD - NIST" citation is a red flag -
NIST's National Vulnerability Database has nothing to do with nsswitch/
AppArmor plumbing, suggesting at least part of that answer may be
AI-generated/unreliable rather than a real sourced reference. That
said, the "bake it into the base snap at compile time" approach it
describes is exactly what we ended up doing here independently (via
the chroot hooks), and it makes sense given our gdm3 runs as an
unconfined, base-snap-provided system service rather than as its own
confined snap - the `layouts:` bind-file trick doesn't actually apply
to our situation, since that only remaps files inside one confined
snap's own mount namespace, not the system-wide /etc/nsswitch.conf that
PID 1/pam_unix/every other process on the host reads.
