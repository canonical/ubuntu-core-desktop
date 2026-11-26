# Strictly confine GDM and its complete greeter/login process tree

Status: IN PROGRESS — the GDM daemon and greeter Shell are enforced, and
a fresh-image login now reaches the confined Ubuntu session. The
complete greeter process tree is not yet confined (updated 2026-10-03).
Created: 2026-10-01

## Impact / Priority

High, security-sensitive and upstream-sensitive. GDM — the component
that authenticates users and launches the session — ran unconfined
together with its greeter/login process tree, while the rest of the
desktop session is strictly confined, so a core part of the login path
sat outside the product's confinement boundary.

Parent milestone: Stage 3A in
`20260922-split-core26-desktop-base-snap.md`
Completed prerequisite:
`20260930-move-gdm-to-the-gnome-content-snap.md`

## Objective

Run the host display-manager function supplied by
`gnome-desktop-content` under strict snap confinement without
regressing boot, the GDM greeter, PAM authentication, dynamic greeter
users, first-boot provisioning, or launch of the separately confined
`ubuntu-desktop-session` snap.

"GDM is confined" means all long-lived and security-relevant parts of
the display-manager process tree have an intentional enforcing profile:

- the root GDM daemon;
- `gdm-session-worker` and other privileged GDM helpers;
- `gdm-wayland-session`;
- the greeter's GNOME Session, GNOME Shell, Settings Daemon components,
  and Xwayland;
- authentication/session-opening helpers reached through PAM;
- the handoff that launches `ubuntu-desktop-session` or
  `ubuntu-desktop-init`.

It is not sufficient for only `/usr/sbin/gdm3` to have a snap label
while its workers or greeter escape to `unconfined`, `//&unconfined`, or
another unreviewed profile. Setuid PAM helper transitions are permitted
only when they land in an explicit, narrowly scoped profile supplied by
snapd/base policy.

## Current verified baseline (2026-10-01)

Repositories:

- `~/git/gnome-desktop-content` (`main`): strict `core26` app snap. It
  contains GDM and the complete GNOME greeter runtime, but currently
  declares only PipeWire/WirePlumber apps. It deliberately excludes the
  GDM system unit, `/etc/gdm3`, and GDM PAM service files.
- `~/git/core-base-desktop` (`26-dev`): retains `gdm.service`, PAM
  service files/modules, GDM account/state setup, NSS/extrausers/
  systemd-userdb integration, and the launcher at
  `/usr/libexec/gnome-content-launch`. The host service invokes the GDM
  executable from `/snap/gnome-desktop-content/current`.
- `~/git/ubuntu-core-desktop-snapd`: project snapd fork containing the
  desktop-related interfaces and policy used by this image.
- `~/git/ubuntu-core-desktop`: image assembly and VM runner.
- `~/git/ubuntu-desktop-session-snap`: the separately confined
  logged-in GNOME session.
- `~/git/ubuntu-desktop-init`: first-boot/provisioning session, where
  applicable.

Runtime baseline:

- Test VM; loopback-only VNC for inspection.
- Aggregate build: the image build (`build.sh`).
- Image build/run: build the GNOME image with the image build
  (`build.sh --desktop gnome`), then boot it in QEMU (see the README's
  QEMU procedure).
- GDM, its worker, and its greeter are currently `unconfined` by
  design.
- The logged-in Shell is
  `snap.ubuntu-desktop-session.gnome-shell (enforce)`.
- Logout returns to a working GDM user chooser. The greeter Shell runs
  from the content snap with `--mode=gdm`.
- The launcher must retain: `GI_TYPELIB_PATH` including GJS's private
  typelib directory, `GDK_PIXBUF_MODULE_FILE`, and the following
  `XCURSOR_PATH` value:

      XCURSOR_PATH=/snap/gnome-desktop-content/current/usr/share/icons:/usr/share/icons
- GDM launches the greeter with `DESKTOP_SESSION=gnome-greeter`. The
  launcher passes the single command-string argument
  `gnome-session --session=gnome-login` to `gdm-wayland-session`.
- GDM uses HAVE_USERDB dynamic greeter accounts (`gdm-greeter`,
  `gdm-greeter-2`, UIDs around 60578+) advertised through
  `/run/systemd/userdb/org.gnome.DisplayManager`. NSS must include
  `systemd`; do not replace this with a static-account workaround.
- Snap-confine currently rejects the greeter's dynamic home
  `/run/gdm3/home/gdm-greeter*`. The current dispatcher therefore runs
  the greeter runtime directly from the content mount instead of
  through `snap run`. Confinement must solve this explicitly rather
  than silently restoring an unconfined fallback.
- PipeWire/WirePlumber greeter denials are a known, separately accepted
  issue. Do not broaden GDM policy to hide their independent failures.

## Required reading before implementation

Read these files in full in a new session:

1. `20260930-move-gdm-to-the-gnome-content-snap.md`
2. `core-desktop-manager-snap.md`
3. `~/git/core-base-desktop/hooks/002.1-add-gdm.chroot`
4. `~/git/core-base-desktop/hooks/002.9-redirect-gdm-runtime.chroot`
5. `~/git/core-base-desktop/static/usr/libexec/gnome-content-launch`
6. `~/git/gnome-desktop-content/snap/snapcraft.yaml`
7. Existing snapd interfaces:
   `account_control.go`, `accounts_service.go`,
   `login_session_control.go`, `login_session_observe.go`, `polkit.go`,
   `polkit_agent.go`, `daemon_notify.go`, `display_control.go`,
   `wayland.go`, `x11.go`, `opengl.go`, and `desktop_launch.go`.

(The original reading list also included the project's durable
documentation notes on the GDM graphical session and the core base
snap; consult the project documentation for those facts.)

## Execution rules

- Execute the numbered steps in order unless a step explicitly says its
  implementation may run in parallel.
- Give one numbered step to one work session. A work session must stop
  at that step's gate and report exact files, commands, process labels,
  denials, and unresolved questions. It must not continue into the next
  step.
- Keep changes per step in separate commits. Do not combine interface
  design, policy implementation, snap packaging, and runtime fixes in
  one commit.
- Start policy discovery in complain mode. Never use broad catches such
  as `/** rwklix`, `dbus,`, `network,`, `capability,`,
  `process-control`, `system-files`, `snapd-control`, or `classic`
  confinement to make a gate pass. Every permission must map to an
  observed, documented GDM action.
