# Publish the core-desktop snaps on the Snap Store (retire the dangerous model)

Date: 2026-10-09
Follows: `20261009-build-and-publish-gnome-dangerous.md` (publishing
precedes), `20261009-build-and-publish-kde-dangerous.md`,
docs/models.md (signing process), ~/git/models (canonical/models
checkout)
Related: `20261029-migrate-gadget-connections-to-store-gadget.md`
(build.sh's gadget connections list must move into the store gadget and
get snap-declaration grants before phase 3/4 can boot a signed model;
the dangerous dev path stays as the local fast lane)

## Impact / Priority

Snaps shipped only as unasserted/local snaps in a dangerous-grade model
are frozen forever: installed images can never `snap refresh`, the model
cannot become grade: signed, and the image build permanently needs local
snap inputs. Impact derived from the original note's symptoms.

## Goal

Publish every core-desktop snap to the Snap Store properly so that:

- snap refreshes work inside installed images (unasserted/local snaps
  are frozen forever - the core limitation of the dangerous images),
- the model can become grade: signed and the image build needs NO local
  snap inputs at all (ubuntu-image + model only),
- the dangerous-grade publishing channel can be retired or demoted to a
  pure dev fast-path.

## Why this is the "old flow" restored

The pre-2026 cdimage builds worked exactly this way: Launchpad recipes
built each snap from GitHub and uploaded to the store under Canonical
publishers (core24-desktop from canonical/core-base-desktop tree/24 is
the proof case - still in the store today), the model was grade: signed
referencing store IDs + channels, and snap
prepare-image/ubuntu-image just downloaded everything. The 26 stack
stopped short of this step, which is why local builds and dangerous
models exist.

## Constraint recap (from this conversation)

- The owner is NOT in the desktop-snappers / ubuntu-desktop / snappy-dev
  Launchpad teams, and Launchpad ACLs are independent of GitHub
  (canonical/desktop grants nothing there).
- BUT: recipes/teams are only ONE mechanism. Store publishing from
  GitHub Actions needs only SNAPCRAFT_STORE_CREDENTIALS (restricted
  snapcraft.io credentials) as a repo secret + collaborator rights on
  the snap names. No Launchpad membership required. Personal recipes
  (`~your_username/+snap/...`) remain possible for Launchpad-hosted
  builds if ever wanted.
- Model signing by the `canonical` brand "models" key is IS-controlled
  via RT (docs/models.md). No GitHub secret can ever substitute - by
  design (HSM-held brand key). The owner is Canonical staff with RT
  access, so this is a ticket, not a blocker.

## Inventory (verified in the store 2026-10-09 unless marked)

- `core26-desktop` — NOT in store (name unresolvable) —
  canonical/core-base-desktop
- `pc-desktop` (gadget) — 24-era in store; 26 track to verify —
  canonical/pc-amd64-gadget-desktop
- `pc-kernel` — 26/stable published — (store-managed kernel)
- `snapd` — edge/ubuntu-core-desktop via ~snappy-dev —
  canonical/ubuntu-core-desktop-snapd
- `ubuntu-desktop-session` — in store (id LVkazk0...) —
  canonical/ubuntu-desktop-session-snap
- `ubuntu-desktop-init` — latest/candidate —
  ubuntu-desktop-provision (fork)
- `gnome-desktop-runtime` — NOT in store —
  canonical/gnome-desktop-runtime
- `pipewire` — in store, Canonical — canonical/pipewire-snap
- `mesa-2404`, `gnome-46-2404`, `core26`, `core24`, `bare`,
  `gtk-common-themes`, `network-manager`, `avahi`, `bluez`, `udisks2`,
  `upower`, `snap-store` — already published by their existing
  publishers (consume only)
- `plasma-desktop-session` — in store, published by KDE —
  chris-bainbridge (planned)
- `plasma-core26-desktop` — not publicly resolvable —
  chris-bainbridge (planned)
- `kf6-core26` — not publicly resolvable — chris-bainbridge (planned)

## Phases

