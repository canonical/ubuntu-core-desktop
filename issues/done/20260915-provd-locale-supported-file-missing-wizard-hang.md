# First-boot wizard hangs on "Next": provd can't find /usr/share/i18n/SUPPORTED

Date: 2026-09-15

## Impact / Priority

Clicking "Next" on the wizard's language page leaves a spinner running
forever with no error shown, so the first-boot wizard cannot be
completed past the locale page. No priority level was stated in the
original note; impact derived from the original note's described
symptoms.

Image: Ubuntu Core Desktop 26 amd64 dangerous (desktop26)

Status: Root cause confirmed. Not fixed.

## Context

Continuation of testing ubuntu-desktop-init.snap (rebuilt with core24
base, source path apps/ubuntu_init) on the desktop26 test VM. Wizard
now launches successfully (see
`20260915-ubuntu-desktop-init-missing-run-gnome-initial-setup-dir.md`
for the /run/gnome-initial-setup fix that got it this far). Selected a
language, clicked "Next" -> spinner appears and never resolves.

## Initial (wrong) hypothesis

Suspected this was the same confined-session AppArmor $HOME-path gap as
the Nautilus/Trash and xdg-desktop-portal-gnome bugs (see
`20260915-trash-nautilus-apparmor-denied-crash-loop.md`), since
xdg-desktop-portal-gnome was indeed observed crash-looping and timing
out D-Bus activations around the same time. That turned out to be a red
herring for *this specific* hang - real cause found below.

## Diagnosis

Using the netcat root shell (see
`20260915-ubuntu-desktop-init-missing-run-gnome-initial-setup-dir.md`
for why SSH was unavailable), inspected the ubuntu_init (Flutter)
process:

- Process was alive and idle (state S, blocked in poll()), not crashed.
- No new dbus-daemon activation timeouts were occurring during the
  hang itself (those had already fired earlier and were unrelated).
- Network connectivity from the VM was fine (nmcli reported
  "connected").

journalctl -b0 _PID=<ubuntu_init pid> showed the actual sequence:

    INFO locale: Selected en_US as UI language
    INFO locale: Set en_US as system locale
    ERROR ubuntu_init: Unhandled exception
            GrpcError: gRPC Error (code: 13, codeName: INTERNAL,
            message: failed to check if locale is supported: failed to open
            locale file: open /usr/share/i18n/SUPPORTED: no such file or
            directory, ...)

So: clicking Next sends a SetLocale gRPC call to provd (the Go backend
from ubuntu-desktop-provision), which succeeds, but a subsequent
locale-support validation call fails because provd tries to read
/usr/share/i18n/SUPPORTED from the local filesystem and that file does
not exist anywhere on this image:

- Not on the writable rootfs (/usr/share/i18n doesn't exist at all).
- Not in the core22 or core24 base snap (checked both
  /snap/core22/current/usr/share/i18n and /snap/core24/current/... -
  neither has it).

This file is normally shipped by the "locales" .deb package on classic
Debian/Ubuntu (part of glibc's locale data). Ubuntu Core has no dpkg/apt
at all and no equivalent package providing it - so this check can never
succeed on Ubuntu Core Desktop as currently built.

Confirmed the exact code responsible:

    canonical/ubuntu-desktop-provision, provd/internal/services/locale/locale.go
      const localeSupportedPath = "/usr/share/i18n/SUPPORTED"

The gRPC INTERNAL error is thrown as an "Unhandled exception" on the
Flutter side - ubuntu_init does not catch/display this error, so the UI
is just left showing the spinner forever with zero on-screen feedback.
This is a secondary bug in its own right (poor error handling / no
timeout / no fallback UI), independent of the missing file.

## Why this wasn't hit before now

This is the first time ubuntu-desktop-init has been run against Ubuntu
Core Desktop's actual base image in this environment (core24 base per
the snapcraft.yaml bump the user was testing); the app/provd stack was
presumably developed and tested against classic Ubuntu Desktop, where
/usr/share/i18n/SUPPORTED always exists via the locales package. Nobody
had exercised this particular gRPC call inside an Ubuntu Core Desktop
VM until now.

## Live workaround

None applied yet. Options to unblock live testing:

1. Create a minimal /usr/share/i18n/SUPPORTED file by hand (it just
   needs to contain "en_US.UTF-8 UTF-8" style lines - one per
   locale/charset - for provd's parser to consider the requested locale
   supported).
2. Bind-mount or copy a real SUPPORTED file from another Ubuntu system
   (e.g. the classic Ubuntu 24.04 desktop reference VM, which does have
   /usr/share/i18n/SUPPORTED via the locales package) onto
   /usr/share/i18n/SUPPORTED on desktop26.

Not yet tried on the live VM at the time of writing.

## Root cause / real fix options

This needs to be fixed in canonical/ubuntu-desktop-provision (provd),
not in this repo, since the hardcoded path assumes a classic
Debian/Ubuntu filesystem layout that doesn't exist on Ubuntu Core:

1. Ship a SUPPORTED-equivalent locale list as part of provd's own snap
   (e.g. bundle a static copy of /usr/share/i18n/SUPPORTED at build
   time, or generate the supported-locale list from `locale -a` /
   glibc-locales data already present via C.UTF-8 + whatever locales
   are actually built into the base snap).
2. Or have provd fall back gracefully (e.g. treat "file not found" as
   "assume supported" or skip the check entirely) rather than raising
   an unhandled gRPC INTERNAL error that the UI can't recover from.
3. Separately (defense in depth, in ubuntu_init): the Flutter UI should
   catch gRPC errors from provd and show a real error dialog instead of
   spinning forever with zero feedback - file as a UX bug against
   ubuntu-desktop-init regardless of which side ultimately owns the
   root fix.

Neither of these has been implemented yet; this file documents the
diagnosis only.

## Diagnostic method

journalctl -b0 --no-pager _PID=<pid> is very effective for pulling a
specific GUI process's full stdout/stderr history out of the journal
without needing to know its systemd unit name or journal tag in
advance - useful again here since ubuntu_init runs under a
dynamically-numbered gnome-initial-setup-N systemd scope each attempt.

## Validation

- [ ] Confirm creating /usr/share/i18n/SUPPORTED unblocks the wizard
      past the locale page (live test not yet done).
- [ ] File/fix upstream in canonical/ubuntu-desktop-provision (provd
      locale service) to not depend on a classic-desktop-only file
      path.
- [ ] File a UX bug against ubuntu_init for swallowing gRPC errors with
      no visible feedback.

## Resolution (2026-11-03)

DONE - via the image-side route, not the provd-side options listed
above. core-base-desktop's hook 002-initialize-locales.chroot now KEEPS
/usr/share/i18n/SUPPORTED when trimming the i18n tree, with a comment
citing this exact provd failure ("failed to open locale file: open
/usr/share/i18n/SUPPORTED"); the first-boot wizard works end-to-end on
the published dangerous images (locale page -> account creation ->
login). Leftover (upstream hygiene, still open): the separate
ubuntu_init UX bug - unhandled gRPC error leaves an infinite spinner
with no error dialog - was never filed against
canonical/ubuntu-desktop-provision.
