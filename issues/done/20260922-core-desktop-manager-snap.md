# Display manager (core-desktop-manager) snap design (historical)

## Impact / Priority

Not a runtime bug: a historical design document from the original team,
outlining what a display-manager snap would require from snapd (new
pam / snap-execute / accounts-daemon interfaces) and how GDM would move
out of the boot base. No user-facing impact and no priority stated in
the original note; the document is kept as background for the base-split
work (see `splitting-the-core-desktop-base-snap.md`). Impact derived
from the original note's described symptoms.

## Abstract

Currently the Ubuntu Core Desktop image uses a custom base snap to boot
that includes a number of additional services not found in the regular
core24 snap, in particular adding support for a graphical login via
GDM. This spec looks at ways the code could be reorganized to let Core
Desktop build with the regular Ubuntu Core base snap.

## Rationale

When we started work on the first prototype of Ubuntu Core Desktop, we
started by modifying the base snap used to boot the system, since there
was the simplest route to add a graphical login to Ubuntu Core. As GDM
brings in a fair portion of a basic GNOME desktop (graphics drivers,
Wayland compositor, session manager, settings daemon, etc), adding the
remaining pieces for a basic desktop session did not add a lot extra
(mostly just file manager, control panel).

While this removed the need to ship additional copies of the binaries
for the desktop session, it also put that session in a favored
position: the ubuntu-desktop-session snap is tiny, while any other
session booting from the base would be significantly larger. We should
not be relying on shortcuts that won’t be available to other desktops.

## Specification

Below are a few of the issues needed for GDM to run with strict
confinement.

### Startup

At present, gdm.service is started by graphical.target. This could
presumably be replaced by a regular snap service, provided we could
configure it equivalently. In particular, it uses directives to ensure
nothing else is running on tty1, integrate with the plymouth startup
screen, and delay start until after various services:

    # replaces the getty
    Conflicts=getty@tty1.service
    After=getty@tty1.service

    # replaces plymouth-quit since it quits plymouth on its own
    Conflicts=plymouth-quit.service
    After=plymouth-quit.service

    # Needs all the dependencies of the services it's replacing
    # pulled from getty@.service and plymouth-quit.service
    # (except for plymouth-quit-wait.service since it waits until
    # plymouth is quit, which we do)
    After=rc-local.service plymouth-start.service systemd-user-sessions.service

    # Start after cloud init is done generating the system configuration
    # otherwise we might end up getting the wrong locale for example
    After=cloud-config.service

    # GDM takes responsibility for stopping plymouth, so if it fails
    # for any reason, make sure plymouth still stops
    OnFailure=plymouth-quit.service

As a Core Desktop specific feature, we also added
After=snapd.seeded.service to prevent GDM from starting during the
initial install boot.

### Users

The GDM greeter relies on a few system user accounts:

- gdm – used to run the graphical login, so it runs with lower
  privilege than the main GDM daemon.
- gnome-initial-setup – used to run the first boot experience (where we
  have ubuntu-desktop-init plugged in).

The GDM user has a preconfigured home directory containing files owned
by it. The directory is writable by that user, allowing some settings
on the login screen to persist (e.g. accessibility).

For a display manager snap, we’d probably place this somewhere in
$SNAP_COMMON, copying the initial state from $SNAP, so wouldn’t
necessarily require any files in the snap squashfs to be owned by the
user.

The gnome-initial-setup home directory is created on demand by GDM
under /run/gnome-initial-setup.

It’s possible we could get by by creating these users in extrausers
databases on install of the snap. For the gdm user in particular, the
home directory would be pointing to a location controlled by the
display manager snap, so it isn’t clear these accounts could be baked
into core24 and shared by multiple display manager snaps.

There’s an open question about how system users should be created in
the extrausers db. We obviously don’t want to number them contiguously
with the baked in user IDs, since that could cause problems on updates
to the boot base snap.

### User database

GDM relies on accounts-daemon to enumerate local users: both to
populate the user picker and to decide whether to start the first boot
experience.

Accounts-daemon will probably run in its own snap, so we’ll need some
way to communicate with it. Currently the account-control interface
allows communication with an unconfined instance of accounts-daemon. It
probably doesn’t make sense to have a regular snap provide a slot for
this interface, given the other stuff it bundles.

We have an accounts-service interface, but it covers access to the
per-user gnome-online-accounts daemon on the session bus. It’s not
clear combining access to a system service makes sense there.

#### Proposed Change

Add a new interface for communication with accounts-daemon. The slot
side permissions would provide the added permissions over
account-control that the daemon needs to run.

### Authentication

GDM needs to perform PAM authentication and session setup, plus
whatever the configured PAM modules decide to do. It installs a number
of service definitions in /etc/pam.d, which is read-only on core24. One
problem here is that the base snap provides a bunch of service
definitions that should remain read-only and be updated when the base
snap is changed.

According to the pam.conf(5) man page on Ubuntu 24.04, service
definitions can now also be loaded from /usr/lib/pam.d. So we don’t
need to mingle service definitions from the base snap with service
definitions from snaps.

We would also need to make sure the snap is able to do everything that
the PAM modules it calls need to do. Some of this is handled by
existing interfaces like login-session-control and the Apparmor
snippet <abstractions/authentication>.

#### Proposed Change

