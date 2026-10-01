# KDE display manager integration

The KDE image selects SDDM at image-build time. The GNOME image continues
to select GDM. A system supports one display-manager/session pairing:
installing a session snap later does not change the manager, and combining
GNOME and KDE sessions on one image is not a supported configuration.

## Runtime ownership

`plasma-desktop-session` owns the SDDM runtime. Its `sddm-runtime` part
stages Ubuntu's `sddm` package with its Qt 6.10.2 libraries, QPA/Wayland
plugins, and required QML modules under the snap's `sddm/` subtree. This
keeps SDDM on its package-matched Qt runtime instead of the newer Qt 6.11.1
runtime used by Plasma. The KDE image wraps SDDM's privileged helper to
restore the Qt library path SDDM sanitizes, and launches the KWin greeter
compositor with the Plasma provider runtime. The Elarun greeter theme is
staged alongside SDDM so it uses the same Qt 6.10.2 runtime; the Breeze
theme supplied by `plasma-core26-desktop` targets Qt 6.11.1 and is not
compatible with SDDM's runtime.

The session snap exposes `xkbcomp` from `kf6-core26` at `/usr/bin/xkbcomp`
inside its confined app layouts. Xwayland invokes that helper by absolute
path; without it Xwayland exits during keyboard initialization and
KSMServer cannot start.

The confined session snap exposes the Plasma content snap's libinput quirks
and PipeWire client configuration through layouts. The host-side SDDM
compositor selects the available Breeze cursor theme and points libinput
and PipeWire at the same content-snap data through their environment
overrides; it does not add global `/usr/share` links that would conflict
with the confined app layouts. The image also sets the system KWin cursor
theme to `breeze_cursors` so a fresh user session does not request the
unavailable literal theme `default`. It restores the native
`user-session-migration` command instead of the GNOME-only snap app path.
The Plasma content build omits the orphaned DrKonqi Sentry path/timer units
and prevents its Polkit agent from starting in SDDM's greeter user manager.

SDDM itself runs as an unconfined host systemd service, matching the
project's GDM host-service model. `build.sh --desktop kde` extracts the
selected KDE session snap at image-build time to install the host PAM
definitions, sysusers account, helper paths, and writable SDDM
configuration. Its state directory is stored in the KDE session snap's
writable `common` data because the system `/var/lib` is read-only. It
writes the SDDM service and display-manager alias only into the
KDE-specific custom image; none of these files or packages are added to
`core-base-desktop`. The service waits until snap seeding and
cloud configuration have completed, then launches the SDDM binary from the
installed KDE session snap. Its environment selects the SDDM-owned Qt
runtime; KWin is launched with the Qt/QML/plugin runtime from the KDE
content snaps.

The KDE build masks GDM, selects SDDM as `display-manager.service`, and
removes the GNOME Wayland session entry. The GNOME build retains GDM and
removes the Plasma session entry. `--autologin` writes KDE's user and
`plasma-desktop-session.desktop` session into the writable SDDM
configuration; on GNOME it continues to configure GDM and install the
GNOME session launcher shim.

The `plasma-ksmserver`, `plasma-kcminit`, `plasma-shutdown`, and logout
prompt apps select the Wayland Qt platform explicitly. `plasma-shutdown`
also declares the `systemd-user-control` plug needed to query the user
systemd manager during logout.

## Build and runtime verification

Build both KDE snaps first, then create and boot the image:

```sh
cd ~/git/plasma-core-desktop && ./go-build
cd ~/git/plasma-desktop-session && ./go-build
cd ~/git/ubuntu-core-desktop && ./go-build kde && VM_DISPLAY=vnc ./go-run-kde
./go-vnc
```

`VM_DISPLAY=vnc` serves the guest on `localhost:5901`; `./go-vnc` opens
the viewer.

The image builder verifies that the KDE session snap was built from the
current `26-dev` source revision. On the booted VM, verify the selected
manager and autologin Plasma session with:

```sh
scp tools/test-kde-sddm.sh chrb@<vm-address>:/tmp/
ssh chrb@<vm-address> 'sudo bash /tmp/test-kde-sddm.sh chrb'
```

Run the test without a username when autologin is disabled; it then requires
the SDDM greeter PID to remain stable for 10 seconds. The test checks manager
enablement, GDM masking, the active display-manager alias, SDDM runtime
availability, visible Elarun theme assets, and either the greeter process
or an SDDM-created Wayland Plasma session. For a logged-in desktop user, it
also waits for KSMServer to own `org.kde.ksmserver` on the user's session
bus; an activatable-but-not-running service does not pass this check. It
waits up to two minutes for the session manager to start, confirms
user-session-migration completed with the native binary, and rejects the
known missing-runtime messages in the boot journal.

## Source/runtime versions

The verified local source set for this build is:

| Component | Source/revision | Runtime version |
| --- | --- | --- |
| `plasma-desktop-session` | branch `26-dev`, HEAD `5178930` (the SDDM part is a local working-tree change) | `20261001+git5178930` |
| SDDM package | Ubuntu Resolute archive | `0.21.0+git20250502.4fe234b-2ubuntu3` |
| SDDM Elarun theme | Ubuntu Resolute archive, staged with SDDM | `0.21.0+git20250502.4fe234b-2ubuntu3` |
| `plasma-core26-desktop` | branch `26-dev`, HEAD `7f268220` (local Milou-module and unit-cleanup changes) | `20261001` (Plasma 6.7.5) |
| `kf6-core26` | branch `26-dev`, HEAD `48e49fc` | `6.11.1-6.30.0-6.7.5-26.04.2` (Qt 6.11.1 / KF6 6.30.0) |

The KDE content snap versions are local build outputs, not store
revisions. Refresh this table when any package or content snap is rebuilt;
the SDDM package's authoritative version is its staged Debian changelog.

Known limitation: SDDM's Wayland greeter mode is marked experimental by the
Ubuntu SDDM 0.21 package. The rebuilt KDE image passed the booted-guest smoke
test for the autologin Wayland session, native user-session migration,
KSMServer, and Polkit agent; no failed system units or targeted startup
errors remained. The greeter uses the SDDM package-matched Qt 6.10.2 runtime,
while its KWin compositor uses Qt 6.11.1. Update/recovery paths remain
untested.
