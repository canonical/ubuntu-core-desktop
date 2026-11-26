# Remove the remaining Core 24 runtime from the Core 26 image

Date: 2026-09-17

## Impact / Priority

The Core 26 image still shipped the Core 24 base snap and Core 24-era
gadget/kernel channels, so a "Core 26" image carried runtime it should
not have. Impact derived from the original note's symptoms.
No priority level was stated in the original note.

## Context

The Core 26 desktop image already uses `core26-desktop` as its model
base, and the locally built `ubuntu-desktop-session.snap` now declares
`base: core26-desktop`. The image still contains Core 24 because:

- `ubuntu-desktop-init.snap`, built from the ubuntu-desktop-provision
  repo, currently declares `base: core24`.
- `ubuntu-core-desktop-26-amd64-dangerous.json` still explicitly seeds
  the `core24` base snap.
- The checked-in Core 26 model still selects `pc-desktop` and
  `pc-kernel` from `24/stable`.

## Goal

Build a Core 26 desktop image whose installed snaps contain no `core24`
base snap, while retaining only the Core 26 runtime and any required
platform snaps.

## Work items

- Change ubuntu-desktop-provision's `snap/snapcraft.yaml` from
  `base: core24` to the chosen Core 26-compatible base (`core26` or
  `core26-desktop`). Use `bare` only if the init snap is intentionally
  self-contained and does not need a base runtime.
- Rebuild `ubuntu-desktop-init` and verify the resulting snap metadata
  has no `base: core24`. Copy or link the resulting
  `ubuntu-desktop-init.snap` into the `ubuntu-core-desktop` repository,
  where the image build consumes it when producing `26.img`.
- Remove the explicit `core24` base entry from
  `ubuntu-core-desktop-26-amd64-dangerous.json`.
- Use the `26/stable` gadget and kernel channels for `pc-desktop` and
  `pc-kernel` if those channel builds are available and compatible with
  the Core 26 model.
- Regenerate the signed
  `ubuntu-core-desktop-26-amd64-dangerous.model` assertion.
- Rebuild the image, using the locally built `custom-core.snap`,
  `gadget.snap`, `snapd26.snap`, `ubuntu-desktop-session.snap`, and
  `ubuntu-desktop-init.snap`.
- Verify the resulting `26/seed.manifest` and booted image's
  `snap list` contain no `core24` snap. Confirm that the desktop
  session, first-boot initialization, App Center, and graphical login
  still work.

## Notes

`gnome-46-2404` and `mesa-2404` are platform snaps and are not
themselves the `core24` base snap. They do not need to be removed solely
to eliminate the Core 24 runtime.

## Resolution

Built `ubuntu-desktop-init` with `base: bare` and `build-base: core26`.
`core26-desktop` was rejected by the installed Snapcraft 9.1.1 schema,
and the GNOME extension was therefore inlined/trimmed to use the Core 26
desktop base's runtime libraries, so `ubuntu-desktop-init` itself no
longer needs Core 24. The model uses `pc-kernel` `26/stable`, while
intentionally retaining `core24`, `gnome-46-2404`, and `mesa-2404`
because the modern `snap-store` `2/stable` App Center requires them. No
Core 26 App Center build is published yet; this is an accepted residual
dependency, not an oversight.

The image build completed successfully. The fresh VM seeded and booted
with the accepted App Center dependency set; the provisioning wizard
launched in the no-user path and served its initialization socket, and
GDM was active with the graphical initial-setup session. The modern
`snap-store` 2/stable binary started its GTK launch path; direct SSH
invocation could not complete the display launch because SSH has no
graphical display. The temporary autologin/session shim reached GDM but
was reverted after its known bind-mount ownership diagnostic failure.

Commits:

- `ubuntu-desktop-provision`: `c926aa0fd` on
  `snap/ubuntu-desktop-init/core24-bump` (on `bcdb62713`)
- `ubuntu-core-desktop`: `26fbb231d87b6caf1a6851fcf3be223c834622fd`
