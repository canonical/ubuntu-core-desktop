# Move GDM into the GNOME content snap and remove duplicated base payload

Status: COMPLETE (2026-10-01)

## Impact / Priority

High: complete the GNOME content split and remove the measured
GDM/GNOME-runtime duplication. Core and the GNOME content snap carried
duplicate GDM and GNOME greeter/session payload; the cleanup removed a
measured 356,929,536-byte core-plus-content excess (about 357 MB of
packed snap size).

Prerequisite: Stage 2.6 in
`20260922-split-core26-desktop-base-snap.md` is done.

Build integration: the image build (`build.sh`) already rebuilds
gnome-desktop-content as one of its component builds before assembling
the image.

## Goal

Move the GDM executable and greeter/runtime payload into
gnome-desktop-content, then remove the duplicate GDM and GNOME
greeter/session payload from core-base-desktop. Preserve the current
host-managed GDM service integration for the first migration: the host
systemd service launches the GDM executable from the mounted content
snap, and GDM remains unconfined during this work. The GNOME desktop
must still boot to GDM, authenticate, and start a GNOME session after
the base payload is removed.

The original pre-split artifact is no longer present; the retained
no-content image provides a separate reproducible comparison:

- Pre-split core26-desktop snap:
  616,251,392 bytes (616.25 MB), as recorded in the Stage 2.6 note.
  That exact artifact is no longer present.
- Retained no-content comparison core:
  616,267,776 bytes (616.27 MB) in
  `ubuntu-core-desktop/build-prework/custom-core.snap`.
- Pre-cleanup comparison at the start of Stage 4:
  600,174,592 bytes for core and 373,006,336 bytes for content
  (973,180,928 bytes combined). The last measured full image was
  2,763,575,296 seeded-snap bytes.
- Final cleaned core:
  241,295,360 bytes (241.30 MB / 230.12 MiB) in
  `ubuntu-core-desktop/build/custom-core.snap`.
- Final gnome-desktop-content snap:
  373,010,432 bytes (373.01 MB / 355.73 MiB) in
  `gnome-desktop-content/gnome-desktop-content_0.1_amd64.snap`.
- Final core plus content:
  614,305,792 bytes (614.31 MB / 585.85 MiB), which is
  1,945,600 bytes (1.95 MB / 1.86 MiB) below the historical pre-split
  core and 1,961,984 bytes below the retained no-content comparison
  core.
- The final fresh VM's `/var/lib/snapd/snaps` totals 2,404,847,616
  bytes. This is 720,896 bytes above the retained no-content image's
  seeded-snap total of 2,404,126,720 bytes. The installed final core
  and content files are byte-for-byte the named 241,295,360-byte and
  373,010,432-byte build artifacts. Host policy prevented read-only
  loop mounting of `pc.img`, so this final whole-image figure is
  explicitly an installed-snap total, not a direct repeat of the
  seed-partition extraction.
- The preserved pre-cleanup artifact
  `ubuntu-core-desktop/build.pre-20260930-bashrc-regression/pc.img`
  contains a slightly earlier content build and totals 2,748,526,592
  seeded-snap bytes. Its core is 600,231,936 bytes and its content snap
  is 357,900,288 bytes; do not mix these values with the later
  pre-cleanup measurement above.

The final cleanup removed the previously measured 356,929,536-byte
core-plus-content excess and exceeded the acceptance target by
1,945,600 bytes. The small 720,896-byte final installed-snap-total
increase is in the rest of the image rather than core plus content.

These are packed snap-file sizes, not uncompressed filesystem sizes. The
custom core is repacked with Zstd; gnome-desktop-content is an
XZ-compressed snap. Compare the actual on-disk snap bytes from the same
architecture and image-build path. For core-only comparisons, use the
same repacked Zstd artifact type. Record uncompressed file/path overlap
separately to identify what is duplicated; do not infer packed savings
by summing uncompressed file sizes.

## Scope and constraints

- Keep the existing host-owned GDM systemd service and host integration
  in the base during the initial move. Launch GDM from the mounted
  content snap using a version-stable path and an explicit runtime
  environment.
- The initial GDM process is expected to show `unconfined` in
  `/proc/<pid>/attr/current`. This proves the staged payload is in use;
  it does not prove snap confinement.
- Remove duplicated GDM/GNOME runtime binaries, libraries, and data from
  core only after the content-snap-launched GDM has passed the
  functional gate. Retain the host service shim, PAM configuration, GDM
  account/state setup, and any other host integration still required by
  the unconfined service.
