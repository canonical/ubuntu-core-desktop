# Autologin+gnome-session-shim technique doesn't work — find out why and fix it

Date: 2026-09-17

## Impact / Priority

Attempts to automate repeated confined-session logins with the
documented autologin+shim technique produced an instant "Session never
registered" fallback to the greeter on every cycle, so the technique
appeared unusable for automated testing (the resolution below shows it
actually works; one unexplained one-off failure could not be
reproduced). No priority level was stated in the original note; impact
derived from the original note's described symptoms.

## Context

A documented reusable technique verifies the confined GNOME session
end-to-end without VNC or keyboard/GUI input: bind-mount a shim script
over `/usr/bin/gnome-session` that execs the real confined-session
wrapper only for a specific user, combined with GDM autologin
(`AutomaticLoginEnable`/`AutomaticLogin` under `[daemon]` in
`/etc/writable/gdm3/custom.conf`) so the session starts without typing
a password.

Followed those documented steps exactly on the Core 26 test VM to
automate multiple login cycles for investigating an intermittent
grey-screen bug:

1. Backed up `/usr/bin/gnome-session` to `/tmp/gnome-session.real`.
2. Wrote a shim script that execs
   `core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME`
   for user `your_username`, else execs the real binary.
3. `sudo mount --bind` the shim over `/usr/bin/gnome-session`.
4. Set `AutomaticLoginEnable = true` and `AutomaticLogin =
   your_username` under `[daemon]` in `/etc/writable/gdm3/custom.conf`
   (verified with `grep -A5 '\[daemon\]'` that both landed under the
   right section).
5. `sudo systemctl restart gdm` to trigger the autologin.

Result: it did NOT work. GDM logs showed the autologin PAM session
opening and then closing again within ~20-100ms, before a real session
was ever registered:

    gdm-autologin][NNNNN]: gkr-pam: no password is available for user
    gdm-autologin][NNNNN]: pam_unix(gdm-autologin:session): session opened
      for user your_username(uid=1000) by your_username(uid=0)
    gdm-autologin][NNNNN]: gkr-pam: gnome-keyring-daemon started properly
    gdm-autologin][NNNNN]: pam_unix(gdm-autologin:session): session closed
      for user your_username
    gdm3[NNNNN]: Gdm: GdmDisplay: Session never registered, failing
    gdm3[NNNNN]: Gdm: Failed to lock passwd database, ignoring: Read-only
      file system

This repeated on 10/10 `systemctl restart gdm` cycles -
`gnome-session-manager@ubuntu.service` never even started (stayed
`inactive`), because the autologin session itself never got far enough
to launch it. This is a different failure than anything the shim/
autologin technique was meant to test - the technique itself is
apparently broken on this image/build, not exercising the intended
confined-session startup path at all.

(All changes were cleanly reverted afterward: shim unmounted, autologin
config lines commented back out, gdm restarted back to a normal
password-prompt greeter - confirmed working via `loginctl
list-sessions` afterward.)

## Goal

Find out why the documented autologin+shim technique fails on this
build/image (root cause of the near-instant "session closed" /
"Session never registered, failing"), fix it if practical, and update
the documented technique (or wherever it is written down) so it
reflects however this needs to actually be done - or clearly flag it as
broken/needing different steps if it turns out to be genuinely not
usable on current Core 26 images.

## Suggested investigation approach

- Reproduce again and capture the FULL gdm/session journal for one
  cycle (not just the summary lines above) - include gdm-autologin's
  own more verbose output if available, and anything logged by
  `gdm-launch-environment`/`Xorg`/`Wayland` compositor startup during
  that ~20-100ms window, to see what actually causes the PAM session to
  close so quickly.
- Check `"Gdm: Failed to lock passwd database, ignoring: Read-only file
  system"` - this looks like it could be a real, unrelated symptom of
  running on this image's writable-overlay setup (see the project
  documentation's notes on writable-overlay gotchas) and may be worth
  ruling in/out as the actual cause (e.g. if GDM's autologin path tries
  to update/lock `/etc/passwd`-equivalent state as part of registering
  the session, and that fails hard here because accounts live in
  `/var/lib/extrausers/` instead - see the project documentation's
  extrausers section).
- Check whether autologin ever worked on any prior Core 26 image/build
  (grep boot logs / other notes), or whether this technique was only
  ever validated in an earlier, differently-configured image and has
  silently bit-rotted.
- Once root-caused, either fix the underlying issue (if it's a real bug
  worth fixing) or correct the documented steps to match whatever
  actually works reliably, so the next attempt doesn't hit the same
  false start.
- Note: while this technique is broken, real (manual, password-entry)
  logins at the console DO work fine and are a valid fallback for
  testing - see `20260917-first-login-only-grey-screen.md` for the
  investigation that used manual logins successfully instead.

## Resolution

The documented technique itself is not broken. Re-tested multiple times
on a live VM (autologin alone, and autologin+shim together, restarting
gdm on an already-running system) and it succeeded within a few seconds
every time - not the ~90s a first pass at this investigation initially
concluded was required. That initial "just needed to wait longer" theory
does not hold up and no documentation change was kept for it (it was
written up, then deleted after further testing contradicted it).

One real, already-documented VM behaviour may explain an apparent slow
first run: the confined-session documentation's "Useful debugging
methods" notes already record that the *first* boot of one of these
images installs snaps/the base system and then reboots, so anything
observed during that first boot (including autologin timing) isn't
representative - always test on the second boot onward. If the earlier
slow/failed run happened to coincide with a first boot, that alone would
explain it without needing any new "wait longer" guidance.

Beyond that, the true cause of the original one-off failure is unknown
and could not be reproduced - the VM that produced it was since
rebuilt, so its journal is gone. No source fix or commit was needed; no
documentation change was needed either, since the existing notes
(including the first-boot caveat above) already cover what's actually
relevant. The passwd-lock warning ("Gdm: Failed to lock passwd database,
ignoring: Read-only file system") was confirmed harmless in all
re-tests - it also appears during normal greeter startup and is
unrelated to autologin success/failure. The VM was reverted to the
normal password-prompt greeter each time, with the shim unmounted and
autologin disabled.