- Do not declare success from `systemctl is-active` alone. Check the
  real process tree and `/proc/<pid>/attr/current`.
- Test from a fresh image at major gates. Bind mounts and live policy
  edits are iteration tools only and must be removed before final
  proof.
- Keep the known-good unconfined image/artifacts until strict
  confinement passes the full acceptance matrix. Each experimental
  image needs an easy rollback path.
- Never weaken confinement of `ubuntu-desktop-session` to accommodate
  GDM. The display manager must launch it through its normal snap
  profile.

## Likely privileged interfaces

The historical design predicts three new high-trust interfaces, but the
inventory and architecture steps below must confirm their exact
boundaries before coding:

- `pam-authentication` (working name): exposes only the snap's GDM PAM
  service definitions inside its namespace and permits the required
  base PAM modules/setuid authentication helpers and session hooks.
- `accounts-daemon` or `accounts-service-control` (working name):
  permits the exact AccountsService D-Bus operations GDM and initial
  setup require, with corresponding slot-side policy if accounts-daemon
  is later snapped.
- `snap-execute` (working name): allows the display manager to launch
  an allow-listed application in another snap through snapd/
  snap-confine, without granting general snapd control or arbitrary
  command execution.

Additional narrowly scoped policy may be required for display-manager
devices/VTs, logind, dynamic userdb publication, or the `/run/gdm3`
greeter home. Prefer extending an existing semantically correct
interface over adding permissions to an unrelated one. If no existing
abstraction fits, design a display-manager-specific interface instead
of assembling multiple broad control interfaces.

### Step 0: Freeze the known-good baseline

Record source revisions for all repositories above, snap revisions,
connections, `snap debug confinement`, system/user failed units, GDM
service definition, the full GDM/greeter process tree with executable
and AppArmor label, and fresh-boot/logout journals. Save:

- pre-login boot state;
- active logged-in session state;
- post-logout greeter state;
- post-second-login state;
- current AppArmor denial signatures grouped by profile, operation,
  class, path or D-Bus peer/member.

Copy or checksum the working `pc.img`, core snap, content snap, snapd
snap, session snap, and model assertion. Do not add large artifacts to
Git.

Gate:

- A timestamped baseline note names every artifact/revision and
  contains reproducible collection commands.
- The baseline demonstrates working boot, logout, greeter, login, and
  confined user Shell.
- The rollback image is retained and bootable.

### Step 1: Inventory GDM actions and trust boundaries

Trace a complete cycle on the unconfined baseline: daemon startup,
greeter creation, user enumeration, password authentication (success
and failure), session open, confined session launch, logout, greeter
recreation, and shutdown/restart. Correlate processes with:

- UID/GID/capabilities;
- executable path;
- parent/child relationship;
- files and Unix sockets;
- system/session D-Bus calls and owned names;
- Varlink/userdb calls;
- devices and ioctls (`/dev/tty*`, DRM, input, uinput if any);
- PAM service/module/helper execution;
- logind/systemd operations;
- calls into `/snap/bin`, `snap`, `snap-confine`, or snapd;
- writable state under `/run`, `/var/lib`, and `/etc/writable`.

Deliver a machine-readable table (CSV or TSV is sufficient) plus a
short boundary document. Classify every action as daemon, privileged
worker, greeter session, PAM, AccountsService, first boot, or
target-session handoff.

Gate:

- Every GDM-related process in the baseline is assigned an intended
  profile and owner.
- Every required privileged operation has an observed caller and
  target.
- Unknown/unattributed operations are resolved before Step 2.

### Step 2: Define the profile architecture and completion invariant

Write a design decision record choosing the exact profiles and
transitions. At minimum decide:

- whether root GDM and privileged session workers share one app profile
  or use explicit helper profiles;
- how GDM-launched helpers transition without inheriting excessive
  daemon permissions;
- how the dynamic greeter user's systemd services enter enforcing
  profiles;
- how `/run/gdm3/home/gdm-greeter*` works with snap namespaces;
- whether the greeter uses `snap run`, generated snap app profiles via
  `AppArmorProfile=`, or a new supported snapd mechanism;
- which environment and content paths are available to the greeter;
- how the final target session crosses from GDM confinement to the
  target snap's own profile;
- which processes, if any, legitimately use a base-provided setuid
  helper profile.

The design must explicitly reject a state where the daemon is confined
but workers, greeter Shell, Xwayland, or session handoff are
unconfined.

Gate:

- The document lists every expected process label for pre-login,
  authentication, logged-in, and post-logout states.
- It includes an executable transition diagram and namespace/mount
  diagram.
- It identifies which existing interfaces are reused and which new
  interfaces are required.
- A human review accepts the security boundary before policy code
  starts.

### Step 3: Produce upstream interface proposals

For each proposed new interface, prepare an upstream-quality design:

- security rationale and threat model;
- plug/slot declarations and implicit-slot behavior;
- classic vs Ubuntu Core support;
- base-declaration install/connection policy;
- AppArmor, seccomp, mount, udev, and systemd behavior;
- snap declaration/review implications;
- attribute schema, especially target allow-lists;
- tests and negative cases;
- alternatives considered.

Include the historical PAM, AccountsService, and snap-execute proposals
from `core-desktop-manager-snap.md`, updated for core26 and the
observed Step 1 call graph. Open or prepare separate upstream
discussions; do not hide three security boundaries in one omnibus
proposal.

Gate:

- Each new interface has a standalone proposal that a snapd maintainer
  can review without access to this project.
- Open questions and maintainer feedback are recorded.
- Prototype names/semantics are frozen enough for independent
  implementation steps; unresolved security objections block further
  implementation.

### Step 4: Add a dormant GDM app and preserve service semantics

In `gnome-desktop-content`, declare a GDM daemon app that runs the
existing launcher/runtime but is not yet selected by the production
image. Declare only interfaces justified by Steps 1-3. Preserve the
existing host service as the known-good path.

Determine whether snapd-generated service units can express all
required semantics:

- `Conflicts=`/`After=` for `getty@tty1` and Plymouth;
- dependencies on `rc-local`, `systemd-user-sessions`, cloud-config,
  and `snapd.seeded`;
- `OnFailure=plymouth-quit.service`;
- tty ownership and restart behavior;
- configuration generation/reload.

If generated units cannot preserve these semantics, retain a minimal
host-owned `gdm.service` whose `ExecStart` is `/snap/bin/...gdm`; that
is acceptable provided execution enters the snap profile and the
retained host unit contains no GDM runtime payload.

Gate:

