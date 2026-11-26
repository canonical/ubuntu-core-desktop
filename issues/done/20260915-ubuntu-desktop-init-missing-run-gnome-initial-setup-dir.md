# First-boot wizard never launches: missing /run/gnome-initial-setup directory

Date: 2026-09-15

## Impact / Priority

On a fresh image with zero local users and `InitialSetupEnable=true`,
the first-boot wizard UI never appears: GDM shows only its
initial-setup background with nothing on top and no error visible
anywhere, so first-boot setup cannot even start. No priority level was
stated in the original note; impact derived from the original note's
described symptoms.

Image: Ubuntu Core Desktop 26 amd64 dangerous (desktop26)

## Summary

To test a rebuild of ubuntu-desktop-init.snap, GDM was configured with
AutomaticLoginEnable=false and InitialSetupEnable=true in
/etc/writable/gdm3/custom.conf, and the existing user account was
removed (accounts-daemon/GDM decide whether to launch the first-boot
flow based on there being zero local user accounts). On reboot, GDM did
launch the initial-setup GNOME Shell mode, but the actual wizard UI
(ubuntu_init, the Flutter app from the ubuntu-desktop-init snap) never
appeared -- just the initial-setup background, indistinguishable from
"sitting at the desktop" with nothing happening.

## Root cause

GDM runs `/usr/libexec/gnome-initial-setup-wrapper` (in this image,
customized to actually exec `/usr/libexec/launch-desktop-provision-init`,
per the "Provd plus scripts to call ubuntu_init in place of
gnome-initial-setup" design in
`splitting-the-core-desktop-base-snap.md`). That wrapper does:

    mkdir -p /run/gnome-initial-setup/desktop-provision
    mkdir -p /run/gnome-initial-setup/.cache
    /usr/libexec/provd &
    until [ -S /run/gnome-initial-setup/desktop-provision/init.socket ]; do
        sleep 1
    done
    ... exec ubuntu_init ...

`/run/gnome-initial-setup` did not exist at all, and nothing on this
image creates it: no systemd tmpfiles.d rule (/usr/lib/tmpfiles.d,
/etc/tmpfiles.d) provides it, and no unit's RuntimeDirectory= covers it
either. Upstream Debian/Ubuntu's actual `gnome-initial-setup` package
normally ships a tmpfiles.d snippet that creates this directory (owned
by the static `gnome-initial-setup` uid 201) before the wrapper ever
runs -- this image doesn't install that package (it uses
ubuntu-desktop-init/provd in its place, per design), and the equivalent
tmpfiles rule for the runtime directory was apparently never carried
over/replicated for the custom setup.

Result: `mkdir` fails with "Permission denied" (mkdir -p can't create a
new top-level directory directly under root-owned /run/), `provd` then
fails to bind its gRPC socket
(/run/gnome-initial-setup/desktop-provision/init.socket) and exits, the
wrapper's `until [ -S ... ]` loop spins forever waiting for a socket
that will never appear, and `ubuntu_init` is never exec'd. GDM shows
only its initial-setup-mode GNOME Shell background with nothing on top
-- easily mistaken for "the desktop" with no error visible anywhere on
screen (this was only diagnosed via the journal, no on-screen error is
shown at all in this failure mode).

A secondary complication observed while diagnosing: each time GDM
(re)starts the initial-setup flow, the actual running session ends up
under a freshly allocated dynamic system user (e.g.
`gnome-initial-setup-2`, uid 60578-60583, differing every attempt) even
though PAM authenticates as the static `gnome-initial-setup` uid 201
account first -- this looks like normal systemd DynamicUser-style
allocation for the greeter-class session, not an actual crash/retry (no
evidence of an actual crash was found once this was checked with the
uid mismatch in mind). This means a fix that only grants uid 201 access
to /run/gnome-initial-setup is not sufficient: whichever transient
system user backs a given GDM invocation must be able to write there,
so any tmpfiles/permissions fix needs to accommodate that this uid is
not fixed across attempts.

