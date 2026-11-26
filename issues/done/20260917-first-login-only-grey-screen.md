# Grey screen on first login after boot only (Core 26 image)

Date: 2026-09-17

## Impact / Priority

On the first login attempt after a cold boot, the login sometimes goes
grey instead of reaching the desktop (`gnome-session-manager@ubuntu.service`
hits its 90s `StartupTimeoutSec` after an AppArmor denial and never
becomes ready); every later login on the same boot succeeds in well
under 1 second. No priority level was stated in the original note;
impact derived from the original note's described symptoms.

## Context

While testing the Core 26 image after the core24-removal work (see
`20260917-remove-core24-from-core26-image.md` and
`20260917-post-login-grey-screen-gnome-session-timeout.md`), the
previously-documented grey-screen bug was reproduced live on the Core 26
test VM:

- `gnome-session-manager@ubuntu.service` was denied `sendmsg` on
  `/run/user/1000/systemd/notify` by AppArmor (class="file",
  requested_mask="w", denied_mask="w"), even though the profile on disk
  already contains the exact matching rule
  (`"/run/user/[0-9]*/systemd/notify" w,`, from the fix documented in
  the note above). The unit never became ready, hit its 90s
  StartupTimeoutSec, and GDM dropped back to the login screen (grey
  screen symptom).
- A live journal check across the whole boot showed this happened only
  on the FIRST login of the boot (at 10:47:15, ~2 minutes after boot).
  Every login attempt after that on the same boot succeeded in well
  under 1 second - both greeter re-logins (`gnome-login.service`) and
  15 further real `ubuntu.service` user logins in a row, with zero
  further AppArmor denials or timeouts.
- This does NOT appear to be caused by the same-day pc-kernel channel
  bump (24/stable -> 26/stable, kernel 6.8.0-136 -> 7.0.0-31): if it
  were a deterministic kernel-version incompatibility, it should recur
  on every login, not just the first one after boot.

## Goal

Find out what is different about the very first login attempt after a
cold boot (vs. every subsequent one) that causes the
`/run/user/1000/systemd/notify` AppArmor denial, and either fix the
race or confirm/rule out each hypothesis below.

## Fast iteration cycle (already set up by the user)

A backup image `26.img.bak` (a copy of a booted/working `26.img`) is
available in the repository working tree. To get a fast repro loop
without a full image rebuild each time:

    cp -a 26.img.bak 26.img

Then boot the image in a test VM and log in once at the console/VNC on
first boot - the bug reproduces on that very first login attempt. This
is much faster than a full image build + first-boot cycle.

## Working hypotheses (NOT yet confirmed)

