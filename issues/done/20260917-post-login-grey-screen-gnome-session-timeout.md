# Intermittent grey screen after password entry on the Core 26 VM

Date: 2026-09-17

## Impact / Priority

After typing the password at the GDM greeter and hitting enter, the
screen intermittently goes grey instead of showing the desktop:
`gnome-session-manager@ubuntu.service` never becomes ready, times out
after 90s, and gnome-shell for the user session never starts. No
priority level was stated in the original note; impact derived from the
original note's described symptoms.

Status: reproduced and root cause NARROWED (not yet fully
diagnosed/fixed).

## Context

User reported: on the Core 26 test VM, after typing the password at the
GDM greeter and hitting enter, the screen intermittently goes grey
instead of showing the desktop. Reported as intermittent - the previous
VM run logged in fine.

Initial live diagnosis (this session, VM freshly booted ~08:23 UTC,
your_username logged in at 08:23:33, grey screen observed):

- `loginctl list-sessions` showed your_username's session (tty2, seat0)
  present, systemd --user (`user@1000.service`) running, but NO
  gnome-shell process for your_username at all (only the gdm-greeter's
  own `gnome-shell --mode=gdm` on tty1 was running).
- `systemctl --user status org.gnome.Shell@ubuntu.service` -> inactive
  (dead).
