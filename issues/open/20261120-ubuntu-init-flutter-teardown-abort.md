# The wizard UI aborts (SIGABRT) at teardown, right after the handover

## Impact / Priority

Priority: Low (end-user impact not observed, but it fires at the most
sensitive moment of provisioning).

What a real user sees: nothing. On the full end-to-end first boot on
the test VM (installer run to completion, English UK, user
your_username created) the wizard finished its job, the account was
created, the handover ran, and the new user's desktop started. The
crash only shows up in the journal as a failed unit and a SIGABRT.

Why it is still worth fixing: it is an unhandled abort of the process
that owns the wizard UI at the exact moment it hands over to the new
user session. It can mask a real teardown bug, and we have no
backtrace (no coredump was produced), so we cannot rule out that on a
slower machine or a different teardown ordering it drops the last
write or leaves the wizard session wedged instead of exiting. The
provisioning itself had already completed before the abort.

Grounding: observed in a real first-boot run (not a synthetic caller),
at the handover; the desktop came up and the created user was intact,
so the user-facing impact today is nil. Reproduction requires a fresh
image and one wizard run (see Steps).

## Addendum 2026-11-23: the same fragility bites on the ERROR path too

During the PR core-base-desktop#92 wizard test (the test VM, nouser
image): when provd's CreateUser fails (there: SetAutomaticLogin denied
by the accountsservice snap's AppArmor profile — see
`20261123-accountsservice-snap-gdm3-apparmor-grants.md`), ubuntu_init
logs `ERROR ubuntu_init: Unhandled exception GrpcError ... failed to
set autologin` and the identity page then SPINS FOREVER — no error
page, no way forward except a hard reboot. Same root class as the
teardown abort: Flutter-side error handling in the wizard doesn't
surface failures. Fix shape: route provd gRPC errors to the wizard's
error page instead of letting them escape as unhandled exceptions.
(The orphan-user half of that failure is the rollback bug in
`20261123-provd-deleteuser-rollback-signature.md`.)

## Evidence (journal of the live run, VM clock GMT)

- 22:02:00.678 ubuntu_init: "identity: Saved identity" (provisioning
  essentially done; telemetry send failed at 22:02:05.620, unrelated).
- 22:02:01.206 provd writes the handover ini; the live read captures
  screen-reader-enabled=true.
- 22:02:05.755 the created user's systemd --user manager starts.
- 22:02:05.933863 sh[20736]:
    embedder.cc (2603): 'FlutterEngineRemoveView' returned
    'kInvalidArguments'. Remove view info was invalid. The implicit
    view cannot be removed.
  and on the same line:
    g_mutex_clear() called on uninitialised or locked mutex
- 22:02:05.944367 systemd-coredump: Process 20736 (ubuntu_init) of
  user 60578 terminated abnormally with signal 6/ABRT.
- 22:02:06.055188 systemd[18859]: gnome-initial-setup.service: Main
  process exited, code=dumped, status=6/ABRT; "Failed with result
  'core-dump'".
- coredumpctl info 20736: Storage: none, "terminated abnormally
  without generating a coredump" - so there is no backtrace.
- Process details: comm ubuntu_init, exe
  /snap/ubuntu-desktop-init/x1/bin/ubuntu_init, unit
  user@60578.service / gnome-initial-setup.service, subj=unconfined.

## Context / likely place

- ubuntu_init is the Flutter wizard UI, run as the Main process of the
  base's user unit
  core-base-desktop variants/desktop/static/usr/lib/systemd/user/
  gnome-initial-setup.service (ExecStart execs the init snap's
  ubuntu_init after provd's gRPC socket appears; ExecStopPost runs
  gnome-session-ctl --shutdown).
- The two messages point at teardown ordering in the Flutter Linux
  embedder/GTK view layer: removing the "implicit view" is rejected by
  the engine ("The implicit view cannot be removed"), and
  g_mutex_clear() on an uninitialised/locked mutex suggests a second
  teardown or teardown while GLib is still dispatching. The app is
  closing its window/engine as the session is switching to the new
  user.
- Not the dconf migration: the unrelated "No DConf source to write to"
  exceptions happened a minute earlier (22:01:00) and are fixed in
  core-base 4fad222. The abort is at the handover instant.

## Steps

1. Reproduce on a fresh image: boot, run the installer to completion,
   then `journalctl -b0 | grep -E "FlutterEngineRemoveView|
   g_mutex_clear|code=dumped"`.
2. Get a backtrace: coredump storage was "none" on the test image.
   Check /proc/sys/kernel/core_pattern and
   /etc/systemd/coredump.conf (Storage=), temporarily enable a
   coredump for the wizard unit (drop-in), rerun, and read
   `coredumpctl info`.
3. Read the app's shutdown path in ubuntu-desktop-provision
   (apps/ubuntu_init, Flutter): where the window is destroyed and the
   engine disposed; look for the GTK embedder's view removal and for
   any explicit engine shutdown racing GTK/GLib teardown.
4. Check the Flutter engine version pinned by the ubuntu-desktop-init
   snap and whether a newer engine/embedder fixes the implicit-view
   teardown assert.
5. Decide the fix: correct the teardown order (or let the process
   exit rather than tearing the view down explicitly), or, if the
   crash is upstream and genuinely harmless, make the intent explicit
   and keep it quiet (do not just silence a failure blindly).
6. A/B against the pre-dconf image if one is available, to record
   whether this predates the dconf line (expected: yes, it is app-side
   teardown, not settings).

## Related

- `20261120-first-boot-session-startup-errors.md` (same live run:
  boot seeding delay, handover path storm, content-data lock stall,
  DCONF_PROFILE exceptions).
- The same run also showed gsd-media-keys
  "g_hash_table_size: assertion 'hash_table != NULL' failed" at
  teardown; check whether that shares a teardown-ordering cause.