1. Rights (one email/RT, longest lead after IS signing)

   Ask the desktop-snappers / ubuntu-desktop team admins to add the
   publishing account as COLLABORATOR on the owned names
   (core26-desktop, pc-desktop, ubuntu-desktop-session,
   ubuntu-desktop-init, gnome-desktop-runtime, ...), including release
   rights on the target tracks (26/stable,
   latest/edge/ubuntu-core-desktop). Alternatives: join the Launchpad
   teams (if collaboration is refused or tracks are locked), or
   Canonical registers fresh names under a dedicated publisher. For the
   KDE three: blocked on the adoption-vs-KDE-handover decision (if
   handed over, names can transfer to KDE's publisher via store
   support).

2. Per-repo publish CI (no Launchpad)

   Extend each snap repo's build workflow (from the GNOME plan) with a
   publish job gated on manual approval:

   - restricted SNAPCRAFT_STORE_CREDENTIALS repo secret
   - `snapcraft upload *.snap` -> edge/ubuntu-core-desktop
     (gadget/kernel snaps are signed automatically by the store on
     upload - mandatory for UC20+; no extra approval step)
   - test, then `snapcraft release` to 26/stable (promotion, not
     rebuild, so edge and stable are the same artifacts)

   Gated edges + promotion keep stable shippable while 26 is in flux.

3. Signed models

   - Update the model JSONs: grade: signed, all snaps store-published
     with final channels, drop nothing local.
   - RT to IS to sign with the canonical brand "models" key
     (account-key 9tydnLa6MTJ-... = account "models"; the same key that
     signs ubuntu-classic dangerous models in canonical/models).
   - Commit signed models to canonical/ubuntu-core-desktop; mirror to
     canonical/models per docs/models.md.
   - Keep the dangerous JSONs as the dev fast-path for unmerged work.

4. Simplify the image build

   build.sh drops --base-snap/--snapd-snap/--snap/--kde-session-snap
   (all inputs now store-resolved by the model); build-image.yaml
   shrinks to ubuntu-image + publish. Keep the per-snap CI - it is now
   the store feed. In-image `snap refresh` starts working at this
   point; verify a refresh cycle end-to-end in a VM.

5. Cleanup / decisions

   - Retire the dangerous GitHub release channel once signed images are
     proven (or keep as nightly-dev, clearly labelled).
   - Decide whether to also revive the INSTALLER ISO story: fix the
     broken livecd-rootfs ubuntu-core-installer:desktop build (broken
     since 26.04.27, see 149a9921) with the new signed 26 model vendored
     in, or port it to the ubuntu-core ubuntu-image path. Separate
     effort, separate approval (livecd-rootfs lives on Launchpad git;
     the owner would need the relevant team or a sponsoring uploader).

## Risks / notes

- Track permissions: some store names lock releasing to specific
  tracks; if 26/stable release is refused for a collaborator, that is
  the fallback point where team membership (or a track grant) is
  needed.
- core26-desktop has never been published; its FIRST store upload is
  the moment to confirm the store auto-signing path for the gadget
  (pc-desktop 26) too, before any model depends on it.
- The signed model is only as good as its channels: keep the model's
  pinned channels in sync with what CI actually promotes.

## Resolution (2026-11-03)

SUPERSEDED (owner decision) - replaced by
`20261103-publish-core-desktop-snaps-to-the-store.md`. The premise
changed since this was written: the per-snap GitHub CI is now live and
publishing desktop-26-latest release assets (see
`20261008-gnome-github-ci.md` and
`20261009-build-and-publish-gnome-dangerous.md` /
`20261009-build-and-publish-kde-dangerous.md`), and the KDE snap set
moved to the chris-bainbridge repos on the deb-repack pipeline.

What carries forward into the new note: the constraint recap (Launchpad
ACLs independent of GitHub; SNAPCRAFT_STORE_CREDENTIALS is sufficient
for GitHub-side publishing; the canonical brand "models" key is
IS-held, requested via RT, and cannot be substituted by any repo
secret), the 2026-10-09 store inventory snapshot, the fact that
gadget/kernel assertions are store-signed on upload (mandatory, UC20+),
and phases 3-5 (signed models, simplified image build, cleanup). The
phase-2 mechanism (restricted store credentials + `snapcraft upload`)
becomes Option A of the new per-snap plan; Launchpad snap recipes - the
historical mechanism that published these snaps from these very repos -
is Option B.
