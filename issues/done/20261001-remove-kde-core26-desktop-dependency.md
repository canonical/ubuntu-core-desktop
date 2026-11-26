# Remove plasma-desktop-session's core26-desktop dependency

Status: COMPLETE (user-directed empirical scope; original broad matrix
superseded)
Created: 2026-10-01
Implements: Stage 2.7 and Stage 2.8 in
`20260922-split-core26-desktop-base-snap.md`

## Impact / Priority

High. The confined KDE session snap still declared the custom
`core26-desktop` base, so the base-split milestones (Stage 2.7/2.8)
could not proceed and the desktop could not move onto the stock `core26`
base until the dependency was removed.

Scope override (2026-10-02): The user rejected exhaustive package/file
inventories and requested preserving the existing KDE image, changing
the session snap to stock `core26`, and testing the candidate VM
directly against the running baseline. This direct dependency-removal
test supersedes the broader inventory, size/overlap, full-clean-
pipeline, GNOME-combination, and update/recovery steps below for this
task.

Ordering:

1. First complete `20260928-switch-from-gdm-sddm-on-kde.md`.
2. Execute this note against that verified SDDM baseline.
3. Complete this before starting `20261001-confine-gdm.md`.

## Objective

Determine whether `plasma-desktop-session` can run on the stock
`core26` base using KDE's existing `kf6-core26` and
`plasma-core26-desktop` content providers, then remove its implicit
runtime dependency on `core26-desktop`. This changes the confined
session snap's base; it does not by itself replace the image/model
system base.

Preserve the existing per-app strict confinement model and the working
SDDM-to-Plasma login path established by the prerequisite work. Start
with a targeted custom-base dependency audit and an unchanged-provider
`base: core26` experiment. Use measured failures, rather than
package-list similarity alone, to decide whether:

1. the existing `kf6-core26` and `plasma-core26-desktop` providers are
   sufficient after small additions;
2. a genuinely desktop-environment-neutral runtime should be split into
   a separate provider; or
3. a KDE-specific third provider is required.

Do not create another KDE content snap by default: KDE already has two
runtime content snaps. Prefer no provider change, then completing an
existing provider, unless measured ownership, ABI, update cadence, or
reuse requirements justify another boundary.

## Completion criteria

This task is complete only when:

- `plasma-desktop-session` declares `base: core26`, not
  `core26-desktop`;
- every runtime path it uses outside stock core26 is supplied by an
  explicit content connection or by the session snap itself;
- `kf6-core26` and `plasma-core26-desktop` ownership is documented and
  non-overlapping except for measured, justified files;
- a clean KDE image boots to a visibly rendered Plasma desktop;
- KWin, Xwayland, plasmashell, kded6, ksmserver, portal-KDE, PowerDevil,
  and the other routed session services use their intended enforcing
  snap profiles;
- Terminal/Konsole, Dolphin, launcher/panel, wallpaper, pointer,
  keyboard shortcuts, logout, second login, screenshot, audio,
  networking, removable media, and a polkit prompt are tested or
  explicitly recorded as pre-existing independent blockers;
- no new unexplained AppArmor/seccomp/D-Bus denials or failed units are
  introduced;
- packed snap/image sizes and uncompressed overlap are recorded against
  a named pre-change KDE baseline;
- the full pipeline succeeds from clean source state, not only from
  reused Snapcraft/LXD state.

## Current architecture and verified facts

Repositories (all under `~/git`):

- `plasma-desktop-session` (`26-dev`): strict session/app snap. It
  currently declares `base: core26-desktop`, `build-base: core26`, and
  mounts:
  - `kf6-core26` at `$SNAP/kf6`;
  - `plasma-core26-desktop` at `$SNAP/plasma`.
  It routes Plasma components through individual snap apps, giving each
  component its own AppArmor profile.
- `plasma-core-desktop` (`26-dev`): builds the
  `plasma-core26-desktop` content snap (slot `plasma-core26`) against
  the local Qt/KF6 SDK snaps. It contains Plasma/KWin/session runtime
  and selected archive dependencies.
