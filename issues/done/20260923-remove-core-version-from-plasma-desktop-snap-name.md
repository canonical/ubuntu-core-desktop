# Drop the coreXY suffix from plasma-core-desktop's snap name

## Impact / Priority

Low / do-later. Purely a maintenance-burden concern, not a functional
bug. Only actionable once core24 KDE support is fully retired (the
stated intent after the current core26 port work lands) — do NOT do
this while both core24 and core26 KDE variants are still maintained
side by side, since that still needs two distinct local snap names (see
point 4 below for why).

What a future base bump would otherwise require: another multi-repo
sweep exactly like the one just done for core24 -> core26 (see the full
file list below).

## Background / the actual question asked

This came up when porting plasma-core-desktop and plasma-desktop-session
from core24 to core26 (see `20260918-kde-core26-port.md`). The
question: why bake the core version into the snap's own `name:` field
at all, instead of just its `base:` field? The research below answers
this properly (do not re-derive):

1. Is "coreXY-in-the-snap-name" actually the wider ecosystem
   convention, or just this project's own choice?
   -> It's the wider convention. Canonical's own core snaps (core18,
      core20, core22, core24, core26) are literally separately-named
      snaps per major version, kept in the store indefinitely -- not one
      "core" name with channels/tracks per base. KDE's own kf6-coreXY
      content-snap family (kf6-core20, kf6-core22, kf6-core24, ...) does
      the same. GNOME's content snap family (gnome-3-38-2004,
      gnome-42-2204, etc.) also encodes the version+base pair directly in
      the name. So renaming per base is the norm for this class of snap,
      not an oddity we introduced.

2. Does anything outside this project actually depend on kf6-coreXY /
    plasma-coreXY-desktop by name?
   -> kf6-core24: YES, heavily. GitHub code search for
      `"kf6-core24" filename:snapcraft.yaml` returns 44 hits across real,
      actively-published KDE app snaps: KDE/krita, KDE/kdenlive,
      KDE/elisa, KDE/falkon, KDE/konqueror, KDE/lokalize,
      KDE/kphotoalbum, FreeCAD/FreeCAD-snap, mapeditor/tiled,
      gcompris/GCompris-qt, and more, all via the "kde-neon-6" extension,
      which auto-adds a `kf6-core24` content plug to any app that lists
      it. This means kf6-core24 (and its future core26 sibling) CANNOT
      be renamed unilaterally -- it's load-bearing for the whole
      KDE-on-Ubuntu-Core snap ecosystem, not just our own two snaps. Any
      rename there would need to go through upstream KDE Neon / the
      kde-neon-6 extension, coordinated with every app above.
   -> plasma-core24-desktop / the `plasma-core24` content interface: NO.
      GitHub code search for `"plasma-core24" filename:snapcraft.yaml`
      returns exactly ONE hit in the entire index, and it's a
      store-review data mirror of our own plasma-desktop-session
      snapcraft.yaml (canonical/seceng-store-reviews-agent-old). No
      third-party app plugs into this interface. Its slots/plugs are used
      exclusively between our own two snaps:
        - plasma-core-desktop (content snap) provides the SLOT:
          `slots: plasma-core26: {content: plasma-core26, interface: content}`
        - plasma-desktop-session (session/app snap) provides the PLUG
          with the same identifier, and mounts it at $SNAP/plasma.
      So THIS specific snap+interface pair is safe to rename freely --
      renaming it only affects files we own, unlike kf6-coreXY.

3. Why does the *content interface identifier* need a version at all
   (separately from the snap's own `name:`)?
   -> snapd does not do any ABI-compatibility checking when connecting a
      content plug to a slot. If plasma-desktop-session (built against
      one Plasma/KF6 ABI) could connect to *any* content snap regardless
      of version, an old session snap could silently connect to a newer,
      incompatible content provider (or vice versa) with no error --
      just runtime breakage. Baking the version into the connection's
      *interface name* (plasma-core26, not just "plasma-core") is what
      makes such a mismatch a hard connect-time failure (wrong interface
      name = no slot found) instead of a silent runtime crash. This is
      the real technical reason interface identifiers stay versioned even
      when a snap's own `name:` doesn't need to be. It's exactly the
      technique gnome-3-38-2004 / gnome-42-2204 use too.

4. "We'd never install both variants side by side on one desktop, so why
    do we need separate names for that?"
   -> Correct, and worth stating explicitly: you never run both a
      core24-desktop KDE session and a core26-desktop KDE session on the
      SAME booted device at once -- only one desktop is active at a time.
      The side-by-side need is purely a *development-machine*
      convenience: locally-built `--dangerous` sideloaded snaps are only
      distinguished by their literal `name:` field (no store
      channel/revision concept for local files), so keeping the core24
      and core26 variants under one shared name would mean the two build
      outputs collide as "the same snap" on disk / in the two parallel
      Makefile targets (24-kde.img vs 26-kde.img) while both are still
      actively maintained for comparison/testing. This goes away once
      core24 KDE support is dropped for good.

## What to actually change (only the two plasma snaps)

Do NOT touch kf6-coreXY (see point 2 above — upstream/ecosystem-wide,
not ours to rename). Scope is just:

- plasma-core-desktop's snap `name:` (currently
  plasma-core26-desktop) -> rename to something version-agnostic, e.g.
  `plasma-core-desktop` or `plasma-desktop-content` (bikeshed the exact
  name later).
- Keep the content interface identifier (currently `plasma-core26`)
  versioned regardless — see point 3. Do not conflate "drop the version
  from the snap name" with "drop it from the interface name" — only the
  former is being proposed here.
