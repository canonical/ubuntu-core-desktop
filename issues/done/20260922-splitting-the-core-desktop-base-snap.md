# Split the Core Desktop base snap's services into their own snaps

## Impact / Priority

Not a runtime bug: the original team's design spec for splitting the
custom boot base's desktop services out into their own snaps. The
problems it describes — additional system/user services running
unconfined on the system, deviation from a regular Ubuntu Core system
beyond what is necessary, and unplanned dependencies between the
desktop session and the boot base — are architecture and
maintainability issues rather than a single observable defect. No
priority stated in the original note. Impact derived from the original
note's described symptoms.

## Abstract

The current Core Desktop prototype ships too many services and makes
it harder to modularise.

## Rationale

While the current Ubuntu Core Desktop prototype runs a strict confined
desktop session and strict confined applications, it relies on a
custom core24-desktop boot base snap. This has a number of downsides:

- There are a number of additional system and user services that run
  on the system unconfined.’
- It deviates further from a regular Ubuntu Core system than necessary.
- We ended up with unplanned dependencies between the desktop session
  and boot base that made it more difficult to build additional desktop
  sessions.

To solve these problems, the additional services in core24-desktop
should be split out into their own snaps, as should desktop neutral
services currently running in ubuntu-desktop-session. This will result
in a system that can be booted using a standard coreNN base snap, and
the ability to replace various components if desired for a particular
Core Desktop variant.

## Specification

While the current Ubuntu Core Desktop prototype runs a strictly
confined desktop session and applications, a lot of the functionality
is

The switch to using core24 as the boot base necessitates finding new
homes for everything that is currently shipped in core24-desktop.
Furthermore, any snaps previously using core24-desktop as a base would
need to ship all the binaries they rely on.

### New System Service Snaps

#### Display Manager

The core24-desktop snap includes GDM to provide a graphical login,
which needs to move somewhere else. While many desktop environments
have a preferred display manager, it doesn’t make sense to merge this
functionality into the user session snaps:

- The relationship is not one-to-one: some display managers are
  preferred by multiple desktop environments.
- There is generally just one display manager running on the system,
  even if multiple user sessions are installed.
- The display manager requires a lot more access to the system than a
  user session.

Converting this to a strict confined snap involves a number of
challenges, since all login methods on regular Ubuntu Core (console
login, sshd) run unconfined. Among other things, it needs:

- Start on boot and take over the first virtual terminal.
- The ability to authenticate as a user and start a new login session
  as that user.
- The ability to launch processes in that new login session, including
  programs provided by other snaps.
- Some level of setuid ability to separate the high privilege core
  from the lower privilege GUI greeter processes.

In addition to these standard display manager features, GDM provides
the environment to run the graphical first boot experience
(ubuntu-desktop-init).

Further details: UD070 - Core Desktop display manager snap

#### Accounts-daemon

Accounts-daemon is a D-Bus system service that helps other services
enumerate, manage users, and access/store additional metadata about
those users (e.g. profile pictures). As a D-Bus service, it also
allows unprivileged processes to manage users via polkit authorisation.

As its own snap, it would talk to the following other snaps:

- GDM: used to enumerate local users and get profile pictures. Also
  indirectly used to start the first boot experience if there are no
  local users.
- ubuntu-desktop-init: used to create the user during the first boot
  experience
- GNOME control center (within ubuntu-desktop-session): update user
  information and create new users.

https://docs.google.com/document/d/1yHU0h_Rp0Td8c1aG3ir9LPYo0y7PTP8KeKUfYiH9T_c

#### Udisks2

The fwupd firmware updater snap uses the udisks2 service to find the
UEFI system partition. It is also used by various desktop sessions for
enumerating and mounting removable media.

There is currently an old version of the snap from 2017 published on
the store. The foundations team is in the process of publishing a
modern snap of udisks2 here:

https://github.com/snapcore/udisks2-snap/

https://snapcraft.io/udisks2

