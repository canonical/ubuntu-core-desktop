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
