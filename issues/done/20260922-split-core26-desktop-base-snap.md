# Splitting up the core26-desktop base snap (Stage 2 + Stage 3)

## Impact / Priority

High (architectural, blocks the project's stated "close to upstream"
goal and every future desktop-session variant). The core26-desktop base
snap currently ships ~519 Debian packages / ~485MB compressed — most of
it unconfined, and duplicated by every other base/session variant (e.g.
a KDE plasma-core-desktop) that wants a desktop. A real user does not
see a crash from this today (Stage 0/1 already fixed confinement and
functionality — see `20260922-stage0-stage1-confined-session-unblock.md`),
but they do inherit: a much larger download/OTA update size than a real
Ubuntu Core system, more unconfined attack surface than necessary, and
a project that cannot add a second desktop session (KDE) without
repeating the same multi-hundred-MB duplication. This is
architecture/maintenance debt rather than a currently-reproducible
user-facing bug — investigate and re-confirm impact empirically (e.g.
actual OTA/update size, actual boot time delta) if that's needed to
prioritize against other work.

## Background

This issue is the direct continuation of the plan in (now archived)
`proposed-plan.md` Stage 2/Stage 3. Verified still relevant as of
2026-09-22: `ubuntu-desktop-session-snap/snap/snapcraft.yaml` still
uses `base: bare` / `build-base: core26` with content supplied by the
`core26-desktop` custom base (no `content` interface anywhere in that
snap), and no `gnome-desktop-content`-style content-providing snap
exists yet. Stage 0/1 (the tactical unblock) is complete and documented
in `20260922-stage0-stage1-confined-session-unblock.md` — do not redo
that work.

Historical design detail (not required reading, but available if a step
needs it) is in `core-desktop-manager-snap.md` and
`splitting-the-core-desktop-base-snap.md`.

## PROGRESS (updated 2026-10-01)

- 2.1 DONE — audit delivered.
- 2.2 COMPLETE to its routing-or-blocker acceptance criterion. Services
  with supported Snap interfaces are routed and verified on a clean
  GNOME image; remaining host-run, inactive, and unsupported cases are
  classified in `20260928-route-remaining-stage2.2-dbus-services.md`.
  Do not interpret this as every optional desktop integration being
  available: that note records the GeoClue, UDisks2, portal frontend,
  UPower keyboard-backlight, and workflow-fixture limitations.
- 2.3 DONE — package manifest extracted:
  `20260922-stage2.3-content-snap-package-manifest.md` (46 declared
  stage-packages across desktop-packages/gdm-packages/
  gnome-desktop-components).
- 2.4 DONE — `gnome-desktop-content` is a strict `core26` app snap
  built from the 2.3 manifest and exposing the `gnome-desktop-content`
  content slot. The snap was built with its repository's build script
  (snapcraft pack) and is now included as one of the six component
  builds in the GNOME image build (`build.sh`).
- 2.5 DONE — `ubuntu-desktop-session-snap` now uses stock `core26` and
  the matching content plug at `$SNAP/gnome`; runtime paths and D-Bus
  service launchers use the content mount. A live Terminal app-search
  failure showed that GLib's `gio-launch-desktop` helper directory also
  had to be added to `PATH`; the session snap and GNOME image were
  rebuilt with the repository build scripts. The clean image boot did
  not auto-connect the content plug: snapd's device initialization
  failed requesting a serial for the local dangerous model, so the test
  VM needed a manual `snap connect`.
