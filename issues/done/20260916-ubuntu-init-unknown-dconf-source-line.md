# ubuntu_init fails with "Unknown DConf source: 'line'" during first-boot wizard

Date: 2026-09-16

## Impact / Priority

High. On a fresh image with no users, the first-boot wizard — the only
path to create a user and reach the desktop — aborted during startup,
so a new device could not be set up at all.

Image: Ubuntu Core Desktop 26 amd64 dangerous (desktop26)

## Summary

The missing `/run/gnome-initial-setup` directory issue is fixed, but the
first-boot wizard still cannot be completed on a fresh image because the
`ubuntu_init` Flutter application fails during startup with:

    Unknown DConf source: 'line'

This is now the remaining blocker for completing the original
`ubuntu-desktop-init` validation through account creation and handing
off to the normal login greeter.

## Observed failure

The VM was rebuilt with the `core-base-desktop` tmpfiles fix, configured
with zero normal local users, `InitialSetupEnable=true`, and
`AutomaticLoginEnable=false`, then rebooted. GDM launched the
initial-setup session as the dynamically allocated system user
`gnome-initial-setup-2` (UID 60579; the greeter/session appeared in
`loginctl` as the dynamic initial-setup session).

The directory and backend path worked:

- `/run/gnome-initial-setup` existed automatically with mode 1777.
- `/usr/libexec/provd` ran as PID 6432.
- The wrapper logged: `Serving GRPC requests on
  /run/gnome-initial-setup/desktop-provision/init.socket`.
- `/snap/ubuntu-desktop-init/current/bin/ubuntu_init` launched as PID
  6777.

After the app started, the journal showed normal early application
startup (`Using default flavor: UbuntuFlavor.ubuntu` and `Loaded 75
languages`), then at approximately 21:19:16 UTC:

    ERROR ubuntu_init: Unhandled exception
    String: Unknown DConf source: 'line'

The stack trace identified the failure in the Flutter `gsettings`
package's `DConfClient._loadProfileFile` / `_loadSources` path. The app
also reported that logging to `/var/log/installer/ubuntu_init.log`
failed with `(Creation failed)`, but the DConf exception was the startup
failure that prevented the wizard from completing.

## Investigation so far

No fix was attempted in this investigation. The failure was observed
only after the runtime-directory/provd problem had been eliminated, so
it is a separate issue rather than a socket or wrapper timeout. The
exact DConf profile/source file being parsed, and why the parser sees
`line` as a DConf source, still need to be traced against the files and
environment visible inside the initial-setup session.

There were also existing confined-session portal/AppArmor errors
involving the dynamic home path under
`/run/gdm3/home/gnome-initial-setup-2`; these were noisy and may affect
portal features, but they did not prevent `provd` from binding or
`ubuntu_init` from being exec'd. The DConf error is the newly observed
blocker for full wizard completion.

## Validation needed

On a fresh rebuilt image, identify and fix the malformed/unexpected
DConf source, then rerun the zero-user first-boot flow and complete the
wizard through account creation. Confirm that it hands off to the
normal GDM greeter without the `Unknown DConf source: 'line'` exception.

## Resolution (2026-09-16)

Root cause was confirmed as a pre-existing compatibility bug, not a
regression from the same-day GNOME-session confinement work and not the
missing `/etc/dconf/profile/gdm` symlink theory.

The initial-setup session exports:

    DCONF_PROFILE=gnome-initial-setup

That profile is valid and contains:

    user-db:user
    file-db:/usr/share/gnome-initial-setup/initial-setup-dconf-defaults

The Flutter `gsettings` 0.2.8 package used by `ubuntu_init` implements
`user-db` and `system-db`, but not `file-db`. Its parser's default error
also incorrectly interpolates the literal word `line`, producing:
`Unknown DConf source: 'line'`. The profile files themselves were valid;
`dconf dump` parsed the profile successfully. The confinement commits
did not touch DConf or GSettings files.

The real fix is in `core-base-desktop` commit `ff2ba20` (`Avoid
unsupported DConf profile source`), in
`hooks/002.4-configure-system-setup-tool.chroot`. The customized
`launch-desktop-provision-init` wrapper now launches the Flutter wizard
with `DCONF_PROFILE=`. This gives `ubuntu_init` the package's supported
default user database without changing the full profile used by the
GNOME initial-setup session:

    env ... DCONF_PROFILE= DESKTOP_PROVISION_PATH=... ubuntu_init

Validation:

1. Before the fix, a fresh zero-user boot on the existing image launched
   `ubuntu_init` as PID 2673. The complete journal at 21:59:55 UTC
   showed:

       INFO flavor_provider: Using default flavor: UbuntuFlavor.ubuntu
       INFO locale: Loaded 75 languages
       ERROR ubuntu_init: Unhandled exception
               String: Unknown DConf source: 'line'
       #0 DConfClient._loadProfileFile (package:gsettings/src/dconf_client.dart:213)
       #1 DConfClient._loadSources (package:gsettings/src/dconf_client.dart:149)
       #2 new DConfClient... (package:gsettings/src/dconf_client.dart:51)

   `/proc/2673/environ` confirmed `DCONF_PROFILE=gnome-initial-setup`;
   `/etc/dconf/profile` had no `gdm` file, while the valid profiles
   existed under `/usr/share/dconf/profile`.

2. A live profile override containing only `user-db:user` eliminated
   the exception, confirming the parser/profile interaction before
   rebuilding.

3. Rebuilt `core-base-desktop` and then rebuilt the image with
   `build.sh`. On a fresh zero-user boot with
   `InitialSetupEnable=true` and `AutomaticLoginEnable=false`, the
   rebuilt wrapper showed `DCONF_PROFILE=` in the deployed file. After
   starting GDM, `ubuntu_init` PID 9147 launched through the normal
   provd socket path and remained alive. Its environment contained
   `DCONF_PROFILE=` and its PID journal contained only the expected
   AT-SPI/cursor warnings; no `Unknown DConf source` or
   unhandled-exception entries occurred.

The full GUI flow through account creation was not automated in this
headless validation, so later-page completion was not independently
confirmed. The VM was restored to a usable state afterward: user
`your_username` (UID 1000, sudo group, SSH key access) exists, GDM is
active, `InitialSetupEnable=false`, and automatic login is disabled.

## Correction (2026-09-16, later)

`ensure-desktop-session-connections.service` was left disabled at the
end of this session, described above as needed because the script
"loops on missing plugs and blocks GDM." This was re-investigated and
found to be inaccurate: the unit has no ordering dependency on
gdm.service (only `After=snapd.service snapd.seeded.service`), so it
cannot block GDM startup. What actually happened: the `wayland-client`
connection attempt in the script was silently failing every time (see
the correction note in
`20260916-terminal-wayland-client-not-auto-connected.md` -- a same-snap
connect bug, fixed in ubuntu-core-desktop commit 5dcddb5), each retry
taking ~15s, plus three Firefox connection attempts that fail fast
because Firefox isn't preinstalled on a fresh image -- together making
the service take ~70s total, which was mistaken for a hang. The service
was manually killed (signal TERM) mid-run and then disabled at the
systemd level; that disabling was never committed to source (the image
build always ships the unit enabled via a static symlink), so it did
not persist into a rebuilt image, but leaving it disabled live would
have silently broken snap-store/Firefox/terminal display connections on
that VM. With the wayland-client bug now fixed, the service completes
with `status=0/SUCCESS` in ~70s on a fresh boot and must remain enabled
-- do not disable it as a workaround for slowness.
