# KDE display manager integration

The KDE image selects SDDM at image-build time. The GNOME image continues
to select GDM. A system supports one display-manager/session pairing:
installing a session snap later does not change the manager, and combining
GNOME and KDE sessions on one image is not a supported configuration.

## Runtime ownership

`plasma-desktop-session` owns the SDDM binaries and non-Qt runtime
dependencies. Qt libraries, QPA plugins, and QML modules come from the
KDE content snaps' Qt 6.11.1 runtime. The image wraps SDDM's privileged
helper to restore these paths after SDDM sanitizes its environment, and
launches the KWin greeter compositor with that same runtime. The Breeze
greeter theme is supplied by `plasma-core26-desktop`, matching the Qt
version used by the greeter.

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
manager, Qt runtime, and autologin Plasma session with:

```sh
scp tools/test-kde-sddm.sh chrb@<vm-address>:/tmp/
ssh chrb@<vm-address> 'sudo bash /tmp/test-kde-sddm.sh chrb'
```

Run the test without a username when autologin is disabled; it then requires
the SDDM greeter PID to remain stable for 10 seconds. The test checks manager
enablement, GDM masking, the active display-manager alias, SDDM runtime
availability, visible Breeze theme assets, the absence of bundled Qt
libraries, and Qt 6.11.1 in the live SDDM process. It also checks either the
greeter process or an SDDM-created Wayland Plasma session. For a logged-in
desktop user, it waits for KSMServer to own `org.kde.ksmserver` on the user's
session bus; an activatable-but-not-running service does not pass this
check. It waits up to two minutes for the session manager to start, confirms
user-session-migration completed with the native binary, and rejects known
startup and incompatible-Qt messages in the boot journal.

## Source/runtime versions

The verified local source set for this build is:

| Component | Source/revision | Runtime version |
| --- | --- | --- |
| `plasma-desktop-session` | branch `26-dev`, HEAD `356621b` | `20261001+git356621b` |
| SDDM package | Ubuntu Resolute archive | `0.21.0+git20250502.4fe234b-2ubuntu3` |
| SDDM Breeze theme | `plasma-core26-desktop` content snap | Plasma 6.7.5 / Qt 6.11.1 |
| `plasma-core26-desktop` | branch `26-dev`, HEAD `7f268220` (local Milou-module and unit-cleanup changes) | `20261001` (Plasma 6.7.5) |
| `kf6-core26` | branch `26-dev`, HEAD `48e49fc` | `6.11.1-6.30.0-6.7.5-26.04.2` (Qt 6.11.1 / KF6 6.30.0) |

The KDE content snap versions are local build outputs, not store
revisions. Refresh this table when any package or content snap is rebuilt;
the SDDM package's authoritative version is its staged Debian changelog.

Known limitation: SDDM's Wayland greeter mode is marked experimental by the
Ubuntu SDDM 0.21 package. The greeter and Breeze theme use the Qt 6.11.1
runtime from the KDE content snaps. Update/recovery paths remain untested.
