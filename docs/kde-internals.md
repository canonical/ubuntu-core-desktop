# KDE Neon Core (Plasma) — model facts, repos, build gotchas

Goal: a KDE/Plasma analogue of ubuntu-core-desktop. TWO parallel build
pipelines now exist for the three KDE runtime snaps (kf6-core26,
plasma-core26-desktop, plasma-desktop-session):

- `desktop/26` (also `26`/`26-dev`): the original from-source SDK
  pipeline (kdesrc-build against the kde-qt6-core-sdk/
  kde-pyside6-core-sdk/kf6-core-sdk snaps) — still maintained, all
  forward-port fixes below are committed on this branch (verified
  2026-10, not an "uncommitted working tree" situation anymore).
- `deb-repack` (also `deb-repack-backup`/`deb-repack-clean`): a NEWER,
  much faster pipeline that stages prebuilt KDE Neon .debs instead of
  compiling anything — see "deb-repack build" below. This is the
  pipeline new work should generally target; the from-source pipeline
  remains as a reference/fallback.

## Repos (reference and working clones)

- `ubuntu-core`, `plasma-core-desktop`, `plasma-desktop-session` (all
  from invent.kde.org/neon/...) — upstream KDE Neon Core clones.
  `plasma-core-desktop` and `plasma-desktop-session` have a `26`
  branch (dev work happens on the paired `26-dev`, per
  dev-branch-conventions.md; this pair was renamed from
  `26`/plasma-core-desktop's existing scheme and from `kde`/`kde-dev`
  in plasma-desktop-session on 2026-09-23).
- `ubuntu-core-desktop-kde`: a COPY of canonical/ubuntu-core-desktop
  used to build the KDE model/scripts without touching the main repo.
  Should eventually be merged back into ubuntu-core-desktop (only one
  repo should exist long-term) — treat this duplication as temporary.

## Model: kde-neon-core-dangerous-amd64

Source of truth is `kde-neon-core-amd64.json` in `ubuntu-core` (the
`.model` file is CI-signed output of it).

- `base: core24-desktop`, same snap-id as our GNOME core24 model — no
  separate KDE/core26 base variant exists upstream yet.
- gadget: `pc-desktop` — same snap-id as our own gadget; KDE Neon Core
  does not maintain its own gadget, it reuses ours.
- kernel/snapd: same snap-ids/tracks as our own models.
- KDE-specific snaps: `kf6-core24` (KF6 runtime, content snap, NOT yet
  cloned/inspected — locate and inspect before assuming its shape),
  `plasma-core24-desktop` (content snap built from
  `plasma-core-desktop`, slot `plasma-core24`),
  `plasma-desktop-session` (app/session snap, already has a real store
  snap-id, so static gadget.yaml connections work normally for it —
  no snap-id workaround needed).
- Notably absent vs. our GNOME models: no cups/ipp-usb, no
  snap-store/snapd-desktop-integration, no console-conf.

## Makefile / build flow (ubuntu-core repo)

- `finalize-json.sh` signs with a KDE-specific key
  (`kde-neon-core-image-key`), a different naming convention than our
  own `test`/`default` (see snap-signing.md) — needs mapping/renaming
  if reusing their Makefile targets.
- `.model` files are normally CI-generated on protected branches, then
  pulled via `update-models.sh` — not regenerated locally in the
  common case.
- `create-snap-list.sh`: for `dangerous` grade, force-injects only
  `optional`-presence snaps plus everything under `local-snaps/` as
  `--snap` args to `ubuntu-image`; everything else resolves from the
  model's default channels. Dev workflow: drop built snaps in
  `local-snaps/` and `make dangerous`.

## plasma-core-desktop (content snap "plasma-core24-desktop")

- `base: core24` (no `build-base`, avoiding the same core24 conflict
  noted in build-tools.md).
- Built via `plugin: make` running kdesrc-build hooks; heavy Qt6/KF6
  build-snap toolchain. Strips pipewire files from prime (provided
  elsewhere). Provides slot `plasma-core24` (content interface).
- Pulls a KDE-neon-specific apt repo (origin.archive.neon.kde.org,
  noble suite) in addition to the standard Ubuntu archive — a
  build-network dependency not present in our own core-base-desktop.

## plasma-desktop-session

- `base: core26-desktop` (with `build-base: core26`). Plugs TWO
  content snaps: `kf6-core26` (->`$SNAP/kf6`) and `plasma-core24`
  (->`$SNAP/plasma`) — KDE splits KF6 and Plasma runtimes, unlike
  GNOME's single `gnome-46-2404` content dependency. (The
  `plasma-core24` slot name is historical; the snap is now
  core26-based — see
  20260923-remove-core-version-from-plasma-desktop-snap-name.md.)
- `scripts/run-session.sh` execs
  `$SNAP/plasma/usr/bin/startplasma-wayland` directly — no display
  manager invoked from inside the snap/hooks (GDM still starts the
  session from outside, same shape as GNOME).
- Per-service apps run as `daemon: dbus`, `daemon-scope: user`, each
  `activates-on:` its own D-Bus name — finer-grained decomposition
  into systemd/D-Bus-activated services than GNOME's single session
  app. Several of these (not just the main session app) plug
  `systemd-user-control`.

## Gadget auto-connect diff (pc-amd64-gadget-desktop vs. Plasma)

Our gadget.yaml's existing auto-connect block is keyed to
`ubuntu-desktop-session`'s snap-id. A comparable block for
`plasma-desktop-session` would need:

- Same as GNOME's block: avahi-control, desktop-launch,
  hardware-observe, home, hostname-control, locale-control,
  login-session-observe/control, mount-observe,
  network-control/observe, network-manager, bluez, bluetooth-control,
  shell-config-files, upower-observe, systemd-user-control,
  polkit-agent (plugged on the `plasma-polkit-agent` app specifically,
  not top-level, but still needs a top-level gadget `plug:` entry).