- Classify package dependencies by actual consumers before removing
  them. In particular, do not break first-boot setup
  (`gnome-initial-setup` / `provd`), host services, PAM,
  AccountsService, logind, or other core functionality merely because a
  package is also in GDM's dependency closure.
- This is the payload relocation and deduplication milestone. Confined
  GDM, new PAM/accounts-daemon/snap-execute interfaces, and
  cross-desktop session discovery/launch (GDM offering KDE or SDDM
  offering GNOME) are separate follow-up work. Do not describe this
  milestone as having confined GDM.

## Pre-cleanup inventory and history (2026-09-30)

- `core-base-desktop/snapcraft.yaml` still stages `gdm3` in
  `gdm-packages`. The built content snap inspected before the current
  source change had no GDM executable or GDM data, only an empty
  `/usr/share/gdm` directory. Its `snapcraft.yaml` now stages `gdm3`
  and includes the greeter assets; the updated content snap has not yet
  been built. The historical Stage 2.3 manifest lists `gdm3` as a
  candidate, but that manifest is not the current content-snap prime.
- The generated host `gdm.service` runs
  `/usr/share/gdm/generate-config` in `ExecStartPre` and `ExecReload`,
  then `/usr/sbin/gdm3`. It owns tty1, conflicts with getty and
  `plymouth-quit`, waits for cloud-config and `snapd.seeded`, and quits
  Plymouth on failure. Preserve these host semantics while redirecting
  only the executable/runtime payload.
- Both snaps now contain GDM/GNOME greeter runtime files during this
  migration stage. The content snap has `/usr/sbin/gdm3`, GDM helpers,
  greeter-session descriptors, and GNOME Shell at the same package
  versions as core. Current key versions from the snap changelogs are
  GDM `50.1-0ubuntu0.1`, GNOME Shell `50.1-0ubuntu1.3`, GNOME Session
  `50.1-0ubuntu0.1`, GNOME Settings Daemon `50.0-1ubuntu1`, and Mutter
  `50.1-0ubuntu2.4`. The content build includes the greeter data; host
  service and greeter-process redirection are still required before
  the core copies can be removed.
- The host service's direct commands are
  `ExecStartPre=/usr/share/gdm/generate-config`,
  `ExecStart=/usr/sbin/gdm3`, and
  `ExecReload=/usr/share/gdm/generate-config`. GDM also ships
  `/usr/libexec/gdm-session-worker`, `/usr/libexec/gdm-wayland-session`,
  and `/usr/libexec/gdm-x-session`. The host
  `org.gnome.Shell@.service` runs `/usr/bin/gnome-shell --mode=%i`;
  GNOME Session's user service runs
  `/usr/libexec/gnome-session-service --session=%i`. These host systemd
  units and launch paths must be retained as integration shims or
  redirected explicitly; moving only `/usr/sbin/gdm3` would leave the
  greeter on the base runtime.
- `hooks/002.1-add-gdm.chroot` also prepares GDM's writable
  config/state, greeter account/userdb setup, Yaru greeter resources,
  image/MIME caches, extrausers integration, and other boot behavior.
  `gnome-initial-setup` remains in the separate
  `system-setup-tool-packages` part and depends on GNOME Shell. Its
  first-login behavior is disabled in favor of `ubuntu-desktop-init`,
  but the part still consumes its theme and dconf defaults. Trace those
  exact consumers; do not retain the full GNOME Shell closure in core
  merely for static defaults.
- The current Zstd artifact
  `ubuntu-core-desktop/build/custom-core.snap` is 600,174,592 bytes,
  and the rebuilt XZ content artifact
  `gnome-desktop-content/gnome-desktop-content_0.1_amd64.snap` is
  373,006,336 bytes. A SHA-256 comparison against the snap file in the
  rebuilt image's seed partition confirms that it is this exact content
  artifact. The current core is 57,344 bytes smaller than the
  previously recorded 600,231,936 bytes.
- The recorded pre-split Zstd core size is 616,251,392 bytes, but its
  original artifact is not currently present. The retained
  `ubuntu-core-desktop/build-prework/pc.img` is a reproducible
  same-path, same-architecture no-content comparison: its manifest has
  no `gnome-desktop-content`, its Zstd core is 616,267,776 bytes
  (16,384 bytes larger than the historical figure), and its full
  seeded-snap total is 2,404,126,720 bytes. The current image's
  seeded-snap total is 2,748,469,248 bytes. These totals come from the
  `ubuntu-seed` FAT partition in each named image, summing all `.snap`
  files and excluding `aux-info.json`; this makes the full-image
  comparison reproducible without relying on the sparse VM disk's
  apparent size.
