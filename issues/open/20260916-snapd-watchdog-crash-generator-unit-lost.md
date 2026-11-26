# snapd.service watchdog death loses its unit definition until manual recovery

Status: Recovered live on test VM. Root cause of the watchdog hang itself
NOT diagnosed (no journal logging showed why it deadlocked). The
secondary bug - snapd-generator failing to regenerate the unit after the
crash - is understood but not fixed at the source.

## Impact / Priority

High. After snapd died, App Center and every snap launch (clicking App
Center or Files did nothing) stayed broken until the unit files were
manually recreated; nothing recovered on its own despite
Restart=always.

Impact derived from the original note's symptoms.

## Context

During the same desktop26 test VM wizard-testing session as the other
20260916 work items, after successfully completing the first-boot
wizard and logging in as the new user, the desktop came up but clicking
App Center or Files did nothing.

## Diagnosis

1. snapd.service had crashed roughly an hour earlier in the session
   (timestamps suggest it happened around the time of the earlier /etc
   and /usr/sbin overlay-mount live-patching work, though no direct
   causal link was established):

    systemd[1]: snapd.service: Main process exited, code=exited,
                status=2/INVALIDARGUMENT
    systemd[1]: snapd.service: Failed with result 'watchdog'.

   snapd's own goroutine dump at crash time showed several goroutines
   blocked for 32 minutes (udev monitor select loop, dbus conn reader,
   etc.) - i.e. snapd deadlocked/hung badly enough that it stopped
   pinging systemd's watchdog (WatchdogSec=5m) and got killed. The
   *reason* for the deadlock itself was not identified from the
   available goroutine dump - this needs further investigation if it
   recurs (e.g. check for udev netlink socket issues, or contention
   introduced by concurrent mount/overlay changes happening on the host
   at the same time).

2. Despite snapd.service's unit having Restart=always, it did NOT come
   back on its own. `systemctl status snapd.service` showed:

    Loaded: not-found (Reason: Unit snapd.service not found.)
    Active: failed (Result: watchdog)

   i.e. systemd had *lost track of the unit definition entirely* - not
   just "failed and rate-limited", but "unit not found" as if it had
   never been loaded. Same for snapd.socket.

3. On Ubuntu Core, snapd.service/snapd.socket are not shipped as static
   unit files under /etc or /usr/lib/systemd/system - they only exist
   via /usr/lib/systemd/system-generators/snapd-generator, which is
   supposed to generate (copy/symlink) them into
   /run/systemd/generator/ from whichever revision of the snapd snap is
   currently active (/snap/snapd/current, here resolved to
   /snap/snapd/x1). Confirmed /run/systemd/generator/ still had
   var-lib-snapd.mount and friends, but NOT snapd.service/snapd.socket.

   Running the generator manually (as root, with fresh scratch
   directories, exactly as systemd would invoke it) produced NO output
   at all - it silently declined to generate anything, for reasons not
   fully understood (its internal logic for deciding whether/what to
   generate was not traced further - this warrants a proper look at
   canonical/snapd's cmd/snapd-generator source if this recurs).

## Recovery (live workaround applied this session)

Since /snap/snapd/x1/lib/systemd/system/snapd.service and snapd.socket
are valid, complete unit files in their own right, copied them directly
into /etc/systemd/system/ (a normal, non-generated location) and enabled
them there:

    cp /snap/snapd/x1/lib/systemd/system/snapd.service /etc/systemd/system/
    cp /snap/snapd/x1/lib/systemd/system/snapd.socket  /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable snapd.socket snapd.service
    systemctl start snapd.service

This brought snapd back up successfully and `snap list` / App Center /
Files all started working again immediately.

NOTE: this bypasses the generator rather than fixing why it failed to
regenerate the units after the crash. If snapd crashes again on a real
device (not just this test VM), the *generator itself* not regenerating
snapd.service/socket after a crash+lost-unit event would leave the
whole snap ecosystem (and thus App Center, Firefox, every snap-packaged
app) permanently broken until someone manually recreates the unit files
as done here - this seems like a significant reliability gap for a
snap-based desktop.

## Next steps

- Investigate why snapd deadlocked in the first place (the specific
  goroutine dump/backtrace is preserved in the journal excerpts from
  this investigation if needed again - worth a closer read of the udev
  netlink / dbus conn related goroutines that were stuck for 32
  minutes).
- Investigate why /usr/lib/systemd/system-generators/snapd-generator
  produced no output when run manually post-crash - under what
  conditions does it decide not to (re)generate snapd.service/socket?
  This looks like it could strand a device with snaps permanently
  inaccessible after any snapd crash, which would be a serious
  reliability bug for Ubuntu Core Desktop.
- Consider whether snapd.service should ship as a normal static unit
  (as done here for recovery) rather than solely via the generator, or
  whether the generator needs hardening to always regenerate on
  daemon-reload/boot regardless of prior crash state.