- 2.6 DONE — the rebuilt image reaches a graphical session, and
  `gnome-shell`, `gnome-terminal-server`, `nautilus-service`, and the
  screencast service run under enforce profiles. A Terminal opened from
  GNOME search and successfully ran `echo terminal-check`. The initial
  `~/.bashrc` permission issue was fixed in session x4; current
  confined checks can read the startup file and run `dircolors`.
  Nautilus activated and confined `gio list file:///home/your_username`
  returned the home directories. Screenshot and ScreenCast tests also
  passed. A live `/proc/<pid>/attr/current` comparison between the
  pre-split VM and the split VM confirms that previously confined GNOME
  Shell, GNOME Settings Daemon, Terminal, portal-GNOME, Xwayland, and
  related session processes that were running on both remain in enforce
  profiles. The pre-split VM's GNOME session launcher delegated to an
  `//&unconfined` child; the split VM's `gnome-session-service` now
  runs under its enforce profile. Several other pre-split-VM unconfined
  processes (including the calendar service, portal frontend,
  LocalSearch, metadata service, and keyring) now run confined. No
  confinement regression was observed.
  The denial gate is accepted with one explicit exception: new denials
  from the newly added PipeWire/WirePlumber profiles are deferred, as
  requested; all other observed denial signatures are in the prior
  baseline.
  - On a fresh image built from the committed ScreenCast changes, the
    Screenshot portal returned a non-empty PNG (91,920 bytes). The
    ScreenCast portal completed CreateSession, SelectSources, and
    Start; after approving Share in the VM, OpenPipeWireRemote
    succeeded and GStreamer captured one video frame.
  - Fresh-boot portal startup was verified: the GNOME backend started
    32 seconds after activation. This does not measure the separate
    first-visible-frame timing gate. The first clean build exposed a
    competing host `xdg-desktop-portal-gnome.service`; core-base-desktop
    now removes it (commit `c5f3e5b`).
  - Before functional tests, the fresh-boot journal contained 13
    `apparmor="DENIED"` records; raw pre-test and post-test captures
    were kept. The historical inventory through 10:55 UTC had 1,719
    records across 60 signatures and included events from before live
    fixes, so record counts are not directly comparable. Signatures
    that recur include Fontconfig probes, cgroup-controller reads,
    `bwrap` `userns_create`, and the known GNOME Shell D-Bus, GeoClue,
    fingerprint, GDM, and UPower requests. New in the fresh set are
    denials from the added PipeWire/WirePlumber provider profiles:
    system-bus/RTKit/BlueZ probes, WirePlumber's snapd
    permission-prompt socket and DMI metadata reads, and PipeWire
    cross-profile ptrace probes. ScreenCast still captured a frame, so
    these did not block capture. The PipeWire/WirePlumber-specific
    denials are accepted for Stage 2.6 and deferred for later triage;
    this is a scoped exception to, not evidence of, a zero-new-denials
    result. The post-test journal had 134 denial records, including
    repeated probes and duplicate audit transport records.
  - A pre-split image was inspected and a copy booted to the GDM login
    screen (login itself not tested). Its seed is `20260922`; backup
    builder commit `ca1ab0a` is dated the same day and references
    core-base commit `3899534`. The actual packed base snaps are a
    like-for-like Zstd comparison: pre-split
    `core26-desktop_20260922+cloud-init.snap` was 616,251,392 bytes;
    current `core26-desktop_20260929+cloud-init.snap` is 618,569,728
    bytes, only +2,318,336 bytes. The file-list diff shows +6,440,783
    uncompressed regular-file bytes, principally the patched
    `xdg-desktop-portal` binary (+3,791,680 bytes) and new
    `xdg-fuse-broker` (+2,637,986 bytes), plus package updates. The
    source `core.snap` XZ measurement (501,010,432 bytes vs the
    historical 485.37 MB XZ note) is a different build output and does
    not represent the packed base-size change in these two images.
  - In the first split build, summing the actual snap files in both
    seed directories (excluding the 2,107-byte `aux-info.json` in each
    system directory), the old image contained 2,403,344,384 bytes and
    the image with the new content snap contained 2,782,658,560 bytes:
    +379,314,176 bytes. That build's `gnome-desktop-content_0.1.snap`
    added 373,694,464 bytes. The pre-existing `gnome-46-2404` snap
    remained in both images (644,382,720 vs 645,148,672 bytes). The
    first split content snap overlapped the core at 27,503 regular-file
    paths (2,475,131,265 uncompressed bytes by path; 43 shared paths
    differed in size). This was the pre-trim measurement, not the size
    reduction achievable by removing user-session-only files while GDM
    stays in core.
  - The 2026-09-29 core trim now removes duplicated user-session
    payload from the host base: LocalSearch/TinySPARQL executables,
    libraries, data, activation files and translations; Control Center
    app/data and translations; portal frontend/backend executables,
    units, activation metadata and translations; Nautilus and its
    extensions/data/schema/translations; Ubuntu user-session
    definitions; Bluetooth SPA modules; and the user-session GNOME
    Shell extensions. GDM-required GNOME Shell, GNOME Session, GNOME
    Settings Daemon, and their host dependencies stay in core.
    Provider systemd/D-Bus files that conflict with the session snap's
    activators are filtered from `gnome-desktop-content`.
  - The rebuilt source `core.snap` is 486,752,256 bytes, down
    10,227,712 bytes from the immediately preceding 496,979,968-byte
    build. In the same Zstd image-build path, the packed core is
    600,231,936 bytes, down 18,337,792 bytes from the earlier
    618,569,728-byte image. The current content snap is 357,900,288
    bytes. Compared with the pre-split packed base (616,251,392
    bytes), current core plus content is 341,880,832 bytes larger
    (about 342 MB / 326 MiB). The whole-image comparison showed a
    +379,314,176-byte increase before the host-base trim; the trim
    recovered about 18 MB, but the combined increase remains
    substantially larger than the preliminary ~150 MB estimate. GDM
    remains in the base and requires GNOME Shell, GNOME Session, GNOME
    Settings Daemon, and their shared dependencies, while the content
    snap also carries desktop userspace. This leaves substantial
    duplicate payload. Moving GDM and tracing its dependency closure is
    the Stage 3A architectural path; it is not a blocker for this
    Stage 2 content-interface milestone.
  - A fresh image built from this core booted to the GNOME desktop on
    the VM's isolated VNC console. GDM and `graphical-session.target`
    are active, there are no failed user units, and LocalSearch plus
    the ScreenCast/Screenshot portal frontend and GTK/GNOME backends
    are running. The first fresh boot exposed a missing
    `/usr/share/localsearch3` path after removing its host copy; the
    session snap now binds that directory from the content snap, and
    the rebuilt image passes the same boot check.
  - The first image build selected the newest session snap artifact
    available by mtime, but that artifact predated the ScreenCast
    commit; `latest_snap` does not rebuild inputs. The session repo's
    build script (snapcraft pack) already removes old artifacts when
    packaging. The image builder now checks the embedded session-snap
    Git revision against source HEAD and rejects stale output (commit
    `017a1fa`).
  - The user reports Firefox installation from App Center fails. GNOME
    Shell's process root sees the helper from its stock core26 base at
    0755; it is not from the content mount. The live VM has Polkit 127,
    whose agent library uses `/run/polkit/agent-helper.socket` when
    that socket exists. The socket unit was disabled/inactive, so the
    agent fell back to direct execution and logged
    `polkit-agent-helper-1: needs to be setuid root`. Snapd's
    `polkit-agent` AppArmor policy also lacked access to this pathname
    socket. Source changes now remove the setuid chmod, enable the
    socket in the image's factory writable `/etc` seed, and add a
    narrow socket-file permission to the snapd interface. The Snapd
    snap and GNOME image were rebuilt in an isolated worktree, leaving
    the user's running VM untouched. The rebuilt VM booted with the
    helper at 0755, the socket enabled/active, and the generated GNOME
    Shell profile containing the new rule; a confined socket-connect
    test activated the systemd helper. The same socket/policy test
    passed on the user's live VM using a temporary profile rule. On
    2026-09-29 the user entered the password requested by App Center;
    the Firefox install completed (revision 8969, strict confinement),
    the helper service completed successfully, and GDM/GNOME remained
    active through Snapd's profile reload. The "Authentication
    required" dialog was the expected Polkit authorization prompt, not
    an error. The App Center blocker is resolved. Screenshot,
    ScreenCast, and fresh-boot portal startup are verified; denial
    triage and removal of duplicate GNOME payload from the core remain
    open.
  - On 2026-09-29 the user reported blank top-bar and Quick Settings
    symbols. The Adwaita SVG files and content search paths were
    present, but GdkPixbuf's Glycin subprocess exited 127 because its
    sanitized environment omitted the snap `LD_LIBRARY_PATH`, so it
    could not load `librsvg-2.so.2`.
    `ubuntu-desktop-session-snap/scripts/gdk-pixbuf-env.sh` now
    generates executable loader wrappers in `SNAP_USER_COMMON` and
    points the Glycin config at them. The updated helper was run live;
    GdkPixbuf successfully decoded representative wired, wireless,
    lock, settings, and do-not-disturb icons at 16x16. The session snap
    build succeeded, and the live icon theme was refreshed. Session
    snap revision x2 is now installed and GDM has started a fresh
    graphical session. Its generated Glycin configuration points to
    the wrapper, and no recent loader exit-127 errors remain. The user
    confirmed the icons are visible, but the active Adwaita theme
    differs from Ubuntu's staged Yaru defaults, so the appearance is
    not yet the stock Ubuntu look.
  - The user reported that Terminal's font looked wrong and its shell
    denied access to `$HOME`. The session settings request `Ubuntu
    Sans Mono 11`, but the content snap had omitted `fonts-ubuntu`;
    adding it made a fresh confined shell resolve the staged font. The
    terminal app also lacked home access; session x4 now requests the
    `home` plug and narrowly scoped Bash startup/history files, and a
    confined shell can read `~/.bashrc`.
  - Bash then failed to run `dircolors`: the content snap staged
    `rust-coreutils`' binary under `/usr/lib/cargo/bin/coreutils` but
    not Ubuntu's `/usr/bin/dircolors` symlink. Provider x5 now
    contains that symlink. After the user approved closing open
    terminal windows, I restarted only the GNOME Terminal server; its
    x4 mount now contains the link, `dircolors` runs in the confined
    shell, and the home directory plus `.bashrc` are readable. The
    user confirms Terminal launches without errors and considers that
    sufficient for now. Defining the intended terminal privilege model
    (including whether to offer a container with broader host-mutation
    access) is deferred; do not broaden confinement until that policy
    is decided.