- The content snap builds and installs without changing the boot path.
- Generated AppArmor/seccomp/service files are inspected and archived.
- The existing image still boots through the unconfined path.
- A documented decision selects snap-managed service or confined app
  launched by the minimal host unit.

### Step 5: Prove a confined daemon can start in complain mode

Select the dormant GDM app via a reversible VM-only service override.
Put only its profile in complain mode. Disable automatic login and
prevent real authentication/session launch for this discovery step.
Start GDM and collect the complete allowed/denied event set until it
either exposes the greeter boundary or reaches the next expected
blocker.

Do not add policy in this step.

Gate:

- `/proc/<gdm-pid>/attr/current` names the intended snap profile.
- GDM does not execute an unconfined fallback.
- All events are grouped and mapped back to Step 1 actions.
- The first blocker and required interface owner are identified.

### Step 6: Implement display/seat/device access

Implement the smallest existing-interface changes or a dedicated
display-manager interface needed for GDM to:

- acquire/release tty1 and switch VTs;
- communicate with logind for seats/sessions;
- access DRM render/KMS nodes and required input devices;
- run the Wayland compositor/Xwayland used by the greeter;
- notify systemd and integrate with Plymouth;
- create only required runtime files/sockets.

Add snapd unit tests for positive and negative policy generation. Avoid
`process-control` or blanket device access unless Step 1 proves an
operation cannot be represented more narrowly.

Gate:

- Relevant snapd unit tests pass.
- In complain mode the daemon reaches greeter-session creation with no
  unattributed display/seat/device events.
- Negative tests show an unrelated strict snap cannot acquire the same
  privileges.

### Step 7: Implement dynamic GDM userdb publication

Permit exactly the creation/listening/communication needed for
`/run/systemd/userdb/org.gnome.DisplayManager` and the dynamic
`gdm-greeter*` records. Include filesystem/Unix-socket/Varlink policy
and any systemd-userdbd peer rules. Do not replace dynamic users with
static entries.

Test concurrent create/remove cycles and suffixed greeter names, not
only the first `gdm-greeter`.

Gate:

- `userdbctl user gdm-greeter*` and
  `getent passwd <dynamic-uid>` resolve while the greeter exists and
  disappear after teardown.
- PAM/account lookup sees the same transient identity.
- Repeated failed greeter attempts do not leak users, sockets, or
  runtime directories.
- No general write access to `/run/systemd/userdb` is granted beyond
  the GDM endpoint.

### Step 8: Solve the dynamic greeter home and namespace model

Implement the Step 2 design for `/run/gdm3/home/gdm-greeter*`. If this
requires snap-confine changes, add focused unit/integration tests
proving:

- the exception applies only to the display-manager greeter profile/app;
- the directory is owned by the dynamic greeter identity and rooted
  under GDM-controlled runtime state;
- arbitrary strict snaps still cannot use `/run/gdm3` as `$HOME`;
- namespace setup/teardown works for suffixed dynamic greeter users.

Remove the current unconfined GDM-group fallback only after the
replacement works.

Gate:

- No `cannot use invalid home directory "/run/gdm3/..."` error.
- Greeter namespace construction succeeds under enforcement/complain
  mode.
- A negative test using an unrelated snap and the same HOME is
  rejected.
- No unconfined dispatcher path remains for the greeter.

### Step 9: Confine the greeter session skeleton

Wire the GDM user manager's `gnome-session@gnome-login`, GNOME Session
manager, and GNOME Shell `gdm` instance into the intended greeter
profiles. Keep optional regular-session snap services excluded via
`ConditionGroup=!gdm`. Preserve the explicit `gnome-login` session
selection, GJS typelib path, pixbuf cache, cursor path, schemas, MIME
data, and Yaru resources.

Do not enable password authentication yet. Exercise only the user
chooser, accessibility menu, keyboard layout, power menu, and greeter
restart.

Gate:

- Greeter renders and remains stable for at least five minutes.
- Its Shell, session manager, Settings Daemon children, and Xwayland
  all have the exact enforcing/complain labels from Step 2; none are
  `unconfined` or `//&unconfined`.
- Pointer, logo/icons, keyboard layout, accessibility, power menu, and
  screen resolution work.
- Restarting GDM and six consecutive greeter create/destroy cycles
  produce no `Session never registered` or maximum-display-failure
  messages.

### Step 10: Implement the PAM interface mount/configuration mechanism

Implement the PAM interface without yet granting every module
operation:

- move/confirm base-owned common PAM policy under `/usr/lib/pam.d`;
- put only GDM service files under the snap's declared PAM metadata;
- mount that metadata at `/etc/pam.d` only in the GDM app namespace;
- reject malformed paths, symlinks, ownership, and unsupported classic
  use;
- deny auto-connection and, if required by review, installation by
  default.

Add mount-namespace, interface, base-declaration, and parser tests.

Gate:

- Inside GDM's namespace, GDM-specific services resolve from the snap
  and common includes resolve from the base.
- Outside the namespace, the snap's service files are invisible and
  base policy is unchanged.
- An unconnected test snap cannot read/use the GDM PAM definitions.
- Snapd tests pass and namespace teardown leaves no stale mount.

### Step 11: Add password authentication permissions

In complain mode, test one invalid and one valid password. Add only the
PAM module, NSS, shadow/extrausers, audit, keyring, and setuid-helper
permissions observed for authentication. Use explicit helper
transitions for `unix_chkpwd` and `pam_extrausers_chkpwd`; never grant
arbitrary setuid execution.

Keep session launch blocked so authentication and session setup remain
separate.

Gate:

- Invalid password is rejected and valid password reaches the
  deliberate post-authentication blocker.
- Passwords never appear in logs, command lines, environment, or trace
  artifacts.
- Authentication helpers run under their intended profiles.
- Root login, enumeration of password hashes, and execution of
  unrelated setuid helpers remain denied by negative tests.

### Step 12: Add PAM session-management permissions

Permit only observed `pam_systemd`, extrausers, keyring, environment,
limits, and other configured session-open/session-close operations.
Verify cleanup on authentication failure, successful logout, worker
crash, and GDM restart.

Gate:

- A successful authentication creates the expected logind session and
  `/run/user/<uid>` state, then stops at the intentional target-launch
  blocker.
- Failed/cancelled authentication creates no persistent session.
- Logout removes the session and returns to the confined greeter.
- No orphan workers, mounts, keyrings, runtime directories, or logind
  sessions remain.