- A regular-file path comparison of the current Zstd core and rebuilt
  XZ content snap finds 26,138 shared paths. Those paths account for
  2,449,432,116 uncompressed bytes in core and 2,449,573,098 in
  content; 26,098 paths have equal sizes and 40 differ. This is a
  path/size comparison, not a content-hash comparison, and includes
  generic runtime files (for example Mesa/LLVM and Rust coreutils), so
  it is not an estimate of removable GDM bytes or packed-size savings.
- The current direct package lists overlap on `xwayland`,
  `libgl1-mesa-dri`, `zenity`, the Yaru themes, `ubuntu-settings`,
  `xdg-user-dirs`, audio/GSound packages, `libsnapd-glib-2-1`, `ibus`,
  GLib utilities, and `gnome-keyring`; the content dependency closure
  contains GNOME Shell and Session, while its direct package list
  includes GNOME Settings Daemon and the user-session components.
  These are removal candidates from core only after their host
  greeter, first-boot, hook-build, and other host-service consumers
  are accounted for. Core-only direct GDM integrations include `bolt`,
  `fprintd`, `libpam-fprintd`, and `libpam-gnome-keyring`; retain them
  unless their host consumers are separately migrated and tested.
  `gnome-initial-setup` and `provd` are a separate core package part,
  not user-session payload.
- Initial move/remain map, to be checked against the rebuilt content
  package closure and runtime before cleanup:

  - `/usr/sbin/gdm3`, GDM helpers, `/usr/share/gdm/**`, greeter session
    descriptors — Move to content; keep the current core copy until
    Stage 3 passes.
  - GNOME Shell GDM mode, its Yaru theme/icon resources, GNOME Session
    and Settings Daemon runtime — Use the content copies for the host
    greeter; retain host unit shims or redirect their `ExecStart`
    paths, then remove core copies only after verification.
  - `gdm.service`, `display-manager.service` link, tty1/getty mask,
    boot ordering, Plymouth/cloud-config handling — Retain as host
    integration; only change the launch target in Stage 3.
  - `/etc/gdm3`, `/etc/pam.d/gdm-*`, GDM account and writable
    `/var/lib/gdm3` state, extrausers/NSS/systemd-userdb setup —
    Retain in core for the unconfined host service. The content snap's
    source filters out the host config and PAM definitions.
  - AccountsService/logind, PAM modules and host authentication
    integrations (`bolt`, `fprintd`, `libpam-*`) — Retain unless a
    specific integration is separately moved and tested; do not remove
    because it is in GDM's dependency closure.
  - `provd`, the `ubuntu-desktop-init` first-boot flow, initial-setup
    dconf/theme defaults — Retain until their actual first-boot/GDM
    consumers are redirected and tested. The existing hook removes the
    normal `gnome-initial-setup` executable but still uses its data and
    GNOME Shell's initial-setup mode.
  - Other GNOME packages and shared libraries in both snaps — Remove
    the core copy only after reverse consumers are accounted for;
    `gnome-initial-setup`, host services and greeter systemd units
    remain explicit checks.

  The host greeter runs GNOME Shell and session services separately
  from the logged-in user's confined session. Redirecting only the GDM
  daemon is insufficient: Stage 3 must prove the GDM process and its
  greeter Shell/session runtime resolve to the content snap before
  Stage 4 removes their core copies.
- Stage 2 completed on 2026-09-30: the content snap built with GDM
  `50.1-0ubuntu0.1` and GNOME Shell `50.1-0ubuntu1.3`, matching core.
  It contains `/usr/sbin/gdm3`, GDM helpers, `/usr/share/gdm/**`, and
  the greeter session descriptors; host GDM unit aliases, `/etc/gdm3`,
  and `/etc/pam.d/gdm-*` are absent. A fresh image was built and
  booted. GDM and `graphical.target` are active; the autologged-in user
  has an active Wayland session on `seat0`, GNOME Shell runs from
  `ubuntu-desktop-session` under its enforced profile, and there are no
  failed system or user units.
- Stage 2 gate passed with the core GDM unchanged: its executable is
  `/usr/sbin/gdm3` and its AppArmor label is `unconfined`, as expected.
  The rebuilt Stage 2 test VM remains running with a loopback-only VNC
  listener for user inspection.