- Stage 2.6 is complete with the documented PipeWire/WirePlumber denial
  exception.
- 3A DONE — GDM and its duplicate GNOME greeter runtime moved into
  `gnome-desktop-content`; core plus content is now 1,945,600 bytes
  below the pre-split core. Boot, confined desktop startup, logout to
  the GDM greeter, and GDM restart were verified on a clean image. GDM
  confinement is separately planned in `20261001-confine-gdm.md`.

## Notes for running the steps

Steps below are tagged by kind — mechanical (audits, greps,
package-list extraction, running existing build/test commands and
capturing output) or judgement-heavy (architecture/interface design,
debugging opaque build/boot failures, end-to-end verification gates).
Run steps within a stage in order (each depends on the previous);
stages 2.7/2.8 (KDE) can run in parallel with nothing later once 2.6 is
done. Stage 3's workstreams (A-D) are independent of each other and of
nothing but Stage 2 being complete — they can be run in parallel.

## STAGE 2 — Content interface split (GNOME)

Goal: get ubuntu-desktop-session running against a real, unmodified
core26 base, with GNOME desktop content supplied via the standard
content interface instead of baked into a custom base snap.

### 2.1: Audit host-exec'd units

On the core26 gnome test VM and/or in the core-base-desktop repo,
enumerate every systemd --user unit file and D-Bus service-activation
file whose ExecStart/Exec references a binary that is currently only
staged inside core-base-desktop (gnome-shell, mutter, gjs,
gnome-settings-daemon components, xdg-desktop-portal-gnome, etc.), as
opposed to units already declared as `apps:` inside
ubuntu-desktop-session-snap's own snapcraft.yaml (those already work
fine under a content interface, per `proposed-plan.md`'s analysis — no
change needed for them). Deliverable: a plain list/table of unit-name
-> ExecStart path, split into "already a snap app" vs "needs the
ExecStart/snap-run fix". Verifiable output: the list, plus the
grep/systemctl commands used to produce it.