- Plugged but no slot in the current KDE model: cups-control (no cups
  snap upstream — same gap as our own GNOME 26 model).
  Not plugged by KDE at all (present in GNOME's block, so skip):
  account-control, time/timeserver/timezone-control.
- Extra plugs KDE needs that our gadget.yaml doesn't cover at all:
  opengl, pulseaudio, pipewire, network-bind, udisks2
  (->udisks2:service), ssh-keys — all plain auto-connectable
  interfaces, just add `plug:` lines. Plus two app-scoped
  personal-files plugs (`dot-hidden` for $HOME/.hidden, a
  `shell-session-locale-files`-style one for
  .pam_environment/.xinputrc/.gtkrc-2.0) — check whether these need
  any slot at all, unclear if there's precedent in our own
  gadget.yaml.
- `kf6-core24`/`plasma-core24` are content-interface, resolved via
  default-provider — no gadget entry needed.

## core26 SDK build

Rebuilding KDE Neon's three core26 SDK snaps (kde-qt6-core26-sdk,
kde-pyside6-core26-sdk, kf6-core26-sdk) from scratch (KF6 SDK, 103
parts, is the long pole) to eventually rebuild plasma-core-desktop
against them and boot a KDE core26 image.

Version set (locked, do NOT downgrade): Qt 6.11.1 + KF6 6.30.0 +
Plasma 6.7.5. Resolute (26.04) ships OLDER (Qt 6.10.2 / KF6 6.24 /
Plasma 6.6.6) — match resolute only for SYSTEM stage-packages
(glibc, libavcodec62, etc.), not for the KDE stack itself. The
"26.04.2" suffix in store SDK version strings is a manually hardcoded
packaging label, NOT evidence of a core26 build — the SDKs were
genuinely core24/noble-built. Use `base: core26` + `grade: stable`
with NO `build-base` line (Snapcraft 9 rejects build-base==base, and
rejects `build-base: devel` as non-reproducible).

meson "ModuleNotFoundError: No module named 'mesonbuild'" — applies
to ANY snap that stages its own python ahead of the host python on
PATH: Snapcraft's meson-plugin validation environment does not
include the part's build-environment (a PYTHONPATH set there is
ignored at validation time), and the plugin prepends
$CRAFT_STAGE/usr/bin to PATH, so `meson` resolves to a stale staged
copy and the staged SDK python3 shadows the host interpreter the
`/usr/local/bin/meson` shebang needs. Fix (all three together):
install meson to SYSTEM site-packages only (`/usr/bin/python3 -m pip
install --break-system-packages .`, no `--target`, to avoid a stale
staged copy); set, in every meson part, the PYTHONPATH below (the
value is exactly what was used; snapcraft does not auto-inherit a
shared anchor across parts — check each one); and use a
Python-3.14-compatible meson (1.10.1; 1.4.0 predates 3.14).

    PYTHONPATH: /usr/local/lib/python3.14/dist-packages${PYTHONPATH:+:$PYTHONPATH}

Related: if a meson-deps part (pins
meson from source) and another part using apt `meson` disagree, you
get "InstallData file ... references functions or classes that don't
exist" (stale generated metadata) — put the consuming part
`after: [meson-deps]` and `snapcraft clean <part>` to drop stale
state.

GLib helper path mismatch: a staged Qt SDK's `gio-2.0.pc` expects
GLib helpers (`glib-compile-schemas`, `gio-querymodules`) below the
SDK prefix, but a freshly-built glib part installs them into the main
stage — make the dependent part `after: [glib]` and symlink the
helpers into the SDK-expected location.

Local SDK staging without host snapd/sudo (reusable technique):
`build-snaps:` resolves from store/host snapd (needs sudo); instead
unsquash each built SDK snap into the consuming repo's .sdk/<name>/
(gitignored), stage via `plugin: dump` + `organize: {'*': <name>/}`,
rewrite `/snap/<name>/current/` -> `$CRAFT_STAGE/<name>/` in env
paths, and add the dump part to consuming parts' `after:`. Do NOT
rewrite the SDK's own .pc files (they hardcode
`prefix=/snap/<name>/current/usr`, hundreds of them) — instead
symlink `/snap/<name>/current` -> `$CRAFT_STAGE/<name>` in the dump
part's override-stage (the build container's /snap is a writable
dir, not a snapd mount).

Fast iteration on a large part graph without re-running full
`snapcraft pack`: on a 100+-part yaml, `snapcraft pack` pins a core
at 100% CPU for ~10 min at the START of every run
(part-state/dependency-graph computation, quadratic in parts x
dependencies, worsened by any part with a huge `after:` list) before
any install/compile even starts — single-threaded Python, not fixable
without pruning `after:` lists. Workaround: let pack fail, then
`lxc start <instance> --project snapcraft` (disk is intact) and
reproduce the failing part's exact command in-container (env lines
are in `~/.local/state/snapcraft/log/`) before re-running pack once
at the end. Do NOT `lxc delete` the build container between
iterations (forces a full re-download of build-packages).

ccache: use `CCACHE_DIR=${SNAPCRAFT_PROJECT_DIR}/.ccache` (outside
the container, survives `snapcraft clean`) + `CCACHE_NOHASHDIR=true`.
In-container the cache lands at `/root/project/.ccache` (NOT
`/root/.cache/ccache`) — `export CCACHE_DIR=/root/project/.ccache`
before `ccache -s`. Consider raising `CCACHE_MAXSIZE` above 5GiB for
large QtWebEngine/Chromium objects.