- `kf6-core26` (`26-dev`): runtime content snap derived from the KF6
  SDK output; contains matching Qt/KF6 runtime plus xkb/locale data.
- `kde-qt6-core-sdk`, `kde-pyside6-core-sdk`, `kf6-core-sdk`: build-time
  SDK snaps, not image runtime dependencies.
- `ubuntu-core-desktop`: the only image builder/runner for this task.
  Build the image from that repository with the image build
  (`build.sh --desktop kde`) and boot it in QEMU.
- `core-base-desktop`: current custom base. GNOME Stage 3A removed GDM
  runtime from this base; host GDM integration remains and launches GDM
  from `gnome-desktop-content`.
- `gnome-desktop-content`: currently supplies GDM and its GNOME greeter
  runtime for GNOME images. It is not a KDE image dependency after the
  SDDM prerequisite is complete.

Current version set (do not silently downgrade):

- Plasma 6.7.5
- KDE Frameworks 6.30.0
- Qt 6.11.1
- core26 / Ubuntu 26.04 for system libraries

Known component build:

A clean KDE component build builds, in order:

1. `kde-qt6-core26-sdk`
2. `kde-pyside6-core26-sdk`
3. `kf6-core26-sdk`
4. `kf6-core26`
5. `plasma-core26-desktop`
6. `plasma-desktop-session`

The authoritative image assembly and run commands are separate and must
be run from `ubuntu-core-desktop`: build with the image build
(`build.sh --desktop kde`) and boot the image in QEMU.

Do not use `ubuntu-core-desktop-kde`; it is an obsolete project whose
work has already been rolled into `ubuntu-core-desktop`.

The SDKs are staged locally through `.sdk/`; they are not Store runtime
dependencies. The KF6 build has more than 100 parts and clean builds are
slow. Reused LXD state is useful for diagnosis but is not final proof.

Known required Plasma fixes already present in current sources include:

- KWin's `login-session-control` app plug so it can acquire DRM master;
- matching core26 xkbcommon/KF6 runtime;
- Breeze defaults patched to use the shipped `Autumn` wallpaper;
- `breeze-cursor-theme` staged so `breeze_cursors` resolves;
- the Plasma/KWin 6.7.5 forward port for Qt 6.11.1;
- preservation of Plasma's
  `org.kde.private.desktopcontainment.folder` QML module;
- removal of stale service files during `override-prime`;
- vendored Wayland protocol XMLs and the PipeWire/GCC compatibility
  patch.

Known independent issues that must not be misclassified as split
regressions:

- `plasma-powerdevil` restart loop due to session-bus `dbus_bind`
  policy;
- `plasma-polkit-agent` `/proc/<pid>/cgroup` denial and historical
  `libxcb-cursor0` dependency issue;
- KRunner/Milou is deliberately disabled upstream;
- earlier pointer and global-shortcut issues may exist in old
  artifacts, but the current source stages Breeze cursors; verify the
  current clean baseline before carrying them forward.

## Display-manager boundary

This task is about the logged-in Plasma session content split, not GDM
confinement or cross-desktop display-manager design.

`20260928-switch-from-gdm-sddm-on-kde.md` is a hard prerequisite. Its
completed KDE image must use SDDM, must not seed
`gnome-desktop-content`, and must not enable or start GDM. Freeze that
working SDDM login/logout behavior as part of the baseline before
changing the session snap's base.

Do not copy GDM/GNOME greeter payload into a KDE provider, reintroduce
GDM as a temporary workaround, or redesign SDDM in this task. If the
SDDM prerequisite is incomplete or its acceptance tests fail, stop and
return to that note rather than diagnosing the failure as a KDE
content/base problem.

## Required reading for a new session

Read these in full before Step 0:

