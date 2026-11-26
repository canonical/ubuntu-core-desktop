# Snaps recipe monorepo: build campaign

## Impact / Priority

The desktop snap recipes lived as non-building / non-core26
recipes; this campaign brought all 138 packages onto core26
(with 140 in the monorepo at the end), ran the builds for the 64
new recipes added 2026-11-17, then refreshed and expanded to the
latest upstream releases — fixing missing runtime libraries,
launcher/runtime path breakage, and toolchain/build failures
along the way. Without it, the desktop snap set cannot build or
ship on core26.

Impact derived from the original note's described symptoms.

## Goal

Turn ~/git/snaps (local-only monorepo of desktop snap recipes,
one directory per snap) into recipes that actually build on
core26, run the build campaign for the 64 new recipes added on
2026-11-17, and then refresh + expand to the latest upstream
releases.

Date: 2026-11-19
Status: refresh + expansion complete; all 138 packages on core26

## Current state (2026-11-19)

- Repository: ~/git/snaps, local only, no remotes. 140 packages,
  every one on core26 and flat/stable: 13 migrated + 42 imports
  (36 migrated on 2026-11-19, 6 already core26) + 1 pipewire +
  64 new recipes (2026-11-17) + 16 new GNOME apps, 2 audio
  utilities and 2 imports (2026-11-19). Per-package commits are
  listed in git log; the final ones are 458d0d4 README
  inventory, 7fc7972 fractal, 2384fcc godot-4, 96ff4fe vocalis,
  066fd8a pavucontrol and 303ac63 README.
- All 18 new apps/utilities build on amd64 with snapcraft 9.2.1:
  papers 51.1, showtime 50.0, gnome-snapshot 51.0, gnome-music
  50.0, gnome-maps 51.2, file-roller 44.8, gnome-connections
  51.0, gnome-usage 48.0, ghex 50.4, gitg 50, gnote 51.0,
  polari 50.0, gucharmap 18.0.0, aisleriot 3.22.35,
  four-in-a-row 3.38.1, atomix 44.0, gthumb 4.0.3, quadrapassel
  51.1, vocalis 1.0.0 and pavucontrol 6.2.
- All 36 legacy imports were audited and migrated: 13 -> 50/51
  series, epiphany 51.2, gnome-boxes 50.0, gnome-terminal 3.60.0,
  shotwell 33.2, loupe 51.2, fractal 14.3, freemind 1.1.0 on
  OpenJDK 21, godot-4 4.7.2, etc. tigervnc and widelands are on
  core26 with their current upstream releases.
- Artifacts: 132 .snap files, ~6.4 GB, in scratch; not in the
  repository.
- Last commit: 303ac63 "Add vocalis and pavucontrol to the
  inventory"; working tree clean.
- Every artifact passed a full transitive ELF DT_NEEDED closure
  audit against the snap + core26 + gnome-core26 + mesa-2604
  (helper script was temporary and has been removed).
- Runtime testing: only where a headless/offscreen run was
  possible (dia, gnumeric, mypaint, geary, deluge, pitivi,
  psql/pgadmin4, wesnoth, ardour, scribus, calligra converter,
  qutebrowser version, etc.). No GUI was launched under a real
  desktop session.
- arm64: declared in every recipe but NOT built. Only amd64
  artifacts exist.
- The store had intermittent HTTP 500s during snap installs
  inside LXD (gnome-core26/sdk, gtk-common-themes); plain
  retries fixed them. Not recipe bugs.

## Changes made by the campaign (committed; see git log)

- Added missing runtime libraries, e.g. libcrack2
  (gnome-disk-utility), libxml2 (gnumeric/pitivi/meld/evolution/
  geary...), libsensors (hardinfo), libxcb-util (guake),
  libxcb-image (wezterm), libmspack and python3-vkbasalt
  (bottles), _cffi_backend (deluge), BLAS/LAPACK alternatives
  symlinks (mypaint, qgis, scribus).
- Worked around the gnome extension cleanup deleting staged
  files that the SDK also ships but the content snap does not:
  libxml2, libsensors, amdgpu.ids, X11 locale data (yakuake,
  texmaker, texstudio, calligra, barrier, resources, hardinfo).
- Built cpu-x, rawtherapee, mysql-workbench and ardour against
  the 26.04 archive GTK/GLib stack instead of the SDK's GLib
  2.90/Pango 1.58 headers, which conflict with archive
  gtkmm/glibmm and mixed Pango versions at link time.
- Shortened descriptions over snapd's 4096-codepoint limit:
  librewolf, yakuake, calligra, qgis, pgadmin4, input-leap,
  qutebrowser, barrier.
- Launcher/runtime path fixes: meld platform Python, ardour's
  hardcoded /usr wrapper and strip/i18n, qbittorrent/stellarium
  private libproxy/pulseaudio dirs, virt-manager ssh_config
  ${HOME} and LIBVIRT_DIR_OVERRIDE, synaptic's dpkg CPU/tuple
  tables.
- Toolchain/build fixes: kitty --ignore-compiler-warnings,
  wezterm Rust lint + libxcb-image, handbrake
  libtool-bin/cmake, strawberry sparsehash and
  qt6-base-private-dev, librewolf/texstudio/calligra/barrier
  X11 data, gnucash lint skip for Guile .go files, pgadmin4
  Yarn 4/npm 11, qgis WITH_PY_COMPILE and PyQt6.uic.