- Update core24 snap to move all files in /etc/pam.d to /usr/lib/pam.d.
  Leave /etc/pam.d as an empty directory.
- Add a new pam interface that is implicit on core systems that does
  the following:
  - When a plug is connected, the $SNAP/meta/pam.d directory is bind
    mounted to /etc/pam.d in the snap’s mount namespace. This makes the
    service definitions available to processes within the snap without
    leaking them to the rest of the system, avoiding the need for
    namespacing. The standard service definitions are still available
    to the snap, so directives like @include common-auth should still
    work.
  - The connected plug AppArmor snippet includes
    <abstractions/authentication>, plus any additional rules needed by
    the PAM modules shipped in core24 (e.g extrausers), plus whatever
    is needed for session management modules to run.
  - The connected plug AppArmor snippet needs to be able to execute the
    setuid unix_chkpwd and pam_extrausers_chkpwd to same-user password
    validation. The <abstractions/authentication> snippet allows
    profile transition on execute of unix_chkpwd. Maybe this should be
    moved to a subprofile instead?
  - The base declaration for pam-authentication should deny connection
    by default. We could deny installation too, but since all
    permissions rely on the plug being connected denying connection
    might be sufficient.

There are a few open questions though:

- A snap is going to be working with the PAM modules and configuration
  of the base snap, which could be different to authentication policy
  on the boot base. Given that this is a privileged interface, perhaps
  this is just something a person setting up a UC model would have to
  keep in mind. Alternatively, we could introduce some kind of “snap
  base must be boot base” constraint.
- I don’t think there is any reasonable way to support this on classic
  systems due to their diversity. The existence of the interface may
  cause people to ask for it to be made available on classic, but it’s
  likely impossible to handle in the general case.
- Some users (e.g. the KDE lock screen) might only need authentication
  without session management. Is it worth having an auth only variant
  of the interface?
- It’s possible this would make it more difficult to plug more user
  database and authentication backends into a UC system (e.g. Active
  Directory). The big hurdle would likely be providing compatible
  authentication modules, so I’m not sure if these changes to the
  config directories make much of a difference.

### Polkit

We currently have GDM run ubuntu-desktop-init/provd to provide our
first boot experience. This relies on the
/usr/share/polkit-1/rules.d/20-gnome-initial-setup.rules polkit rules
file granting permission to configure the system via the various
systemd daemons, NetworkManager, and accounts-daemon without entering
an admin password. This is required because it runs before any
administrator account or password has been set, and isn’t being run as
root.

While we currently have support for snaps installing polkit action
files, we don’t yet have a way to install rules files. This would need
to be locked down further since we can’t meaningfully validate the
JavaScript rules files as we can for declarative XML files.

Polkit already supports reading Javascript rules from both
/usr/share/polkit-1/rules.d and /etc/polkit-1/rules.d so we can make
the latter writable without causing problems for rules distributed
with core24.

#### Proposed Change

- The polkit interface is updated to add an install-rules plug
  attribute.
- If install-rules is set to true, then .rules files will be copied
  from $SNAP/meta/polkit to /etc/polkit-1/rules.d when the plug is
  connected. Similar namespacing to the .policy files should be
  enforced.
- At present the polkit interface errors out if the `action-prefix`
  plug attribute is not set or the snap provides no .policy files. We
  should accept snaps without these if they have install-rules: true
  set and provide at least one .rules file.
- All existing snap declarations on the store that allow the polkit
  interface should be updated to enforce install-rules: $MISSING.
  Review guidelines should make clear that installing rules requires a
  lot more trust in the snap than installing policy files.

### Run Snap Commands

GDM will need to be able to run commands provided by other snaps. In
particular:

- The ubuntu-desktop-session snap provides a command entry point to run
  the user session.
- The ubuntu-desktop-init snap provides a command to run the first user
  experience.

These commands would be launched from within the display manager’s
sandbox. We would expect them to run as if they had been launched from
an unconfined parent process.

#### Proposed Change

- Add a new snap-execute interface whose base declaration denies
  connection by default, and maybe even denies installation similar to
  snapd-control.
- An implicit slot is provided on core.
- In the connected plug AppArmor rules does the following:
  - Grants read access to the contents of /snap/bin
  - Grants execute access to /usr/bin/snap plus the common targets it
    symlinks to (since this is the target of symlinks in /snap/bin).
  - Grants execute access to /usr/lib/snapd/snap-confine with profile
    transition.
  - Grant the access that snap run needs prior to calling
    snap-confine.

Note that this interface likely cannot be made to work reliably on
classic systems. Some of the setup within the core24 snap assumes that
the snapd snap exists on the system, which is not guaranteed to be
installed on classic.

## Resolution (2026-09-22)

Old design doc from the original team. Its useful content/critique has
already been extracted into `20260922-split-core26-desktop-base-snap.md`
(Stage 3A: Display manager snap). Archived unchanged as historical
reference only — no further action needed on this issue itself.

## Registering new Wayland sessions

Currently we have the main Ubuntu desktop session registered with GDM
via a file in /usr/share/wayland-sessions. To support multiple desktop
session snaps, we would need some way to register with the display
manager.

It’s possible we could do this via the content interface, with each
desktop session providing a slots-per-plug: * slot, and the display
manager writing the session files based on that data.

Alternatively we could have snapd mediate it a bit more closely to
verify the contents of the session desktop files.