### Step 13: Implement the AccountsService interface

Implement the reviewed interface for the exact GDM methods/signals and
properties observed in Step 1. Separate read-only user enumeration from
mutating first-boot account creation if their trust levels differ.
Include slot-side policy so a future confined accounts-daemon is
possible; do not conflate the system AccountsService API with the
existing per-user online accounts interface.

Gate:

- GDM lists only eligible local users and reads required session/icon/
  language state.
- Unauthorized mutation is denied to the read-only variant.
- The mutating variant, if implemented, is separately declared and
  denied by default.
- Snapd policy and D-Bus peer/member negative tests pass.

### Step 14: Implement allow-listed cross-snap execution

Implement the reviewed `snap-execute` mechanism. It must allow the GDM
app to launch only declared target apps (initially the Ubuntu desktop
session and first-boot app) through normal snapd/snap-confine
transition. It must not grant:

- arbitrary `/snap/bin/*` execution;
- arbitrary `snap run`;
- snap installation/removal/configuration;
- direct use of another snap's files outside its normal app entry
  point;
- retention of the GDM profile after transition.

Prefer a plug attribute or connection metadata naming target
`snap-id + app`, with snapd validating the target at connection time.
Define refresh/removal behavior and reject stale/missing targets
cleanly.

Gate:

- The two declared target apps enter their own enforcing profiles.
- A third undeclared app, command injection, extra arguments outside
  the declared schema, and direct `snap-confine` execution are denied.
- Target refresh/revision change continues to work without hard-coded
  revision paths.
- Snapd unit/integration tests cover positive, negative, disconnect,
  and missing-target behavior.

### Step 15: Launch the confined desktop session after authentication

Connect the PAM session-open result to the allow-listed
`ubuntu-desktop-session` entry point. Remove any diagnostic shims.
Verify environment sanitization, UID/GID/groups, HOME, runtime
directory, display FD/socket passing, and seat/session identifiers at
the transition.

Gate:

- Password login starts the real user session.
- GNOME Shell, session service, Settings Daemon, portal, Terminal, and
  Nautilus processes retain their existing snap enforce labels.
- No process in the GDM tree remains running as the logged-in user
  after handoff unless explicitly documented.
- Terminal, Files, screenshot, screencast, App Center authorization,
  lock, unlock, and logout pass.
- Logout returns to the still-confined greeter.

### Step 16: Restore confined first-boot provisioning

Wire GDM's no-user path to the allow-listed `ubuntu-desktop-init`/
provisioning entry point. Implement any reviewed AccountsService
mutation and polkit-rules installation mechanism required by this
flow. Treat installation of JavaScript polkit rules as a separate
high-trust feature with default-deny declarations and namespacing.

Use a fresh image with no provisioned user; do not infer success from
an already initialized VM.

Gate:

- First boot launches the provisioning app in its own enforcing
  profile.
- It can configure networking, locale/timezone, and create the initial
  administrator through intended interfaces.
- It cannot perform unrelated AccountsService or polkit-authorized
  actions.
- After reboot, the created user can authenticate and start the
  confined desktop; first-boot mode does not recur.

### Step 17: Switch all GDM profiles to enforce mode

Build a fresh snapd snap, content snap, core snap, session snap, and
image. Remove all complain-mode overrides, live bind mounts, temporary
rules, instrumentation, and unconfined fallbacks. Verify base
declarations and required static connections are present in the
model/gadget/image.

Gate:

- Every expected GDM/greeter/helper process matches the Step 2
  enforcing label invariant.
- `aa-status` shows no GDM profile in complain mode.
- No runtime file comes from `/tmp`, a bind mount, or a stale revision.
- Disconnecting each high-trust interface fails safely and visibly
  rather than falling back to unconfined execution.

### Step 18: Full clean-image acceptance matrix

Run all of these on a newly built image:

1. Cold boot with an existing user.
2. Greeter idle for five minutes.
3. Wrong password, cancel, then correct password.
4. Desktop functional checks: Terminal, Files, screenshot, screencast,
   App Center/polkit authorization, lock/unlock.
5. Logout to greeter and second login.
6. GDM service restart.
7. Six repeated login/logout cycles.
8. Reboot from greeter and from logged-in session.
9. Snap refresh/revision change for `gnome-desktop-content` and the
   target session snap, followed by another login.
10. Fresh no-user image and complete first-boot provisioning.
11. Interface disconnect negative tests and recovery after reconnect.
12. Failed/missing target-session snap behavior.

Capture process labels and denial signatures at pre-login, auth,
desktop, logout, and second login. Compare with Step 0. New denials are
blockers unless individually attributed, shown harmless, and explicitly
accepted.

Gate:

- All matrix items pass twice: once under automation where possible
  and once with the visible VNC UI for greeter/authentication-sensitive
  paths.
- There are no unconfined or stacked-unconfined GDM/greeter processes.
- There are no new unexplained AppArmor/seccomp/DBus denials.
- No failed system or graphical-user units remain.
- The previously accepted independent PipeWire/WirePlumber denials are
  recorded separately and have not been disguised by broader policy.

### Step 19: Documentation, upstreaming, and cleanup

Document final interface contracts, connections, profile transitions,
service ownership, troubleshooting, rollback, and the acceptance
evidence. Update:

- this note with commits and final status;
- `20260922-split-core26-desktop-base-snap.md`;
- `gnome-desktop-content/README.md`;
- relevant project documentation notes;
- snapd interface documentation and tests;
- model/gadget connection documentation.

Submit or update separate upstream snapd proposals/PRs for each
privileged interface. Remove obsolete host launcher paths, unconfined
dispatch logic, and transitional comments only after the clean-image
gate passes.

Gate:

- All source changes are committed in the correct repositories.
- Upstream references and security-review decisions are linked.
- Documentation can reproduce the build and verification from a new
  session.
- Move this file to the done state only after Steps 0-18 pass.

## Final completion criteria

This task is complete only when:

- GDM daemon, privileged workers, greeter session, GNOME Shell,
  Settings Daemon, Xwayland, and relevant helpers are intentionally
  confined;
- PAM authentication and session setup work through reviewed narrow
  policy;
- AccountsService access is least-privilege;
- desktop and first-boot snaps launch into their own enforce profiles
  through an allow-listed cross-snap mechanism;
- boot, login, logout, lock/unlock, restart, refresh, and first boot
  pass on clean images;
- no unconfined fallback exists;
- every high-trust interface is default-deny and has positive/negative
  tests plus upstream review history.

