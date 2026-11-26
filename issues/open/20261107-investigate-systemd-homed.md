# Investigate using systemd-homed in Ubuntu Core Desktop

## Impact / Priority

Not a bug report: an open architecture question. The original note
records no observed failure and no priority. It asks whether
systemd-homed should replace or complement the extrausers/provd account
stack, what the advantages and disadvantages would be, and how the
first-boot wizard and provd would be affected. No user observes
anything today. Impact derived from the original note's described
symptoms (an architecture question; no failure was described).

## Questions

1. Is this worth pursuing?
2. What changes exactly should we consider making (if anything)?
3. What would be the explicit advantages of using systemd-homed?
   (There's no point in doing any work if it provides no advantages
   over extrausers)
4. And the disadvantages?
5. How would this affect the first boot wizard, provd etc?
6. Actionable next steps? Write a todo?

## For context: the discussion below

**is there a way to manage user accounts with systemd**

Yes, although systemd doesn't provide a complete user-account
management system in the traditional sense. It does provide several
components for managing users, sessions, and user services.

The main distinction is between creating/managing Unix accounts and
managing their runtime environment.

### 1. systemd components

- systemd-homed: Manages user accounts, home directories and user
  storage
- systemd-userdbd: Provides a dynamic user/group database
- systemd-logind: Manages user logins, sessions and seats
- systemd user manager: Runs per-user services and sessions
- systemd-sysusers: Declaratively creates system users and groups

### 2. systemd-homed — actual user account management

systemd-homed is probably the most interesting one if you're looking
for a systemd-native alternative to traditional /etc/passwd account
management.

It supports:

- Creating and deleting user accounts.
- Managing home directories.
- Encrypted home directories.
- Portable user accounts.
- User records stored as JSON.
- User accounts backed by LUKS, filesystem directories or other
  storage.

For example:

    homectl create chris
    homectl list
    homectl inspect chris
    homectl passwd chris
    homectl remove chris

User records are JSON-based and can contain information such as UID,
GID, shell, home directory and resource limits.

For example, creating a user with a specific shell and administrator
privileges:

    sudo homectl create chris \
        --real-name="Chris Bainbridge" \
        --shell=/bin/bash \
        --member-of=sudo

One important limitation: systemd-homed does not manage traditional
accounts created with useradd. It is intended for human users, not
system/service accounts.

### 3. systemd-sysusers — declarative system accounts

For system accounts, there's systemd-sysusers.

It reads configuration files under:

- /usr/lib/sysusers.d/
- /usr/local/lib/sysusers.d/
- /etc/sysusers.d/

Example /etc/sysusers.d/myservice.conf:

    u myservice - "My Service" /var/lib/myservice /usr/sbin/nologin

Apply it:

    sudo systemd-sysusers

This is particularly useful for packaging because accounts can be
created declaratively during package installation.

### 4. systemd-userdbd — unified user database

This is an interesting architectural component.

systemd-userdbd provides a unified interface for looking up user and
group records from different sources.

For example:

- Traditional /etc/passwd accounts.
- systemd-homed accounts.
- LDAP and other external identity providers.

You can inspect accounts using:

    userdbctl
    userdbctl user chris
    userdbctl groups

See systemd JSON User Records documentation.

### 5. systemd-logind — session management

systemd-logind handles the runtime side:

    loginctl list-users
    loginctl user-status chris
    loginctl terminate-user chris
    loginctl enable-linger chris

It manages sessions, seats, user runtime directories and per-user
resource management.

### What I'd recommend

- Create system/service accounts — systemd-sysusers
- Manage human accounts — systemd-homed
- Unified account lookup — systemd-userdbd
- Manage login sessions — systemd-logind
- Run per-user services — systemd user manager

One particularly interesting possibility: if you're thinking about
Ubuntu Core Desktop, systemd-homed could potentially provide a more
portable, self-contained user-account model, with JSON identity records
and independently managed home storage.

However, it isn't a drop-in replacement for Ubuntu's existing
account-management stack. You'd need to consider PAM, NSS, GDM
integration, and how existing desktop components interact with it.

**can gdm use systemd-homed or systemd-userdbd ?**

Yes. GDM can work with systemd-homed and systemd-userdbd, although the
integration is mostly provided through PAM and NSS rather than GDM
having its own systemd-homed backend.