- `systemctl --user status gnome-session-manager@ubuntu.service` ->
  inactive (dead), with in its journal:

      08:23:34 gnome-session-service[8723]: unable to create file
        '/run/user/1000/dconf/user': Permission denied. dconf will not
        work properly.  (repeated ~7x)
      08:23:34 gnome-session-service[8723]: GsmSessionSave: Failed to
        ensure state dir exists: Permission denied
      08:23:34 dbus-daemon[8665]: apparmor="DENIED"
        operation="dbus_method_call" bus="session"
        path="/org/gtk/vfs/Daemon" member="ListMonitorImplementations"
        label="snap.ubuntu-desktop-session.ubuntu-desktop-session//&unconfined"
        peer_label="unconfined"
      (~90s later, i.e. after gnome-session's StartupTimeoutSec expired)
      08:25:04 systemd[8592]: gnome-session-manager@ubuntu.service: start
        operation timed out. Terminating.
      08:25:04 dbus-daemon[8665]: apparmor="DENIED" ... member="RemoveMatch"/
        "ReleaseName" on org.freedesktop.DBus itself, same
        snap.ubuntu-desktop-session...//&unconfined label
      08:25:04 gnome-session-service[8723]: Error releasing name
        org.gnome.SessionManager: GDBus.Error:
        org.freedesktop.DBus.Error.FileNotFound: Failed to query AppArmor
        policy: No such file or directory
      08:25:04 systemd[8592]: gnome-session-manager@ubuntu.service: Failed
        with result 'timeout'.
      08:25:04 systemd[8592]: ... Triggering OnFailure= dependencies.

  After this, the unit stayed dead (no automatic successful retry seen
  in this session) - matches the grey screen the user described.
- By the time of inspection, `/run/user/1000/dconf/user` DID exist with
  correct your_username:your_username 0700 ownership - so whatever
  blocked the write at 08:23:34 was a transient/race condition, not a
  permanent misconfig. This fits "intermittent" / "worked last time".
- `gnome-session-service[8723]` (the confined process driving the
  ubuntu session) also logged "Couldn't get type for session '3'/'2':
  Permission denied" and several "X-GNOME-Autostart-Phase, but
  gnome-session no longer manages session services" notices - may or
  may not be related, worth ruling in/out.

## Working hypotheses (NOT yet confirmed)

1. Race at session start between systemd/pam_systemd creating
   /run/user/1000 (and dconf creating its own subdir/file inside it)
   and gnome-session-service (running as the confined
   snap.ubuntu-desktop-session label) trying to write
   /run/user/1000/dconf/user before permissions/ownership have
   settled, OR before some AppArmor rule/mount is in place yet -
   intermittent depending on scheduling. Check dconf's own source/
   systemd unit ordering for what's supposed to guarantee this
   directory exists+is writable before gnome-session starts.
2. The AppArmor D-Bus denials (`org.gtk.vfs.Daemon`
   ListMonitorImplementations, and later `org.freedesktop.DBus`
   RemoveMatch/ReleaseName against the bus daemon itself under the
   stacked `//&unconfined` label - see
   `20260916-confine-gnome-session-user-units.md` for background on
   this confinement work and the `**` AARE wildcard gotcha for stacked
   labels) may be what actually causes
   gnome-session-service to hang for the full 90s StartupTimeoutSec
   instead of completing its startup handshake - i.e. this might be the
   real root cause with the dconf errors being a secondary/unrelated
   symptom logged around the same time. Don't assume causation between
   the two without checking gnome-session-service's actual code path
   (what does it block on during startup, and does that path go through
   the D-Bus calls that are being denied?).
3. Since this is intermittent (previous boot logged in fine), check
   whether it correlates with boot-to-login timing (e.g. some
   dependency service like dbus/gvfs/dconf still initializing when the
   password is entered quickly) rather than being deterministic on
   every boot.

## Suggested investigation approach

- Reproduce multiple times (reboot VM / restart gdm + login cycles) to
  get both a failing and succeeding case, and diff the journals
  precisely (timestamps, ordering of dconf/dbus/apparmor lines) between
  the two to find the actual differentiator.
- Check `/etc/systemd/user/org.gnome.Shell@ubuntu.service.d/99-confine.conf`
  and `gnome-session-manager@ubuntu.service.d/99-confine.conf` (added
  per the confinement work, see
  `20260916-confine-gnome-session-user-units.md`) plus the AppArmor
  profiles in `ubuntu-core-desktop-snapd`
  (`interfaces/builtin/desktop_launch.go`,
  `interfaces/builtin/systemd_user_control.go`,
  `interfaces/builtin/login_session_observe.go`) for whether
  `org.gtk.vfs.Daemon` and bus-daemon-self (RemoveMatch/ReleaseName/etc)
  D-Bus calls are covered by existing rules, and whether the `**`
  wildcard gotcha applies to any relevant rule.
- Determine what `gnome-session-service` actually does during the ~90s
  it hangs before hitting StartupTimeoutSec (put the profile in
  complain mode temporarily per the documented complain-mode technique
  to see the full gap list of would-be denials in one pass, rather than
  fixing one denial at a time).
- Check dconf/pam_systemd unit ordering guarantees for
  /run/user/<uid>/dconf creation vs. gnome-session-manager@.service
  start, and whether anything here is new/changed vs. the already-fixed
  confinement work, or is an independent gap.
- Follow the established diagnostics methodology and the reusable
  confined-session techniques (this is the same confined-session area)
  rather than re-deriving those from scratch.
- Write up findings (and a fix, if a safe one is identified) in this
  issue file, and move it to `done/` once resolved - but if only
  investigated/not fixed, update this file in place with findings and
  leave it open for the next round, per existing practice in this
  project.

## Resolution

Root cause confirmed: the confined gnome-session-service was denied
AppArmor write access to the systemd --user notification socket:

    apparmor="DENIED" operation="sendmsg"
    name="/run/user/1000/systemd/notify"
    pid=8723 comm="gnome-session-s"

The service is `Type=notify`.  Its `sd_notify(READY=1)` therefore
failed, so `gnome-session-manager@ubuntu.service` never became ready
and systemd waited for its 90-second StartupTimeoutSec.  The later
RemoveMatch/ReleaseName D-Bus denials were shutdown cleanup after that
timeout, not the cause.  The `org.gtk.vfs.Daemon ListMonitorImplementations`
denials and the dconf errors also occur in successful sessions and are
not sufficient causes.  The failing boot additionally showed denied
reads of `/run/systemd/sessions/2` and `/run/systemd/sessions/3`; those
explain the concurrent logind "Couldn't get type" messages and were
another missing observation rule in the stale loaded profile.

Evidence:

- The retained failing boot (`journalctl -b -11`) shows the
  notify-socket denial immediately after the confined process starts,
  followed by no service-ready event and the 08:25:04 timeout.
- The same boot has AppArmor `open` denials for
  `/run/systemd/sessions/{2,3}`.  The dconf and gvfs denials are
  present but non-fatal; the process reaches the timeout because its
  readiness notification is denied.
- A successful boot (`journalctl -b 0`) still logs the gvfs denial and
  the `.local/state` mkdir/dconf state warning, but also logs
  `Started gnome-session-manager@ubuntu.service` and `Entering running
  state` within about one second.
- Five GDM restart/login cycles and ten clean/early-boot reboot cycles
  after the corrected policy loaded all reached an active
  `gnome-session-manager@ubuntu.service` and running confined
  `gnome-shell`.

Fix:

This was already fixed by `ubuntu-core-desktop-snapd` commit
`9e2a5148db` (`interfaces: confine gnome-session AppArmorProfile=
units`).  Its `systemd-user-control` policy grants write access to
`/run/user/[0-9]*/systemd/notify` and read access to the gnome-session
dconf/state paths; its `login-session-observe` policy covers systemd
session observation.  The deployed profile contains both
`"/run/user/[0-9]*/systemd/notify" w,` and
`/run/systemd/sessions/*[0-9] rk,`.  No additional code change was
needed.  The targeted Go test could not run because this checkout has
inconsistent vendoring (`go.mod` and `vendor/modules.txt` disagree);
the existing commit is clean (`git show --check`).

The VM was restored after testing: the temporary gnome-session shim was
unmounted, automatic login was disabled again, and the normal greeter
configuration is in place.  This item is complete.
