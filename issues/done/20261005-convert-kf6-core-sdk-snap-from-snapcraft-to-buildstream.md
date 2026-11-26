# Convert the kf6-core-sdk snap build from Snapcraft to BuildStream

The repository `~/git/kf6-core-sdk` contains a Snapcraft build that
could potentially be optimized by exploiting parallelism. Unfortunately
Snapcraft operations are generally serialised and single thread.

Implement a build using buildstream for kf6-core-sdk instead of
snapcraft. Make sure that the build exploits as much parallelism as
possible. The build should be a proper system that retrieves the .deb
packages and/or chisel packages etc. and composes them, runs the hooks
etc. and finally runs mksquashfs to create the snap. Do not just run
`snapcraft` inside buildstream — this should be a replacement for
snapcraft.

Do the work in the 26-dev-buildstream branch (which has parent 26-dev).
Check the repo's local build script: it has an important optimization of
setting http_proxy which helps speed up package downloads. Make sure
the buildstream build uses the local proxy too (but do not hardcode it
in the source; allow it to be set in a local build script).

Use the existing snap to establish correctness — the new build snap
should be largely the same (except for obvious differences like
timestamps, etc.).

This machine has lots of cores and plenty of memory. Use up to 10 CPU
cores for testing (equivalent make -j10) but do not hardcode that
anywhere apart from a local uncommitted top-level build script (if one
is created/used).

## Impact / Priority

Snapcraft builds the ~100-part KF6 SDK serially — snapcraft operations
are generally serialized and single-threaded — so a build that could
exploit the machine's parallelism could not, making the SDK rebuilds
unnecessarily slow. Impact derived from the original note's described
symptoms.

## Architecture (decided 2026-10-05)

Decision: BuildStream owns the whole expensive pipeline; snapcraft is
NOT invoked anywhere (not even --destructive on a reduced yaml).
snapcraft.yaml stays committed as the source of truth for *snap
metadata* only, consumed by the generator.

Why no snapcraft in the loop (verified against this repo, not assumed):

- This snap has no apps, plugs, slots, hooks, layout or command-chain.
  snapcraft.yaml: `slots: {}`; packed snap's meta/ = snap.yaml + empty
  gui/. The snap-specific metadata surface is ~15 lines: name, version,
  summary, description, base, confinement, grade, compression + the
  `environment:` block. There is no plug/slot/interface knowledge for
  BuildStream to miss.
- snapcraft's $CRAFT_STAGE -> /root/stage environment rewriting happens
  at STAGE time, not pack time. `snapcraft pack <dir>` on a BuildStream
  tree needs meta/snap.yaml to already exist in the dir, so delegating
  to snapcraft buys nothing but lifecycle overhead, YAML schema
  babysitting of a parts-less yaml, and version drift. Keeping a second
  "reduced" snapcraft.yaml also means maintaining a second YAML schema
  valid enough for snapcraft.
- Tested both remaining pack options against the reference snap:

      snap pack <tree> --compression=lzo   (snapd CLI)
      mksquashfs <tree> out.snap -noappend -comp lzo -no-fragments -no-xattrs -all-root

  Both reproduce the reference superblock EXACTLY (lzo, 128k blocks,
  exportable, no fragments, no xattrs, root/root, identical filesystem
  size 2082352234 bytes). So the final serialization is one mksquashfs
  command in a script element - the "tiny packaging step" of the
  proposed architecture, minus snapcraft. If hooks/layout/apps ever
  appear here, swapping the last element to `snap pack` (or snapcraft
  pack) is a one-element change at the boundary.