### 2.2: Route host-exec'd units through snap run

For each unit identified in 2.1 as needing the fix: change its
ExecStart to invoke `/snap/bin/ubuntu-desktop-session.<app>` instead of
a bare path, and add a matching `apps:` entry (command + any needed
plugs) to ubuntu-desktop-session-snap's snapcraft.yaml. Build and
verify EACH unit individually before moving to the next (do not batch):
confirm the unit starts, confirm confinement via
`/proc/<pid>/attr/current`, confirm no new AppArmor denials. This step
depends on 2.1's list.

### 2.3: Extract candidate content-snap package manifest

From the core-base-desktop snapcraft.yaml, extract the full set of
`stage-packages` entries from the desktop-related parts
(desktop-packages, gdm-packages, gnome-desktop-components, and any
other part that isn't purely base-OS/chisel content). Produce a plain
package-name manifest to use as the starting stage-packages list for a
new content-providing snap. Do not judge which packages should move yet
— just produce the accurate current list with each package's source
part noted.

### 2.4: DONE — Scaffolded the GNOME content snap

Create a new snap (working name `gnome-desktop-content`, type: app,
base: core26 — no custom-base workaround needed) that stages the
package manifest from 2.3 and exposes it via one or more `content`
interface slots (following the standard content-interface pattern
already used by e.g. gnome-42-2204/gtk-common-themes — see any existing
example in the snap store for the slot/source stanza shape). Get it
building successfully with stock snapcraft. Depends on 2.3.

### 2.5: DONE — Wired the content plug into ubuntu-desktop-session-snap

Remove the `base: core26-desktop` / custom-base dependency from
ubuntu-desktop-session-snap; add the matching content `plugs:` stanza
targeting the new content snap; fix up PATH, LD_LIBRARY_PATH,
GI_TYPELIB_PATH, GSETTINGS_SCHEMA_DIR, XDG_DATA_DIRS, and D-Bus
service-file locations so they correctly reference the non-standard
content-mount prefix (expect this to be the most fiddly part — budget
real iteration time). Depends on 2.4 and on 2.2 already having fixed
the host-exec'd units to route through snap run (otherwise those units
still can't see the new content).

### 2.6: DONE — End-to-end gate passed (PipeWire/WirePlumber denial exception)

On the core26 gnome test VM: full build + boot with the new
content-snap architecture. Verify: (a) confined session boots and stays
fully confined end-to-end (same `/proc/<pid>/attr/current` check as
Stage 1); (b) no new AppArmor denials vs. the Stage 1 baseline, except
the explicitly accepted PipeWire/WirePlumber profile denials; (c) basic
desktop functionality works (open a terminal, launch nautilus, take a
screenshot/screencast); (d) measure and record the new
core-base-desktop / boot-base size and compare against the measured
baseline. The GDM-related duplication was subsequently removed in
completed Stage 3A; it did not block Stage 2.7/2.8.

### 2.7: DONE — Audit KDE's remaining custom-base dependency

Prerequisite: first complete `20260928-switch-from-gdm-sddm-on-kde.md`,
because Stage 3A removed GDM from the base and the KDE image needs a
working SDDM login path before it can provide a valid baseline. KDE
already supplies its runtime through `kf6-core26` and
`plasma-core26-desktop`; do not assume another content snap is needed.
Compare stock `core26`, `core26-desktop`, the session snap, and both
existing providers, then trace which custom-base files the running
session actually consumes. Deliverable: a measured ownership table and
an exact list of gaps, if any, in the existing providers.

### 2.8: DONE — Remove KDE session's core26-desktop dependency

Change `plasma-desktop-session` from `base: core26-desktop` to
`base: core26`, retaining the completed SDDM image architecture. First
test the two existing KDE content providers unchanged. Add only runtime
files proven missing by the conversion, preferably to the appropriate
existing provider; create another provider only when measured
ownership, ABI, or update-cadence evidence requires it. Verify per
2.6's checklist, adapted for the KDE session, including SDDM login,
logout, and second login. The detailed, independently gated execution
plan for 2.7 and 2.8 is
`20261001-remove-kde-core26-desktop-dependency.md`.

## STAGE 3 — Base splitting proper (workstreams once Stage 2 is done)

These four workstreams are independent of each other; dispatch in
parallel once staffed. Each must follow the same discipline as Stage 2:
smallest possible verified change, one thing at a time, real boot
verification before moving on within the workstream.

### 3A: DONE (2026-10-01) — Display manager payload moved out of the base

GDM, its greeter runtime, GNOME Shell, GNOME Session, Mutter, and GNOME
Settings Daemon payload now come from `gnome-desktop-content`; only the
host service/PAM/account/state integration remains in core. A clean
image boots the confined desktop, logout returns to a stable
content-snap GDM login screen, and restarting GDM restores the confined
user session. GDM and the greeter intentionally remain unconfined at
this milestone. Final packed sizes are 241,295,360 bytes for core and
373,010,432 bytes for content (614,305,792 combined), 1,945,600 bytes
below the 616,251,392-byte pre-split core. Full implementation history
and verification: `20260930-move-gdm-to-the-gnome-content-snap.md`.

## PROGRESS (updated 2026-11-05)

- PipeWire split-out verified live on the GNOME VM: the `pipewire` snap
  (x1, 14.4 MB, core26 base, resolute-versioned) provides
  pipewire-bin/pipewire-pulse (user, socket-activated) and
  wireplumber-bin (user, always-on), all running under enforce
  profiles; `snap interface pipewire` confirms the custom interface in
  the snapd fork; gadget static connections confirmed (session:pipewire
  and session:audio-playback connected via gadget, audio-record
  deliberately unconnected, pipewire's portal/permission-store dbus
  plugs wired to session slots).
- Portal trio state confirmed on the same VM: xdg-desktop-portal,
  -gnome, -gtk, xdg-document-portal and xdg-permission-store run as
  ubuntu-desktop-session apps (enforce) with binaries from the
  gnome-desktop-runtime content mount; the document portal FUSE mount
  (/run/user/1000/doc) exists inside the session namespace. Stage 3C's
  remaining work is therefore only the portal split + its FUSE
  namespace question, plus porting the pipewire snap wiring to the KDE
  image (which still uses system:pipewire).
- core26-desktop's remaining role is as the MODEL base
  (all four model assertions declare base: core26-desktop — it is the
  rootfs, not a mere snap dependency). The gadget's source
  snapcraft.yaml already uses stock core26; the installed pc-desktop
  x1 gadget is stale on that point. Scoping for dropping the custom
  base entirely and switching the model to stock core26 (measured
  241.5 MB vs 63.6 MB packed, 15,223 vs 4,808 files; full re-homing
  inventory, pivotal unknowns, staged gates):
  `20261105-replace-model-base-core26-desktop-with-stock-core26.md`.

Strict confinement is a separately gated follow-up, not unfinished
Stage 3A payload work. Its executable plan is `20261001-confine-gdm.md`.
That work includes the GDM daemon, session workers, dynamic greeter
user/session, PAM, AccountsService, and handoff into other confined
snaps; a confined daemon that still launches unconfined workers or
greeter components does not satisfy the gate.

- 3B udisks2 DONE (2026-10-04) — udisksd is now provided by the
  upstream `udisks2` snap (snap-24 branch, built locally and
  unmodified; 6.4MB) instead of dead payload inside
  `gnome-desktop-content`. Verified on a clean image: the daemon runs
  D-Bus-activated as `snap.udisks2.udisksd (enforce)` as root, the
  session's confined `gvfs-udisks2-volume-monitor` activates it through
  the provider's `udisks2` interface slot, ext4 and vfat loop-device
  mount/unmount work end-to-end through polkit, and the fresh-boot
  journal has no new denial class (one recorded one-off:
  `snap.udisks2.udisksd` CAP_NET_ADMIN capability probe,
  non-blocking). Related fixes made en route (each independently
  verified):
  - gnome-desktop-content: pruned all daemon-side udisks2/UPower
    payload (they were staged transitively — gvfs-daemons Depends
    udisks2, gnome-control-center Depends upower — and inert inside a
    content mount; host systemd/system-bus cannot see units there) and
    made the xdg-desktop-portal-patched override-build idempotent for
    incremental rebuilds. Commit 9763df5.
  - ubuntu-core-desktop build.sh: gadget static connections rewired —
    `session:udisks2 -> udisks2:udisks2` (was the implicit system
    slot), plus `udisks2:polkit`, `udisks2:hardware-observe`,
    `udisks2:mount-observe`, `udisks2:block-devices` and the provider's
    own `udisks2:udisks2-client`. Commit 2e4ed06. Note: snapd installs
    the polkit action file itself into the factory-writable
    /usr/share/polkit-1/actions (no base-side action file needed), and
    the implicit `:polkit` slot exists on this core26 image.
  - ubuntu-core-desktop-snapd (26-dev 93c6f2a3a0): udisks2 interface
    slot policy now allows `loop*` device names (mount + raw read) so
    loop-mounted media works, and grants udisksd the polkit `Changed`
    signal receive (both upstreamable).
  - ubuntu-desktop-session-snap (26-dev 6717870): gvfs daemons/monitors
    and GOA services now declare `daemon: dbus` + `activates-on` so
    snapd generates session-bus activation entries for them — their
    activation had silently broken when the trim moved their service
    files into the content mount (only portals/terminal/nautilus-class
    apps had the wiring). gnome-keyring-daemon deliberately excluded
    (PAM-launched). Also: gdk-pixbuf-env.sh's content-data setup was
    racy (concurrent `ln -s`/update-mime-database between
    gnome-session-monitor and user-session-migration aborted first
    login twice); the link step now tolerates an existing correct link
    and the MIME database is built in a private staging directory and
    published by directory swap, making concurrent invocations safe.
  - The 2.2-era `system:udisks2` implicit-slot gate
    (ImplicitOnCoreDangerous) remains in snapd for compatibility; the
    session no longer uses it.
  upower is DONE too (2026-10-04) — upowerd is now provided by the
  upstream `upower` snap (snap-24 branch, built unmodified; 462KB).
  Verified on the same clean image: upowerd runs D-Bus-activated as
  `snap.upower.upowerd (enforce)` as root, `upower -d` through the
  provider's own confined client works, gsd-power/gsd-media-keys/
  gnome-shell query UPower with zero AppArmor denials in both
  directions, and the session's `upower-observe` plug connects to the
  provider's slot via the gadget (the old `system:upower-observe`
  connection could not resolve anymore because the post-trim base has
  no host upowerd). image build.sh commit 2252502. Related snapd fixes
  (26-dev, upstreamable): the upower-observe connected-plug policy now
  grants read-only UPower.KbdBacklight brightness queries (2.2-era
  gap, commits 99d6fbc332 + syntax fix 9f37714aa6); a stray comma in
  that rule initially aborted the whole seed with an AppArmor parser
  error (the boot then sat in snapd.seeded waiting for a manual
  restart — keep that failure mode in mind when a seed's policy fails
  to parse). The session-side UPower client gaps fixed along the way:
  gsd-media-keys needed the app-attached upower-observe plug (session
  commit 8f69f44; top-level plugs do not implicitly apply to apps that
  declare their own plug lists). Remaining known one-off denials for
  triage: a single CAP_NET_ADMIN capability probe each from
  snap.udisks2.udisksd and snap.upower.upowerd at first activation.
  The core base still carries a stray `libupower-glib.so.3` from the
  gdm3 dependency closure; the greeter gets the library from the
  content snap, so that copy is dead weight worth pruning in a later
  base cleanup. Stage 3B udisks2+upower milestone complete; the
  remaining 3B items (colord, boltd, geoclue, rtkit, fwupd) remain
  per-service investigate-then-implement pairs.

