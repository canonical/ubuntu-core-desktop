# First GDM greeter session exits and is replaced during Core Desktop 26 boot

Date: 2026-09-15

## Impact / Priority

Boot initially reached a command-line login prompt, and the graphical
login screen only appeared after GDM stopped and started again: the
first greeter session failed or exited and GDM launched a replacement
greeter session, so the user could be left at a text console while the
greeter retry was occurring. The GDM daemon itself did not restart
(NRestarts=0).

Impact derived from the original note's symptoms.

Image: Ubuntu Core Desktop 26 amd64 dangerous

## Summary

On the rebuilt Core Desktop 26 VM, boot initially displayed a command-line
login prompt. GDM then appeared to stop and start again, after which the
graphical login screen returned. The GDM daemon did not actually restart:
systemd recorded one successful gdm.service start and NRestarts=0. The first
greeter session failed or exited, and GDM launched a replacement greeter
session.

## Observed sequence

The system journal showed:

1. gdm.service started at 19:35:13 UTC.
2. GDM created the gdm-greeter Wayland session and started GNOME Shell.
3. The first greeter session closed at 19:35:18.
4. GDM created gdm-greeter-2 and started GNOME Shell again.
5. The second greeter registered its display successfully.
6. graphical.target was reached at 19:35:46.

Relevant evidence:

    gdm.service: Active: active (running)
    NRestarts=0
    Failed to lock passwd database, ignoring: Read-only file system
    pam_unix(...): session closed for user gdm-greeter
    New session 'c2' of user 'gdm-greeter-2'

The visible symptom is therefore a delayed/repeated greeter startup, not a
GDM service crash. It is still a boot-time bug because the user can be left
at a text console while the greeter retry is occurring.

## Related errors

The first greeter logged:

    Gdm: Failed to lock passwd database, ignoring: Read-only file system

The read-only root is expected for Core, so GDM must not require a writable
passwd database in its greeter startup path. The image provides writable
system-data paths, but the greeter's passwd/group state and any lock files
must be read from or created in the writable location expected by GDM and
PAM.

The journal also contained repeated snap-confine AppArmor denials while
opening:

    /run/gdm3/

These denials predate this test and may contribute to greeter/session
startup instability. They must be checked against the intended confined
desktop-session and GDM policy rather than ignored as harmless noise.

## Likely root cause

The first greeter environment is not fully compatible with the read-only
Core root and confined desktop session. GDM starts successfully, but the
initial greeter session cannot complete all of its setup, exits, and is
replaced by a second greeter session. The precise fatal operation is not
yet isolated because the system journal shows the read-only passwd warning
and AppArmor denials, but no gdm.service failure.

## Required fix

Make the first greeter session start cleanly without relying on a writable
root filesystem:

* Ensure GDM, PAM, and the greeter accounts use the writable system-data
  locations supplied by Core, including passwd/group lock and state files.
* Ensure the GDM runtime directory and its required contents under
  /run/gdm3 are accessible to the greeter and the confined
  ubuntu-desktop-session without broadening policy unnecessarily.
* Add the required narrow snapd/AppArmor rules or desktop-session interface
  connections for the documented /run/gdm3 access.
* Preserve the existing read-only-root design; do not make the Core root
  writable as a workaround.

## Resolution

The remaining boot-time failure was caused by console-conf claiming
/dev/tty1 concurrently with GDM.  Its state-completion marker was hidden by
the mounted /var/lib/console-conf directory, so console-conf@tty1.service
still started and its tty reset coincided with the first greeter teardown.
The base image now masks both console-conf@.service and getty@tty1.service
in hooks/005.1-mask-gdm-getty.chroot.

The earlier confined-session failures were separately fixed by skipping the
incompatible screencast and IBus portal services in GDM sessions.  The
resulting base commits are 5f25b15 and de00051.

## Validation

After each image change:

1. Rebuild the image with the image build (`build.sh`).
2. Boot the image in the test VM.
3. Confirm the graphical greeter appears on the first attempt without a
   text-console interval.
4. Verify gdm.service has NRestarts=0 and only one greeter session is
   created during boot.
5. Check journalctl -b for the read-only passwd warning and /run/gdm3
   AppArmor denials.
6. Log into the confined desktop and verify App Center still launches and
   Firefox installation remains functional.

Do not treat the current recovery to gdm-greeter-2 as a fix. It only masks
the first-session failure and makes boot behavior timing-dependent.