- Manage any *future* base bump (core26 -> core28 etc.) by publishing a
  new revision of the same-named snap under an appropriate track, once
  this project actually has a store presence for it (today it's still
  dangerous/locally-sideloaded only, so this only matters once/if it's
  published for real).

IMPORTANT CAVEAT — this does NOT eliminate all future-bump edits, only
most of them. Of the ~13 edit sites listed below, they split into two
different categories:

- Snap-name / mount-path edits (7 of the ~13 sites: the model JSON's
  "name" field, the Makefile's --snap filename, the image build
  script's snap-glob pattern/fallback/output filename, the wrapper
  script's hardcoded /snap/plasma-coreNN-desktop/... symlink, the hook
  script's /snap/plasma-coreNN-desktop/... in XDG_DATA_DIRS, and
  XDG_DESKTOP_PORTAL_DIR) — these all reference the snap's install
  path, /snap/<name>/current/.... Renaming the snap to something
  version-agnostic makes ALL of these permanently stable across every
  future base bump. This is the actual win.
- Content-interface-identifier edits (the remaining ~4-6 sites: the
  `slots:`/`plugs:` declarations in both snapcraft.yamls, and the
  `snap connect plasma-desktop-session:plasma-coreNN
  plasma-core-desktop:plasma-coreNN` strings in the image build script)
  — these WILL still need bumping at core28, core30, etc., even after
  the snap rename. This is not accidental cruft left behind by an
  incomplete rename — it's the deliberate compatibility gate from
  point 3 above (snapd has no other mechanism to stop an old consumer
  silently connecting to an incompatible new provider). Every
  ecosystem convention that uses versioned content interfaces
  (kf6-coreNN, gnome-42-2204, ...) accepts this same narrow recurring
  cost as the price of that safety property.

Net effect of doing this rename: shrinks each future base-bump's
required edits from a 4-repo / 7-file / ~13-site sweep down to a couple
of well-contained interface-identifier bumps in 2 files. It does not
(and should not try to) get you to zero future edits.

## Full list of coreXY edit sites in the core24 -> core26 port

For scale/reference — redoing this exercise for every future base bump
is the exact cost this todo was trying to avoid:

1. plasma-core-desktop/snapcraft.yaml
   - name: plasma-core24-desktop -> plasma-core26-desktop
   - slots.plasma-core24 -> slots.plasma-core26 (+ its `content:` field)
2. plasma-desktop-session/snap/snapcraft.yaml
   - plug identifier plasma-core24 -> plasma-core26 (+ `content:` field)
   - XDG_DESKTOP_PORTAL_DIR path referencing
     /snap/plasma-core24-desktop/... -> plasma-core26-desktop
   - an explanatory comment mentioning plasma-core24
3. plasma-core-desktop/hooks/250-workaround-base-snap-services.sh
   - XDG_DATA_DIRS Environment= entry hardcoding
     /snap/plasma-core24-desktop/current/usr/share
4. ubuntu-core-desktop-kde's image build script
   - a comment, two `snap connect` connection strings, the
     PLASMA_CORE_SNAP glob pattern + fallback, an error message, and an
     output-filename comment (7 spots total)
5. ubuntu-core-desktop-kde/Makefile
   - the 26-kde.img target's `--snap plasma-core24-desktop.snap` ->
     `plasma-core26-desktop.snap`
6. ubuntu-core-desktop-kde/ubuntu-core-desktop-kde-26-amd64-dangerous.json
   - the model's declared snap "name" field for the plasma content snap
7. core-base-desktop/static/usr/bin/core-desktop-session-wrapper.sh
   - a hardcoded
     `ln -sf /snap/plasma-core24-desktop/current/usr/lib/systemd/user ...`
     symlink target — this one was NOT caught by the initial rename
     pass and caused a real grey-screen boot regression (kwin_wayland's
     systemd user units became invisible once the stale
     plasma-core24-desktop snap was no longer installed as a
     coincidental fallback). See the 2026-09-23 debugging trail for the
     full story if useful.

That's 4 separate repos, 7 files, ~13 distinct edit sites, for one base
bump. This is the concrete cost this todo was proposing to eliminate
for next time by dropping the version from the snap's own name.

## Resolution

REJECTED, 2026-09-23. Initially implemented (renamed
plasma-core-desktop's snap `name:` from plasma-core26-desktop to
plasma-core-desktop, version-agnostic, in all 4 repos on 26-dev), then
reverted the same day after further research: the coreXY-in-the-name
scheme is a deliberate, established KDE/Canonical ecosystem convention
(see point 1 above, kf6-coreXY et al.), not an oddity worth diverging
from even for our own two snaps — upstream is unlikely to accept a
differently-shaped convention here, and staying close to it going
forward outweighs the future-base-bump maintenance saving this todo was
chasing. Decision: keep plasma-core26-desktop / plasma-core26 versioned
as-is; no further action needed on future base bumps beyond what's
already documented above (the ~13-site sweep per bump is accepted as
the ongoing cost).

History was cleaned up afterwards: rather than leaving the rename
commit + its revert in place, each repo's 26-dev branch was reset to
just before the rename and a single commit ("Fix missed
plasma-core24-desktop/plasma-core24 leftovers from core26 port") was
reapplied on top, carrying only the unrelated leftover-bug fixes (a few
plasma-core24-desktop/plasma-core24 remnants from the earlier
core24->core26 port that had incidentally been caught/fixed alongside
the now-abandoned rename — the wrapper.sh grey-screen regression noted
above was exactly this class of leftover). Net effect: repos are on
plasma-core26-desktop/plasma-core26 naming with no rename-then-revert
noise in history and no core24 regressions reintroduced. Did not touch
kf6-coreXY (always out of scope, see point 2).
