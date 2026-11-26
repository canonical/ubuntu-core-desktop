# Update KDE Qt/KF6 SDK snaps (kde-qt6-core24-sdk, kf6-core24-sdk) to core26

Date: 2026-09-18

## Impact / Priority

High. This blocks the KDE core26 port (`20260918-kde-core26-port.md`).
The Plasma desktop build (plasma-core-desktop content snap) depends on
two build-time SDK snaps for its Qt/KF6 toolchain; those SDK snaps are
still core24-based, so mixing them into a core26 build risks hidden
ABI/version drift and is the stated reason the KDE stack cannot yet be
cleanly rebased onto core26.

What a real user would observe: nothing directly (the core24 image
still works), but the KDE desktop cannot be shipped on core26 until its
toolchain is also core26, leaving the whole KDE flavour pinned to an
end-of-life base.

## Motivation / root cause

The two SDK snaps are built by KDE Neon and published to the Snap Store
under the publisher "KDE**", NOT by us and NOT by Canonical:

    name: kde-qt6-core24-sdk   (Qt fork SDK)   snap-id isco3uAbV8loHXUSaF1yGB7gjAVyKPF2
    name: kf6-core24-sdk       (KF6 SDK)       snap-id hUFjXP7x8Tpffs9LbTiTLwf7DbSls5Tu

They were created in the core22/core24 era and carry `base: core24`
(verified by unsquashfs-ing the store snaps). Unlike GNOME's
gnome-46-2404 / mesa-2404 (Canonical-supported content snaps), these KDE
SDK snaps are the upstream KDE packaging and we have no control over
when (or if) KDE finishes a core26 rebuild.

