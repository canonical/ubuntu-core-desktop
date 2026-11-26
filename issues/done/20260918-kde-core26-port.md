# Port the KDE Neon Core (Plasma) image from core24 to core26

Date: 2026-09-17

## Impact / Priority

High. This is the stated end goal of the KDE work: get the KDE image
onto the same Ubuntu 26.04 (core26) level as the active GNOME Core 26
work, so both desktop flavours ship on the current base. Until this is
done the KDE image is stuck on the older core24 base and cannot track
the core26 security/feature updates the GNOME image already gets.

What a real user would observe: nothing yet (the core24 KDE image
works), but the KDE image is a dead-end on core24 — it cannot be
shipped as the current product alongside GNOME 26, and any core26-only
fixes/features (e.g. the confined-session AppArmor work already done
for GNOME 26) would have to be re-derived for KDE on a base that is
being left behind.

## Context

Stage 1 (core24 baseline) is DONE and verified: the KDE Neon Core image
builds and boots to a rendering Plasma desktop (see
`20260917-build-kde-neon-core-image.md`). This is stage 2: port it to
core26, mirroring the GNOME desktop24 -> desktop26 migration already
done in ubuntu-core-desktop.

Current versions (core24 build): Plasma 6.7.5, KF6 6.27.0, Qt 6.11.1,
base core24.

Version note: Ubuntu 26.04 (resolute) ships Plasma 6.6.6
(plasma-workspace 4:6.6.6-0ubuntu0.1, the current -updates SRU). That is
OLDER than our 6.7.5, because Ubuntu LTS pins a Plasma minor (6.6) and
only SRUs bugfixes, whereas we build from KDE Neon's own snap sources
and track KDE's latest (6.7.5). So the Plasma/KF6/Qt versions are
already at-or-above 26.04 level; the core26 port is about the BASE
(core24 -> core26), not about bumping Plasma. When porting, keep Plasma
6.7.5 (or KDE's latest) rather than downgrading to 6.6.6.

## Key facts / gotchas (do not re-derive)

- No core26 KDE base exists upstream. kf6-core24 /
  plasma-core24-desktop are core24-only. There is no "just bump the
  channel" path — the kf6-core26 / plasma-core26-desktop content snaps
  must be built from scratch (or check whether upstream neon has since
  published a core26 track before assuming a from-scratch build).
- The KDE model reuses the SAME core24-desktop base snap-id and
  pc-desktop gadget snap-id as our GNOME 24 image. A core26 KDE model
  would reuse core26-desktop + pc-desktop 26, same as GNOME 26.
- plasma-core24-desktop's snapcraft.yaml pulls a KDE neon apt repo
  (origin.archive.neon.kde.org, noble suite) in addition to the
  standard archive — a build-time network dependency to keep in mind
  for core26.
- The snapcraft `base: core26-desktop` validation issue (see
  `20260915-snapcraft-core26-desktop-base-not-supported.md`) applies to
  any core26-desktop-based snap build.

## Steps (mirror the GNOME 24->26 pattern)

1. Duplicate the KDE Core 24 build/boot scripts into Core 26 variants
   (copy-and-rename, like the Core 26 GNOME build relates to the Core
   24 one), with its own IP/MAC so it doesn't clash with the existing
   Core 26 test VM.
2. Duplicate the KDE model into
   ubuntu-core-desktop-kde-26-amd64-dangerous.model with base:
   core26-desktop, following the same snap/channel adjustments made
   when porting the GNOME model 24 -> 26 (see
   `20260915-update-old-snaps-in-desktop26-model.md` for the pattern:
   which snaps needed 26/stable channels, which bases could be
   dropped).
3. Rebuild plasma-core-desktop / plasma-desktop-session against core26
   (or confirm/adjust their snapcraft.yaml base). This is genuinely new
   porting work — same category as the core24->core26 GNOME migration
   (the chisel/apt conflict issues documented for core-base-desktop
   likely apply).
4. Build and boot the KDE Core 26 image, debug until Plasma boots on
   core26, reusing the confined-session AppArmor/systemd fixes already
   discovered for GNOME's core26 port where applicable (see
   `20260916-confine-gnome-session-user-units.md` and the other
   confined-session items — the KDE app snap will likely hit the same
   class of confinement gaps).
5. Final regression: verify the GNOME Core 24/26 builds still build and
   boot unmodified.

Note: this is a follow-on from `20260917-build-kde-neon-core-image.md`
(stage 1 done, stage 2 = this file).

## Progress update (2026-09-22)

Steps 1-2 DONE: the Core 26 KDE build/boot scripts, the core26 KDE model
(ubuntu-core-desktop-kde-26-amd64-dangerous.json), and the
`26-kde.img` build target are all created in the ubuntu-core-desktop-kde
repo.

Step 3 (SDK portion) DONE — all three core26 SDK snaps are built from
scratch (see `20260921-update-kde-core24-sdk-snaps-to-core26.md`):

- kde-qt6-core26-sdk      6.11.1
- kde-pyside6-core26-sdk  6.11.1
- kf6-core26-sdk          6.11.1-6.30.0-6.7.5-26.04.2

REMAINING:

- Step 3 (continued): rebuild plasma-core-desktop against the 3 core26
  SDKs. PARTLY STARTED — the plasma-core-desktop repo (branch `kde`)
  already carries UNCOMMITTED changes that: bump
  `base: core24 -> core26` + summary to "Ubuntu 26.04"; bump resolute
  stage-packages (libavcodec60->62, libavfilter9->11, libavformat60->62,
  libdisplay-info2->3, libqalculate22t64->23, drop
  libproxy1-plugin-networkmanager); and wire ccache into
  build-environment (replacing the old hardcoded /root/.ccache). Do NOT
  lose this uncommitted diff. STILL TO DO in that file: rewrite the SDK
  references — build-snaps + all /snap/kde-qt6-core24-sdk/... and
  /snap/kf6-core24-sdk/... paths (PATH, PKG_CONFIG_PATH,
  LD_LIBRARY_PATH, CMAKE_PREFIX_PATH, QML2_IMPORT_PATH, hooks
  000/200/400/999) to core26 names; drop the neon apt repo block +
  qt6-base-private-dev/qt6-wayland-private-dev/corrosion
  build-packages (private headers now come from the Qt SDK snap).
- Step 4: build + boot the KDE Core 26 image and confirm Plasma 6.7.5
  renders (reuse GNOME core26 confined-session AppArmor/systemd fixes
  where applicable).
- Step 5: GNOME 24/26 regression.

Version set locked (do NOT downgrade): Qt 6.11.1 + KF6 6.30.0 + Plasma
6.7.5.