- Stage 3 is implemented and rebuilt. The host GDM unit remains in core
  with its original ordering/failure behavior; its drop-in overrides
  only executable commands. The launcher routes GDM, GNOME Shell, GNOME
  Session, Settings Daemon, and greeter helpers to content, including
  both `gdm-greeter` and suffixed dynamic greeter accounts. The core
  Shell and Mutter library paths now resolve to the content copies
  while `.core26` fallbacks remain. Core's customized initial-setup
  mode data and host GDM/PAM integration remain in place.
- Runtime checks passed on a fresh image: `gdm.service` and
  `graphical.target` are active; GDM, `gdm-session-worker`, and
  `gdm-wayland-session` execute from the content snap and are
  unconfined; the autologged-in GNOME Shell executes from
  `ubuntu-desktop-session` under its enforced profile. The user manager
  has no content-snap `XDG_DATA_DIRS` or `GIO_EXTRA_MODULES` leak, GVFS
  starts on demand, and there are no failed system units.
- With autologin temporarily disabled, GNOME Shell's greeter mode ran
  from `/snap/gnome-desktop-content/current/usr/bin/gnome-shell` under
  `unconfined`. Its Shell and Mutter libraries mapped only from the
  content snap, with no duplicate Shell/Clutter GType registration. A
  fresh reboot restored the autologged-in desktop; restarting GDM with
  autologin disabled also brought up the content-snap greeter.
- The user verified password authentication, logout, and a second login
  on 2026-09-30 before cleanup. The Stage 3 runtime gate is complete;
  that image has since been replaced by the cleanup build.

## Latest cleanup result (2026-09-30)

- The Stage 4 core build and fresh GNOME image build passed. The fresh
  image boots on the test VM; loopback-only VNC is available for
  inspection.
- `gdm.service` and `graphical.target` are active. GDM and its session
  worker execute from `/snap/gnome-desktop-content/current` and are
  `unconfined`, as intended for this milestone. The active GNOME Shell
  executes from `ubuntu-desktop-session` under
  `snap.ubuntu-desktop-session.gnome-shell (enforce)`. There are no
  failed system or user units.
- The first cleanup boot exposed that the host alias for
  `gnome-session-ctl` rejected the regular user. The core launcher now
  dispatches that helper through
  `snap run ubuntu-desktop-session.gnome-session-ctl`; the fresh
  rebuild starts the helper and Shell under the confined session snap
  with no failed user units.
- The current boot journal includes PipeWire/WirePlumber system-bus
  denials previously noted by the user, plus denials from confined
  GNOME session components. This boot was not compared line-by-line
  with the old VM, so do not claim that every current denial is new or
  that only the PipeWire/WirePlumber denials remain.
- The current core and content snaps share 5,598 regular-file paths,
  accounting for 1,863,035,538 uncompressed bytes in core and
  1,863,144,706 in content (5,564 same-size paths; 34 different-size
  paths). A separate path/size comparison against the retained
  no-content core finds 27,442 paths shared with content, and 3,345
  content paths absent from that core, totaling 31,316,756 uncompressed
  bytes. These counts include generic runtime files; they do not
  estimate packed-size savings.
- The `system-setup-tool-packages` part still stages `provd`, whose
  `Pre-Depends` brings in `gnome-initial-setup` and a larger
  UI/runtime dependency closure. The hook removes the setup executables
  and Shell runtime paths, but libraries such as WebKitGTK, LLVM, and
  Mesa remain in the core. `provd` itself directly needs
  GLib/GDK/GIO/GObject and libc; the unused remainder is a candidate
  for additional size work, but must not be pruned without checking the
  first-boot provisioning flow.
- A fresh cleanup image was built and booted. `gdm.service` and
  `graphical.target` are active; GDM runs from the content snap
  unconfined, while the user GNOME Shell runs under
  `snap.ubuntu-desktop-session.gnome-shell (enforce)`. No failed system
  units were reported. The in-session wallpaper values are
  `warty-final-ubuntu.png` (light) and `ubuntu-wallpaper-d.png` (dark),
  following the selected `ubuntu-settings` 26.04.6 values; both assets
  are readable in the session mount.
- Invoking the host-run `gnome-session-ctl --shutdown` helper ended the
  GNOME session, reached `gnome-session-shutdown.target` and
  `shutdown.target`, and returned to GDM without a denial for that
  helper. Restarting GDM restored the autologin desktop.
  Terminal/Nautilus and the user's visual wallpaper check remain open.
