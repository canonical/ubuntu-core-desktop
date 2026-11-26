# getty@tty1.service races with GDM's greeter for tty1 after a greeter crash

Date: 2026-09-15

## Impact / Priority

After a fresh boot, GDM's greeter is shown, the user types their
password, and the login hangs forever with no graphical session and no
error shown on screen. The live workaround is temporary only, so the
race can recur on any boot where GDM's first greeter attempt
crashes/retries. No priority level was stated in the original note;
impact derived from the original note's described symptoms.

Image: Ubuntu Core Desktop 26 amd64 dangerous (desktop26)

## Summary

After rebuilding/relaunching the VM (testing an ubuntu-desktop-init.snap
rebuild), the user rebooted, saw the GDM greeter, typed their password,
and the login just hung -- no graphical session ever appeared, no error
shown.

What actually happened (from the journal, `loginctl list-sessions`,
`systemctl status`, `ps`):

1. The VM did a genuine fresh boot at 21:58:25 UTC (confirmed: the
   host's qemu process itself was only ~4 min old, not a mid-session
   crash of an already-running VM).
2. gdm.service started at 21:59:08. Its first greeter child died
   almost immediately ("Gdm: Child process -9536 was already dead"),
   so GDM internally spun up a second greeter (gdm-greeter-2) at
   21:59:13.
3. In the same second, `getty@tty1.service` (plain text agetty login)
   ALSO (re)started on tty1 ("Started getty@tty1.service" at
   21:59:13.788).
4. gdm.service declares `Conflicts=getty@tty1.service` /
   `After=getty@tty1.service`, which per systemd semantics should stop
   getty@tty1 whenever gdm (re)starts, and vice versa. That works for
   an explicit `systemctl start`, but getty@tty1's own unit has
   `Restart=always`, `RestartSec=0`, `TTYVHangup=yes`: when GDM's
   crashing/retrying greeter hung up tty1's VT, agetty exited and was
   immediately restarted by its OWN auto-restart logic. Systemd's
   auto-restart path re-invokes ExecStart directly and does NOT
   re-run the full Conflicts/job-transaction evaluation the way a
   fresh `systemctl start` would -- so getty@tty1 silently reclaimed
   tty1 without gdm.service ever being stopped.
5. Result: both a plain-text `login -- your_username` process (leader
   of session 3, tty1) and GDM's greeter (session c2, also tty1) were
   simultaneously "on" seat0/tty1. The user's password went to GDM's
   greeter (gdm-password PAM session opened, session 4 on tty2), but
   with tty1 already contested, no `gnome-session`/`gnome-shell` user
   process ever launched -- the login just hung with nothing on
   screen, no error.

This is a plausible (not yet confirmed) explanation for at least some
of the earlier "GDM restart" flakiness/clean-session-teardown mystery
noted in `20260915-remove-app-center-sudo-workaround.md` -- that one
involved a session being torn down rather than a hung login, so it may
be a related-but-distinct manifestation of the same underlying
crash-then-getty-race window, or a separate issue. Not merged with that
item since the symptom (hang vs. clean teardown) differs and the
trigger here (post-boot greeter crash) wasn't confirmed as the cause
there.

## How it was unblocked live (temporary, not persisted)

    sudo systemctl stop getty@tty1.service
    sudo systemctl restart gdm.service

This produced a single clean greeter session on seat0/tty1 with no
getty contention, and the next login attempt succeeded normally. This
is a live workaround only -- getty@tty1 will come back on the next
boot and the race can recur any time GDM's greeter crashes/retries
early in boot.

## Root cause still open

Two separate things would need fixing for a durable solution:

1. Why does GDM's FIRST greeter die almost immediately on every(?)
   boot ("Child process -9536 was already dead")? This forces the
   crash-retry window that triggers the getty race in the first
   place. Not yet investigated -- worth checking gnome-shell/mutter
   startup logs for the first greeter attempt specifically.
2. getty@tty1 should not be able to silently steal tty1 back from a
   display manager on auto-restart. Options:
   - Mask getty@tty1.service on this image entirely, since a
     serial console (ttyS0, per the kernel cmdline) remains
     available for headless/recovery access without it. This is
     the simplest, most robust fix and matches how many desktop
     images avoid exactly this class of race.
   - Or add an explicit override drop-in for getty@tty1.service
     with `Conflicts=gdm.service` on its own side plus
     investigate whether that actually gets re-evaluated on
     auto-restart (per the analysis above, it may not, in which
     case masking is the only reliable fix).

## Validation

1. Reboot the VM repeatedly (a handful of times) and confirm GDM's
   greeter comes up cleanly every time with no getty@tty1 contention
   (`systemctl is-active getty@tty1.service` should stay inactive,
   `loginctl list-sessions` should show exactly one greeter session on
   seat0/tty1 before login).
2. Confirm login succeeds and a full gnome-session/gnome-shell launches
   every time, including on a boot where the first greeter attempt
   happens to crash (if that can be forced/observed).

## Resolution (2026-09-16; established in later work, note appended on
## import)

Fixed by masking: getty@tty1.service is masked on the image so its
`Restart=always` behavior cannot reclaim tty1 during a GDM greeter
retry (the analysis in this file; the fix landed as the
`005.1-mask-gdm-getty.chroot` hook, see
`20260915-fix-gdm-greeter-fail-restart.md`). The current thin
desktop-variant base carries the equivalent mask in
`variants/desktop/static/etc/systemd/system/getty@tty1.service`
(-> /dev/null), together with the console-conf mask, so the race no
longer exists on current images.