1. Some directory/socket/permission that `gnome-session-service` and
   sd_notify depend on (e.g. `/run/user/1000/systemd/notify` itself, or
   its parent directory's ownership/mode) is still being created by
   systemd-logind/pam_systemd/systemd --user at the moment of the very
   first login, and the confined process races ahead of that setup only
   on a cold/first login - by the second login the directory already
   exists with stable permissions from the previous session, masking
   the race.
2. Some one-time boot-time AppArmor policy load/compile step (e.g.
   `snapd` generating/loading the `ubuntu-desktop-session` profile, or
   the `ensure-desktop-session-connections.service` connect-loop
   mentioned in the confinement notes) has not fully completed by the
   time of the very first login, so the profile enforced at that moment
   is stale/incomplete/not yet reloaded, even though the correct rule is
   present in the profile file on disk shortly afterward.
3. Cold caches (e.g. AppArmor's own profile cache under
   `/var/cache/apparmor/`, or something in systemd's own generator
   output under `/run/systemd/generator/`) are still being populated
   for the first time and this is slower/different than on later
   attempts, causing the confined process to start before the correct
   policy is actually loaded/enforced by the kernel.
4. Something reboot/boot-count-specific in gdm itself, unrelated to
   AppArmor.

## Suggested investigation approach

- Use the fast iteration cycle above to reproduce repeatedly (cheaper
  than a full rebuild); confirm the "only fails first login" pattern
  holds across several fresh copies of 26.img.bak, not just the one
  boot already observed.
- On a fresh boot, right as GDM shows the greeter, poll/tail in a tight
  loop (before logging in) for: `/var/cache/apparmor/*/` cache writes
  for the ubuntu-desktop-session profiles, snapd's own service logs
  (profile generation/reload), and
  `ensure-desktop-session-connections.service` completion state - to
  see whether policy loading is still in progress at the moment login
  is attempted.
- Compare timestamps precisely: boot time, snapd profile-load
  completion time, `ensure-desktop-session-connections.service`
  completion time, vs. the moment the first login is submitted and the
  moment the notify-socket denial is logged.
- Check whether deliberately waiting longer after boot before
  attempting the first login makes the bug disappear (supports a
  one-time boot-settling race) vs. still happening after a long wait
  (points elsewhere).
- Follow the established diagnostics methodology and the reusable
  confined-session techniques (this is the same confined-session area,
  and the earlier note above already has the
  AppArmor-profile/notify-socket root-cause context) rather than
  re-deriving those from scratch.
- If a real fix is found, note whether it belongs in
  `core-base-desktop` (boot ordering/units), `ubuntu-core-desktop-snapd`
  (AppArmor interface rules), or `ubuntu-core-desktop` (gadget/model
  boot sequencing).

## Resolution

Hypothesis 2 confirmed as the root cause, via live journal evidence on
the Core 26 test VM (single boot, both a failing and a succeeding login
present in the same `journalctl -b0`):

- `ensure-desktop-session-connections.service` (the snap-id-independent
  boot-time `snap connect` loop) is NOT ordered before `gdm.service` at
  all -- `systemctl cat gdm.service` showed no dependency on it. GDM
  starts and accepts logins completely independently of whether that
  loop has finished.
- The loop reconnects ubuntu-desktop-session's ~24 interfaces one at a
  time; each successful `snap connect` triggers snapd to
  `profile_replace` the snap's AppArmor profile immediately (confirmed
  via dozens of `apparmor="STATUS" operation="profile_replace"
  ... name="snap.ubuntu-desktop-session.ubuntu-desktop-session"` audit
  lines spaced ~1-2s apart through the boot).
- The first login of the boot landed only ~13s into that loop (loop
  started at T+0, first login's PAM session opened at T+12s), i.e.
  while the profile was still being incrementally rebuilt with
  interfaces not yet all connected. The
  `/run/user/1000/systemd/notify` sendmsg denial happened at that exact
  moment. All real interface connections finished by roughly T+48s (the
  loop's remaining runtime, up to ~95s total on that boot, was spent
  purely retrying `firefox:*` connections 5x each with a 3s backoff,
  since firefox isn't installed on this image -- a separate, wasteful
  tail, not itself the race). The second login came well after the loop
  had finished and succeeded instantly.
- Ruled out 1/3/4: no evidence of `/run/user/1000` or the notify-socket
  parent directory itself being late-created (pam_systemd's own
  ordering is unrelated to snapd's profile reloads); no AppArmor cache
  population delay found independent of the profile_replace events
  above; no boot-count/gdm-specific behavior found or needed to explain
  the symptom once the profile-reload race was confirmed.

Fix, implemented and verified in `ubuntu-core-desktop` commit
`6463bd1` (in the image build script):

1. Ship a `gdm.service.d/99-wait-for-session-connections.conf` drop-in
   (`After=`/`Wants=ensure-desktop-session-connections.service`) so GDM
   cannot start, and therefore cannot accept any login, until the
   connect loop has fully finished and the AppArmor profile is
   complete.
2. Skip the retry/backoff loop entirely for connections whose
   plug-side snap isn't installed (checked via `snap list <snap>`
   first) -- removes the wasted firefox-retry tail, cutting the new
   GDM-start wait roughly in half (~95s -> ~38s observed on this
   image).

Verified end-to-end on a from-scratch rebuild (no cached artifacts
reused for the fix itself) + fresh boot: the very first login after
boot now starts `gnome-session-manager@ubuntu.service` in ~30ms instead
of hitting the 90s `StartupTimeoutSec`, across multiple repeat
reboot/login cycles, including one with a real user typo/retry on the
password prompt (unrelated PAM auth failures, not this bug) before the
successful login. Confirmed the fix is baked into the resulting
`custom-core.snap` and `26.img` (not just applied live on a mutated
running VM).

Trade-off accepted: GDM's login screen now appears later after boot
(bounded by the connect loop's runtime, ~38s observed after the
optimization above) instead of racily sometimes-working immediately --
this is a deliberate width-for-correctness trade, not a regression.
Further shrinking that wait (e.g. more of the loop's remaining runtime,
or parallelizing/removing more of it) is open follow-up work, not part
of this fix.
