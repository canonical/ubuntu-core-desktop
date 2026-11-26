# Clicking a snap desktop icon can trigger a runaway desktop-launch retry storm

## Impact / Priority

High. A real end user who clicks a desktop icon (e.g. the App Store /
snap-store icon) can trigger dozens of new transient systemd units per
second, climbing system load (observed 0.4 -> 2.8+ within 1-2 minutes)
and eventually making the session unusable. This was reproduced on a
clean boot, on the very first click, with no prior manual intervention,
and fires whether or not the underlying app launch itself succeeds or
fails. Killing individual PIDs (including the `snap userd` process
itself) does not stop it — D-Bus immediately respawns `snap userd` and
it resumes churning. The only reliable mitigation found so far is
killing the entire user session cgroup (forced logout) or a full VM
reboot. This is a much more severe, user-visible failure than "the app
is slow to start" — it can make the whole desktop session unresponsive.

## Reproduction

VM: the core-desktop test VM (freshly built GNOME image).

1. Fresh boot, autologin to desktop.
2. Click the App Store (snap-store) desktop icon once.
3. Watch `journalctl -f` or `top`/load average: within a few seconds,
   `Started run-p....service - /usr/bin/snap routine desktop-launch ...`
   lines start appearing at a rate of roughly 25-54 per second,
   continuously (not obviously exponential — looks closer to a
   steady/linear rate once started), and do not stop on their own.
4. Reproduced identically across at least 3 separate clean-boot
   attempts.
5. Confirmed independent of the XAUTHORITY/XDG_RUNTIME_DIR env leak
   bug: on the run where the storm was captured and analysed, there
   were zero "failed to launch ... exit status 1" errors in the journal
   window before the storm was killed, meaning the underlying
   privileged launch call was actually succeeding each time, yet the
   storm still occurred.

## What is ruled out

- `snap routine desktop-launch` (the confined client invoked by
  gnome-shell) makes a single, non-looping D-Bus call to
  `io.snapcraft.PrivilegedDesktopLauncher.OpenDesktopEntry2` and
  returns. See
  ubuntu-core-desktop-snapd/cmd/snap/cmd_desktop_launch.go — no retry
  loop there.
- Not caused by manual test intervention: reproduced on a clean single
  click with no PID-killing or other meddling beforehand.

## Suspected origin (not yet confirmed)

Not investigated in depth per explicit instruction to not spend time on
this right now. The most likely suspect is gnome-shell's own
app-activation / icon-click handling in the confined
ubuntu-desktop-session snap re-issuing the launch request in a tight
loop (e.g. because it doesn't see the expected window appear within
some short timeout and retries), but this has not been confirmed by
reading gnome-shell source or capturing a stack/strace of the retrying
caller. `snap userd`'s handler
(ubuntu-core-desktop-snapd/usersession/userd/privileged_desktop_launcher.go)
has been identified as the next file to read if/when this is
root-caused, but has not yet been read in detail.

## Mitigation used during other investigation (not a fix)

A watchdog script was deployed to the VM at /root/storm-watchdog.sh
(not part of any git repo — VM-local only, will not survive a rebuild):
it polls `journalctl -S "-1s"` every 0.3s for >=10 "Started
run-p...desktop-launch" events in the last second, and on detection
does:

    echo 1 > /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/cgroup.kill

This atomically SIGKILLs every process in the user's session cgroup
(equivalent to an instant forced logout) in about 1-2 seconds, and GDM
returns to the greeter afterward. This was found to be dramatically
more reliable than `pkill -f <pattern>` in a tight loop (which could
not keep up with the spawn rate) and much faster than a full VM
`systemctl reboot`. This is purely an operational safety net for
continued testing, not a fix, and is not committed anywhere.

## Next steps

1. Identify the actual caller that re-issues the desktop-launch request
   repeatedly — capture a stack trace / strace of gnome-shell (or
   whatever confined process is re-triggering it) at the moment the
   storm starts, or add temporary logging to
   privileged_desktop_launcher.go to log caller PID/times for every
   OpenDesktopEntry(2) call.
2. Determine whether the retry is time-based (e.g. some short "did the
   app show a window yet" timeout in gnome-shell's app-system code) or
   event-based (e.g. re-triggered by some D-Bus signal each activation
   emits).
3. Once the origin is confirmed, fix at the source (e.g. add a
   debounce/backoff, or fix whatever condition gnome-shell is
   incorrectly treating as "the previous launch failed, try again").
4. Consider, independently of the root cause, whether
   `io.snapcraft.Launcher`/`snap userd` or the desktop-launch path
   should have its own rate-limiting as defense in depth, given how
   easily this can be triggered by a single user click.

## Resolution (established in later work; note appended on import)

The suspected origin was never root-caused, but the storm is not
reproduced on current images: the icon-click launch path was
rewritten since (the XDG_RUNTIME_DIR/XAUTHORITY leak fix and the
session environment broker — see
`20260926-xwayland-xauthority-private-runtime-dir.md` and
`20260927-gnome-session-service-environment-broker.md`), and the
later broker work's validation gate ("real cold App Center icon
click shows the window in <=2 seconds, no retry storm") passed. The
rate-limiting defense-in-depth idea below was never implemented; if
the storm ever reappears, the investigation recipe in this file
still applies.