#### Upower

Upower provides information about power devices on the system. The
foundations team have a relatively modern snap published on the store,
which should be easy to migrate to:

https://github.com/snapcore/upower-snap

https://snapcraft.io/upower

#### Colord

The colord daemon managed colour profiles for various devices connected
to the system: i.e. displays, printers, and scanners. It has been
designed as a system service to allow multiple users on the system to
share colour profiles.

While it is primarily a D-Bus service, the API involves passing file
system paths to the client, which is a problem when processes run in
different mount namespaces. More investigation is needed.

#### Boltd

Boltd is a system daemon for managing Thunderbolt devices, including
authorisation of newly connected devices.

While we were shipping this in the prototype, we hadn’t configured the
desktop session to be able to talk to it.

#### Geoclue

Geoclue is an abstraction for location services, either direct from
GPS devices or with the assistance of an online service.

#### Rtkit

Rtkit is a system daemon whose purpose is to give user processes
limited access to realtime or high priority scheduling without them
needing to be setuid root. Both Pipewire and gnome-shell will try to
use it if available.

It looks like most of the access the rtkit daemon uses is already
available from the base template and process-control interfaces.
Communication between the daemon and user processes could be handled
by the generic dbus interface, but a special purpose interface might be
a better fit as we could then make it available on classic systems
where the rtkit daemon is unconfined.

Further details: SD196 - RealtimeKit interface proposal

#### Fwupd

TODO. The fwupd daemon should also be in its own snap. There is, still,
a problem with encryption when working on Core, thus a patch to avoid
using it when the disk is encrypted should be required.

### New User Service Snaps

#### Pipewire

Pipewire has become the defacto standard sound and media server on
modern desktops. While the current prototype runs pipewire within the
ubuntu-desktop-session snap, this meant the KDE folks had to duplicate
this arrangement for their desktop session.

Instead, the services will move to a new snap, and applications will
connect to pipewire:audio-playback and pipewire:audio-record for
Pulseaudio protocol access.

We still need direct pipewire protocol access in the
ubuntu-desktop-session snap in order to implement screen sharing and
the associated xdg-desktop-portal APIs. This will need a new
interface, since it doesn’t fit into our existing audio interfaces. It
wouldn’t be a general purpose interface, since we expect application
snaps to either use the PulseAudio protocol or use xdg-desktop-portal
to access a Pipewire remote (e.g. for screen sharing, camera access,
etc).

Further details: UD072 - Pipewire snap

#### Xdg-desktop-portal

The xdg-desktop-portal collection of services perform privileged
operations on behalf of strict confined applications. This includes the
special access to the desktop shell, and controlled access to areas of
the file system that would be otherwise inaccessible (either due to
permissions or because they’re outside of the app’s sandbox).

In the current prototype, the xdg-desktop-portal user service is
provided by the core24-desktop base snap and runs unconfined. It talks
to a backend xdg-desktop-portal-gnome service provided by
ubuntu-desktop-session that provides the UI and integration with the
shell and a consistent view of the file system in file choosers.

This split will persist in the new architecture, but the currently
unconfined components will move to a new xdg-desktop-portal snap. In
particular, the following services will run as part of the snap:

- xdg-desktop-portal
- xdg-document-portal
- xdg-permission-store

Currently the backend services can communicate with xdg-desktop-portal
thanks to permanent slot rules from the desktop interface. This should
be moved to a new special purpose interface, with the
xdg-desktop-portal snap providing a slot and desktop sessions providing
plugs.

There is also an open question about how to handle the
xdg-document-portal’s FUSE mount. Allowing a snap to create a FUSE
mount is not too difficult, but we need to be able to bind mount
subtrees from this FUSE file system into every other desktop snap’s
mount namespace. It’s less obvious how to handle this if the document
portal is no longer mounted in the primary mount namespace.

Further details: UD082 - XDG Desktop Portal snap

### New Application Snaps

#### Admin Terminal

