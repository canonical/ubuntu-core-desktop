# ubuntu-desktop-provision: snapcraft pack fails on the desktop extension

Date: 2026-09-24

## Impact / Priority

Low (build tooling only, not runtime). Blocks a full from-scratch
`snapcraft clean` rebuild of the ubuntu-desktop-init snap (the
first-boot wizard) in the ubuntu-desktop-provision repo. Does not
affect any already-built ubuntu-desktop-init.snap or any running image —
the previously-built snap (dated 2026-09-17) is unaffected and still
usable. Real-world impact is purely "can't rebuild this one snap from
source right now"; not yet investigated whether every snapcraft
invocation in this repo fails or only a full `--clean` one (both were
tried below and both failed the same way).

## Context

While rebuilding all local snap dependencies for the image
(pc-amd64-gadget-desktop, core-base-desktop, ubuntu-core-desktop-snapd,
ubuntu-desktop-session-snap, ubuntu-desktop-provision), the first four
built successfully, but `ubuntu-desktop-provision`'s `snapcraft pack`
(via the snap/ubuntu-desktop-init/26.04-dev branch) failed:

    Initializing lifecycle
    Failed to pull source: unable to determine source type of
    '/snap/snapcraft/19108/share/snapcraft/extensions/desktop/command-chain'.
    Failed to run snapcraft in instance

Full traceback in ~/.local/state/snapcraft/log/snapcraft-20260924-*.log
points at craft_parts.sources.sources.get_source_type_from_uri() raising
InvalidSourceType while building the `flutter-git` part of
`ubuntu-desktop-init`'s snapcraft.yaml (project uses the "desktop"
extension from snapcraft's `gnome-sdk`/extensions machinery).

Reproduced twice: once with a full `snapcraft clean` first, and once
running `snapcraft pack` directly afterwards (no extra clean) — same
failure both times, so this isn't specific to a fresh clean build; it
looks like an environment/snapcraft-version incompatibility with this
repo's use of the "desktop" extension (snapcraft revisions 19108/19149
at the time), not a state/caching issue.

Not yet investigated: whether a different/older snapcraft revision
works, whether the extension usage in
ubuntu-desktop-provision/snap/snapcraft.yaml needs updating for the
current snapcraft, or exact commit/version bisection.

## Resolution (2026-11-03)

No longer blocks — resolved by time/CI rather than by bisection. The
ubuntu-desktop-init snap builds green in GitHub CI on every push
(chris-bainbridge/ubuntu-desktop-provision desktop-26-latest release
live since 2026-10-09 and consumed by the image workflow), so "can't
rebuild this snap from source" no longer holds. The original failure
was specific to the then-installed snapcraft revisions 19108/19149; the
installed snapcraft is now 9.2.1 (rev 19387). The exact revision bug
was never bisected: if a local snapcraft clean build of this repo ever
fails the same way on a current snapcraft, re-open with the log.