Element model (the build graph BuildStream represents):

  plugins/sources/deb.py   deb source: downloads Packages indexes
                           (honours http_proxy set by the local build
                           script), resolves the closure apt-style
                           (first alternative, Essential counts as
                           installed), ref pins name/version/pool
                           path/sha256 in project.refs, fetch downloads
                           8-way parallel, stage = dpkg-deb -x + glob
                           file-excludes.

  elements/
    runtime-base.bst   import + deb source: packages = the 328-package
                       stage-packages closure exactly as resolved by the
                       last snapcraft build (build.log "Downloading
                       package:" lines) -> hard parity anchor for deb
                       content.
    system.bst         filter element: applies the union of per-part
                       `stage:` exclude globs (gdk-pixbuf loader
                       conflicts etc.) and strips /.deb-manifest.json.
                       Frameworks depend on this.
    toolchain.bst      import + deb source (resolve mode): closure of
                       (Essential set + all build-packages +
                       python3-setuptools, python3-wheel), exclude =
                       runtime-base package list. Build-only; provides
                       the equivalent of the snapcraft managed instance
                       (gcc, clang-18, cmake, doxygen, ...).
    meson-deps.bst     git mesonbuild/meson 1.10.1 -> pip install
                       --no-build-isolation --break-system-packages to
                       /usr/local (no network in sandbox), shebang fix.
                       Build-only (not in the snap, matches reference).
    ninja.bst          ships /usr/bin/ninja into the snap (was the nil
                       part).
    sdk-qt6.bst        import of .sdk/kde-qt6-core26-sdk (local dir).
    sdk-pyside6.bst    import of .sdk/kde-pyside6-core26-sdk (local
                       dir).
    sdk-build-paths.bst  /snap/kde-qt6-core26-sdk/current ->
                       /kde-qt6-core26-sdk symlinks; build-only
                       (verified absent from reference prime; needed at
                       build time because SDK .pc/.cmake files hardcode
                       /snap/... paths).
    hunspell-dictionaries.bst  replicates stage-snaps semantics as
                       observed in the reference: dicts ->
                       /usr/share/hunspell, launcher -> /bin, repo
                       files -> snap.hunspell-dictionaries/, meta ->
                       meta.hunspell-dictionaries/.
    <framework>.bst    one element per snapcraft part (~100 of them):
                       cmake or meson element; build-depends = the
                       part's `after:` graph + system + toolchain +
                       meson-deps + sdk-build-paths + sdk-qt6 (+
                       sdk-pyside6 when its env references it); sources
                       = git@tag (+ patch sources from patches/);
                       environment = translated build-environment
                       ($CRAFT_STAGE -> /, ccache entries dropped, full
                       PATH/PKG_CONFIG_PATH/LD_LIBRARY_PATH emitted
                       explicitly).
    sdk-fs.bst         compose element: union of system + sdk-* +
                       hunspell + all frameworks = the
                       CRAFT_STAGE/prime equivalent.
    snap-pack.bst      script element: stages sdk-fs at / and toolchain
                       at /toolchain (per-dependency `location:`
                       layout), writes meta/snap.yaml (+ empty meta/gui)
                       from the template the generator emitted from
                       snapcraft.yaml, runs mksquashfs with the exact
                       flags. Artifact = the .snap file.

Parallelism (the point of the exercise):

- Element graph is the snapcraft `after:` DAG (~115 elements);
  BuildStream builds independent branches concurrently:
  `bst build --builders N`.
- Inside each element, cmake/ninja parallelism via `${JOBS}` =
  `%{max-jobs}`: `bst build --max-jobs N`.
- go-bst (an uncommitted local top-level script) exports http_proxy from
  the local environment (never hardcoded), and passes
  `--builders`/`--max-jobs` (10 during bring-up).
- Deb downloads are parallelised inside the deb plugin; all sources
  cache in the casd; artifacts cache -> rebuilds are incremental per
  element.
This replaces snapcraft's serial pull/build/stage/prime loop.

Parity strategy:

- tools/compare-snap.py: unsquashfs reference + new snap, diff file sets
  (paths, symlink targets, modes, size buckets); meta/snap.yaml diffed
  exactly.
- Benign deltas: mtimes, binary bits (build IDs embed different build
  paths), squashfs creation time.
- Reverse-engineered no-ops already dropped (verified in reference
  prime): glib's stage-time symlinks into the SDK dirs (SDK ships its
  own relative links), gdk-pixbuf loaders.cache (absent), libtoolize
  fix (absent), no ELF stripping (no strip lines in build.log), qca's
  rsync-to-/ hack (build-time only; explicit build-dep edges added if
  some part misses it).
- The .pc rewrites to /snap/kf6-core26-sdk/current are done per-element
  in install-commands (ownership-based equivalent of the fix_pc_files
  part).

Open items / risks:

- Toolchain closure calibration (resolver excludes = runtime-base set).
- Per-part stage: excludes must be unioned into the system.bst filter
  without over-excluding (they applied per part in snapcraft).
- /dev/null (0-byte file, not a device) is in the reference prime;
  replicate if the diff demands it.
- arm64: .sdk dumps are amd64-only today; elements parameterised with
  `%{triplet}` so arm64 needs only cross-toolchain + SDK dumps later.

## Status (2026-10-05, end of day)