Other resolute-specific fixes (recorded, not re-derived): ninja
source build fails (imports removed `pipes`, gone in py3.13+) — use
apt `ninja-build`; add `gobject-introspection` to build-packages for
parts using `-Dintrospection` (was transitively present on noble);
libdbusmenu-qt6's frozen cmake_minimum_required 2.x is rejected by
resolute's CMake 4 — add `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`; there
is no ffmpeg-2604-sdk snap, use resolute apt ffmpeg dev packages;
noble->resolute package renames (t64/numeric bumps):
libcanberra0t64->libcanberra0, libglib2.0-0->0t64, libical3->3t64,
libimath-3-1-29->t64, libimobiledevice6->-1.0-6, libjxl0.7->0.11,
libmtp9->9t64, libraw23->23t64, libsmbclient->0,
libtag1v5-vanilla->libtag2, libdmtx0b->0t64, libexiv2-27->28;
dropped: libjasper-dev, libglu-dev, libpostproc-dev, libxml2,
default-logind; python3.12 -> python3.14 across the yaml.

## core26 full pipeline: builds and boots end-to-end

A clean image build (stages: kde-qt6-core-sdk, kde-pyside6-core-sdk,
kf6-core-sdk, kf6-core26, plasma-core-desktop, plasma-desktop-session,
then 26-kde.img) completes from a fully clean state with no errors.

Ubuntu 26.04's packaged wayland-protocols (1.47) and libspa-0.2-dev
headers lag behind what kwin 6.7.5/kpipewire actually need. Fixes are
wired into plasma-core-desktop/snapcraft.yaml's sdk-stage
`override-stage` and vendored under
plasma-core-desktop/vendor/wayland-protocols/ (see that dir's
README.md for provenance and the removal condition — once core26 SDKs
ship wayland-protocols >= 1.48):

- kpipewire (and any other pipewire consumer): spa/utils/json-core.h
  calls bare isnormal()/isinf()/signbit() relying on <math.h> macros;
  if a translation unit already included <cmath> (e.g. via Qt's
  qnumeric.h), glibc's include guard suppresses the later macro defs
  and libstdc++'s <cmath> only provides std:: versions under GCC 15.2
  (reproduces even pinned to g++-14). Patch adds `#include <cmath>` +
  `using std::isnormal/isinf/signbit;` before the file's `extern "C"`
  block.
- kwin needs wayland-protocols >= 1.48 for
  staging/xdg-session-management/xdg-session-management-v1.xml —
  entirely missing from Ubuntu 26.04's 1.47 package.
- kwin's wayland/CMakeLists.txt also needs
  unstable/text-input/text-input-unstable-v3.xml at interface version
  2; Ubuntu 26.04's package only ships version 1.

Fast in-container verification (avoids a full `snapcraft pack`, which
can take hours for the Qt6/QtWebEngine stage): `lxc --project
snapcraft list` to find the stopped build container from a prior run,
`lxc start` it, then resume `kdesrc-build --no-src --rc-file <path>
[module]` directly inside it rather than rerunning the whole
pipeline. Must reconstruct snapcraft.yaml's exact `build-environment`
(PATH, PKG_CONFIG_PATH, XDG_DATA_DIRS, XDG_CONFIG_DIRS,
LD_LIBRARY_PATH, CMAKE_PREFIX_PATH, QML2_IMPORT_PATH), including
`$CRAFT_PART_INSTALL/usr` from earlier modules (e.g.
/root/parts/plasma-desktop/install/usr) — a `--no-src` rerun skips
install for already-built modules, so a missing search path silently
breaks only downstream modules. `kdesrc-build` binary lives at
.../install-data/kdesrc-build/kdesrc-build (a same-named directory
also exists), needs `--rc-file .../install-data/kdesrc-buildrc` and
`KDESRC_BUILD_IGNORE_MISSING_PROGRAMS=1`. Still do a real
`snapcraft clean` + full rebuild before trusting a container-side fix
(see diagnostics-methodology.md's "a live-patched build container is
not a fix" note) — that's the step that actually proves it's
committed/working.

## Porting risk: no core26 KDE base upstream

`kf6-core24`/`plasma-core24-desktop` are core24-only; there is no
drop-in "bump the channel" path to a `kde-neon-core-26-*` model — new
core26-equivalent content snaps would need to be built from scratch.
Check upstream again before assuming this from scratch is still
needed (not found as of the last check). Because KDE Neon Core
deliberately shares our exact gadget/base snap-ids, any KDE
gadget.yaml support must be additive (both auto-connect blocks
coexisting), not a fork.

## core26 build (confinement model, now stable)

Confinement model (verified working): each Plasma component runs
under its OWN named AppArmor profile in enforce mode (cleaner than
GNOME's approach of forcing confinement onto systemd-spawned units
via drop-ins) — startplasma-wayland, kwin_wayland(+Xwayland),
plasmashell (+kioworkers), kded6, ksmserver, kcminit,
kactivitymanagerd, gmenudbusmenuproxy, xembedsniproxy,
xdg-desktop-portal-kde, powerdevil each get their own `...plasma-*`
profile. Unconfined (expected, same as GNOME): systemd --user,
dbus-daemon, gnome-keyring-daemon, gvfsd, gcr-ssh-agent, generic
xdg-desktop-portal, gdm-wayland-session, core-desktop-session-wrapper.

Current versions: Plasma 6.7.5, KF6 6.30.0, Qt 6.11.1 (from-source
pipeline); the deb-repack pipeline (below) floats with whatever
Neon's release suite currently carries (was Plasma 6.7.5 / KF6
6.30-6.31 / Qt 6.11.1 as of 2026-10). base: core26-desktop
(plasma-desktop-session) / core26 (plasma-core-desktop).

