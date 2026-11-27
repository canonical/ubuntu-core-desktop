# GNOME Keyring Secret Service is not available in the desktop session

## Impact / Priority

Medium. The user-visible impact has not yet been confirmed with a real
application. Apps that rely on the Secret Service may be unable to save
or retrieve credentials; reproduce this with an actual credential-using
app before estimating the impact more precisely.

## Context

On the Core Desktop GNOME VM, the systemd user
`gnome-keyring-daemon.socket` and `.service` units were disabled and
inactive even though they are wanted by `graphical-session-pre.target`.
The PAM-launched `gnome-keyring-daemon` logged that it unlocked the login
keyring, but this was a separate process from the systemd-managed daemon.

As a diagnostic, `systemctl --user enable --now
gnome-keyring-daemon.socket` was run. Afterwards, `org.freedesktop.secrets`
and `org.freedesktop.impl.portal.Secret` were still activatable with no
owner. Enabling the socket did not change the separate xdg-desktop-portal
startup delay tracked in
`20260926-portal-realtimekit-pipewire-startup-delay.md`.

## Next steps

1. On a fresh boot, determine why the user socket/service are not
   started by `graphical-session-pre.target` and whether the PAM-launched
   and systemd-managed daemons are configured to conflict.
2. Use an actual application that saves or retrieves a credential to
   verify the end-user failure, then check D-Bus ownership for
   `org.freedesktop.secrets` and test recovery after correcting unit
   activation.

## Update (2026-11-27): the activation path now exists; one live check left

This file's diagnosis (units disabled, `org.freedesktop.secrets`
"activatable with no owner") predates the keyring wiring that landed in
the desktop base on 2026-11-08. The base now ships, and the built
squashfs contains:

- `/usr/share/dbus-1/services/org.freedesktop.secrets.service` with
  `Exec=/snap/bin/ubuntu-desktop-session.gnome-keyring-daemon --start
  --foreground --components=secrets` and
  `AssumedAppArmorLabel=snap.ubuntu-desktop-session.gnome-keyring-daemon`
  - so a Secret Service client now D-Bus-activates the confined, snap-
  routed daemon instead of a unit that is merely "activatable".
- `gnome-keyring-daemon.service` plus `.socket` and a
  `core-override.conf` that swaps `ExecStart=` to the same snap app
  (`ConditionGroup=!gdm` keeps it out of the greeter session), next to
  the private/system prompter service files.

That addresses the defect as stated. What is NOT done is step 2's
end-to-end check (a real credential-using app, then confirm
`org.freedesktop.secrets` gains an owner) - but that is exactly the
functional verification `20261108-check-gnome-keyring-pam-handoff.md`
exists to do, together with the unlock-prompt behaviour. This file
stays open only until that check runs; if the handoff item passes,
close this one with it. If activation still fails with the files
present, the useful evidence is which Exec= the session bus actually
tried and whether the `desktop`-plug-connected app can reach the snap's
`dbus-freedesktop-secrets` slot.