1. `20260922-split-core26-desktop-base-snap.md`
2. `20260928-switch-from-gdm-sddm-on-kde.md`
3. `20260930-move-gdm-to-the-gnome-content-snap.md`
4. `~/git/plasma-desktop-session/snap/snapcraft.yaml`
5. `~/git/plasma-desktop-session/scripts/run-session.sh`
6. `~/git/plasma-core-desktop/snapcraft.yaml`
7. `~/git/kf6-core26/build.sh` and its metadata
8. the KDE component build script(s) and their environment handling
9. the image build (`build.sh`) in `ubuntu-core-desktop` and its KDE
   model/gadget inputs
10. `20260918-kde-plasma-apparmor-denials.md`

(The original reading list also included the project's durable
documentation notes on KDE, the GDM graphical session, and the core
base snap; consult the project documentation for those facts.)

## Execution rules

- One numbered step is one work assignment; stop at that step's gate
  and report exact evidence before continuing to the next step.
- Steps run in order unless explicitly marked parallel.
- Each implementation step gets its own commit in the repository it
  modifies. Never mix SDK repair, content ownership, session
  conversion, model changes, and policy fixes in one commit.
- Preserve dirty working trees. Before editing, identify tracked
  changes, untracked artifacts, and build-container state. Do not
  discard or fold unrelated work into this task.
- Build artifacts, extracted snaps, SDK staging directories, and logs
  stay untracked.
- Verify the visible desktop. Running daemons do not prove that KWin
  has DRM master or that plasmashell is rendering.
- Use `/proc/<pid>/attr/current` for confinement evidence.
- Use clean builds at baseline and final gates. Incremental builds are
  permitted only for iteration.
- Never solve a missing content path by broadening AppArmor, using
  classic confinement, or restoring `core26-desktop`.
- Treat a missing library/data path and an AppArmor denial as distinct
  hypotheses. Prove which one applies.

### Step 0: Freeze repository and artifact state

Before collecting repository state, verify that
`20260928-switch-from-gdm-sddm-on-kde.md` is complete and that its final
source revisions and accepted exceptions are recorded. Stop if the KDE
image still relies on GDM or `gnome-desktop-content`.

Record branch, HEAD, remotes, dirty status, and worktree path for:

- `plasma-desktop-session`
- `plasma-core-desktop`
- `kf6-core26`
- the three SDK repos
- `ubuntu-core-desktop`
- `core-base-desktop`
- `gnome-desktop-content`

Classify every uncommitted path as source change, local build helper,
generated artifact, diagnostic extraction, or unrelated work. Ignore
`ubuntu-core-desktop-kde` completely; it is not an input, reference, or
fallback for this task. Check that all known runtime fixes listed above
exist in committed source rather than only in LXD state or extracted
trees.

Gate:

- The prerequisite SDDM work is complete, and the KDE build/run path
  uses SDDM without GDM or `gnome-desktop-content`.
- A baseline note lists exact commits and dirty paths for every
  repository.
- No required fix exists only in a generated/extracted directory.
- The active source of truth for image assembly is unambiguous.
- A fresh session can rebuild without guessing which backup/copy to
  use.

### Step 1: Produce a clean pre-change KDE image

Run a clean KDE component build from the frozen revisions to rebuild
the KDE component snaps. Then use only the active combined image
repository: build the image with the image build (`build.sh --desktop
kde`) and boot it in QEMU.

Preserve component logs and checksums/sizes of all produced runtime
snaps and the KDE image. Record the test VM's address/VNC endpoint.

Do not change architecture to make this baseline pass. If the clean
build fails but an incremental build passes, fix reproducibility first
in a separate commit and rerun from clean.

Gate:

- All six component snaps and the image build from clean state.
- The image boots without manually replacing files inside a snap.
- Snap checksums and source revisions are recorded.
- Any clean-build-only fix is committed and the build is repeated.

### Step 2: Verify the visible pre-change desktop baseline

Exercise the current `core26-desktop`-based image:

- boot/login;
- wallpaper, panel, launcher, pointer;
- KWin DRM master and active output/plane;
- Konsole and Dolphin;
- keyboard layout and Meta/application launcher shortcut;
- screenshot;
- audio output enumeration;
- network status;
- removable-media enumeration if test hardware/device is available;
- polkit prompt;
- logout to display manager and second login;
- reboot.