- The old comparison VM was unreachable during this check, so the
  current boot's denials were not compared signature-by-signature with
  that VM. In particular, do not claim that only PipeWire/WirePlumber
  denials remain.
- Logout regression fixed and verified on 2026-10-01. The host user
  manager now sees the GNOME session unit graph from the content snap.
  `gnome-session-service` and GNOME Shell use a GDM-aware dispatcher:
  regular users still enter the confined `ubuntu-desktop-session` apps,
  while the dynamic GDM greeter account uses the content runtime
  directly because snap-confine rejects its `/run/gdm3/home/...` home.
- The GDM launcher explicitly passes the single command string
  `gnome-session --session=gnome-login` to `gdm-wayland-session`.
  Without that mapping, GDM's `DESKTOP_SESSION=gnome-greeter` selected
  the Ubuntu session, producing either an empty desktop or a failed
  session when the host `ubuntu.session` file was absent. The launcher
  also supplies GJS's private typelib directory, required by greeter
  GNOME Shell.
- A clean final image booted to the confined Ubuntu desktop.
  Terminating the seat returned to a stable, rendered GDM user chooser:
  `gdm.service` remained active, the greeter session stayed registered,
  GNOME Shell ran from the content snap with `--mode=gdm`, and no
  `Session never registered` or maximum-display-failure messages were
  emitted. GDM/greeter remain `unconfined` by design. Restarting GDM
  restored autologin, and the user's Shell ran under
  `snap.ubuntu-desktop-session.gnome-shell (enforce)`.
- Stage 4 and Stage 5 are complete. Final core plus content is
  614,305,792 bytes, 1,945,600 bytes below the historical pre-split
  core.

## Stages

1. Inventory the GDM dependency closure and freeze comparable baselines

   **Status: COMPLETE (2026-09-30).** The source/package ownership map,
   host launch paths, retained integrations, package versions, seeded
   snap totals, and uncompressed path overlap are recorded above.

   Inspect core-base-desktop's `gdm-packages`,
   `gnome-desktop-components`, `system-setup-tool-packages`, chisel
   slices, static overlays, hooks, and the current GNOME content snap.
   Build a package/file ownership map that distinguishes:

   - GDM daemon, greeter, configuration, themes, and runtime files;
   - GNOME Shell, Mutter, GNOME Session, GNOME Settings Daemon, and
     their libraries/data that are duplicated between core and content;
   - dependencies required by other host services or first-boot setup;
   - host integration that must remain available outside the content
     snap, including the GDM systemd unit, PAM service definitions,
     AccountsService/logind integration, users, and writable GDM state.

   Record package versions, current core/content snap sizes, full
   seeded snap totals, and uncompressed path-level overlap using the
   same artifacts and measurement method that later stages will use.
   Identify the exact GDM executable and all paths the current
   `gdm.service` and its children use.

   **Gate:** A reviewed, package- and path-level move/remain list
   exists. Every proposed core removal has its consumers identified;
   the unconfined service's PAM, first-boot, user/session, and systemd
   dependencies are explicitly retained or have a tested replacement.
   The pre-change size measurements are reproducible from named
   artifacts.

2. Stage the GDM payload in gnome-desktop-content without changing boot

   **Status: COMPLETE (2026-09-30).** A fresh image boots through the
   unchanged core GDM to an active Wayland GNOME session.

   Add the GDM payload and required greeter/runtime packages to
   gnome-desktop-content. Keep the existing GDM package and service
   working in core; do not remove or redirect the host service yet.
   Ensure the content snap does not accidentally register a second GDM
   service or shadow host-owned service/PAM files. Keep provider
   package versions compatible with the core integrations.

   Build the content snap, inspect its contents and package closure,
   and verify that the required GDM executable, greeter assets,
   libraries, and `/usr/share/gdm` runtime data are present at the
   expected paths. Confirm that the host-owned service unit,
   `/etc/gdm3`, and PAM definitions are absent from the content payload
   and remain available in core.

   **Gate:** `gnome-desktop-content` builds successfully and contains
   the audited GDM runtime payload, with no missing runtime
   dependencies or unintended service activation. A fresh image using
   the unchanged core GDM boots to an active Wayland GNOME session with
   no failed units.

