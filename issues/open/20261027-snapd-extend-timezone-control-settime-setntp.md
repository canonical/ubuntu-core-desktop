# Extend snapd fork's timezone-control with SetTime/SetNTP (kcm_clock gaps)

## Impact / Priority

Priority: Medium-low. The Date & Time KCM now loads data and can change
the TIMEZONE (with a polkit prompt, admin credentials work). But the
page's other two operations -- manually setting the date/time
(timedate1.SetTime) and the "set date and time automatically" NTP
toggle (timedate1.SetNTP) -- still fail at the AppArmor layer: snapd's
timezone-control interface grants only Introspect, Properties.Get{,All},
ListTimezones, SetTimezone and PropertiesChanged receive on
/org/freedesktop/timedate1 (verified in
ubuntu-core-desktop-snapd/interfaces/builtin/timezone_control.go,
the fork's dev branch). Real user impact: an end user cannot fix a
wrong clock or enable NTP from the GUI -- on a Core image with no other
admin surface that is a genuine functional gap, not cosmetic.

## Context

Written 2026-10-27, immediately after the timezone-control plug work
(plasma-desktop-session 9392c66 + build.sh f352a66) got the Date & Time
KCM's timezone path working through the polkit prompt.

## Why extending is safe (write this in the commit message)

The AppArmor grant is transport permission only. Authorization is still
polkit's job: org.freedesktop.timedate1.set-time and set-ntp are
allow_active=auth_admin_keep in
/usr/share/polkit-1/actions/org.freedesktop.timedate1.policy (verified
on image 20261027), and the image's admin rule is unix-group:sudo
(49-ubuntu-admin.rules) -- so every SetTime/SetNTP call pops the polkit
agent prompt exactly like SetTimezone already does. The same argument
the existing SetTimezone grant rests on.

## Work

1. ubuntu-core-desktop-snapd (branch dev):
   interfaces/builtin/timezone_control.go -- add dbus (send) rules for
   members "SetTime" and "SetNTP" on path=/org/freedesktop/timedate1
   interface=org.freedesktop.timedate1, peer=(label=unconfined),
   mirroring the existing SetTimezone stanza (timedated is
   dbus-activated; the existing comment explains the introspection
   stanza's differing peer label -- keep that reasoning).
2. Update interfaces/builtin/timezone_control_test.go so the verifier
   covers the new members (the test files enumerate the expected
   rules; missing entries FAIL the test -- add, don't assume).
3. Consider (optional, separate decision): propose the same member
   additions upstream to snapd (the narrowness is upstream's, not our
   fork's). The fork already carries local interface additions
   (pam-unix-chkpwd, systemd-user-environment), so a local-only change
   is consistent with current practice; an upstream PR would need the
   same polkit-mediation argument.
4. Rebuild the snapd snap and rebuild the image with the image build
   (`build.sh`) so the new snapd gets baked in -- a refresh of just the
   session snap is NOT enough, snapd itself must ship the extended
   profile. Watch the image build picks up the freshly built snapd
   snap.
5. While in there (optional): audit whether any OTHER kcm/system-bus
   path needs a sibling interface (the earlier session had 82
   PolicyKit1/timedate denials; polkitd calls from ordinary session
   apps are still ungranted -- only the agent profile talks to
   PolicyKit1. If a future GUI admin action needs pkexec-style polkit
   checks from a confined app, that is a separate gap).

## Verify (fresh image, reboot)

- Date & Time KCM: all three paths work with a prompt:
  a) timezone change (regression -- worked before, must keep working)
  b) manual date/time set -> prompt -> `timedatectl` shows the new
     time
  c) NTP toggle -> prompt -> `timedatectl` shows NTP enabled
- journalctl -b: zero NEW apparmor DENIED lines for
  /org/freedesktop/timedate1 (Properties.Get denials stay gone; SetTime/
  SetNTP denials must not appear).
- `snap interface timezone-control` on the VM lists the connection;
  `snap change` shows the plug connected at first boot (baked gadget).
- polkit journal shows the auth_admin_keep decisions succeeding for
  unix-user:your_username on set-time and set-ntp.

## Done when

a-c verified on a freshly built+flashed image, snapd fork change
committed on dev, image rebuilt via the image build (`build.sh`), and
the residual-gap note (SetTime/SetNTP) removed from the
plasma-desktop-session yaml comment if desired (the NOTE in the
timezone-control plug comment at the plasma-plasmashell app).