Remaining known issues: plasma-powerdevil restart-loops (AppArmor
dbus_bind denial); org.kde.milou (KRunner backend) is deliberately
disabled upstream (commit 3be9eb9), not by us — leave as-is.
plasma-polkit-agent also fails on an unrelated AppArmor denial
(reading /proc/<pid>/cgroup). plasmashell logging "Invalid PipeWire
installation" (support.system handle) is pre-existing/non-fatal — the
pipewire-snap's SPA plugins/config aren't wired into the session env
(SPA_PLUGIN_DIR/PIPEWIRE_CONFIG_DIR); only affects screencast/media
monitor, not the desktop itself. No upowerd anywhere on this image
(base lacks it, upower-snap not yet in the KDE model) -> powerdevil
runs degraded.

The from-source pipeline's black-desktop/cursor/DRM-master/wallpaper
bugs (kwin DRM master via `login-session-control` on the kwin app,
xkbcommon ABI mismatch, missing default wallpaper/cursor-theme
packages) and the stale-prime-service/folderplugin-removal build bugs
are all FIXED and committed on the `26`/`desktop/26` branches — treat
them as historical, do not re-derive; only the reusable diagnostics
below remain relevant:

- To check DRM master/scanout authoritatively, read
  `/sys/kernel/debug/dri/<pci>/state` and `.../framebuffer` — the
  `.../clients` debugfs "master" column is NOT "is DRM master" (a
  non-zero "magic" column means authenticated, not master).
- "Daemons running" (kwin/plasmashell/ksmserver all up) is not
  sufficient evidence of a working desktop — verify plasmashell's
  QSGRenderThread is actually active, not idle in poll/futex.
- A snap's plug declared at the top level of snapcraft.yaml but not
  attached to any specific app's `plugs:` list gets NO AppArmor grant
  applied to any process — always check `plugs:` is on the actual app
  that needs it, not just declared globally.
- plasmashell scripting API notes: `screenCount` is a property, not a
  function; containment objects have no `.geometry`, use the global
  `screenGeometry(screenIndex)`; inside `snap run --shell <app>`,
  `busctl --user` fails with "Operation not permitted" even with
  correct uid/env — use `dbus-send` instead for same-snap D-Bus
  calls.
- Confined-session diagnostics for a library/ABI mismatch:
  `snap run --shell <snap>.<app> -c "..."` gives the real confined
  mount view. `ldd` inside that shell shows which content snap
  actually resolves a shared lib (mount order in LD_LIBRARY_PATH can
  prefer one over another). `LD_DEBUG=libs` (run inside the confined
  shell, redirect to a file, grep from a separate non-LD_DEBUG shell)
  pinpoints the exact library whose loader constructor is crashing.
  systemd-coredump reports "Storage:none" even with
  `Storage=external` set — don't rely on it here; grepping a raw .so
  for symbol-name substrings in `.dynstr` is a viable
  no-gdb/no-nm/no-readelf fallback for "does this build export symbol
  X".

Worth reporting upstream (not yet done): plasma-workspace-wallpapers
could ship "Next" itself (Breeze's look-and-feel defaults reference
it but Ubuntu's package doesn't ship it), or
`DefaultWallpaper::defaultWallpaperPackage()` could fall back to any
available wallpaper/solid color instead of silently giving up
forever.

Key build gotchas for the from-source SDK pipeline (do not
re-derive):

- QML module lookup: `ecm_find_qmlmodule` checks
  KDE_INSTALL_FULL_QMLDIR (=/usr/lib/<triplet>/qml) and
  QT_INSTALL_QML (Qt SDK's qt6/qml — note: NOT under qt6/qml for KF6
  SDK modules, those are directly under qml/).
- Plasma EXTENDS KF6 modules, so KF6 modules must be COPIED (not
  symlinked) into the install QML dir for the build to succeed; a
  later cleanup hook removes the copies again since the kf6-core24
  runtime snap provides them at runtime.
- snapcraft's `make` plugin "fix symlink" step scans
  $CRAFT_PART_INSTALL for symlinks during the PULL phase and chokes
  on directory symlinks (IsADirectoryError) — any such cleanup must
  happen in `override-pull` (before that scan), not `override-build`.
- `$CRAFT_PART_INSTALL` is not reliably exported into override-*
  scriptlets — use a hardcoded fallback (e.g.
  `/root/parts/plasma-desktop/install`).
- ccache is NOT preserved through `snapcraft clean` (wipes
  /root/.ccache). Setting `-DCMAKE_C_COMPILER=gcc-14` bypasses ccache
  entirely — use `CMAKE_C_COMPILER_LAUNCHER=ccache` instead to
  actually get caching.
- Incremental `snapcraft pack` (no `clean`) reuses container state —
  hooks must be idempotent.
- SDK snap versions only have a `latest/stable` channel:
  kde-qt6-core24-sdk = Qt 6.11.1, kf6-core24-sdk = KF 6.27.0.

## deb-repack build: staging Neon .debs instead of compiling

The three KDE runtime snaps are also built (branch `deb-repack` in
each repo) by staging packages from KDE Neon's apt suite instead of
compiling anything — build time drops from hours to minutes. Source:
`deb http://origin.archive.neon.kde.org/release resolute main`
(key-id 444DABCF3667D0283F894EDDE6D4736255751E5D, "Neon CI"; verify
InRelease with gpgv before trusting the key; https 404s on that host,
use http). Neon has rebased onto resolute (26.04); the "release"
suite is the User Edition, version train Qt 6.11.1 / KF6 6.30-6.31 /
Plasma 6.7.5 / apps 26.08.x. Versions FLOAT (unpinned
stage-packages); each snap records its resolved set in
`meta/pkg-manifest.txt`, and the build fails if Qt/KF6 versions
differ between the two content snaps — rebuild both if one drifts, or
you get the same ABI-skew class of bug as the noble-vs-resolute
libxkbcommon SIGSEGV. A clean image build completes end-to-end on
these branches and has been verified by inventory-diffing each new
snap against the equivalent from-source one; arm64 is NOT covered
(release/resolute suite has no kwin/plasma binaries there —
amd64-only).