### 3B: Peripheral system daemons

- udisks2 and upower: modern upstream snaps already exist
  (github.com/snapcore/udisks2-snap, github.com/snapcore/upower-snap
  per `splitting-the-core-desktop-base-snap.md`) — integrate them into
  the image build and verify they provide the same functionality
  currently baked into core-base-desktop (removable-media enumeration,
  power-device info). Lowest risk, start here.
- colord, boltd, geoclue, rtkit, fwupd: each needs its own
  investigation before a snap can be split out (see
  `splitting-the-core-desktop-base-snap.md` for the specific open
  questions on each — e.g. colord's filesystem-path-passing API across
  mount namespaces, fwupd's disk-encryption interaction). Treat each as
  its own investigate-then-implement pair of steps, not one combined
  task.

### 3C: Pipewire + xdg-desktop-portal snaps

PIPEWIRE HALF DONE (2026-10-05): the audio daemons (pipewire,
pipewire-pulse, wireplumber) and client tools now live in a
locally-built `pipewire` snap (branch 26 of the pipewire-snap repo,
core26 base, version-matched resolute packages), served by a custom
`pipewire` interface in the snapd fork, wired via gadget static
connections (audio-record deliberately left unconnected for record
privacy). Verified live on the VM 2026-11-05: all three user-scope
daemons run socket-activated/always-on under enforce profiles.
Resolution history: `20261004-pipewire-snap-evaluation.md`. The content
snap keeps only the pipewire/wireplumber libraries/configs/client
binaries. REMAINING: split the xdg-desktop-portal/xdg-document-portal/
xdg-permission-store trio into their own snap(s), per the design in
`splitting-the-core-desktop-base-snap.md`, and resolve how the
xdg-document-portal's FUSE mount gets bind-mounted into every other
desktop snap's mount namespace if the document portal itself is no
longer in the primary mount namespace. (Verified 2026-11-05: the
portal trio still runs as ubuntu-desktop-session apps with binaries
from the gnome-desktop-runtime content mount, and the document portal
FUSE mount exists inside the session namespace, so the FUSE question
is only a problem once they are split out.) NOTE: the KDE image ships
no pipewire snap yet — its gadget still wires
plasma-desktop-session:pipewire -> system:pipewire (see
`20260915-app-center-installed-snaps-need-desktop-interface-connections.md`);
porting the pipewire snap wiring to the KDE image is outstanding work
under this item.

### 3D: systemd-user-control proxy redesign

Replace the current broad, wildcard-unit-path systemd-user-control
AppArmor stopgap (added in Stage 0, see
`20260922-stage0-stage1-confined-session-unblock.md`) with a
properly-scoped D-Bus proxy: own D-Bus name, an allow-listed set of
unit names the client can start/stop/monitor, and restricted
environment-change permissions. Design this using real usage
experience from Stage 0-2 (which specific unit names/calls are actually
needed — this should already be a short, closed list per the
investigation in the archived
`20260906-gnome-session-investigation-findings.md`). This is the piece
intended to eventually be proposed upstream to snapd instead of the
current interface extension.

## RESOLUTION OF STEP 2.2 (2026-09-22)

An earlier draft submission reported 2.2 as blocked on three
"architectural" issues requiring Stage 3A. That conclusion was WRONG,
and the following reconfirmed all three are simple, verified fixes.
Summary here.

The three "blockers" and their actual fixes:

1. "GDM greeter shares gsd-*/gnome-session-ctl unit names" ->
   FIX: [Unit] ConditionGroup=!gdm on the NON-templated gsd-* units
   (the greeter runs as user gdm-greeter, gid gdm, so !gdm skips it).
   The templated @ubuntu units were already scoped away from @gdm. Not
   architectural; no Stage 3A.

2. "gnome-shell X11-socket bind (x11 slot ownership)" ->
   FIX: add slots: [wayland, x11] to the gnome-shell app (mirrors
   KWin's wayland/x11-server slots). Not architectural.

3. "confined<->unconfined D-Bus peer rules" ->
   FIX: a handful of AppArmor rule additions to EXISTING interfaces
   (login-session-observe GetSessionByPID +
   CanRebootToBootLoaderMenu, systemd-user-control app.slice/cpu.max).
   Not architectural.

Plus one prerequisite bug discovered en route: the image had been built
from a snapd missing fix-tmpdir-permissions-bug (ba1b318139), which
breaks EVERY snap-run app. Merged into branch 26 and rebuilt.

Committed (branch 26, 2026-09-22):
- core-base-desktop: 3899534, d478aa3 (gnome-shell + 16 gsd-* snap-run
  drop-ins).
- ubuntu-desktop-session-snap: c918a62 (gnome-shell slots) + the
  earlier 61 app entries.
- ubuntu-core-desktop-snapd: fix-tmpdir merge + 13a2864559 +
  7e1160f609 (login-session-observe) + systemd-user-control app.slice
  rule.

Verified end-to-end on a clean boot: gnome-shell and all 16 gsd-* units
run clean per-app (enforce) labels; 0 denials for the fixed members;
only benign fprint + pre-existing bwrap userns_create denials remain.

## REMAINING STAGE 2.2 TRANCHE — RESOLUTION (2026-09-28)

The later routing audit and clean-image verification are recorded in
`20260928-route-remaining-stage2.2-dbus-services.md`. The acceptance
criterion for that tranche was that each candidate be routed and
verified, or have a specific unsupported/inactive/fixture blocker:

- Verified confined: GVFS daemon, metadata daemon and the AFC/GOA/
  GPhoto2/MTP monitors; LocalSearch/Tracker services; GOA and identity;
  Secret Service keyring; Nautilus FileManager1; IBus daemon and
  portal; portal GTK/GNOME backends and document portal; and the routed
  settings, session, migration, and user-directory services where
  activated. Active process labels were
  `snap.ubuntu-desktop-session.* (enforce)`.
- GNOME gadget auto-connections now include the network-manager, BlueZ,
  login-session-control, UPower-observe, home, and declared
  personal-files plugs. A clean boot verified BlueZ `GetManagedObjects`,
  the IBus portal bus name, a confined home browse, Secret Service
  introspection, and the portal FileChooser interface. A prior
  clean-image end-to-end chooser test selected a home file and read it
  through its document-portal URI.
- Remaining blockers/limits: UDisks2 monitor has no connectable slot;
  host portal frontend cannot own `org.freedesktop.portal.Desktop` when
  confined, so the permission store also stays host-run; GNOME Shell's
  GeoClue agent call has no connectable host slot; `gsd-power`'s
  KbdBacklight `GetBrightness` is not allowed by `upower-observe` and
  there is no `upower-control` interface; the GNOME portal
  service-channel handshake times out at initial activation but
  succeeds after a later restart; Malcontent's executable is absent;
  SPICE has no virtio port in the test VM; first-run/upgrade setup
  needs a dedicated fixture; and GCR prompt/unlock flows were not
  exercised.
- Inactive/not exercised: dconf (the session uses the keyfile settings
  backend), PACRunner (no proxy is configured), plus lazy-activated
  Settings/Extensions and other optional providers not triggered by
  this account's normal boot. Keep their route changes, but do not
  claim their user workflows were tested.

The test image reached `graphical-session.target`; IBus registered
automatically under its enforce profile using the current per-display
bus address. The final boot had no new error-level journal entries. The
expected LocalSearch `.hidden` probe remains denied; no hidden-file
access was granted. Remaining portal RealtimeKit/PipeWire/AT-SPI
warnings reflect services absent from this image and were not treated
as routing failures. These explicit blockers do not prevent starting
Stage 2.4, but must be carried into later integration decisions. No
commit was made for this work.