The BuildStream build is complete and achieves file-level parity with
the reference snapcraft-built snap:

  - meta/snap.yaml: BYTE-IDENTICAL to the reference
  - file tree: 254451/254452 entries identical (paths, types,
    permissions, symlink targets; 0 type diffs, 0 symlink-target diffs)
  - superblock: lzo/128k blocks/no-fragments/no-xattrs, matching snap
    pack
  - the 2 accepted deltas:
      * EXTRA /usr/lib/python3.14/sitecustomize.py symlink - python3.14
        security update (resolute-updates) added it after the reference
        build; version drift, expected for a fresh build
      * MISSING /usr/share/doc/libdbusmenu-qt6-doc/dir_98cdb10f...html -
        doxygen directory-graph page whose generation depends on the
        build directory layout (ref: /root/parts/<part>/build, bst:
        /canonical/buildstream)
  - sizes: new snap 2083241984 vs ref 2082352234 bytes (~0.04%
    difference, newer deb versions + build-path-dependent binary bits)

How it runs:

  ./go-bst            (local, uncommitted; proxy exported locally,
                       BUILDERS/MAXJOBS default 10, never committed)
  tools/compare-snap.py <new.snap>   vs the reference snap

Committed on 26-dev-buildstream: project.conf, plugins/deb.py (the apt
source plugin), elements/*.bst (generated, plus project.refs pinning git
refs and deb name/version/filename/sha256), tools/generate-elements.py
(snapcraft.yaml -> elements converter), tools/compare-snap.py.

Key fixes found during bring-up (all recorded above):

  - %{lib} must be prefix-relative (usr/usr/lib doubling)
  - BuildElement commands run with a read-only root -> ca-certs and
    graphviz-config generate postinst files into their artifacts; pip
    installs with --prefix
  - GCC include-order: $CRAFT_STAGE/usr/include -> /usr/include entries
    are dropped (system-tail dedupe broke #include_next)
  - deb index merging picks the HIGHEST version (resolute-updates was
    missing initially -> mesa and friends drifted)
  - undeclared snapcraft stage-order dependencies made real:
    * transitive closure of the framework graph as explicit
      build-depends (each edge = a find_package/find_dependency cmake
      must resolve)
    * build.log REQUIRED-packages feature summaries parsed per part
      (kfilemetadata->kcodecs, purpose->QML modules, etc.)
    * meinproc6 consumers -> karchive; qca -> ca-certs (system
      certstore keeps qca from generating /usr/certs)
  - base-image gaps added to the toolchain: libedit2 (shiboken),
    libcap2 (samba link check), squashfs-tools (mksquashfs for the pack
    element)

Parallelism: the graph builds with --builders 10 --max-jobs 10;
independent framework branches build concurrently (12 topological layers
collapsed into the plain DAG after replacing the layer experiment with
real closure edges).

Clean-build semantics (verified 2026-10-06):

- `bst artifact delete --deps all <element>.bst` deletes exactly that
  subtree's cached artifacts; the next build re-executes for real
  (verified: kcodecs recompiled after deletion; import elements are fast
  because re-staging from CAS is instant, which can look like a cache
  hit).
- GOTCHA: bst talks to a buildbox-casd daemon which can OUTLIVE its bst
  frontend (force-killed runs leave zombies). A zombie casd started
  BEFORE an `bst artifact delete` still serves stale in-memory cache
  state, so a subsequent build can find "everything cached" even though
  the refs are gone from disk. Check for stray daemons before suspecting
  the delete:

      pkill -u your_username -f buildbox-casd
      rm -f ~/.cache/buildstream/casserver-*.sock

  (fresh bst invocations spawn a fresh casd and see the true on-disk
  state, which is why the same delete looked both working and
  not-working in the same hour).
- Full clean (sources, CAS, artifacts): `rm -rf ~/.cache/buildstream` as
  your_username, then ./go-bst (after killing stray casd daemons).

## Resolution (2026-11-03)

Work COMPLETED, direction superseded. The BuildStream replacement was
fully implemented on branch 26-dev-buildstream (commit ace3601 "Replace
snapcraft lifecycle with BuildStream": deb source plugin, generated
elements/, project.conf, generator + comparator tools) and achieved
file-level parity with the reference snapcraft-built snap (meta/
snap.yaml byte-identical; 254451/254452 tree entries identical, 2 benign
deltas; ~0.04% size difference), with --builders/--max-jobs parallelism
and clean-build semantics verified as described above.

Superseded before adoption: the project switched the KDE runtime snaps
to the Neon deb-repack pipeline (prebuilt release/resolute debs, no
compilation at all - branches deb-repack; see
`20261009-build-and-publish-kde-dangerous.md`), which takes the whole
from-source SDK chain - and therefore BuildStream - off every build
path. 26-dev-buildstream is kept as a reference; nothing further to do.