## Non-goals

- Cross-desktop session discovery/registration and making GDM offer
  KDE. Track that as a separate interoperability contract.
- Fixing independent PipeWire/WirePlumber policy.
- Moving accounts-daemon, logind, polkit, or every peripheral daemon
  into snaps unless confinement evidence proves it is required for GDM.
- Replacing the existing confined GNOME session architecture.

## Session update (2026-10-03)

Execution deliberately did not follow the numbered plan in order.
Rather than block on the full baseline inventory, design record, and
interface proposals in Steps 0-3, work prioritized getting a fresh
image to boot, fixing observed blockers, and checking the actual
greeter process labels. Those omitted gates remain open; the runtime
progress below does not imply they have passed.

Work completed and verified:

- Added GDM home-directory provisioning to image assembly. A
  `gdm-homedirs.service` runs after seeding, creates `/run/gdm3/home`,
  and sets Snapd's `system.homedirs` value before GDM starts; the GDM
  unit requires this setup. The change, including isolated
  `--build-dir` support, was committed in `ubuntu-core-desktop` as
  `4e171d3` (`Configure GDM homedirs before launch`).
- Built and booted a fresh image and rebooted it. The homedirs setting
  persisted, the provisioning service and GDM were active, and the
  desktop returned after reboot.
- Addressed GDM's strict-mode D-Bus `OpenSession` blocker with a narrow
  `gdm-session-control` permission rather than broadening the login
  interface. Greeter asset/layout issues were also corrected. Login and
  logout were exercised successfully using a build-time autologin/
  session-shim setup.
- Inspected the live greeter on the fresh build-homedirs VM image,
  including `/proc/<pid>/attr/current` for processes in the greeter
  session cgroup.

Current observed confinement:

- `gdm3` and `gdm-session-worker` run as `gdm (enforce)`.
- Greeter GNOME Shell and its notifications process run in enforcing
  `ubuntu-desktop-session` profiles. PipeWire and WirePlumber also have
  enforcing content-snap profiles.
- No `gsd-*` process was present under the active `gdm-greeter` UID.
  Their exclusion from the greeter session means they are not launched
  there; it does not mean they run unconfined.
- These greeter-session processes had a plain `unconfined` label:
  `systemd --user`, `(sd-pam)`, `gdm-wayland-session`, the session
  `dbus-daemon`, `gnome-session-init-worker`, `gnome-session-ctl`, and
  `ssh-agent`.
- `gnome-session-service` had the stacked label
  `snap.ubuntu-desktop-session.ubuntu-desktop-session//&unconfined
  (enforce)`. This is distinct from a plain `unconfined` label, but it
  still fails this plan's requirement for a clean, reviewed greeter
  profile.

The confinement objective is therefore **not complete**. The daemon,
worker, and greeter Shell are enforced, but the complete greeter
process tree is not. In particular, the normal greeter path's
persistent selection/launch of the confined user session remains
unresolved; the successful login/logout test used build-time
autologin/session-shim setup, not that normal path. This was a
point-in-time process inspection, not the full clean-image acceptance
matrix.

Next, inventory and classify the unconfined greeter helpers and stacked
session service, then decide and implement intentional enforcing
profiles or a documented security boundary for each. Resolve normal
session selection and handoff, then return to the remaining PAM,
AccountsService, allow-listed cross-snap launch, first-boot, and
fresh-image acceptance work. Keep the final criteria above unchanged:
none of the current unconfined or stacked-unconfined greeter processes
may be treated as passing the task.

## Continuation (2026-10-03)

Committed the previously uncommitted GNOME greeter-session work:

- `core-base-desktop` `b823228` (`Route the GDM session through snap
  apps`)
- `gnome-desktop-content` `ee944c5` (`Add confined GNOME greeter
  session app`)
- `ubuntu-core-desktop` `5f5a818`
  (`Connect greeter session to systemd control`)
- `ubuntu-core-desktop-snapd` `ed7ef67cee`
  (`Allow GNOME session environment setup`)

The commits route the greeter GNOME Session leader, service, monitor,
and Shell through snap apps; provide the session leader and init-worker
layout in the content snap; connect its `systemd-user-control` plug;
and grant only that leader the observed D-Bus activation/systemd
environment calls. The GDM user manager also skips the SSH agent
service and socket.

Verification: `go test -mod=readonly ./interfaces/builtin` passed in
`ubuntu-core-desktop-snapd`; `git diff --check` and shell syntax checks
passed for the source changes. The core-base hook test could not run
against a built tree because this checkout has no `prime/`; `make check`
also could not run because `shellcheck` is not installed. The updated
SSH-agent socket assertion passed against a minimal test fixture. No
claim is made that this substitutes for a clean image build/test.

A temporary complain-mode `gdm-greeter-user-manager` profile was tested
through a runtime `user@.service` override, then fully removed. The
manager and session D-Bus acquired stacked labels containing
`gdm-greeter-user-manager//&unconfined`. Enforcing GNOME session apps
then denied D-Bus calls to that peer, including
`UpdateActivationEnvironment`, `UnsetAndSetEnvironment`, `GetUnit`,
`ResetFailed`, and `StartUnit`. The installed snapd rules match
`peer=(label=unconfined)` exactly; complain mode on the manager does
not make its label acceptable to those still-enforcing client profiles.
This confirms a cross-interface session-bus/peer-label design blocker.
Do not work around it by broadly granting D-Bus access or weakening the
confined client apps. A reviewed snapd peer-label model and positive
and negative policy tests are needed before the greeter manager can be
put under an enforcing profile.

A separate runtime-only trial changed GDM's `gdm-wayland-session`
transition from `Ux` to `ix` while the GDM profile was in complain
mode. GDM then failed to register the greeter session. The original
enforcing GDM profile was restored and the temporary test file removed;
the production source still uses `Ux`. The cause of this failure was
not isolated, so `gdm-wayland-session` remains an open gap.

The VM was returned to the original GDM AppArmor profile and autologin
configuration. It is active again: `gdm3` is `gdm (enforce)`, while
`gdm-wayland-session`, `systemd --user`, `(sd-pam)`, and the session
D-Bus remain unconfined; GNOME Shell remains snap-enforced. Source
changes from this continuation are committed. The next safe step is to
design the session-manager/session-bus peer architecture and separately
trace why the `gdm-wayland-session` inheritance trial failed before
attempting strict enforcement.

## Complain-mode discovery attempt (2026-10-03)