- Imported `pipewire` from canonical/pipewire-snap desktop/26
  (13c610e8). It is already core26/strict, stages the archive's
  daemons, and provides the
  pipewire/audio-playback/audio-record/pulseaudio slots. It
  requires a snapd with the pipewire-server interface. The
  store snap itself is still core24.
- README inventory updated to 120 packages and a separate
  "Imported 2026-11-18 (1)" infrastructure section for
  pipewire.

## Open / next

1. Artifacts retention: decide whether to keep or delete the
   4.0 GB of .snap artifact files; build outputs should not be
   left in scratch.
2. arm64: run arm64 builds (e.g. ./build <snap> --
   --build-for=arm64) on an arm64 host/CI, or state that only
   amd64 is supported so far.
3. Real-session smoke tests: launch GUI apps on a Core
   Desktop/26.04 desktop, check portals, audio via pipewire,
   file chooser, D-Bus activation, tray/MPRIS, and the
   documented manual connections (udisks2, removable-media,
   password-manager-service, cups...).
4. synaptic is built but still non-functional by design
   (private empty APT cache, no dpkg/apt/pkexec). Consider
   dropping it from the repo or keeping it as a documented
   non-goal.
5. VirtualBox, Timeshift/Deja Dup/Back In Time, VeraCrypt, Tor
   Browser, Dropbox, KDE Connect/GSConnect remain agreed poor
   fits. etcher and flatseal were skipped as impossible under
   strict confinement.
6. Engineering todos remain separate: Wireshark, GParted,
   usb-creator-gtk are their own separate work items.
7. Consider adding a short "build status" note to README
   (campaign validated on amd64 only; artifacts are scratch).
   Not required.
8. Re-run builds after recipe/upstream refreshes; expect
   occasional store 500s from the snap installs inside LXD
   (retry).

## Layout convention (adopted 2026-11-18, commit 1be5e80)

- Flat default: one recipe at the package root, implicitly
  stable. metadata.yaml stays at the package root.
- Nested: if a package needs beta/edge/candidate, stable moves
  too; every track is a complete build project under stable/,
  beta/, edge/. Never mix flat and nested; nested always keeps
  stable/.
- ./build <snap> defaults to stable; --track, <snap>/<track>
  and <snap>:<track> select another track. Workspaces are
  <snap> for flat and <snap>-<track> for nested. --list shows
  NAME TRACK BASE PUBLISHER.
- All 120 packages are still flat/stable; no nested package
  exists yet.

## Refresh campaign (2026-11-18, core26 complete)

- All 13 migrated core26 packages reviewed.
- Built and verified: gnome-calculator 51.1, gnome-text-editor
  51.0, gnome-logs 50.0, gnome-clocks 51.0, simple-scan 50.0,
  eog 50.4, evince 48.5, gedit 51.0, gnome-characters 51.0,
  gnome-calendar 51.0.
- gedit also moved its bundle: amtk 5.11.0, gfls 0.5.0,
  gtksourceview 299.8.0, tepl 6.15.0; gedit-plugins was folded
  into gedit 51 and the obsolete girepository-2.0 patch was
  dropped.
- tigervnc 1.16.2 built from upstream source instead of the
  1.15.0 deb.
- pipewire 1.6.11 and wireplumber 0.5.19 built from upstream
  source instead of the 1.6.2/0.5.13 debs.
- No change needed: cheese 44.1 (final archived tag),
  gnome-contacts 51.0.
- Thunderbird: flat-layout exception. Re-vendored the core26
  packaging from ubuntu/thunderbird beta head (d025ed45) and
  pinned version 160.0-1, so it builds current stable 160.0 on
  core26. The upstream stable branch is still core24; the store
  latest/stable is core24. The compiled update channel was
  switched to release and rebuilt (updater remains disabled;
  distribution.ini sets app.update.enabled=false).
- Commits: 26884b6, 30b7fef, 316ea3b, dec986f.
- All refreshed artifacts pass a DT_NEEDED closure audit except
  evince's optional DjVu/XPS/DVI backends (libraries not in the
  platform; PDF, TIFF and comics work). Documented in README.

## Version policy and audit (remaining)

- Default is the latest stable upstream release, not the Ubuntu
  freeze. Build the app from upstream; use archive libraries
  where they work.
- The 42 imported core24/22/20/18 recipes have not been
  version-audited. This is the next campaign; many are pinned
  to old core24/22 branches.
- New recipes were written 2026-11-17 and were at current
  upstream versions then; re-check them on the next sweep
  (wezterm, totem, pitivi, stacer and mysql-workbench are at
  their latest/abandoned releases).
- Candidate edge tracks: ardour (git master), qutebrowser,
  librewolf, wezterm, kitty, godot-4, prismlauncher, bottles,
  lutris, heroic. Evaluate only after the stable refresh; do
  not create a track without a real upstream stream and a
  working recipe.

## Resume commands

    cd ~/git/snaps
    ./build --list                 # 120 packages, all stable today
    ./build <snap>                 # flat package, or nested stable
    ./build <snap> --track edge    # nested package only
    ./build <snap> -- --build-for=arm64   # untested arm64 route
    git log --oneline              # per-wave fix commits