Packaging gotchas (do not re-derive):

- Neon debs use SOURCE-style control names (`kf6-kcoreaddons`), not
  the Contents-index binary names (`libkf6coreaddons6`);
  stage-packages takes binary names fine, but any deb-ownership logic
  (e.g. the kf6-closure prune in plasma-core-desktop) must match
  control fields, regenerated from kf6-core26's
  `meta/pkg-manifest.txt`.
- Neon's sddm deb version sorts BELOW Ubuntu's unpinned "sddm" — pin
  the Neon build explicitly or you silently get Ubuntu's Qt
  6.10-linked sddm (the exact ABI mismatch this architecture exists
  to avoid). Neon's `sddm-theme-breeze` deb is an empty docs-only
  shell (the real theme files are inside Neon's plasma-desktop deb) —
  the session snap pins Ubuntu's `sddm-theme-breeze` instead, which
  has the real files.
- No deb in the Neon suite (or Ubuntu's pre-6.6.x plasma-workspace)
  ships the `plasma-*.target` user units the source build produced —
  `plasma-core-desktop` vendors the four target files from Ubuntu's
  resolute plasma-workspace 6.6.6 deb, with a hook rewiring them to
  the session snap's units. The deb closure also ships user units the
  source build never staged (xdg-desktop-portal daemon, kio-fuse,
  obex, mpris-proxy, appmenu-gtk-module) — a `removed_services` list
  in the hook covers them; the base provides those daemons at runtime
  instead.
- GENERAL RULE for any content runtime that uses snapd `layout:`
  symlinks pointing at the base/content snap's own paths: every path
  a `layout:` target resolves through must actually exist in the
  target snap, including the whole EGL/GLX vendor discovery chain — a
  kf6-closure deb-ownership prune that removes a package also used by
  a `layout:` target breaks it invisibly (the linter can't see this
  class of breakage; see first-boot findings below for two concrete
  instances).
- The snapcraft library linter flags ~180 "missing dependency" libs
  in plasma-core26-desktop, nearly all false positives (resolved from
  kf6-core26 or the base at runtime). To find the REAL misses, check
  each flagged soname against the base core.snap AND kf6-core26
  inventories at SEARCHABLE depth (`usr/lib[/<triplet>]/<soname>`,
  path depth <=4) — subdirectory copies (e.g.
  `usr/lib/<t>/libproxy/`) do NOT count as found, and that's exactly
  the bug class below.

First-boot findings (all fixed, kept for the general lesson):

- A library whose DT_NEEDED dependency lives in a SUBDIRECTORY
  reached only via that library's own absolute RUNPATH (not
  `$ORIGIN`) is INVISIBLE inside a session snap's mount namespace
  even when "the file exists in the base" — snapd's `layout:` mounts
  a tmpfs over `/usr/lib/<triplet>` and re-binds base entries
  individually, so a subdirectory under that path can be selectively
  hidden. Hit twice: `libproxy.so.1` -> `libpxbackend-1.0.so` under
  `usr/lib/<t>/libproxy/` (startplasma-wayland died exit 127, SDDM
  looped back to greeter), and `libpulse.so.0` ->
  `libpulsecommon-17.0.so` under `usr/lib/<t>/pulseaudio/` (dolphin
  crashed; the core26-desktop base ships NO pulseaudio stack at
  all). Fix pattern both times: symlink the subdirectory .so to the
  TOP LEVEL of kf6-core26's own `usr/lib/<triplet>` (which IS on the
  session's LD_LIBRARY_PATH) in override-prime. Every "provided by X"
  linter hit that resolves via a subdirectory RUNPATH is a potential
  session-namespace breakage — do not dismiss it via `$ORIGIN`
  reasoning unless you've confirmed the RUNPATH is actually relative.
- The kf6-closure prune list removing a package ALSO used by one of
  the session snap's `layout:` symlinks breaks those symlinks
  invisibly: removing
  libgbm1/libgl1-mesa-dri/libvdpau1/libglvnd0/libinput-bin (to dedupe
  with kf6-core26) broke the `/usr/lib/<t>/{gbm,dri,vdpau}` and
  `/usr/share/{libinput,glvnd}` layout targets -> kwin "No suitable
  DRM devices" -> no session, then after excluding those five,
  `libegl-mesa0` (EGL vendor .so + `egl_vendor.d/50_mesa.json`)
  turned out to also be needed -> "No provider of
  eglGetPlatformDisplayEXT found". Audit any future prune list
  against BOTH the session's `layout:` section and the glvnd vendor
  discovery paths.
- Xwayland execs `xkbcomp` at a compile-time absolute path and dies
  silently (kwin disables Xwayland after 4 crashes without surfacing
  its stderr) if the package providing it (`x11-xkb-utils`, an
  UBUNTU package, not a Neon one) isn't staged — mapping an old SDK
  inventory through the Neon Contents index alone will miss it.
  After deriving a package list from an inventory mapping, audit the
  UNMAPPED set for runtime binaries (`usr/bin`, `usr/libexec`) a
  `layout:` symlink expects, not just libraries. Run Xwayland
  manually inside `snap run --shell` to see its real stderr when kwin
  disables it silently; an orphaned abstract X listener left behind
  by a crashed Xwayland fills its accept backlog and makes EVERY
  subsequent X client `connect()` block forever (inspect with
  `ss -x` inside `nsenter -t <pid> -n`) — this is how an Xwayland
  crash-loop can present as an unrelated "logout hangs" bug (ksmserver
  blocked in connect(2), never claims `org.kde.ksmserver`, logout
  stalls on D-Bus activation).
- `after:` lists on snap daemon apps are serialised by snapd — keep
  them MINIMAL for anything that must own a D-Bus name at login
  (ksmserver `after: [plasma-kwin-wayland, plasma-kcminit]` delayed
  it ~90s behind a slow `Type=forking` kcminit, causing exactly the
  same "logout hangs" symptom independently of the Xwayland bug
  above; fix by starting them in parallel, matching upstream's
  plasma-core.target which has no such ordering).
- Cosmetic/non-fatal boot noise seen on this pipeline:
  `pw.conf "can't load config client.conf"` (pipewire config lives in
  the pipewire snap, not here), `gkr-pam "unable to locate daemon
  control file"`, polkit-agent failing (pre-existing, unrelated),
  logout-greeter qmlRegisterType "requires absolute URLs" spam.
- `shared-mime-info` must be staged explicitly or ksycoca builds with
  no service types ("Service type not found" spam, broken KService
  lookups).

Reference-desktop validation methodology: to tell whether a suspect
binary's misbehaviour (e.g. a SIGSEGV only seen inside the snap) is a
real packaging/environment delta rather than a genuine upstream bug,
reproduce the Neon desktop's full dependency closure in a throwaway
LXD container (`ubuntu:26.04` + the Neon repo, signed-by the same
key, through the pkgproxy) and run the suspect binary there. If it
runs clean in the faithful closure but fails in the snap, the delta
is the snap ENVIRONMENT (confinement/env vars), not the distro
package set — bisect
`QT_PLUGIN_PATH`/`QML2_IMPORT_PATH`/`XDG_*`/`LD_LIBRARY_PATH` ordering
against the working reference container. Do NOT substitute
Ubuntu-archive packages for Neon ones to "fix" a mismatch (Ubuntu's
breeze/breeze5 are stubs without the lookandfeel data; mixing
package trains from two different Plasma minor versions is the
version-mixing bug class this whole architecture exists to avoid).

The Neon release/resolute suite rolls continuously and can be
TRANSIENTLY self-inconsistent mid-rollout (e.g. libplasma6 published
at a new soname-bumping version while plasma-workspace/kwin were
still on the old one for ~1.5h) — an apt resolution during that
window mixes ABI-incompatible builds and every Plasma binary dies
with "error while loading shared libraries"; nothing in the archive
metadata prevents this (floating Depends, no Breaks, dpkg tracks
versions not sonames). Monitor via the Release file's Date field
(`curl -s .../dists/resolute/Release | grep ^Date`) and don't
rebuild mid-rollout; guard rails exist in the snap build
(link-checks key binaries against the staged tree, cross-snap Qt/KF6
skew check) but don't rely on them alone — confirm the suite is
internally consistent first.

## Build-infra notes specific to this pipeline

- The apt package-cache proxy (pkgproxy) previously had an issue
  where its cache keys dropped the first URL path segment, aliasing
  KDE Neon's `release` and `unstable` suite index URLs onto one cache
  entry — this has since been fixed upstream; no special handling
  (manual cache purges, suite-specific URL fetching) should be needed
  going forward. If index-vs-suite-mismatch symptoms (e.g. apt
  "Splitting up ... into data and signature failed", or packages from
  the wrong Neon suite) reappear, that's a regression worth
  re-reporting, not an expected recurring workaround.
- python-apt's fetch methods ignore `http_proxy` env and read
  `apt.conf` only — `snapcraft`'s stage-packages download runs as the
  apt CLI (which DOES honor the env proxy), so deb fetches work
  through a proxy, but any `apt.conf` Acquire proxy written for INDEX
  fetches applies too; all three KDE snapcraft.yamls write
  `/etc/apt/apt.conf.d/95proxy` from `$http_proxy` in `override-pull`
  (skipped when unset, so CI goes direct).
- craft-parts: `override-pull` runs AFTER craft fetches/extracts
  stage-packages — `rm`-ing a part's `state`/`stage_packages` from
  override-pull empties the extracted tree mid-lifecycle and silently
  packs an EMPTY snap (a 176KB kf6-core26 snap packed without error);
  only purge per-build generated LISTS from override-pull, never the
  part state itself.
- LXD build instances/containers from past `snapcraft` runs
  accumulate (a new yaml hash -> a new container name) and can keep
  running their own apt-update timers in the background — clean out
  old ones periodically. Reused containers can also keep stale
  `/var/lib/apt/lists/partial/*` entries from a prior failed update;
  clean those between builds too.
- Keyring seeding for a fresh LXD build instance (when no keyserver
  is reachable) comes from the
  `base-instance-snapcraft-buildd-base-v71--*` template instances
  (`/etc/apt/keyrings/craft-55751E5D.gpg`) — not needed in CI.

## KDE Neon unstable-suite packaging gap (found 2026-10-12)

Report upstream if targeting the unstable suite again.

Neon's unstable sddm build
(0.21.0+p26.04+vunstable+git20260901.0932-0) ships only
`/etc/pam.d/sddm-autologin` and `sddm-greeter` — it DROPS the plain
`/etc/pam.d/sddm` file that the release suite and Ubuntu both carry,
breaking SDDM password login on a fresh install (upgrades keep the
old conffile, masking it). `plasma-desktop-session` vendors Ubuntu's
`sddm` PAM file as the deterministic fix regardless of which suite is
targeted.

## PAM service files for KDE's lock screen / SDDM: host /etc/pam.d requirement

The screen-locker greeter + workers (and SDDM) authenticate against
PAM services (`kde`, `kde-fingerprint`, `kde-smartcard`, `sddm`,
`sddm-autologin`, `sddm-greeter`) resolved from the HOST `/etc/pam.d`
— a snap cannot provide its own PAM service directory. The image must
install the plasma snap's `usr/lib/pam.d/kde*` files into
`/etc/pam.d/` AND the first-boot factory seed (ubuntu-core's `/etc`
is a writable path seeded at first boot from
`usr/share/factory/writable/system-data/etc` — anything the image
needs under `/etc` must be written to BOTH places). Symptom when
missing: the greeter starts, the PAM worker never initializes
("Worker not ready yet, cannot authenticate"), the greeter dies, and
kwin emergency-unlocks on input.

`XDG_CONFIG_DIRS` for KDE session apps is:

    /snap/kf6-core26/current/etc/xdg:/snap/plasma-core26-desktop/current/etc/xdg:/etc/xdg

— snap system defaults PRECEDE the image's own `/etc/xdg`, and
`[$i]` kiosk-immutability markers defeat user overrides. A bad
default shipped inside a content snap cannot be fixed at image or
user level — it must be fixed in the snap itself.

## Confined desktop-session snaps: base vs. system rootfs

Confined snap apps run against THEIR OWN base snap's rootfs (its
`/usr`), not the system rootfs. On these images the system rootfs IS
core26-desktop, but a session snap that declares `base: core26` sees
plain core26's `/usr` — fixes baked into core-base-desktop
(chown/chmod hooks, static `/etc/apparmor.d`, extrausers bits) are
INVISIBLE to it until the snap's base is switched. If a confined
app's behaviour differs from the same binary run from the host, diff
`stat` of the relevant files through `/proc/<pid>/ns/mnt` (or the
app's `/proc/<pid>/mountinfo`) first.

Switching a snap's declared base: snapcraft rejects non-store base
names (e.g. `core26-desktop`) even when `build-base` is valid —
workaround pattern (see `plasma-desktop-session`'s
`build-github.sh`): sed the yaml `base` -> `core26` before EVERY
snapcraft call (including `clean`), then patch `meta/snap.yaml` in
the already-packed snap back to the real base and re-run mksquashfs.

When the base gains content a session snap used to shadow via
`layout:`, a `layout:` pointing at the SAME path the base now also
provides fails with "cannot create symbolic link ...: existing
symbolic link in the way" from snap-update-ns and aborts EVERY app of
the snap (session falls back to the greeter) — `snap-update-ns` only
reuses an existing symlink at a `layout:` path if the targets are
BYTE-IDENTICAL, and a `layout:` target (always `$SNAP`-relative) and
an image-baked rootfs symlink (always pointing at the fixed `/snap`
content mount) can never be byte-identical — so this combination is
ALWAYS broken for the whole session the moment both exist at once,
silently (sddm's session helper exits, every restart-looping app dies
instantly). Diagnose via `journalctl _UID=<uid>` grepping
"snap-update-ns failed", not the app's own logs. Resolution: the
image rootfs symlink wins (it serves confined AND
unconfined/D-Bus-system-activated processes alike, since `/snap`
content mounts are visible from every namespace) — drop the snap's
`layout:` entry and leave a NOTE comment in snapcraft.yaml so it
doesn't come back. When adding a rootfs symlink for a snap's benefit,
put it in the build.sh path that runs for EVERY image of that
desktop, not a gated/conditional build path — the snap loses its
`layout:` everywhere, always.

LD_LIBRARY_PATH ordering: keep the base's `/usr`,`/lib` paths LAST in
the snap's environment. core26-desktop ships libs the content snaps
also ship (e.g. `libwayland-server`) at OLDER versions; base-first
ordering makes the loader pick the older one and crashes Neon
binaries (`kwin: undefined symbol:
wl_global_set_withdrawn_listener`, needs
`libwayland-server >= 0.26`, base has 0.24). This latent trap only
fires once the base gains overlapping desktop packages — it was
irrelevant with an older, leaner base.

`apparmor.service` parses the WHOLE `/etc/apparmor.d` tree at boot;
one unparseable profile fails the unit and leaves that profile (and
only that one) unloaded. Profiles copied from the upstream
apparmor.d project need the standard header added
(`abi <abi/x.y>`, `include <tunables/global>`, locally-defined
`@{exec_path}`) — Ubuntu doesn't ship apparmor.d's global tunables.
Check actually-loaded profiles via
`/sys/kernel/security/apparmor/profiles`, not just file presence
under `/etc/apparmor.d`.

PAM's helper log line "check pass; user unknown"
(`helper_verify_password` in passverify.c) fires for ANY
`get_pwd_hash()` failure — `getpwnam` failing OR
`getspnam`/shadow being unreadable (PAM_AUTHINFO_UNAVAIL) — don't
trust it as literally "user unknown". Likewise "password check failed
for user (x)" is skipped (not printed) when the password was blank
and `nullok` is set.

Debugging short-lived setgid helpers (chkpwd etc.) when strace lies:
`strace` cannot observe them faithfully — a ptraced exec ignores
setuid/setgid bits (the kernel drops privileges for tracees), so an
EACCES on shadow seen under strace is an artifact of tracing itself,
not the real behaviour; attaching strace also slows the pre-exec
`close(RLIMIT_NOFILE)` loop (~180k fds) enough to blow multi-minute
timeouts before execve even happens. Working method instead: a small
STATIC C poller hammering `/proc` and dumping
`/proc/<pid>/status`(Uid/Gid/NoNewPrivs/Seccomp) + cmdline for any
process whose `comm` matches — catches a ~100ms-lived helper
reliably. Gotchas: `comm` truncates to 15 chars (grep
`pam_extrausers_`, not `chkpwd`); the helper refuses `argc!=3` or tty
stdin, so it must be caught via a REAL PAM auth attempt; `/tmp` is
`nosuid` on UC, so a setgid experiment binary placed there silently
does nothing — use a path on a non-nosuid mount; the base's
`coreutils` multi-call binary rejects unknown `argv[0]` names, so a
copied+renamed coreutils tool is not a valid probe;
`/proc/PID/status` Gid fields are real,effective,saved,fs — setgid
success shows as `egid=42` (shadow).

Getting tooling onto a fresh VM image for this kind of work: build
the QEMU VM with `-netdev user,hostfwd=tcp:127.0.0.1:<port>-:22`
(slirp; bridge devices may not exist in every sandbox), then `scp`
static binaries (`gcc -static` on the host; `strace` needs libunwind
— ship the host's
`libunwind.so.8`/`libunwind-ptrace.so.0`/`libunwind-x86_64.so.8`
alongside and `LD_LIBRARY_PATH` them, assuming host and image share
the same libc ABI).

Tooling bugs to fix before trusting a QA script's output: running
checks as ROOT over ssh queries the WRONG user manager (`--user`
flags resolve against root's own manager, not the real session's); a
wayland socket name should never be hardcoded (discover it from the
compositor's cmdline — the real session can use `wayland-1`, not
always `wayland-0`); launching apps or running
`loginctl lock/unlock`/logout "tests" without targeting the real
session's uid/bus can stop or affect a DIFFERENT (e.g. root's ssh)
session by accident. Run checks via:

    runuser -u <user> -- env XDG_RUNTIME_DIR=/run/user/<uid> DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus ...