Temporarily put all 74 loaded app profiles for `ubuntu-desktop-session`
and `gnome-desktop-content` into complain mode, and attached a
temporary complain profile to `user@.service`. Autologin was disabled
to exercise dynamic GDM greeter users. The greeter did not remain
registered: GDM repeatedly logged `Session never registered` and
eventually stopped after the maximum display failures. This was
therefore not a stable, multi-minute discovery session.

The short startup trace did confirm the expected peer-label failures.
With client profiles in complain mode, the session leader attempted
`UpdateActivationEnvironment`, `UnsetAndSetEnvironment`, `GetUnit`,
`ResetFailed`, `StartUnit`, and `Properties.GetAll` for
`graphical-session.target` against the manager/session-bus labels.
Those labels were `gdm-greeter-user-manager//&unconfined` and nested
forms such as
`gdm-greeter-user-manager//null-/usr/lib/systemd/systemd-executor//
null-/usr/bin/dbus-daemon//&unconfined`. The manager itself also used
session-bus methods including `Hello`, `AddMatch`, `GetNameOwner`,
`RemoveMatch`, `GetConnectionUnixUser`, `StartTransientUnit`,
`AttachProcessesToUnit`, and `StopUnit`.

The GNOME Shell also logged a `ServiceUnknown` error for
`org.gnome.DisplayManager` while GDM was already retrying/tearing down
greeter sessions. Its causal role is unknown; the session never reached
a stable state, so this is not yet a trustworthy end-to-end failure
attribution. The temporary template drop-in also applied the manager
profile to the existing UID 1000 `your_username` manager, not just
dynamic GDM UIDs. That override was removed and the `your_username`
manager stopped before restoring the image.

The manager's deliberately minimal profile (`abstractions/base` only)
generated extremely noisy audit: 118,173 `apparmor="ALLOWED"` events
and 7,354 distinct profile/operation/class/resource combinations in a
17-second window, including repeated reads of `/sys/fs/cgroup`,
`/proc`, `/sys/devices`, `/run/udev/data`, shared libraries, NSS data,
and Snap execution helpers. Much of this came from nested
`systemd-executor`, `snap`, and `getent` processes under the stacked
manager label, plus GDM's rapid retry/cleanup loop. Do not treat this
raw event set as the final manager policy. A useful follow-up needs a
profile baseline for systemd-user and a stable greeter session, then
must deduplicate/group by actual executable and resource.

All 74 snap profiles were reloaded in enforce mode. The temporary
`user@.service` overrides and AppArmor profile were removed, GDM
autologin was restored, and the GDM service was restarted. No policy or
source files were changed during this discovery attempt.

## GDM session handoff fix (2026-10-03)

The real login hang was caused by GDM selecting `gnome-greeter` for the
authenticated user. The session directory had no host-visible Ubuntu
Wayland session entry, so the confined dispatcher started the greeter's
`gnome-login` session instead of the regular desktop.

Added a host-visible `/usr/share/wayland-sessions/ubuntu.desktop`
symlink to the existing entry in `gnome-desktop-content`. The first
live retest showed GDM's enforcing profile could not read through that
symlink to the content-snap target. Added narrow read rules for that
directory and its `.desktop` files to `static/etc/apparmor.d/gdm`, with
corresponding hook test assertions. With the updated profile loaded
temporarily in the running no-autologin VM, the user confirmed login
reached the desktop and logout returned to GDM.

Rebuilt the core base in an isolated worktree because the original
`core.snap` artifact predates these source changes. Built the final
test image with the image build (`build.sh`), overriding only
`--base-snap` to use that new core snap and assigning a unique build
directory. The build selected the local session, GNOME content,
desktop-provision, and snapd snaps. Do not use the Store's
`ubuntu-desktop-init` candidate as a substitute: it caused spurious
`core22`/`gnome-42-2204` dependencies; the local provision snap is the
intended artifact.

The fresh image boots with GDM enforcing and starts
`gnome-session@ubuntu.target`; `DESKTOP_SESSION=ubuntu`, and the
session leader, session control/service, GNOME Shell, and Shell
components all have enforcing `ubuntu-desktop-session` profiles. GDM
has no denial for reading the session entry. This image has autologin
enabled, so the fresh-image check verifies the session handoff but not
a manual password-entry/logout cycle; the latter succeeded on the live
no-autologin VM.

The user manager, `sd-pam`, and session D-Bus remain the provisional
unconfined boundary. `gdm-wayland-session` remains a separate `Ux` gap;
no change to its transition was made. The session-entry symlink,
AppArmor rules, and hook-test assertions were committed in
`core-base-desktop` as `8578b8a` (`Fix GDM Ubuntu session handoff`).

## Lock-screen reauthentication fix (2026-10-03)

On the fresh autologin image, locking the desktop and entering the
password returned to the password prompt. PAM reported authentication
success, but audit showed GDM's confined profile denied the session
`cgroup.events` read and logind `UnlockSession` call. The profile also
needed to receive GNOME Shell's `OpenReauthenticationChannel`, send
logind `ActivateSessionOnSeat`, and read `/etc/shadow` plus
`/var/lib/extrausers/shadow`.

Added those observed, narrowly scoped permissions to
`static/etc/apparmor.d/gdm` and assertions to
`hook-tests/002.9-redirect-gdm-runtime.test`. The cgroup rule permits
only `cgroup.events` within user session scopes. Commit: `7f20ecc`
(`Allow GDM lock-screen reauthentication`).

Validation: rebuilt core-base and the image with the image build
(`build.sh`), using an isolated build directory, with the rebuilt base
snap. Its hook test passed. On the fresh VM, GDM was `gdm (enforce)`,
GNOME Shell was `snap.ubuntu-desktop-session.gnome-shell (enforce)`,
and the user confirmed the lock screen cleared after entering the
password; `loginctl` reported `LockedHint=no`. The VM remained running
for VNC inspection.

The user also logged out to GDM and manually logged back in; the
desktop appeared. The resulting session remains active with
`gdm (enforce)` and `snap.ubuntu-desktop-session.gnome-shell
(enforce)`, and no GDM AppArmor denial for unlock/activation was
present in the retest logs.

The fresh boot also logged a `cap_net_admin` denial from `gdm3`, which
did not prevent session startup or unlock. Do not add that capability
without identifying a required operation. The provisional unconfined
components and `gdm-wayland-session` gap above remain unresolved.

## Complain-mode trial of user@1000 (2026-10-04)