The important point is that GDM doesn't need to know where an account
is stored. It needs to be able to:

- Discover the account.
- Authenticate the user.
- Obtain the user's UID, GID, home directory and shell.
- Start the user's desktop session.

systemd provides the infrastructure for this.

### 1. Account discovery: NSS / userdbd

GDM uses standard Unix account lookup APIs. nss-systemd makes homed
accounts visible to those APIs.

For example:

    getent passwd chris
    id chris

These can resolve homed users even though they aren't in /etc/passwd.

systemd-userdbd provides the underlying user database lookup
infrastructure. GDM doesn't need to call it directly.

### 2. Authentication: PAM

This is the critical integration.

The PAM module is:

    pam_systemd_home.so

It handles:

- Authenticating against homed user records.
- Unlocking and mounting encrypted home directories.
- Managing account validation.
- Tracking sessions.
- Unmounting homes after the last session ends.

The systemd documentation even provides an example PAM configuration
for supporting homed users.

### 3. GDM-specific considerations

There is one particularly important detail: GDM needs to configure its
PAM stack appropriately.

On Ubuntu, inspect:

    cat /etc/pam.d/gdm-password
    cat /etc/pam.d/gdm-autologin

You would need to ensure that the relevant PAM authentication, account
and session stacks support pam_systemd_home.

Also, for encrypted homes that should be suspended during system sleep,
the display manager should use:

    pam_systemd_home.so suspend=yes

This is explicitly recommended in systemd's desktop integration
documentation.

### 4. One interesting limitation: GDM's user list

GDM has a greeter user-selection mechanism. There are additional
considerations around discovering and displaying homed users,
particularly when accounts are not currently active.

Basic NSS compatibility makes this possible without changing GDM, but
full integration with richer JSON user records would require
additional desktop integration.

Interestingly, systemd also defines dynamically allocated greeter
users specifically for display managers, including GDM, using the
userdb Varlink API.

### My recommendation for Ubuntu Core Desktop

I'd investigate this as a potential architecture:

- GDM / GNOME — Login UI and desktop sessions
- PAM + NSS
  - PAM — pam_systemd_home
  - NSS — nss-systemd
- systemd-homed / systemd-userdbd — Account records, authentication
  and home storage

This would give you a system where human user accounts are managed
independently of the immutable OS image.

In particular, I'd investigate whether you could have:

- No statically provisioned human users in /etc/passwd.
- User accounts stored as JSON records in homed.
- Home directories independently encrypted and portable.
- GDM automatically discovering homed accounts.
- Account creation and deletion through homectl.

The main caveat is that Ubuntu's accountsservice integration and
GNOME's user-management UI would also need investigation. GDM login
compatibility is considerably easier than integrating the entire
desktop account-management experience.

Reference: systemd: UserDB and Desktop Environments — this is
particularly relevant because it discusses exactly how GNOME and KDE
should integrate with homed.

**at the moment ubuntu core desktop uses provd**

Ah, that changes the architectural question quite significantly.

If Ubuntu Core Desktop currently uses provd for user provisioning, I'd
look at whether systemd-homed could eventually replace or complement
it, rather than treating homed as simply another backend for GDM.

There are really three separate responsibilities:

- Provisioning: creating the initial user and configuring the device.
- Identity management: storing account records, credentials and group
  membership.
- Login/session management: authenticating users and starting GNOME
  sessions.

The interesting question is whether these responsibilities could be
handled by systemd components instead of being split between provd,
traditional account files and PAM.

### How the current architecture fits together

The Ubuntu Core Desktop repository identifies ubuntu-desktop-init as
the first-boot setup wizard, with provd providing its backend. provd
has a dedicated user service as well as GDM-related functionality.

That suggests a potentially useful division:

- Keep provd responsible for the provisioning workflow and
  desktop-specific configuration.
- Delegate actual account creation to systemd-homed.
- Let GDM discover accounts through nss-systemd.
- Let PAM authenticate and unlock homed accounts.

This would avoid making provd responsible for maintaining a separate
account database.

### An important distinction

I wouldn't necessarily replace provd.

Its responsibilities go beyond creating a Unix account: it exposes a
gRPC API to the setup frontend and coordinates other desktop
configuration tasks.

I'd instead consider changing its user service implementation:

- Create user — homectl create
- Set password — homectl passwd
- Set real name — homed JSON user record
- Configure home directory — systemd-homed
- Discover users — systemd-userdbd / NSS
- Authenticate — pam_systemd_home
- GDM integration — Existing PAM/NSS interfaces

One caveat: systemd-userdbd is read-only. Actual account creation and
modification must go through homed or another account-management
backend.

### The bigger opportunity

Homed has some features that are particularly attractive for Core
Desktop:

- Self-contained user records rather than mutable /etc/passwd.
- Encrypted, portable user home directories.
- Automatic UID allocation.
- Password-based unlocking integrated with PAM.
- Resource management and per-user storage quotas.

There is also a potential complication: Ubuntu Core Desktop's confined
desktop environment and writable-data layout. You'd need to establish
whether homed's storage backends and mount lifecycle work cleanly with
that architecture.

I'd be interested in one architectural question: are you considering
replacing the current provd user-management implementation with
something more systemd-native, or are you primarily interested in
getting rid of the traditional /etc/passwd and /var/lib/extrausers
account databases? Those lead to slightly different designs.

**The first-boot wizard is supposed to be replaced by the new Ubuntu
Welcome App but I don't know anything about it**

That is an important development, because it potentially changes where
user provisioning belongs in Ubuntu Core Desktop.

If the first-boot wizard is being replaced by the Ubuntu Welcome App,
I'd distinguish between the frontend and its backend. The Welcome App
may take over the onboarding experience without necessarily replacing
provd or its account-management responsibilities.

I'd want to establish whether the new app is intended to be a general
Ubuntu onboarding application or specifically the provisioning
frontend for Ubuntu Core Desktop.

I think the application you're referring to is ubuntu_init.

Canonical's development is in:

    canonical/ubuntu-desktop-provision on GitHub

ubuntu_init architecture overview

There is a potentially confusing naming issue: the old
canonical/ubuntu-welcome repository was archived in 2024. Its
development was consolidated into Ubuntu Desktop Provision.

### What is it?

The ubuntu-desktop-provision repository contains several Flutter
applications:

- ubuntu_bootstrap — Desktop installer UI
- ubuntu_init — First-boot initialization UI
- factory_reset_tools — Factory reset and recovery UI
- ubuntu_provision — Shared provisioning functionality
- provd_client — Client library for the provisioning daemon

The particularly relevant detail is that ubuntu_init already uses provd
as its backend. It communicates with it through gRPC and D-Bus.

### What does this mean for Core Desktop?

The architecture is roughly:

    Ubuntu Welcome / ubuntu_init
      Flutter frontend
        gRPC / D-Bus
    provd
      Provisioning backend
    Operating system
      Users, passwords, system configuration, etc.

This is interesting in the context of your systemd-homed
investigation. Replacing GNOME Initial Setup with the Flutter
application doesn't inherently change account management. The
application can continue talking to provd, while provd could
potentially delegate account creation to systemd-homed.

### What I'd investigate

I'd look at these three things in the source:

- apps/ubuntu_init — how the identity creation page works.
- packages/provd_client — the API exposed to the frontend.
- The provd repository — how user creation and password management are
  actually implemented.

One important observation: the public Core Desktop README still
documents gnome-initial-setup as its first-boot wizard. So I wouldn't
assume the Flutter replacement is already integrated into your current
image.

My instinct is that provd is the more interesting component to
investigate than the Welcome App itself. If its account-management
backend can be made pluggable, you could experiment with systemd-homed
without having to rewrite the onboarding frontend.

**regular ubuntu core already has a system for managing users
"extrausers" - how could this integrate with systemd-homed?**

I think this is where the distinction becomes particularly important:
extrausers and systemd-homed solve overlapping problems, but they have
quite different architectures.

Ubuntu Core's extrausers approach is essentially an extension of the
traditional Unix account database. systemd-homed introduces a separate
identity-management system with richer user records and lifecycle
management.

You could integrate them, but I'd avoid trying to make them two equally
authoritative databases.

### 1. There has already been an experiment specifically for Ubuntu Core

This is actually better than I expected: James Henstridge (Canonical)
experimented with exactly this in December 2023.

Experimenting with systemd-homed on Ubuntu Core — Snapcraft Forum