and discover the wayland socket dynamically.

Konsole under `snap run` can get `HOME=/root` (wrong HOME inherited),
producing `.bashrc: Permission denied` — a known open gap, not yet
fixed.

Image size facts: `pc.img` raw size (21.5GB) is the pc-amd64 gadget
partition layout (13GB data partition), identical for GNOME/KDE/old
source builds — this is fixed by the gadget, not a reflection of how
much content snaps actually use. A deb-repack KDE image uses ~6.8GB
of the 13GB data partition (host sparse footprint ~5.9GB); content
snaps: kf6-core26 614M + plasma-core26-desktop 641M + session 569M
(compressed).

## plasma-setup: the KDE first-boot wizard

KDE now has a first-boot wizard analogous to GNOME's
`ubuntu-desktop-init`: `plasma-setup` (part of
`plasma-desktop-session`), launched via `plasma-setup.service`
(enabled through a `multi-user.target.wants` symlink build.sh
installs — `systemctl is-enabled` shows "disabled" despite this
actually running; don't be confused by that mismatch).

- Gate file: `/etc/plasma-setup-done`, checked via
  `ConditionPathExists` on `plasma-setup.service`. `/etc` is
  read-only on Core, so the helper writes the file via direct
  `QFile::open` (follows symlinks) — the standard `/etc/writable`
  symlink pattern works for this (`ConditionPathExists` treats a
  dangling symlink as absent; `open` creates the real file on first
  run). Second-boot skip verified end-to-end (service shows
  "skipped, unmet condition
  ConditionPathExists=!/etc/plasma-setup-done").
- `authhelper.cpp`'s `createuser()` order is useradd
  (extrausers-shimmed) -> extraGroups validation (`getgrnam` each,
  ABORTS on first miss) -> chpasswd. The upstream default
  `plasmasetuprc` ships `UserGroups=wheel`, which doesn't exist on
  Ubuntu — the abort lands AFTER account creation but BEFORE password
  setting, leaving a locked shadow entry (`<user>:!`) that rejects
  every password at the greeter. Fix: rewrite `UserGroups=sudo` in
  the image (matches the cloud-init `--user` path); the resulting
  `usermod -aG sudo` lands correctly in the pre-seeded writable
  `/var/lib/extrausers/group`.
- snapd-private `XDG_CONFIG_HOME` hides plain-`$HOME` config from
  confined session apps: snapd runs every confined app with
  `XDG_CONFIG_HOME=$SNAP_REAL_HOME/snap/<snap>/common/.config` (and
  matching CACHE/STATE/DATA), so config an upstream package drops
  into plain `$HOME/.config` is INVISIBLE to confined processes. Hit
  as `plasma-setup`'s `kscreenlockerrc` (`Autolock=false`, written by
  its tmpfiles fragment to `/run/plasma-setup/.config`) never
  reaching confined kwin, whose default 5-min idle timer then locked
  the passwordless wizard session with no unlock path except reboot.
  Fix pattern: a SECOND `tmpfiles.d` fragment mirroring the same
  files into the snap-private dir (name it to sort BEFORE any
  upstream fragment that does a final recursive `Z` ownership pass;
  `/run` is tmpfs so `f`/`C` create-if-missing lands fresh content
  every boot). Diagnose what config a confined process ACTUALLY
  reads via
  `tr "\0" "\n" < /proc/<pid>/environ | grep XDG_CONFIG` — not
  `$HOME` conventions. This class of bug (confined-app config going
  to the wrong `XDG_CONFIG_HOME`) can recur for any other upstream
  component that assumes plain `$HOME` dotfiles.
- `/usr/lib/<triplet>/qt6/plugins/kf6/kauth` is a concrete instance
  of the snap `layout:`-vs-rootfs-symlink conflict described above
  (KAuth loads plugins from that hardcoded path regardless of
  `QT_PLUGIN_PATH`) — resolved by dropping the snap's `layout:`
  entry in favor of the image rootfs symlink, per the general rule
  above.
- Verification loop that worked for this wizard: build the image with
  a root password set (`build.sh --desktop kde --root-password x`,
  no `--user`, so the wizard runs) and run it with a VNC display (VM
  run tooling: build-tools.md) — VNC on localhost for wizard
  clicking, `ssh root@<vm-ip>` password `x` for introspection.
  Wizard-session health check via `pgrep -x` (NOT `-f` over ssh —
  see diagnostics-methodology.md's pgrep/pkill section); idle-lock
  absence verified by zero "kscreenlocker" journal lines across a
  boot plus >10 min of untouched idle time.
- Harmless noise on the wizard session:
  "pam_extrausers(kde:auth): unrecognized ENCRYPT_METHOD value
  [YESCRYPT]" (extrausers shadow's yescrypt entries) — the
  greeter-side auth path is what actually matters, this line alone is
  not evidence of a real auth problem.
