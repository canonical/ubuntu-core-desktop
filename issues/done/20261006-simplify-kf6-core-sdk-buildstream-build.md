# Simplify the kf6-core-sdk BuildStream elements

Date: 2026-10-06
Project: `~/git/kf6-core-sdk` (110 elements)
Separate from: `20261006-improve-buildstream-build.md` (speed work).
This one is about readability and maintainability; speed is only a side
benefit.

## Impact / Priority

Each of the 110 generated element files repeated the same
snap-specific configuration, so the elements were noisy and any path or
snap-name change meant editing 110 files (and every element's cache
key). A maintenance/readability cost rather than a user-visible
failure; impact derived from the original note's described symptoms.

## Problem

Each element repeats snap-specific details, e.g. elements/kwallet.bst
has:

- a `find ... -name '*.pc' -exec sed -i` install command rewriting
  /root/stage, libdir=/usr and includedir=/usr to
  /snap/kf6-core26-sdk/current/usr
- a long `environment:` block (PATH, PKG_CONFIG_PATH, LD_LIBRARY_PATH,
  QT_PLUGIN_PATH, QML_IMPORT_PATH, LLVM paths, ...) with
  /kde-qt6-core26-sdk and /kde-pyside6-core26-sdk paths
- a `cmake-local` variable with CMAKE_PREFIX_PATH / FIND_ROOT_PATH etc.
- a long list of build-depends that is the same for most KF6 elements

Consequences: elements are noisy, any path/snap-name change means
editing 110 files, and the .pc rewrite changes every element's artifact
(cache key) even though it only matters for the final snap.

## Background

Upstream KDE/kde-buildstream was checked and is NOT a drop-in base
(freedesktop-sdk overlay, no KF6 frameworks elements, different ABI from
the Ubuntu core26 debs). Only borrow ideas from it (split rules, cache
config, individual component elements). Do not adopt it for this work.

## Rules

- One change at a time; after each, run the gate check before
  continuing.
- Generated elements: tools/generate-elements.py produces the .bst
  files. Change the generator and regenerate, don't hand-edit 110
  files, or the next regeneration will undo the work. (Check the script
  first.)
- Keep a baseline of the current output snap to compare against.

### Step 0: Baseline

- Record the current built snap's file list and .pc contents:

      unsquashfs -ll kf6-core26-sdk_*_amd64.snap | sort > /tmp/base.lst
      unsquashfs -d /tmp/base-squash kf6-core26-sdk_*_amd64.snap
      (keep /tmp/base-squash/**/*.pc for diffing)

- Commit or tag the current state so each step can be reverted.
- Note which elements differ from the template (kwallet is one; list
  others via `grep -L` / diff of the environment blocks).

GATE 0: baseline file list + pc files saved; git tree clean.

### Step 1: Move the .pc rewrite to one place

- Remove the per-element `find ... sed -i` install command (in the
  generator template, then regenerate).
- Add the rewrite once in snap-pack.bst (or sdk-fs.bst), running over
  the fully merged tree before mksquashfs.
- Beware: the rewrite must be idempotent and must produce the same
  results. Check that /root/stage substitution is still needed or is
  now obsolete.

GATE 1: build passes; diff of every *.pc file in the new snap against
the baseline is empty (or only explained differences); file list diff
shows no path changes. Bonus check: element artifact keys no longer
contain the snap name (a rename only rebuilds snap-pack).

### Step 2: Shared environment and cmake flags

- Create include/snap-env.yml (or put them in project.conf, if
  applicable to every element) holding:

    * the environment: block (PATH, PKG_CONFIG_PATH, LD_LIBRARY_PATH,
      QT_PLUGIN_PATH, QML_IMPORT_PATH, XDG_*, LLVM_*, PYTHONPATH)
    * the common cmake variables (CMAKE_PREFIX_PATH, FIND_ROOT_PATH,
      BUILD_TESTING=OFF, CMAKE_BUILD_TYPE=Release,
      CMAKE_INSTALL_PREFIX=/usr, QT_MAJOR_VERSION=6) built from
      variables, so the sdk paths are defined once (e.g.
      `qt6-sdk: /kde-qt6-core26-sdk`) and referenced as %{qt6-sdk}

- Pull it into elements with `(@): include/snap-env.yml`, or, if every
  cmake element shares it, via the project.conf `elements:` defaults
  for kind cmake.
- Elements keep only what is different: dependencies, source, extra
  flags (cmake-local becomes `cmake-local: "%{cmake-common}
  -DEXTRA=..."`).

GATE 2: `bst show --format "%{name} %{key}"` still resolves for all
elements; a handful of elements (kwallet, kio, kirigami, extra-cmake-
modules) build, and their install trees are the same as before (compare
`bst artifact checkout` file lists).

### Step 3: Collapse the repeated build-depends

- Replace the ~30 repeated deps (sdk-qt6.bst, sdk-pyside6.bst,
  system.bst, toolchain.bst, sdk-build-paths.bst, ...) with a single
  stack element, e.g. `kf6-build-env.bst`, that each framework depends
  on, plus its real framework deps.
- Make sure sdk-build-paths.bst carries the /kde-qt6-core26-sdk and
  /kde-pyside6-core26-sdk path handling so elements don't mention them.
- Only list real framework dependencies per element (e.g. kwallet:
  kconfig, kcoreaddons, ki18n, ...). Dropping transitive/unneeded ones
  also reduces the staging work (helps the speed note).

GATE 3: every element has `build-depends` = kf6-build-env + its own
real deps; build graph (`bst show --deps all`) has no missing deps and
no new cycles. Check by building one element with only its listed deps.

### Step 4: Update the generator and docs

- Make tools/generate-elements.py emit the slim form; regenerate;
  confirm the diff to the committed elements is empty (generator =
  source of truth).
- Move any remaining snap-specific values (snap name,
  /snap/<name>/current, sdk paths) to project.conf variables or
  snapcraft.yaml-derived variables.
- Add a short README section: where each piece lives (project.conf,
  include/snap-env.yml, kf6-build-env.bst, snap-pack.bst), and how to
  add a new framework element (should be about ten lines).

GATE 4: grep shows no "kf6-core26-sdk", "/snap/" or
"kde-qt6-core26-sdk" outside project.conf, include/, snap-pack.bst and
the generator:

      grep -rn -E 'kf6-core26-sdk|/snap/|kde-(qt6|pyside6)-core26-sdk' elements

Optional: try renaming the snap in project.conf and check that only
snap-pack rebuilds.

### Step 5: Full verification

- Full clean build and snap pack. Compare with the Step 0 baseline:

    * file list (unsquashfs -ll) identical, apart from understood
      changes
    * .pc files identical, and `pkg-config --cflags KF6Wallet` etc.
      work against the unpacked snap
    * smoke test: install the snap (dangerous) and build a small KDE app
      against it, or run the project's existing checks

- Check host independence still holds (build still works with a clean
  PATH / in a clean container).

GATE 5: no content regressions; build time not worse than baseline
(record in the speed note's results table).

## Later (not part of this)

- Borrow ideas from KDE/kde-buildstream: split-rules.yml
  (runtime/cleanup domains), buildstream.conf.* for a shared remote
  artifact cache.
- Plug other snaps this one depends on in as junctions/elements.

## Resolution (2026-11-03)

NEVER STARTED, moot. No step was executed (no generator changes,
elements untouched) and the target is gone: the BuildStream build left
the build path when the project adopted the Neon deb-repack pipeline
(see the resolution on
`20261005-convert-kf6-core-sdk-snap-from-snapcraft-to-buildstream.md`).
Kept only as a record of the planned refactor shape.