We currently ship gnome-terminal in the ubuntu-desktop-session snap as
an admin console. To escape the snap sandbox, it makes an ssh
connection to localhost and prompts the user for their password again.

As it isn’t using any special permissions, it can easily be moved out
into its own snap. This would also make it possible to build a Core
Desktop system without the admin console present.

### Features requiring new snapd functionality

#### Socket activation support from regular $XDG_RUNTIME_DIR

For some services, it will be needed to have socket activation from
sockets located in global folders, like the real XDG_RUNTIME_DIR.
Although it can be replaced by a hack (using a one-shot daemon to
create soft links from the global folder into the snap-specific one),
it’s an ugly solution, so having support for them in Snapd is very
desirable.

Further details: SD193 - Global socket activation

#### Greedy plugging to support multiple desktop session snaps

A desktop session snap

Further details: UD086 - Supporting multiple desktop sessions on Core
Desktop

#### Limited access to systemd user service control

A number of modern desktop environments make use of the systemd user
instance to sequence the startup of various desktop components. This
presents two main requirements for snapd:

- Give more flexibility over when services provided by snaps are
  started. This includes starting up targets other than default.target,
  and more control over when services are stopped.
- Allow the desktop session snap to communicate with the systemd user
  instance to start and stop various targets, and monitor their state.

As part of KDE Plasma Core Desktop work, an attempt at (2) was done in
the form of a systemd-user-control interface. This provides AppArmor
permissions to talk directly to the D-Bus interface, which is less
restrictive than we’d like.

An alternative we’re investigating is to provide a proxy offering a
restricted subset of the API:

- Restrict which unit names the client can start/stop/monitor.
- Restrict environment changes.

This would need to be offered via a different D-Bus name and require
some code changes, but the changes would hopefully be more manageable
than an entirely new API.

UD075 - Snap Service Requirements for Core Desktop

## Further Information

### Contents of the core24-desktop snap

The core24-desktop snap adds a number of additional services and
configuration files not found in the regular core24 snap. These
include:

The GDM service, plus services necessary to manage the greeter session:

- Gnome-session
- Gnome-shell
- Gnome-settings-daemon
- etc

Provd plus scripts to call ubuntu-desktop-init in place of
gnome-initial-setup.

display-manager.service symlink to GDM (causes it to be started by
graphical.target).

Other system services:

- accounts-daemon.service – user account creation, enumeration, and
  property store
- bolt.service – Thunderbolt support
- colord.service – color management daemon
- fprintd.service – fingerprint reader daemon to support associated PAM
  module
- geoclue.service – geolocation services
- spice-vdagent*.(service|socket) – SPICE agent support
- udisks2.service
- upower.service

For user services, we have:

- dconf.service – backend for glib’s gsettings.
- dirmngr.service / dirmngr.socket / gpg-agent-* / keyboxd.* – GPG
  related stuff.
- gnome-keyring* – Keyring services
- gnome-session* – systemd based gnome session startup
- gvfs-service-*.service – gvfs backend daemons
- org.gnome.SettingsDaemon.*.{service,target} – systemd session startup
  for settings daemon.
- spice-vdagent.service – SPICE integration for VMs
- tracker-* – full text indexing service
- xdg-desktop-portal*.service / xdg-document-portal.service /
  xdg-permission-store.service – xdg-desktop-portal
- pipewire.service and pipewire-pulse.service

Some of these are remnants not actually being used by the display
manager or desktop session (e.g. the units are inaccessible within the
desktop session, and are started some other way).

## Resolution (2026-09-22)

Old design doc from the original team. Its useful content/critique has
already been extracted into `20260922-split-core26-desktop-base-snap.md`
(Stage 2/3, and Stage 3B/3C/3D specifically), plus the three Stage 4
parking-lot issues (multiple-desktop-session support, global socket
activation, toolbox/podman). Archived unchanged as historical reference
only — no further action needed on this issue itself.