https://forum.snapcraft.io/t/experimenting-with-systemd-homed-on-ubuntu-core/38019

[fetch this URL for context, and also fetch the links in the post to
"a bit of a pain point" and the github repo]

The experiment was specifically motivated by problems with
libnss-extrausers:

- It had been orphaned upstream since December 2016.
- Account-management utilities needed patches to support the separate
  database.
- Creating users on Ubuntu Core Desktop was particularly troublesome.

He built a Core 24 image with:

- systemd-homed
- libnss-systemd
- Updated /etc/nsswitch.conf

And successfully created a homed account alongside the existing
extrausers account.

For example:

    sudo homectl create james \
        --real-name="James Henstridge" \
        -G sudo \
        --ssh-authorized-keys="$(cat ~/.ssh/authorized_keys)" \
        --storage=directory

The resulting account was visible through ordinary NSS:

    getent passwd james
    # james:x:60136:60136:James Henstridge:/home/james:/bin/bash

Even membership of the existing sudo group worked, despite /etc/group
being read-only. The membership was stored in the homed JSON identity
record.

### 2. How extrausers and homed can coexist

The experiment effectively used two account databases:

    Traditional Core accounts
      extrausers
        /var/lib/extrausers/passwd
        /var/lib/extrausers/group

    New homed accounts
      systemd-homed
        /var/lib/systemd/home/*.identity
        Home directory contains its own .identity record

    NSS
      nss-extrausers + nss-systemd
        Applications, GDM, SSH, sudo
      Ordinary Unix account lookup APIs

The key is NSS configuration. Conceptually:

    passwd: files extrausers systemd
    group:  files extrausers [SUCCESS=merge] systemd
    shadow: files extrausers systemd

The systemd NSS module obtains homed accounts through the userdb/
Varlink interface. The [SUCCESS=merge] directive is particularly
useful for combining group memberships from multiple sources.

### 3. Problems discovered in the experiment

There were some interesting issues worth considering before adopting
this.

- User lookup — Worked
- Group membership — Worked with group merging
- Read-only /etc/group — Worked
- SSH public-key authentication — Home activation was problematic
- Snap confinement — Worked in Core24 snaps
- Older snap bases — NSS lookup didn't work without compatible
  libnss-systemd
- Boot performance — Group merging initially caused slow boot due to
  userdbd startup problems

The SSH issue is especially interesting. Homed couldn't automatically
activate an unencrypted directory home for SSH public-key
authentication without a password. The workaround was:

    sudo homectl activate james

For a graphical desktop using password authentication, this is less
problematic.

### 4. What I'd do for Ubuntu Core Desktop

I see three possible approaches:

Option A: Hybrid migration

Keep the initial provisioning account in extrausers, but create
subsequent desktop users with homed.

Advantages:

- Minimal changes to existing Core infrastructure.
- Existing system users remain untouched.
- Can test GDM and PAM integration independently.

Disadvantage: two account-management systems remain.

Option B: Replace extrausers for human accounts

Use:

- /etc/passwd and /etc/group for system accounts.
- systemd-homed for all human accounts.
- nss-systemd for account discovery.
- pam_systemd_home for authentication.

This is probably the cleanest long-term architecture.

Option C: Extend systemd userdb without homed

You could theoretically use static JSON user records in /etc/userdb or
/var/lib-backed records with a custom userdb provider.

This would give you the richer systemd account representation without
adopting homed's home-directory lifecycle. However, you'd need to
implement account creation, deletion and authentication separately.
userdb itself is read-only.

### 5. One thing I'd investigate before proceeding

The Snap account-control interface currently specifically manages the
extrausers database. If you move to homed, that interface and any
management snaps relying on it would need consideration.

Also, homed's directory storage backend is particularly interesting
for Core Desktop. You could use ordinary directories rather than
individual encrypted home images, relying on Ubuntu Core's existing
full-disk encryption.

That would avoid introducing a second encryption layer.

My preference would be Option B, with a transitional period where the
initial Core provisioning account remains in extrausers.

The really valuable part of James Henstridge's experiment is that it
demonstrates this isn't just a theoretical possibility: homed was
already successfully running alongside extrausers on Ubuntu Core 24.

I'd actually start by retrieving his systemd-homed-experiment branch
and seeing how much of that work can be reused.