## How it was diagnosed and unblocked live

Diagnosed via `journalctl` after regaining a root shell on the VM (SSH
access was unavailable at this point since the user account had been
deliberately removed to test the zero-accounts first-boot trigger; a
netcat reverse-shell listener run from the VM's own graphical terminal,
piped through a FIFO, was used to get back in: `nc -l 4444` on the VM
piped through `/bin/sh -i`, connected to from the host with
`nc <vm-ip> 4444` -- reasonable here since this is our own disposable
local test VM, not a security boundary).

Live workaround applied (not yet persisted into the build):

    mkdir -p /run/gnome-initial-setup
    chmod 1777 /run/gnome-initial-setup
    systemctl restart gdm.service

World-writable+sticky (mode 1777, like /tmp) was used rather than
restricting ownership to uid 201, specifically because of the dynamic
per-attempt uid behaviour noted above -- a fix restricted to uid 201
alone did NOT work (provd still failed to bind after chown'ing the dir
to gnome-initial-setup:gnome-initial-setup with mode 0700; only after
loosening to 1777 did provd bind its socket and ubuntu_init launch
successfully, confirmed reaching the "Choose your language" wizard
page).

## Correct fix

Add a proper tmpfiles.d rule (rather than a live/manual mkdir+chmod)
that creates /run/gnome-initial-setup at boot, e.g. in a snippet
shipped by whichever package/snap owns launch-desktop-provision-init:

    d /run/gnome-initial-setup 1777 root root -

or, if the dynamic-uid behaviour turns out to be avoidable/wrong and
this should really always run as the static gnome-initial-setup (uid
201) account, track down why the session ends up under a different
dynamic uid instead and fix that, then a tighter
`d /run/gnome-initial-setup 0700 gnome-initial-setup gnome-initial-setup -`
would be preferable to a world-writable directory. Also worth checking
whether this tmpfiles rule belongs in the image build (`build.sh`)
(like the existing snap-connect workarounds), the ubuntu-desktop-init
snap itself, or wherever launch-desktop-provision-init/provd is
packaged from -- not yet determined, wasn't chased down this session.

Also unresolved / secondary from this same investigation: the confined
`snap.ubuntu-desktop-session.xdg-desktop-portal-gnome` service
crash-loops during the initial-setup session for the same reason
documented in `20260915-trash-nautilus-apparmor-denied-crash-loop.md` /
`20260915-followup-confined-session-apparmor-gaps.md` (an
invalid-looking `$HOME` under /run/gdm3/home/gnome-initial-setup-2
causes snap's "ensure-dir" mount-namespace setup to fail with
"permission denied"). This did not prevent ubuntu_init's window from
eventually appearing, but it means portal-dependent features (e.g. file
choosers) invoked from the setup wizard may not work correctly. Worth
linking these two items once someone works on the general
confined-session $HOME-path fix.

## Validation

1. Reboot the VM with no local user accounts and InitialSetupEnable=true,
   AutomaticLoginEnable=false, and confirm ubuntu_init's wizard appears
   automatically without any manual directory/permission fixups.
2. Complete the wizard through account creation and confirm it hands
   off cleanly to the normal login greeter afterwards.

## Resolution

Implemented in `core-base-desktop` as
`static/usr/lib/tmpfiles.d/gnome-initial-setup.conf`:

    d /run/gnome-initial-setup 1777 root root -

Final commit: `3f9419e`.

Validation on a rebuilt desktop26 image confirmed that the directory is
created automatically at boot with mode 1777, `provd` binds
`/run/gnome-initial-setup/desktop-provision/init.socket`, and the
`ubuntu_init` wizard process launches under the dynamic
`gnome-initial-setup-2` session UID. Full wizard completion through
account creation could not be confirmed because `ubuntu_init` then hits
a separate unresolved error, `Unknown DConf source: 'line'`, documented
in the follow-up item
`20260916-ubuntu-init-unknown-dconf-source-line.md`.