Capture failed units, process executable paths/profiles, and denial
signatures before and after the functional tests. Separate known
PowerDevil/polkit issues from new failures.

Gate:

- A screenshot/VNC observation proves Plasma visibly renders.
- Every core session component has its expected enforcing profile.
- All baseline failures and denials are explicitly catalogued.
- This baseline becomes the regression comparison for later steps.

### Step 3: Extract declared package manifests (Stage 2.7, part 1)

Create normalized package manifests with source locations for:

- all desktop-related `core-base-desktop` parts;
- `plasma-core-desktop` build packages and stage packages;
- `plasma-desktop-session` stage packages, build packages, and apps;
- `kf6-core26` runtime contents and the SDK packages it derives from;
- `gnome-desktop-content` direct stage packages for comparison;
- stock `core26` contents where needed to avoid counting base-provided
  libraries as KDE content.

Keep direct declarations separate from transitive package closures.
Record versions and origins (Ubuntu archive, KDE Neon source build,
local SDK).

Gate:

- Machine-readable manifests are reproducible from named
  files/commands.
- Direct and transitive package sets are not mixed.
- Every package has a provider/repository and version/origin.

### Step 4: Measure artifact-level package and file overlap (Stage 2.7, part 2)

Unsquash the exact baseline artifacts and compare regular paths and
hashes among:

- custom `core26-desktop`;
- stock `core26`;
- `kf6-core26`;
- `plasma-core26-desktop`;
- `plasma-desktop-session`;
- the SDDM runtime/provider fixed by the prerequisite baseline.

Produce:

- identical-path/identical-content overlap;
- same-path/different-content conflicts;
- unique files by provider;
- uncompressed byte totals by top-level package/path family;
- packed snap sizes;
- ELF SONAME/version conflicts;
- QML/plugin/config/data overlaps.

Do not infer packed savings by summing uncompressed files.

Gate:

- Every overlap number names exact artifacts and hashes.
- Same-path/different-content files are separately reviewed.
- The report distinguishes session payload, KDE runtime, generic system
  runtime, and display-manager payload.

### Step 5: Trace actual runtime consumption from core26-desktop

On the baseline VM, for each active Plasma app/profile, capture:

- executable and mapped libraries;
- plugin/QML lookup paths;
- environment variables;
- opened configuration/data files where practical;
- D-Bus/systemd activation files;
- host paths used before the content mounts;
- files resolved specifically from `core26-desktop` rather than stock
  core26 or the two content snaps.

Use confined `snap run --shell` probes and `ldd`/`LD_DEBUG=libs` where
needed. Include inactive-but-required paths for logout, screenshot,
polkit, PowerDevil, portal-KDE, and removable media.

Gate:

- Every non-stock-core runtime dependency has an intended owner.
- No item is classified as required solely because package metadata
  lists it; an actual consumer or activation path is named.
- Unknown lookups are resolved before architecture selection.

### Step 6: Decide content ownership and provider boundaries

Using Steps 3-5, write the Stage 2.7 shared-vs-DE-specific table. At
minimum classify:

- Qt/KF6 runtime;
- Plasma/KWin runtime;
- generic graphics/Wayland/X11 libraries;
- PipeWire/audio;
- portal common frontend vs portal-KDE backend;
- xkb/locale/input data;
- icon, cursor, wallpaper, fonts, MIME, schemas;
- session unit/D-Bus activation files;
- display manager/greeter files;
- system utilities.

Choose one provider architecture and justify it with size, ABI/update
cadence, ownership, and reuse:

- keep two providers and add missing files;
- split a measured DE-neutral provider;
- add a narrowly scoped KDE provider.

Avoid sharing libraries merely because package names overlap: Qt/KF6
and GNOME stacks have different ABI/update ownership. Avoid duplicating
stock core26 content unless the session requires a different version.

Gate:

- The package table completes Stage 2.7's deliverable.
- Every required file family has exactly one intended runtime owner,
  or a documented justified duplication.
- A human accepts the provider boundary before implementation.

### Step 7: Freeze the completed SDDM handoff contract

