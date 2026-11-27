# snapcraft rejects base: core26-desktop despite PR #4850

Date: 2026-09-15

## Impact / Priority

Building any snap with `base: core26-desktop` fails snapcraft's schema
validation outright, so snaps that need this base cannot be built until
the schema-level support lands. Impact derived from the original
note's described symptoms.

## Context

Building a snap with `base: core26-desktop` in snapcraft.yaml fails
validation, even though canonical/snapcraft#4850
(https://github.com/canonical/snapcraft/pull/4850) was supposedly
merged to add support for "-desktop" bases. Confirmed against the
installed snap: snapcraft 9.1.0, revision 19021 (latest/candidate).

Investigated
    /snap/snapcraft/19021/lib/python3.12/site-packages/snapcraft/models/project.py
and confirmed PR #4850 only patches `Project._providers_base()`:

    if base.endswith("-desktop"):
        core_base = base.rpartition("-")[0]
    else:
        core_base = base
    return SNAPCRAFT_BASE_TO_PROVIDER_BASE[core_base]

That method maps a base to the BaseAlias used to launch the LXD/
Multipass build environment - it's a later step. The actual schema
validation of the `base:` field in snapcraft.yaml happens first and
rejects "-desktop" values entirely:

  - snapcraft/const.py: `StableBase` enum only lists core22, core24,
    core26 (no *-desktop variants).
  - snapcraft/models/project.py: `Core22Project.base: Literal["core22"]`,
    `Core24Project.base: Literal["core24"]`,
    `Core26Project.base: Literal["core26"]`, and the discriminated
    union `_StandardProject = Core22Project | Core24Project |
    Core26Project | DevelBaseProject | _BareProject` - there is no
    Core26DesktopProject (or similar) and no "-desktop" literal
    anywhere in the union.

So `base: core26-desktop` fails pydantic validation ("Input should be
'core22', 'core24', 'core26' or 'devel'") before the request ever
reaches `_providers_base()`, making that PR's fix unreachable for real
project files. PR #4850's own test changes only call
`Project._providers_base()` directly for "core22-desktop" /
"core24-desktop" - they never exercise full project validation via a
real snapcraft.yaml, so the gap wasn't caught.

## TODO

- Fork/clone canonical/snapcraft locally and write a fix completing
  what #4850 started: add "*-desktop" support to the schema itself
  (snapcraft/const.py `StableBase` enum, the `Core*Project.base`
  Literals, and the discriminated project union in
  snapcraft/models/project.py), e.g. a Core26DesktopProject (and
  Core22/Core24 equivalents) class or a validator that strips the
  "-desktop" suffix before Literal/discriminator matching, mirroring
  the approach already used in `_providers_base()`.
- Add/extend unit tests that exercise full project validation (not
  just `Project._providers_base()` directly) with a real snapcraft.yaml
  using `base: core26-desktop` (and core22-desktop/core24-desktop) to
  close the gap #4850's tests missed.
- Verify locally:
    - Run the project's existing test suite (tox/pytest) for the
      changed files and confirm the new desktop-base tests pass.
    - Build an actual test snap with `base: core26-desktop` using the
      patched snapcraft (e.g. via `pip install -e .` or a locally
      built snap) and confirm `snapcraft` no longer rejects it and
      produces a working build environment.
- Once verified, open a pull request against canonical/snapcraft
  referencing #4850, explaining that it only fixed
  `_providers_base()` and this PR completes the schema-level support.
- After the PR merges upstream, re-check whether
  pc-amd64-gadget-desktop / core-base-desktop snap builds can drop any
  workarounds for the core26-desktop base.
- Cross-reference with `20260915-fix-github-ci.md`, which also tracks
  #4850 (there in the context of switching snapcraft-channel from edge
  back to stable) - update both once resolved.

## Re-checked (2026-11-27): still not fixed upstream, workaround documented

Confirmed against snapcraft 9.2.2 (rev 19607, latest/candidate,
`/snap/snapcraft/current`) and against `canonical/snapcraft` main as of
2026-10-01: `snapcraft/const.py`'s `StableBase` still lists only
core22/core24/core26, and `snapcraft/models/project.py` still declares
the per-base `base: Literal["core26"]` plus the project union with no
`*-desktop` variant. Only `_providers_base()` strips the suffix, so the
schema rejection described above is unchanged. The TODO in this file is
still the accurate next step; nothing has been submitted upstream.

Until then the workaround is written down for the three affected repos
(accountsservice-snap, provd-snap, plasma-desktop-session): swap
`base: core26` for the snapcraft call, pack, then patch the built
snap's `meta/snap.yaml` base back to `core26-desktop` - see the
"Build/CI notes" section of `docs/core-base-desktop.md`. Do not
rediscover it.