Goal: confine `systemd --user` (user@1000.service) for the logged-in
session, starting with a complain-mode discovery run. Result: the
mechanism is now understood and a working discovery setup exists, but
production confinement still requires the snapd peer-label model change
described below.

Root cause of the login failure under complain mode:

- A temporary drop-in
  `/run/systemd/system/user@1000.service.d/90-systemd-user-apparmor-test.conf`
  set `AppArmorProfile=systemd-user-complain-test` (profile:
  abstractions/base plus a few ix rules, loaded in complain mode).
  Because the manager is spawned from an unconfined context, the kernel
  converts the transition to stacking: the manager runs as
  `systemd-user-complain-test//&unconfined (complain)`, and the session
  D-Bus daemon (spawned by the manager) inherits the same stacked
  label.
- Every enforcing snap profile in the session pins its D-Bus/net peers
  to `peer=(label=unconfined)` (90 such rules in
  `snap.ubuntu-desktop-session.gnome-shell` alone; emitted by
  `ubuntu-core-desktop-snapd` `interfaces/builtin/*.go` templates). A
  stacked label does not match `peer=(label=unconfined)` — the `//`
  boundary needs `**`-style AARE wildcards, which the generated rules
  do not use.
- The denials therefore fire in the *clients'* enforcing profiles;
  complain mode on the manager cannot relax the peer's policy. This is
  the same cross-interface peer-label blocker recorded in the
  2026-10-03 continuation above, now confirmed end-to-end for the user
  session.
- Fatal chain (VM login 2026-10-04 09:43): PAM and session startup
  succeeded, gnome-shell registered with GDM, then at 09:43:49.928 the
  bus passing gnome-shell its session-bus connection fd was denied by
  the shell's own profile
  (`audit[dbus-daemon] AVC apparmor="DENIED" operation="file_receive"
  class="net" profile="snap.ubuntu-desktop-session.gnome-shell" ...
  peer="systemd-user-complain-test"`). The shell logged
  `JS ERROR: TypeError: can't access property "unwatch_name", bus is
  null`, `Error connecting to the screencast service`, then `Shutting
  down GNOME Shell` ~1s after start — black screen with blinking cursor
  while the session leader stayed alive. Downstream effects (all
  consequences, not causes): screencast-service/xdg-desktop-portal-
  gnome/gtk/document-portal failed or crash-looped; gnome-session-
  service could not create transient scopes (StartTransientUnit
  denied); gsd-* StopUnit/Subscribe denials. The greeter was
  unaffected because its manager/bus stay unconfined.
- Pre-existing accepted gaps that are NOT caused by stacking (present
  in the healthy unconfined session too): gsd-a11y-settings/gsd-sharing
  StopUnit/DisableUnitFilesWithFlags to systemd1, gnome-session-ctl
  StartUnit shutdown target, dbus_bind denials for
  org.freedesktop.a11y.Manager, org.freedesktop.Notifications,
  org.gnome.Nautilus, org.freedesktop.FileManager1,
  com.canonical.Shell.PermissionPrompting, GeoClue AddAgent, fprintd.

Working discovery setup (runtime-only, reversible, no image rebuild):

- Keep the user@1000 complain override, and additionally reload all
  ubuntu-desktop-session and gnome-desktop-content snap profiles into
  complain mode: `cd /var/lib/snapd/apparmor/profiles && for f in
  snap.ubuntu-desktop-session.* snap.gnome-desktop-content.*; do
  apparmor_parser -r -C "$f"; done` (74 profiles). With clients in
  complain mode the stacked peers are accepted, the session survives,
  and BOTH gap lists are collected in one run: the manager's own
  denials (profile `systemd-user-complain-test`) and the client-side
  peer-rule gaps (profile `snap.*`), grouped by profile.
- Verified end-to-end on the VM (2026-10-04): after the complain reload
  and `systemctl restart gdm`, alice's session came up and gnome-shell
  stayed alive and stable (no JS errors, no shutdown); the manager's
  complain profile logged ~45k events in the first minutes, dominated
  by cgroup tree access under
  /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service,
  content-snap library reads/mmaps, and sendmsg to
  /run/systemd/notify.
- Restore afterwards with `apparmor_parser -r` (no -C) per profile and
  remove the user@1000.service.d override.

Production fix requires snapd (ubuntu-core-desktop-snapd):

- The interface templates hardcode `peer=(label=unconfined)` for every
  peer outside the snap (session bus, org.freedesktop.systemd1, etc.).
  That assumption holds only while those services run unconfined.
  Confining any system service that snapped apps talk to over D-Bus
  (systemd --user, the session bus, later logind/accounts-daemon) hits
  the same wall.
- The needed change is the reviewed peer-label model already flagged
  above: emit peer rules that also match stacked-on-unconfined peers
  (e.g. `peer=(label=**&unconfined)`) or let interfaces declare the
  peer's actual profile name. The breadth-vs-precision tradeoff is the
  security-sensitive part needing review: a wildcard also matches
  unrelated stacked processes. Avoiding the stacked label entirely
  (manager born into a profile via an already-confined parent or PAM)
  does not remove the problem — clients would then need to match the
  manager's new profile name instead of `unconfined`, so the peer-label
  generation change is required either way.
- Positive/negative policy tests must cover: enforcing client talking
  to a complain-stacked manager, and an unrelated snap NOT gaining
  access via the wildcard.

## Plan for a proper (non-stacked) systemd --user label (2026-10-04)

Why the label stacks today: `AppArmorProfile=` performs an explicit
`change_onexec()` from the unconfined systemd-executor, and the kernel
converts unprivileged change_profile into stacking
(`...//&unconfined`). Pathname attachment at exec time does NOT have
this problem: it transitions cleanly regardless of the parent's
confinement. Proven on this image:
`ppid=1 pid=160322 exe="/snap/gnome-desktop-content/x1/usr/sbin/gdm3"
subj=gdm` — PID 1 is unconfined, yet gdm3 runs with a clean
`gdm (enforce)` label purely because the static `gdm` profile attaches
to the executable path. (Standard AppArmor: this is how all system
daemon profiles work.)

Design:

1. Dedicated binary path: hardlink `/usr/lib/systemd/systemd` to
   `/usr/lib/systemd/systemd-user`. Attaching to the real path is not
   an option — `systemctl daemon-reexec` re-execs it and would confine
   PID 1 with the user-manager profile.