From the completed SDDM prerequisite, record the exact service, greeter
runtime owner, Plasma session metadata, wrapper command, PAM path, and
image/model integration used to launch `plasma-desktop-session`.
Repeat cold boot, login, logout, and second-login checks immediately
before the session-base conversion. Do not change the display-manager
architecture in this step.

Gate:

- Cold boot, SDDM login, logout, and second login work on the
  pre-conversion session.
- SDDM ownership and the Plasma session content ownership are separate
  in the architecture diagram.
- Neither GDM nor `gnome-desktop-content` is installed, enabled, or
  used by the KDE image.

### Step 8: Add provider completeness tests

Before changing content, add build-time tests to the chosen provider
repos for every critical runtime family discovered in Step 5:

- binaries and ELF libraries/SONAME links;
- Qt plugins and QML modules;
- Plasma/KWin plugins;
- xkb/locale data;
- Breeze icons/cursors and selected wallpaper;
- Wayland protocol/runtime data;
- systemd user units and D-Bus service files;
- portal-KDE files;
- MIME/schema/font caches where applicable.

Add absence tests for service files that must remain session-owned or
host-owned.

Gate:

- Tests fail against an intentionally removed representative file.
- Tests pass against the unchanged baseline providers.
- The test names state why each file family is required.

### Step 9: Fill `kf6-core26` runtime gaps

Implement only the ownership changes assigned to `kf6-core26`. Preserve
the matching Qt 6.11.1/KF6 6.30.0 ABI and xkb/locale fixes. Do not copy
Plasma-owned QML/modules into KF6 merely to satisfy a lookup.

Build the runtime from a freshly built or checksum-verified KF6 SDK,
inspect its prime, and run its completeness tests.

Gate:

- `kf6-core26` builds reproducibly.
- ELF/QML/plugin probes resolve within the intended KF6 content root.
- No new same-path/different-content conflicts with Plasma provider
  exist without an explicit exception.
- Artifact size delta is recorded and attributed.

### Step 10: Fill `plasma-core26-desktop` runtime gaps

Implement only the ownership changes assigned to the Plasma provider.
Preserve the current forward-port, Wayland protocol, PipeWire/GCC,
folder containment, Autumn wallpaper, Breeze cursor, and stale-prime
fixes.

Audit every `ignore-modules` entry: if the build assumes an archive
package provides runtime data, ensure a matching `stage-packages` entry
or another named provider exists.

Gate:

- Clean provider build and completeness tests pass.
- KWin/plasmashell can resolve their plugins, QML, wallpaper, and
  cursor from an isolated content-root probe without
  `core26-desktop`.
- Artifact size delta and new package closure are recorded.

### Step 11: Convert `plasma-desktop-session` to stock core26

Change the session snap to `base: core26` and remove the custom-base
workaround. Preserve both existing content plugs and add only the
provider plug selected in Step 6, if any.

Update all required runtime variables and layouts:

- `PATH`
- `LD_LIBRARY_PATH`
- `QT_PLUGIN_PATH`
- `QML2_IMPORT_PATH`
- `XDG_DATA_DIRS`
- `XDG_CONFIG_DIRS`
- `XDG_DESKTOP_PORTAL_DIR`
- `XKB_CONFIG_ROOT`
- `XLOCALEDIR`
- cursor/icon/font/MIME/schema paths if Step 5 showed explicit needs.

Do not leave `/usr` fallbacks that happen to work only in
`core26-desktop`. Add build tests that reject the old base and stale
`plasma-core24`/`kf6-core24` identifiers.

Gate:

- Snapcraft metadata validates with `base: core26`.
- The session snap builds without temporarily swapping back to
  `core26-desktop`.
- Inspection shows all content plugs and paths use core26 names.
- No custom-base files are copied into the session snap as a shortcut.

### Step 12: Audit every app's interface and content attachment

For each `apps:` entry, verify:

- the command exists in the session/provider mount;
- required plugs are attached to that app, not merely declared
  globally;