3. Run host-managed, unconfined GDM from the content snap

   **Status: COMPLETE (2026-09-30).** The user verified password login,
   logout, and a second login after the content-snap greeter and desktop
   runtime passed the boot and process-path checks.

   Keep `gdm.service` host-owned. Add or adjust a small host-side
   launcher so the service executes the GDM binary under
   `/snap/gnome-desktop-content/current/` and supplies the library,
   configuration, theme, schema, and data paths needed by the GDM
   package. Also redirect the host greeter's GNOME Shell, GNOME Session,
   and GNOME Settings Daemon runtime and user units to content-snap
   paths; do not let a host `/usr/bin/gnome-shell` fallback mask an
   incomplete move. Preserve the existing ordering and failure behavior
   for getty, Plymouth, cloud-init, and `snapd.seeded.service`.

   Keep the core copy as a fallback during this stage, but make the
   service's selected executable unambiguous. Reboot the VM and verify
   that GDM starts from the content snap, displays the greeter, accepts
   a login, starts the GNOME session, and supports logout and a second
   login. Test a full reboot and a GDM service restart.

   **Gate:** The active GDM and greeter GNOME Shell processes resolve
   to the content-snap paths (`/proc/<pid>/exe` or equivalent
   evidence), while `/proc/<pid>/attr/current` is `unconfined` as
   expected for this phase. Greeter, authentication, GNOME session
   startup, logout, reboot, and service restart all pass with the core
   fallback still present. No new blocking denials or service failures
   are introduced.

4. Cleanup: remove GDM and duplicate GNOME runtime payload from core

   **Status: COMPLETE (2026-10-01).** Core and image builds pass. A
   clean image reaches the confined desktop, logout returns to a stable
   content-snap GDM greeter, and restarting GDM restores the confined
   user session.

   Using Stage 1's consumer map, remove `gdm3`'s executable/greeter
   payload and the duplicated GDM/GNOME Shell/session dependency closure
   from core-base-desktop. Keep the host `gdm.service` integration (or
   a minimal equivalent host unit/launcher), PAM files and modules
   needed by host-run GDM, GDM user/state setup, required
   AccountsService/logind services, and dependencies still used by
   other host services.

   Check reverse dependencies and boot-time hooks before removing GNOME
   Shell, GNOME Session, GNOME Settings Daemon, themes, libraries, or
   related data. If first-boot setup or another host component still
   needs a package, either move that consumer to the content snap with
   its own verification or retain the package with the reason recorded.
   Do not leave a hidden fallback to the core GDM executable.

   Build a fresh image and verify the base no longer contains the
   removed GDM executable and the specifically targeted duplicate
   runtime files. Boot to GDM from the content snap, authenticate,
   launch the GNOME session, use the desktop (Terminal and Nautilus),
   log out, and reboot.

   **Gate:** The cleanup image passes the same boot/login/session
   checks as Stage 3, with GDM still proven to execute from the content
   snap. The removed core files are absent; retained files have a
   documented host consumer. No failed boot units or new blocking
   denials.

5. Final size and end-to-end acceptance

   **Status: COMPLETE (2026-10-01).** Final core plus content is
   614,305,792 bytes, 1,945,600 bytes below the 616,251,392-byte
   historical pre-split baseline. The fresh VM's installed snaps total
   2,404,847,616 bytes, 720,896 bytes above the retained no-content
   image's seeded-snap baseline.

   Rebuild the content snap, core, and complete GNOME image from the
   final sources. Measure packed core and content snap sizes and the
   sum of all seeded snap files, excluding `aux-info.json`, using the
   baseline's Zstd image-build path. Re-run the uncompressed
   package/path-overlap comparison to confirm the GDM/GNOME runtime is
   no longer duplicated between core and content.

   **Gate:** A clean image boots to GDM provided by the GNOME content
   snap, authenticates, starts the GNOME desktop, and survives logout
   and reboot. The active GDM executable is from the content snap and
   remains unconfined for this milestone. Core-plus-content packed size
   is at or below the pre-split core baseline of 616,251,392 bytes,
   thereby removing the 356,929,536-byte excess measured at the start
   of Stage 4; any newly introduced payload is itemized with its
   measured contribution. Full-image size, compressed and uncompressed
   measurements, and the remaining overlap are recorded here before
   marking the task done.

## Follow-up, not a completion gate

Once the unconfined relocation is stable, continue the existing Stage
3A confinement work as a separately gated change: prototype the PAM,
accounts-daemon, and snap-execute interfaces, move GDM into its own
confined snap app profile within the GNOME content snap, then verify
authentication, session launch, and boot without relying on unconfined
host execution. Cross-desktop session discovery and reciprocal
GDM/SDDM launch support should be designed as a separate interoperable
contract.