The store `latest/stable` version strings contain a "26.04.2" component,
which LOOKS like it means "built against 26.04", but this is NOT
confirmed and is in fact misleading. Verified directly from the
work.core24 snapcraft source: the version is a MANUALLY HARDCODED string
(`version: 6.11.1-6.27.0-6.7.1-26.04.2`, with an upstream comment
"Please update to match qt-version, &kf6-version, &plasma-version,
&apps-version"), while the actual build is still `base: core24` + apt
suite `noble` (Ubuntu 24.04). So the SDK snaps are genuinely
core24/noble-built; the "26.04.2" is only a KDE packaging-wave label,
not evidence of a 26.04 build. Do NOT treat these as already-26.04-built.

Upstream git repos (both under KDE Neon snap-packaging,
invent.kde.org):

    https://invent.kde.org/neon/snap-packaging/kde-qt6-core-sdk.git
    https://invent.kde.org/neon/snap-packaging/kf6-core-sdk.git

Note: these SDK repos carry ad-hoc version pins that can be stale.
Example found: kf6-core-sdk commit be7bb1d "try release/24.12 for
kio-extras" (Scarlett Moore, 2025-02-25) pins kio-extras to
source-branch release/24.12 instead of the released 6.x tag. That pin
lives on `master` (the stale core22 branch), not work.core24, but it
illustrates the risk of blindly adopting upstream's ad-hoc pins. When
we do our own core26 rebuild we should pin to the exact released
versions (Qt 6.11.1, KF6 6.27.0, Plasma 6.7.5) rather than inherit
upstream's one-off branches.

Branch state as of 2026-09-21 (verified via git ls-remote / clone):

    kde-qt6-core-sdk:
      master           -> name kde-qt6-core22-sdk, base core22, Qt 6.8.0  (stale)
      work.core24      -> the core24 SDK we currently consume
      work.core26      -> name kde-qt6-core26-sdk, base core26,
                          build-base devel, grade devel, Qt 6.11.1   (IN PROGRESS)

    kf6-core-sdk:
      master           -> name kf6-core22-sdk, base core22, KF 6.10.0  (stale)
      work.core24      -> name kf6-core24-sdk, base core24, pins kf6-version
                          v6.27.0, apt suite noble
      work.core26      -> DOES NOT EXIST (only kde-qt6 has it)

So upstream has started the Qt side (work.core26) but has NOT started
the KF6 side. We need to finish/adopt both.

## Technical facts to keep in mind (do not re-derive)

- BUILD BASE decision: use `base: core26` (with NO `build-base` line)
  and `grade: stable`. Two reasons bundled:
  * Do NOT use `build-base: devel`: upstream's kde-qt6-core-sdk
    work.core26 used it, but `devel` tracks Ubuntu's moving development
    series and will eventually roll past resolute (26.10/27.04) and
    break reproducibility.
  * Do NOT write `build-base: core26` either: Snapcraft 9 REJECTS
    declaring `build-base` when its value equals `base` ("cannot
    specify a core 'build-base' alongside a 'base'"). `build-base`
    defaults to `base` when unset, so just `base: core26` with no
    build-base line is correct (and `grade: stable` is allowed since
    the base is stable). This matches the project's documented build
    convention: omit build-base when base is already coreNN.
- glibc is backward-compatible: the core24-built SDK libs
  (libQt6Core.so.6) reference at most GLIBC_2.35; resolute (26.04)
  ships glibc 2.43, which satisfies them. So ABI drift is a *latent
  risk*, not something that already fails today — but rebasing the SDK
  to core26 removes the risk cleanly rather than relying on backward
  compatibility.
- The SDK snaps are build-time only (`-sdk` suffix). snapcraft mounts
  build-snaps independently of the project base, so they are referenced
  by their store name under `build-snaps:` and via absolute paths
  /snap/<name>/current/... throughout plasma-core-desktop's
  snapcraft.yaml and hooks. Renaming the snaps (core24 -> core26) means
  updating every one of those references.
- The Qt SDK bundles the private Qt headers KWin needs (verified: 4443
  private headers present, including QtCore/private, QtGui/private,
  QtWaylandClient/private, QtQuick/private). This means the neon apt
  repo's qt6-base-private-dev / qt6-wayland-private-dev / corrosion
  build-packages in plasma-core-desktop are REDUNDANT and can be
  dropped once the SDK is core26 (see `20260918-kde-core26-port.md`).
- kde-qt6-core-sdk's work.core26 uses `build-base: devel` and
  `grade: devel`; we override BOTH to `core26` / `stable` per the BUILD
  BASE decision above. (See also
  `20260915-snapcraft-core26-desktop-base-not-supported.md` for the
  general "base: core26-desktop" validation caveat.)

## Steps

1. Clone the SDK repos (alongside plasma-core-desktop /
   plasma-desktop-session), on the core26 theme. There are THREE SDK
   snaps, not two:

   - kde-qt6-core-sdk:      upstream work.core26 exists (Qt 6.11.1).
   - kde-pyside6-core-sdk:  work.core24 only; no core26. Must scaffold
                            core26 ourselves (PySide6 6.11.1 bindings).
   - kf6-core-sdk:          work.core24 only; no core26. Scaffold
                            core26.

   All three end with `base: core26` + `grade: stable` and NO
   `build-base` line (Snapcraft 9 rejects build-base when it equals
   base).

2. Rebuild both SDK snaps with a core26 base, targeting KDE Neon's
   CURRENT stable version combination (verified from the neon noble
   archive on 2026-09-21), NOT the older versions our core24 SDK snaps
   happen to pin:

        Qt 6.11.1  +  KF6 6.30.0  +  Plasma 6.7.5

   The core24 SDK snap we currently consume pins KF6 6.27.0 (store
   version string 6.11.1-6.27.0-6.7.1-26.04.2, dated 2026-07-03), but
   KDE Neon has since moved to KF6 6.30.0 (libkf6archive6
   6.30.0-0zneon+24.04+noble). So the core26 rebuild should bump KF6
   6.27.0 -> 6.30.0 to match KDE Neon's current tested set, while
   keeping Qt 6.11.1 and Plasma 6.7.5 (both already current). This is
   the "later, better-tested" combination the user asked about.

   Version-set decision (do NOT downgrade to resolute defaults):
   resolute (26.04) ships Qt 6.10.2 / KF6 6.24.0 / Plasma 6.6.6, all
   OLDER than the KDE stack we build (Qt 6.11.1 / KF6 6.30.0 / Plasma
   6.7.5). KDE Neon's design intentionally tracks KDE's latest
   releases rather than Ubuntu's frozen LTS minors. Downgrading to
   resolute's Plasma 6.6.6 would (a) contradict the parent item's
   explicit "do not downgrade from 6.7.5" instruction and (b) not even
   build (Plasma 6.6.6 predates the Qt 6.8+ compatibility fixes that
   forced the 6.2.5 -> 6.7.5 forward-port). So: keep the KDE layer
   (Qt/KF6/Plasma) at 6.11.1 / 6.30.0 / 6.7.5, rebuilt against core26;
   match resolute only for the SYSTEM library stage-packages (glibc,
   libavcodec62, libqalculate23, etc. -- already bumped in
   plasma-core-desktop's snapcraft.yaml).

3. KEY PORT DECISIONS (made during the actual port, 2026-09-21):

   - ffmpeg: `ffmpeg-2604-sdk` does NOT exist upstream. Use resolute's
     apt ffmpeg dev packages instead of any ffmpeg SDK snap (same fix
     as the Qt SDK).
   - PySide6: KDE Neon publishes `kde-pyside6-core24-sdk` but no core26
     equivalent. We scaffold `kde-pyside6-core26-sdk` ourselves
     (pyside-setup 6.11.1 against kde-qt6-core26-sdk); needed because
     kio/kcoreaddons ship PySide6 bindings.
   - kf6-core-sdk theme cluster: the SDK builds a stale Plasma theme
     (libplasma + oxygen + breeze + plasma-integration +
     qqc2-breeze-style + kdecoration2) that our Plasma build does NOT
     use (plasma-core-desktop ignores oxygen/breeze and builds its own
     libplasma 6.7.5). DROP all 6 parts from kf6-core-sdk. Also
     removes a libplasma<->oxygen circular dependency and the
     kf6-core24-sdk bootstrap self-reference.
   - kf6-core24/ RUNTIME content snap: references in QT_PLUGIN_PATH/
     QML_IMPORT_PATH are left AS-IS (kf6-core24) for now — build-time
     QML/plugin search paths to the separate runtime content snap, not
     a build-snap. Building a kf6-core26 runtime snap is deferred.
   - python: resolute ships python3.14, so python3.12 -> python3.14
     across the SDK snapcraft.yamls.
   - RESOLUTE-SPECIFIC BUILD FIXES (each surfaced one-at-a-time during
     the KF6 SDK build; record so they aren't re-derived):
     * ninja: the source-built ninja v1.11.1 configure.py imports the
       `pipes` module, removed in Python 3.13+. Replace the source
       build with apt `ninja-build` (1.13.2 on resolute).
     * gobject-introspection: gsettings-desktop-schemas and gdk-pixbuf
       use -Dintrospection but lacked `gobject-introspection` in
       build-packages (was transitively present on noble). Add it
       explicitly.
     * libdbusmenu-qt6: a frozen 2016-era library (last release 0.9.3)
       whose cmake_minimum_required(VERSION 2.x) is rejected by
       resolute's CMake 4. Fix: add -DCMAKE_POLICY_VERSION_MINIMUM=3.5
       to its cmake-parameters.
     * stage conflict: knotifications (via libcanberra stage-packages)
       stages a different set of org.gnome.desktop.*.gschema.xml than
       gsettings-desktop-schemas. Fix: extend knotifications'
       `stage:` -list to exclude
       calendar/default-applications/lockdown/search-providers/session
       schemas too.
     * build ordering: gdk-pixbuf (and glib/libffi/
       gsettings-desktop-schemas) are leaf bootstrap parts that
       snapcraft built AFTER fix_pc_files rewrote all .pc files
       (/root/stage -> /snap/kf6-core26-sdk/current), breaking their
       meson environment validation. Fix: add gdk-pixbuf, glib,
       libffi, gsettings-desktop-schemas to fix_pc_files's `after:`
       list so they build before the .pc rewrite.
     * TWO meson versions (pre-existing upstream quirk): meson-deps
       pins meson 1.4.0 from source (pip install to /usr/local/bin +
       staged $CRAFT_STAGE/usr/bin), while wayland-protocols uses apt
       `meson` (1.10.1 on resolute). meson 1.4.0 predates Python 3.14
       and is the fragile one. Long-term: bump meson-deps to a
       Python-3.14-compatible meson; short-term the ordering fix above
       suffices.
     * meson ModuleNotFoundError: the pip-installed meson 1.4.0's
       `mesonbuild` module lands in $CRAFT_STAGE/usr/lib/python3/dist-
       packages, but the shared &buildenvironment PYTHONPATH only
       listed the SDK paths, so `meson --version` failed with "No
       module named 'mesonbuild'". ROOT CAUSE (final): the meson
       plugin's VALIDATION environment does NOT include the part's
       build-environment (so PYTHONPATH fixes never apply). The meson
       plugin prepends $CRAFT_STAGE/usr/bin to PATH, so `meson`
       resolves to the STAGED meson (from meson-deps'
       `pip install --target`), whose mesonbuild is in the staged
       dist-packages that the system python3 can't find. FIX: make
       meson-deps install meson ONLY to the system
       (`pip install --break-system-packages .`, no --target staged
       copy), so `meson` resolves to /usr/local/bin/meson whose
       mesonbuild is in /usr/local/lib/python3.14/dist-packages. Also
       bump meson 1.4.0 -> 1.10.1 (Python-3.14-compatible).
     * package renames (noble -> resolute):
       libcanberra0t64->libcanberra0, libexiv2-27->28,
       libglib2.0-0->0t64, libical3->3t64, libimath-3-1-29->t64,
       libimobiledevice6->-1.0-6, libjxl0.7->0.11, libmtp9->9t64,
       libraw23->23t64, libsmbclient->0, libtag1v5-vanilla->libtag2,
       libdmtx0b->0t64; DROPPED (gone): default-logind,
       libpostproc-dev, libxml2.
   - LOCAL SDK STAGING (no host snapd/sudo): the built SDK snaps are
     NOT in the store, and `build-snaps:` resolves from the store/host
     snapd (needs sudo). Instead, unsquash each built SDK snap into the
     consuming repo's `.sdk/<name>/` (gitignored), stage it via a
     `plugin: dump` part with `organize: {'*': <name>/}`, and rewrite
     `/snap/<name>/current/` -> `$CRAFT_STAGE/<name>/` in env paths.
     Add the dump part to every consuming part's `after:` list.
   - SDK .pc RELOCATION: the SDK snaps' pkg-config (.pc) files hardcode
     absolute `prefix=/snap/<name>/current/usr` (782 files in the Qt
     SDK). Do NOT rewrite them; instead symlink
     `/snap/<name>/current` -> `$CRAFT_STAGE/<name>` in the dump
     part's `override-stage` (the build container's /snap is a plain
     writable dir, not a snapd mount). This makes all hardcoded paths
     resolve unchanged.

4. Enable and VERIFY ccache before/while iterating (see the "fast
   iteration" requirement below) — these are massive C++ builds (Qt is
   a ~1GB snap, KF6 ~734MB), each full build is long.

5. Update plasma-core-desktop's snapcraft.yaml + hooks to reference the
   new core26 SDK snap names everywhere (build-snaps, PATH,
   PKG_CONFIG_PATH, LD_LIBRARY_PATH, CMAKE_PREFIX_PATH,
   QML2_IMPORT_PATH, hooks 000/200/400/999 that hardcode
   /snap/kf6-core24-sdk/... and /snap/kde-qt6-core24-sdk/...).

6. Drop the now-redundant neon apt repo block + qt6-base-private-dev /
   qt6-wayland-private-dev / corrosion build-packages from
   plasma-core-desktop (private headers are provided by the Qt SDK
   snap).

7. Rebuild plasma-core-desktop against the new SDKs and confirm Plasma
   6.7.5 still compiles + the content snap still passes its hook tests.

8. Regression: build + boot the KDE Core 26 image to a rendering Plasma
   desktop.

## Fast iteration / ccache requirement

IMPORTANT: do NOT `lxc delete` the snapcraft build container between
iterations. Snapcraft reuses the existing LXD instance across
`snapcraft pack` runs (only deletes if incompatible or >90 days old),
so build-packages stay installed and only changed parts rebuild.
Deleting the container forces a full re-download + re-install of all
build-packages each time (the "several minutes redoing" cost). Just
re-run the snap build (`snapcraft pack`) without deleting the instance.

FASTER ITERATION: test fixes directly inside the running container via
`lxc exec <instance> --project snapcraft -- bash -c '...'` (reproduce
the exact failing command with the part's env) BEFORE re-running
`snapcraft pack`. This avoids the ~1-2 min snapcraft grammar/part-graph
processing (100% CPU, inherent to the 102-part YAML) on every fix. Only
re-run `snapcraft pack` once a fix is verified in-container.

CONCRETE IN-CONTAINER ITERATION WORKFLOW (avoid snapcraft pack per fix):

1. Let `snapcraft pack` fail; snapcraft leaves the LXD instance STOPPED
   but its disk (pulled sources under /root/parts/<name>/src, staged
   deps under /root/stage) is intact.
2. `lxc start <instance> --project snapcraft`, then manually reproduce
   the failing part's build command (meson setup / cmake / ninja / the
   environment-validation command like `meson --version`) with the
   exact environment snapcraft logged
   (`:: export PATH=... PYTHONPATH=...` etc. and the
   `plugin validation command` / cmake invocation are all in the
   snapcraft log at ~/.local/state/snapcraft/log/).
3. Iterate on the fix in-container (seconds per cycle); edit
   snapcraft.yaml only once the command succeeds in-container.
4. Run `snapcraft pack` one final time to confirm the part (and the
   rest) builds. The ~10 min part-graph cost is only paid on this final
   run.

WHY the 100% CPU takes ~10 min (not 1-2): it's snapcraft's part-state/
dependency-graph computation -- a tight "check if Part('X'):N is dirty/
outdated" loop (~6000 checks for 103 parts). It is QUADRATIC in parts x
dependencies, and the KF6 SDK's fix_pc_files part has ~90 `after:`
entries (making it pathological). Single-threaded Python, so one core
pegged at 100%. Inherent to snapcraft + this snapcraft.yaml design; not
fixable without reducing the huge `after:` lists (risky upstream
change).

The SDK builds are huge. Set up persistent ccache and verify it
actually hits before doing repeated builds:

- Use `CCACHE_DIR: ${SNAPCRAFT_PROJECT_DIR}/.ccache` in each part's
  build-environment (so the cache lives outside the LXD container and
  survives `snapcraft clean`) + `CCACHE_NOHASHDIR: "true"` so cache
  hits survive the snapcraft project-path remounts.
- Ensure the compiler/cache launcher is actually used: either
  `PATH: /usr/lib/ccache:<...>` or
  `-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache`.
- Verify with `ccache -s` (cache hit rate > 0, growing cache dir) after
  a second build of the same source, before relying on it for
  iteration.
- Add `.ccache/` to .gitignore.

    VERIFIED 2026-09-21 (Qt SDK build): ccache works. In-container the
    cache lands at /root/project/.ccache (the mount of
    $SNAPCRAFT_PROJECT_DIR/.ccache), NOT the default /root/.cache/ccache
    — so `ccache -s` only shows real stats after
    `export CCACHE_DIR=/root/project/.ccache`. Observed during the
    first full Qt 6.11.1 compile: 82% of calls cacheable, ~18% hit rate
    (expected cold on a fresh build), cache growing to 655MB+. Consider
    raising CCACHE_MAXSIZE above the 5GiB default before the 2nd build
    so large QtWebEngine/Chromium objects are not evicted between
    iterations.

## References

- `20260918-kde-core26-port.md` (the parent port this unblocks)
- Upstream tracking: canonical/snapcraft#6297 "Task: kde-neon-6 core26
  support" (filed by Scarlett Gately Moore, KDE Neon snap-packaging
  maintainer). It asks snapcraft for a first-class KDE/Plasma desktop
  extension on core26 (analogous to the gnome extension). As of
  2026-09-21 it is OPEN/triaged; Scarlett is "working on content snaps"
  (i.e. the kf6-core26/plasma-core26 content snaps we found absent).
  Our manual SDK build is effectively doing by hand what this issue
  asks upstream to provide as a feature.
- What a "desktop extension" is: a snapcraft extension (e.g.
  kde-neon-6, gnome) is a declarative bundle of snapcraft.yaml
  boilerplate that wires a GUI app to its runtime: the KF6/GTK content
  snap, theme/icon content plugs, build-snaps
  (kde-qt6-core24-sdk/kf6-core24-sdk), build env
  (PATH/LD_LIBRARY_PATH/CMAKE_PREFIX_PATH/XDG_*), desktop/wayland/x11/
  opengl plugs, and a desktop-launch command-chain. Verified:
  snapcraft 9.1.1's kde-neon-6/gnome extensions only support
  core22+core24 (get_supported_bases() returns ("core22","core24"));
  gpu supports core26. So there is NO core26 KDE extension yet -- which
  is why we hand-build the SDKs and hand-wire the environment instead
  of using `extensions: [kde-neon-6]`.
- The extension is a CONVENIENCE FOR APP AUTHORS, not for the desktop
  session. It assumes a standard app shape (one command + desktop/
  wayland/x11 plugs + desktop-launch). The Plasma/GNOME desktop SESSION
  (KWin, plasmashell, daemon:dbus services, activates-on,
  systemd-user-control, confined-session AppArmor) needs far more than
  any extension provides, so we hand-build it regardless of base. It
  might marginally help if the big ubuntu-desktop-session snap is later
  split into per-component snaps, but the session-specific parts
  (daemons, confinement, D-Bus activation) still dominate.
- KDE core26 model does NOT use a separate gnome-session/
  ubuntu-desktop-session snap. Its session stack is
  plasma-desktop-session (app) + plasma-core24-desktop + kf6-core24
  (content). BUT it DOES use the core26-desktop BASE snap, which is the
  "big" snap that packs GDM + gnome-session + the GNOME stack
  (gnome-shell + extensions) as binaries. So the KDE image carries the
  whole GNOME stack even though Plasma only needs GDM from it. This is
  the architectural debt the original core desktop authors left (they
  packed everything into the base to prove the concept, planning to
  later split it out -- the project documentation cautions to "move
  most of this content out of the base into separate snaps and use a
  plain core26 base instead"). The split work (moving GDM/
  gnome-session/gnome-shell out of the base) is a separate item; the
  desktop extension is NOT useful there because those are
  daemons/session components, not apps.

## Resolution (2026-09-22)

This item's headline deliverable — rebuilding the three core26 SDK
snaps — is COMPLETE. All three were built successfully from scratch:

    kde-qt6-core26-sdk      6.11.1            (~1.29 GB)  built 2026-09-21
    kde-pyside6-core26-sdk  6.11.1            (~1.30 GB)  built 2026-09-21
    kf6-core26-sdk          6.11.1-6.30.0-6.7.5-26.04.2  (~2.08 GB)  built 2026-09-22

The KF6 SDK build (the long pole, 103 parts) succeeded after resolving
the meson ModuleNotFoundError and the follow-up failures documented
during the build (staged-SDK-python shadowing /usr/bin/env python3
shebang; PYTHONPATH for the two-meson-versions quirk; meson-deps using
/usr/bin/python3 -m pip; GLib helper-path (gio-2.0.pc) mismatch;
duplicate GLib staging from qtkeychain; stale wayland-protocols meson
install.dat metadata). Final artifact:
kf6-core26-sdk_6.11.1-6.30.0-6.7.5-26.04.2_amd64.snap. The build reused
the retained snapcraft LXD instance and completed without recreating
the container.

STEPS 1-4 (clone repos, rebuild 3 SDKs, port decisions, ccache) are
DONE.

STEPS 5-8 REMAIN and are carried by the parent port item
`20260918-kde-core26-port.md` (steps 3b-5):

5. Update plasma-core-desktop's snapcraft.yaml + hooks to reference the
   new core26 SDK snap names (build-snaps, PATH, PKG_CONFIG_PATH,
   LD_LIBRARY_PATH, CMAKE_PREFIX_PATH, QML2_IMPORT_PATH, hooks
   000/200/400/999).
6. Drop the now-redundant neon apt repo block + qt6-base-private-dev /
   qt6-wayland-private-dev / corrosion build-packages.
7. Rebuild plasma-core-desktop against the 3 core26 SDKs.
8. Build + boot the KDE core26 image and confirm Plasma 6.7.5 renders.

kf6-core-sdk git state at hand-off: branch `core26`, HEAD 5b8c4a0, with
a large UNCOMMITTED snapcraft.yaml diff (the meson/PYTHONPATH/
package-rename fixes described above). The build script, .gitignore,
build.log, and the built .snap are untracked. Do NOT lose the
uncommitted snapcraft.yaml diff.