- required slots (Wayland/X11/desktop) are attached;
- systemd/D-Bus activation points to the snap app;
- it does not execute a host path unavailable under stock core26;
- environment overrides do not bypass the chosen content roots.

Pay special attention to KWin DRM/logind access, portal-KDE,
PowerDevil, polkit agent, KSMServer, KDED, and launcher/global
shortcuts.

Gate:

- A generated app matrix covers every app.
- `snap connections` expectations are explicit.
- No required permission/content dependency exists only at top-level
  metadata without attachment to the consuming app.

### Step 13: Update model, gadget connections, and image assembly

Make the active `ubuntu-core-desktop` builder include exact local
artifacts for:

- `kf6-core26`;
- `plasma-core26-desktop`;
- `plasma-desktop-session`;
- the SDDM runtime/provider established by the prerequisite work;
- any newly justified shared provider.

Add static gadget connections or the existing dangerous-model
connection workaround for every required interface. Preserve existing
GNOME entries; KDE support must be additive, not a fork. Reject stale
artifacts by embedded source revision/checksum where the builder
supports it.

Gate:

- The assembled seed/model contains the intended snaps exactly once.
- All content and critical interface connections are established
  before GDM/session startup.
- A deliberately stale or missing provider causes image assembly to
  fail clearly, not boot into a partial desktop.

### Step 14: Build the converted stack incrementally

Build in dependency order using checksum-verified SDK/runtime
artifacts. First build providers, then session, then image. Use
incremental builds for iteration, but record which LXD state was
reused.

Inspect each snap before booting:

- metadata/base/content plugs/slots;
- key files;
- service/activation files;
- package versions;
- no custom-base dependency.

Gate:

- All artifacts build successfully.
- Static inspection catches no missing critical path or stale core24
  name.
- Checksums and sizes are recorded for the candidate artifacts.

### Step 15: First boot and early failure triage

Boot the candidate image and verify in order:

1. seeding/connections complete;
2. display manager starts;
3. authentication/session wrapper selects Plasma;
4. KWin acquires DRM master and publishes an output;
5. plasmashell's render thread is active;
6. panel/wallpaper/pointer are visibly rendered.

Stop at the first failed layer. Do not patch multiple layers in one
iteration. Classify failures as content path, ABI/version, activation,
interface connection, AppArmor/seccomp, display-manager handoff, or
pre-existing baseline issue.

Gate:

- A visible Plasma desktop appears on the candidate image.
- The first successful boot required no live file replacement.
- Every fix made during triage is committed and rebuilt before
  continuing.

### Step 16: Verify confinement and denial regression

Capture the complete Plasma process tree and
`/proc/<pid>/attr/current`. Compare against Step 2 for KWin/Xwayland,
plasmashell/kioworkers, KDED, KSMServer, KCMinIt, KActivityManager,
proxies, portal-KDE, PowerDevil, and polkit agent.

Capture AppArmor/seccomp/D-Bus denials before interaction and after the
functional suite. Fix only new split-induced denials here. Keep the
known PowerDevil/polkit work separate unless a content change altered
it.

Gate:

- No previously confined component becomes unconfined or
  `//&unconfined`.
- No new unexplained denial signature exists.
- Failed units match only explicitly accepted pre-existing baseline
  issues.

### Step 17: Run the KDE functional acceptance suite

Exercise:

- panel, launcher, wallpaper, pointer;
- Meta shortcut/global shortcuts;
- Konsole command execution;
- Dolphin home browse and file open;
- settings app;
- screenshot;
- clipboard;
- audio playback/device enumeration;
- network status/control;
- removable media if available;
- portal-KDE file chooser and screenshot where supported;
- polkit prompt;
- power/brightness behavior where available;
- lock/unlock;
- logout to display manager;
- second login;
- reboot.

For baseline-known failures, reproduce on both old and new images
before accepting them as unchanged.

Gate:

- All previously working functions still work.
- Any accepted failure has old/new evidence and a separate note.
- Logout, second login, and reboot pass without manual recovery.

### Step 18: Measure final size and duplication

Using the same methods/artifact types as Steps 3-4, record:

- stock core26/base contribution;
- each KDE content snap;
- session snap;
- display-manager provider;
- sum of seeded/installed snap files;
- uncompressed regular-file overlap and conflicts;
- size change versus the custom-base baseline.

Report both:

1. Plasma-session architecture cost excluding SDDM; and
2. actual bootable KDE image cost including the prerequisite SDDM
   runtime/provider.

Gate:

- Every number names exact artifacts and compression formats.
- Packed and uncompressed values are not conflated.
- Residual duplicate families are attributed to an owner/follow-up.

### Step 19: Run a full clean rebuild

Delete only documented generated build state through
repository-supported clean commands. Run a clean KDE component build
from committed sources, then assemble and boot a new image from those
exact artifacts with the image build (`build.sh --desktop kde`) and a
QEMU boot.

Do not use artifacts from Step 14. Verify embedded
revisions/checksums.

Gate:

- The full pipeline passes from clean state.
- The new image repeats Steps 15-17.
- No source fix exists only in an old LXD container, `.sdk`, extracted
  tree, or manually modified VM.

### Step 20: Document and close Stage 2.7/2.8

Update:

- this note with final revisions, artifacts, measurements, and accepted
  exceptions;
- `20260922-split-core26-desktop-base-snap.md` to mark 2.7 and 2.8
  done;
- the project's KDE documentation with durable architecture/build
  facts;
- provider/session READMEs;
- aggregate build documentation;
- separate notes for genuine pre-existing or deferred issues.

Move this file to the done state only after Steps 0-19 pass.

Gate:

- All source changes are committed in the correct repositories.
- A new session can reproduce the build and verification from docs.
- Stage 2.7's shared-vs-specific table and Stage 2.8's clean-image
  acceptance evidence are linked from the parent plan.
- GDM confinement has not been started or mixed into these commits.

## Non-goals

- Confining GDM; that is `20261001-confine-gdm.md`.
- Designing cross-desktop session registration or making GDM
  dynamically discover arbitrary session snaps.
- Implementing or redesigning SDDM; that is the prerequisite
  `20260928-switch-from-gdm-sddm-on-kde.md`.
- Fixing unrelated PowerDevil/polkit/AppArmor issues unless the content
  split itself regresses them.
- Changing the Qt/KF6/Plasma version set.
- Publishing SDK snaps to the Store.
- Merging all KDE/GNOME content into a single desktop mega-snap.

## Resolution (2026-10-02)

- Preserved and ran the pre-change image on one test VM while the
  stock-base candidate remained running on a second test VM, each on
  its own VNC display.
- Changed `plasma-desktop-session` to `base: core26` and removed the
  temporary custom-base swap/metadata rewrite from its build script.
  Its packed snap reports `base: core26`, strict confinement; SHA-256
  `d3aa1c305fe5785f6fdb1123efec37522d1d6fab5884af5d2792bb92f103dd5f`.
  Candidate image build-time SHA-256:
  `2b07643501901458ead74b859a0957d10cea6229b5b2e5261a6e1f84ca7918c6`.
- Direct boot triage found missing `gbm`, DRI-driver, Mesa EGL vendor
  registration, and XKB data paths. The session now maps these from
  the existing Plasma/KF6 content snaps; KWin starts, and Xwayland
  remains active under the enforcing session profile.
- Verified the visible Plasma desktop, launcher, Dolphin, System
  Settings, Konsole command execution, network/SSH access, and logout
  followed by a second login. The principal compositor/session services
  are active and no KWin EGL-provider, XKB keymap, or Qt
  platform-plugin startup failures remain.
- On the second login, the KSplash oneshot timed out waiting for KWin
  once; the desktop still started, and a retry after KWin was available
  completed. Konsole's `.bashrc` permission warning was also
  reproduced on the preserved baseline, so it is not a base-split
  regression.
- As directed, no exhaustive package/ownership or size inventory,
  all-source clean pipeline, GNOME-combination, update/recovery,
  audio/removable-media, or polkit acceptance matrix was run. Source
  changes were left uncommitted.