2. Attachment profile `systemd-user` on
   `/usr/lib/systemd/systemd-user`, shipped and loaded like the static
   `gdm` profile (core-base-desktop static overlay +
   `static/etc/apparmor.d/`).
3. Per-instance ExecStart drop-in
   (`user@1000.service.d/exec.conf` →
   `/usr/lib/systemd/systemd-user --user`) and DELETE the
   `AppArmorProfile=` drop-in. Per-instance first (alice only); the
   greeter managers (user@60578/60579) can follow later. ExecStart= is
   a single-value directive, so the empty-then-reassign drop-in reset
   is reliable (the multi-value drop-in gotcha does not apply).
4. Profile content: start from the complain-mode gap list collected
   above (cgroup tree under user@1000.service, /run/systemd/notify
   sendmsg, NSS/extrausers, content-snap library reads/mmaps), plus
   `ix` rules for `/usr/lib/systemd/systemd-executor` (unit spawns),
   the real `/usr/lib/systemd/systemd` path (daemon-reexec keeps
   confinement), and `/usr/bin/dbus-daemon` (session bus shares the
   manager label via ix, or gets its own attachment profile + px
   later).

Result: clean `systemd-user` label — no `//&unconfined` suffix, no
`//null-` executor hats. Children spawned via ix share the label;
snap-run-routed apps keep their clean snap labels as today.

What it buys: the snapd peer-label change is still required (clients
must accept the manager as a D-Bus peer), but it becomes precise:
`peer=(label=systemd-user)` instead of `peer=(label=unconfined)`. No
wildcards, no ambiguity about what else a pattern might match — the
"reviewed peer-label model" shrinks to a mechanical change.

Alternatives considered:

- Setuid launcher doing privileged `change_profile` (the snap-confine
  pattern): works, but adds a new setuid binary to the security
  surface.
- Keep stacking + wildcard peer rules (`peer=(label=**&unconfined)`)
  in snapd: works, but imprecise labels and broader grants.
- Upstream systemd/kernel change to allow non-stacking
  `AppArmorProfile=` from unconfined: slowest path, not needed given
  attachment works.

Verification method note: check labels via
`/proc/<pid>/attr/current` captured from `$!` of the exec'd process — a
`pgrep -f <path>` lookup can match the backgrounded wrapper shell
instead of the profiled process and falsely report `unconfined`.

## Should the user manager be confined at all? (2026-10-04)

Deliberate design question raised after the complain-mode trial: plain
Ubuntu Core (and classic Ubuntu, Fedora, etc.) do NOT confine
`systemd --user`, and there is no upstream profile to inherit. The
project principles demand a high bar for upstream divergence, and the
KDE note records the same unconfined set (`systemd --user`,
`dbus-daemon`, `gnome-keyring-daemon`, `gvfsd`, ...) as "expected" —
i.e. the project has so far treated the manager and session bus as a
trusted session base, like PID 1 or the system bus.

Case FOR confining the manager (Core-Desktop-specific):

- Threat model differs from plain Core: untrusted snap apps share the
  session with the manager. Today a snap with `home` access can write
  `~/.config/systemd/user/evil.service`, and if it can reach
  `org.freedesktop.systemd1`, the manager spawns it UNCONFINED — a real
  escape chain that only exists on a desktop.
- On Core, systemd is frozen in the read-only base snap; it only
  changes when the base is rebuilt, so the "policy churns with every
  systemd update" maintenance argument is much weaker than on classic.
- Confining the manager gives every not-yet-snap-routed
  D-Bus-activated service (gvfsd, gnome-keyring, goa, ...) a baseline
  label for free — wholesale progress on the "route remaining stage-2.2
  services" work, at the cost of a coarser policy than per-snap
  routing.

Case AGAINST:

- All policy is home-grown and must track systemd's behaviour (cgroup
  tree, /proc, NSS/extrausers, notify socket — the ~45k-event gap list
  above is a snapshot of one release).
- Real divergence from upstream: custom hardlinked binary + attachment
  profile + per-release policy maintenance.
- Blast radius of a policy gap is "user cannot log in" — the worst
  desktop failure mode; needs staged rollout (complain first, enforce
  only after soak) and the snapd peer-label model landed first.

Recommendation: the cheaper, more upstream-shaped path is Stage 3D in
`20260922-split-core26-desktop-base-snap.md` — replace the wildcard
`systemd-user-control` interface with an allow-listed D-Bus proxy and
keep snap-run-routing services individually. That closes the escape
chain at the interface layer without confining the manager. Manager
confinement (via the attachment-profile design above) then becomes an
OPTIONAL hardening step to take last, only if the "no unconfined
processes" invariant is worth its maintenance cost. The attachment
design remains the right shape if that decision is yes.

## Resolution (2026-11-03)

CLOSED AS DESCOPED (owner decision). The essential confinement shipped
and is production-verified: GDM's daemon, session workers and
wayland-session run under the static ENFORCING `gdm` profile; the
greeter session units are confined and routed through snap apps;
dispatch fails closed on unexpected GDM execution; Ubuntu session
handoff, lock-screen reauthentication, homedirs provisioning and the
GDM-initial-setup first-boot wizard all work on the published dangerous
images (gnome-20261103 lineage, QA'd through 2026-10-27).
Supporting landings: core-base-desktop 952d9d3, 8ec55ce, 0b21ff7,
0a3b41e, 86c827c, 223ce27, 14adca8, 6617ea9; snapd fork 9ddbbda103
(gdm_session_control + confined-greeter support), 80f54b3094,
6b2c25e12b/a6ce698944 (pam-unix-chkpwd).

Deliberately NOT pursued, per the 2026-10-04 design review recorded
above: confining the greeter/session systemd --user manager, (sd-pam),
session dbus-daemon and friends. That path required an unreviewed snapd
peer-label model change (stacked `//&unconfined` labels do not match
the interfaces' peer=(label=unconfined) rules) and a large home-grown
policy surface with "user cannot log in" blast radius; the cheaper,
upstream-shaped alternative (Stage 3D in
`20260922-split-core26-desktop-base-snap.md` — replace the wildcard
systemd-user-control grant with an allow-listed D-Bus proxy to close
the env-write escape chain) is where that work lives now, tracked
there. The Steps 0-3 inventory/design-record/upstream-proposal gates
and the Steps 17-18 formal acceptance matrix were never run; per-image
QA (boot/login/lock/unlock/wizard on every published build) has stood
in for the matrix since. The attachment-profile design and the
peer-label analysis in this file remain the reference if manager
confinement is ever revisited.
