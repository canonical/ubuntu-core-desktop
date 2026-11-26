# Publish the CI-built core-desktop snaps to the Snap Store, one at a time

## Impact / Priority

Priority: High as a roadmap gate, with no live user-facing bug today.
What a real user of the current published images loses if this never
happens: the dangerous images' snaps are unasserted and frozen forever -
no `snap refresh` ever, so every installed image stays at exactly the
snap set it was built with (security fixes included), and the image
build needs seven local snap inputs. This gates the signed-model /
store-publishing roadmap (retire-or-demote the dangerous channel), which
is blocked until each snap is store-published with working refreshes.
It is not blocking any currently-shipping behaviour; the dangerous
pipeline is live and green.

## Context

Supersedes `20261009-build-and-publish-on-the-snap-store.md` (read it
for background). What changed since it was written: the per-snap GitHub
CI is live (`20261008-gnome-github-ci.md`,
`20261009-build-and-publish-gnome-dangerous.md`,
`20261009-build-and-publish-kde-dangerous.md`) - every snap already
builds on push and publishes a desktop-26-latest release asset; the KDE
snaps moved to chris-bainbridge repos on the deb-repack pipeline. The
old note's phase-2 mechanism (restricted store credentials +
`snapcraft upload`) and its phases 3/5 (signed models, cleanup) remain
valid; phase 4 is struck through (see Hard constraints).

## HARD CONSTRAINT (owner, 2026-11-03)

Do not remove the development build path. build.sh's local-input flags
(--base-snap, --snapd-snap, --snap, --kde-session-snap,
--model-account-key, and the local gadget patching) MUST keep working -
the dangerous dev fast-path (rebuild the image with `build.sh`, boot it
in the test VM) is the daily loop. Concretely: the old note's "phase 4 -
simplify the image build / build.sh drops the snap flags" must NOT be
done. The store-published path is ADDITIVE: a separate signed model that
resolves everything from the store, coexisting with the dangerous
local-input build. (Same constraint as
`20261029-migrate-gadget-connections-to-store-gadget.md`: the dev path
must keep working throughout and after the migration.)

## Method: one snap at a time

For EACH snap in the inventory below, work through this checklist and
record the answers here (append a per-snap section; do not proceed on
assumptions):

1. Store state today: `snap info <name>`, `snapcraft names`, store API
   or dashboard. Does the name exist? Who is the verified publisher?
   Which channels/tracks carry what? (The old note's 2026-10-09
   snapshot is a starting point, not current truth.)
2. Rights: who can upload/release to this name? Options in order of
   preference: collaborator grant on the existing name (store ticket /
   ask the publisher), existing team membership, registering a fresh
   name under a dedicated publisher. The owner is NOT in the
   desktop-snappers / ubuntu-desktop / snappy-dev Launchpad teams, and
   Launchpad ACLs are independent of GitHub (canonical/* push rights
   grant nothing there).
3. Publishing mechanism - decide per snap between:
   - Option A (build and push the .snap): extend the existing
     build-snap GitHub workflow with a gated publish job - restricted
     SNAPCRAFT_STORE_CREDENTIALS repo secret (created via `snapcraft
     export-login` with minimal scopes), `snapcraft upload <snap>
     --release=<channel>`, promotion to stable only after VM
     verification. This publishes the exact CI-built artifact.
   - Option B (source-to-store): Launchpad snap recipe building from
     the GitHub repo and uploading to the store - the historical
     mechanism ("these snaps previously built and published from these
     repositories"). CHECK FOR EXISTING RECIPES FIRST (Launchpad web
     UI / API, per snap name and per source repo) - the mechanism must
     already exist for at least the snaps with store history; reuse it
     rather than creating a parallel one. Recipe creation needs
     Launchpad rights (team membership or a sponsored/personal recipe -
     a personal recipe under your own Launchpad account is possible).
     Note the store accepts no source uploads directly - "push the
     source" always means Launchpad builds it and pushes the resulting
     snap.
   - Pick whichever matches each snap's existing history and
     maintenance cost; record the decision and why.
4. Signing key provenance - settle explicitly per snap:
   - Snap assertions: the SNAP STORE signs on upload; there is no
     user-held snap signing key to find. Launchpad recipe uploads and
     `snapcraft upload` are both store-signed (mandatory store-side
     signing for gadget/kernel snaps, UC20+). The locally-held `test`
     key in this project signs only the DANGEROUS MODEL assertions and
     is unrelated to store publishing.
   - The "somewhere" the historical keys/mechanisms live: existing
     Launchpad recipes under Canonical/team accounts, and store-side
     signing. Find them per snap (step 3's recipe search) rather than
     assuming.
   - Model assertions for the eventual grade: signed model: the
     canonical brand "models" account key (9tydnLa6MTJ-...), held by
     IS; request signing via RT per docs/models.md. No GitHub secret
     can ever substitute - by design.
5. Channel policy: publish to a gated edge (edge/ubuntu-core-desktop or
   26/edge) and promote to 26/stable only after a VM refresh/first-
   boot verification. Keep stable shippable while 26 is in flux.
6. Verification per snap: revision visible in `snap info` on the target
   track; refresh works inside a booted image; for the gadget
   (pc-desktop 26) the FIRST store upload doubles as the proof that
   the store auto-signing path works for our gadget - confirm before
   any signed model depends on it.

## Inventory

Current GitHub-CI-built set, desktop/26; store state from the
2026-10-09 snapshot - re-verify each in step 1:

- pc-desktop (gadget): canonical/pc-amd64-gadget-desktop - 24-era in
  store; 26 track to verify
- core26-desktop (base): canonical/core-base-desktop - NOT in store
  (name unresolvable)
- snapd: canonical/ubuntu-core-desktop-snapd - edge/ubuntu-core-desktop
  via ~snappy-dev
- ubuntu-desktop-session: canonical/ubuntu-desktop-session-snap - in
  store (id LVkazk0...)
- gnome-desktop-runtime: canonical/gnome-desktop-runtime - NOT in store
- pipewire: canonical/pipewire-snap - in store, Canonical
- ubuntu-desktop-init: chris-bainbridge/ubuntu-desktop-provision -
  latest/candidate, publisher seb128 (PERSONAL account, verified
  2026-11-03 store lookup, account-id tBdY...) - publisher-trust gap,
  see note below
- kf6-core26: chris-bainbridge/kf6-core26 - not publicly resolvable
- plasma-core26-desktop: chris-bainbridge/plasma-core-desktop - not
  publicly resolvable
- plasma-desktop-session: chris-bainbridge/plasma-desktop-session -
  already published by KDE upstream

PUBLISHER-TRUST note (found 2026-11-03): ubuntu-desktop-init is
store-published by a personal account (seb128), not a verified
Canonical publisher - the same concern recorded for the `upower` snap
("for a Core Desktop product image we should not depend on a
non-verified personal snap"). Fix before any product/signed model
consumes it: get the name transferred to (or republished under) the
verified Canonical publisher (snapcraft.io/canonical), with the
publishing wired to canonical/ubuntu-desktop-provision (the snap's
actual upstream repo) - not to any personal account or this project's
fork. Also folds into
`20261103-land-ubuntu-desktop-provision-off-the-personal-fork.md` step
2.

KDE caveat (from the old note): for the three KDE snaps there is an
open adoption-vs-KDE-handover decision - if handed over, names can
transfer to KDE's publisher via store support; if adopted, we need
collaborator rights. Resolve that before publishing KDE snaps.

## Order of work

1. Re-verify the inventory (step 1 per snap) and search for existing
   Launchpad recipes per snap - this answers the "where does the
   signing/publishing mechanism live today" question with facts.
2. Prove the mechanism end-to-end on ONE low-risk snap (candidates:
   pipewire - already Canonical-published; or ubuntu-desktop-init -
   has a candidate channel). Wire the gated publish job or recipe,
   upload, release to the gated edge, refresh in a VM.
3. Roll out to the rest in inventory order, recording each per-snap
   decision (mechanism, rights, channel) in this file.
4. Signed models + image-build coexistence (old phases 3/5, phase 4
   struck): update model JSONs to a grade: signed variant, RT to IS for
   the brand "models" key, commit signed models, keep the dangerous
   JSONs/build path untouched as the dev fast-path. Gated by
   `20261029-migrate-gadget-connections-to-store-gadget.md` (the store
   gadget must carry the connections first, or a signed boot fails
   gadget validation).
   [2026-11-04: SUPERSEDED by "Decisions" below - the grade: signed
   variant is DROPPED (core26-desktop stays unpublished); both models
   stay grade: dangerous, no RT/IS signing. The store migration
   proceeds via the dev build adopting store snaps one at a time with
   --snap overrides kept; see "Revised per-snap order and loop". The
   gadget-connections migration remains the gate for the pc-desktop
   conversion, and its declaration grants now gate the earlier
   conversions too (see "Per-snap facts", connection-policy
   discovery).]

## References

- `20261009-build-and-publish-on-the-snap-store.md` (constraint
  recap, 2026-10-09 inventory, original phases)
- `20261008-gnome-github-ci.md`,
  `20261009-build-and-publish-gnome-dangerous.md`,
  `20261009-build-and-publish-kde-dangerous.md` (the CI this plan
  extends)
- `20261029-migrate-gadget-connections-to-store-gadget.md` (signed
  model blocker)
- docs/models.md (model signing process)

## Decisions (owner, 2026-11-04)

- core26-desktop (core-base-desktop) will NOT be store-published.
  Reason: the plan is to eliminate the core26-desktop base entirely
  and move to a plain core26 base (separate issue, matches the
  long-term direction for the core-base-desktop base). Until then
  the base stays a LOCAL --base-snap input in every build path (dev
  and release); build.sh's base patching (polkit socket, ssh,
  sudoers, gdm config, gnome-session shim, fix-console) stays
  required. Consequence: grade: signed is impossible for the 26
  models (a signed model must reference a store-published base) -
  both models stay grade: dangerous, signed by the local test key
  (no RT/IS needed).
- snapd will NOT be published by this project - publishing snapd is
  the snapd team's job (we are not the snapd team). The models should
  reference a snapd-team channel; precedent: the old signed 24 model
  used latest/edge/ubuntu-core-desktop (Signed-model history below),
  which no longer shows in `snap info snapd` today. Owner action:
  ask ~snappy-dev / the snapd team to build
  canonical/ubuntu-core-desktop-snapd desktop/26 into that (or a
  26/*) channel again - the channel must carry our fork's required
  patches (Per-snap facts). Until it exists AND carries them, snapd
  stays a local --snapd-snap input in BOTH dev and release builds.
- The DEV build migrates to store snaps too, one snap at a time:
  the dev build path stops passing each converted snap locally by
  default and lets the model channel resolve it, while
  --snap/--snapd-snap stay as the way to override and hack any snap
  locally. HARD GATE: after every conversion the dev fast-path (the
  dev build + boot loop) must build and boot identically (same
  connection set, no regressions) before the next snap is converted.
  The dangerous dev build must remain buildable and testable at all
  times.
- Two model JSONs (owner decision): the existing dangerous JSONs
  stay as the dev models (their channels may ride edge/candidate);
  a NEW release JSON ubuntu-core-desktop-26-amd64.json (pinned
  stable channels) drives the release image build (build-image.yaml).
  Both grade: dangerous (see above).

## Signed-model history (answer to "there was a signed model before")

The signed model that worked was ubuntu-core-desktop-24-amd64.json
(grade: signed, authority/brand canonical; deleted in 068e868 when
22/24 support was dropped). It worked because EVERY snap in it was
store-published: core24-desktop IS in the store today (snap-id
GY5GohJ4F1ZsWpkosG0joeZyDfHzTZrD, latest/stable 20250326 - visible,
not hidden), and snapd came from the snapd-team channel
latest/edge/ubuntu-core-desktop. There was NEVER a signed 26 model:
the 26 stack went straight to grade: dangerous because core26-
desktop was never published.

## Per-snap facts (checklist steps 1-3, verified 2026-11-04)

- Store state re-verified: pc-desktop (22/24 tracks only, no 26),
  snapd (latest/* + fips-updates only; no 26 track, no
  latest/edge/ubuntu-core-desktop), ubuntu-desktop-session
  (latest/stable + 24/stable; NO 26 channel), pipewire (Canonical,
  latest/stable 1.2.4-1ubuntu1), gnome-desktop-runtime (NOT
  registered), core26-desktop (NOT registered - by decision above),
  ubuntu-desktop-init (seb128 personal account, latest/candidate
  0+git.9ee3f2649).
- Mechanism: Option A - extend each snap repo's existing
  build-snap.yml with a manually-gated publish job
  (SNAPCRAFT_STORE_CREDENTIALS repo secret + `snapcraft upload
  <snap> --release=26/edge`), promoting to 26/stable only after VM
  verification. Publishes the exact CI-built artifact. Option B
  check: 2026-11-04 anonymous api.launchpad.net probes of
  ~snappy-dev / ~desktop-snappers / ~canonical +snaps returned
  empty - INCONCLUSIVE (may just mean the API needs auth); confirm
  via the authenticated Launchpad web UI before investing in Option
  B. Option A needs no Launchpad rights.
- Rights (owner, in order): collaborator grants on the Canonical
  names (pc-desktop, ubuntu-desktop-session, pipewire); registration
  of gnome-desktop-runtime under Canonical; seb128 collaboration for
  ubuntu-desktop-init (publish to a 26 channel on his name until the
  verified-publisher transfer in
  `20261103-land-ubuntu-desktop-provision-off-the-personal-fork.md`).
  No store credentials existed in the build environment (`snapcraft
  whoami`: no keyring); the SNAPCRAFT_STORE_CREDENTIALS secrets are
  owner actions.
- build.sh patching surface (what must stay local): ONLY the base
  (--base-snap) and the gadget (--gadget-snap) get unsquashed and
  patched. snapd, ubuntu-desktop-session, gnome-desktop-runtime,
  pipewire and ubuntu-desktop-init pass into ubuntu-image UNMODIFIED
  - converting them to store-resolved inputs loses nothing from the
  build pipeline.
- pipewire and gnome-desktop-runtime are NOT in the model JSONs
  today - they ride in purely via --snap. The release JSON must ADD
  entries (name/type/default-channel) for both.
- The snapd fork (desktop/26) carries ~15 required runtime patches
  (confined GDM greeter, GNOME Shell registration, pipewire audio
  delegation, udisks2/upower/pam-unix-chkpwd/KAuth/polkit fixes,
  name-based gadget endpoints, current libseccomp for snap-seccomp).
  Whatever snapd the models resolve MUST carry them; upstream
  latest/stable does not - hence the channel request above names our
  fork, not upstream.
- CONNECTION-POLICY DISCOVERY (affects the whole loop): snaps
  resolved from the store are ASSERTED (they carry snap-declarations
  in the model), so snapd's connect checker stops skipping policy
  for their gadget connections - the skip is only for unasserted/
  dangerously-installed snaps (see
  `20261029-migrate-gadget-connections-to-store-gadget.md`). The
  moment a converted snap (e.g. pipewire) is store-resolved, its
  gadget connections (audio-playback, dbus-portal-*, ...) become
  policy-checked, and pipewire/pulseaudio deny-connection (and
  wayland/x11/desktop deny-connection/installation) apply on Core
  unless granted. So the 20261029 declaration-grant audit is NOT
  just the pc-desktop blocker - it gates the conversion loop
  itself. Watch snapd logs for connection-policy denials in every
  per-snap VM verification; expect store declaration grants to be
  needed per converted snap.
- Gadget (pc-desktop): blocked on
  `20261029-migrate-gadget-connections-to-store-gadget.md`
  (snap-ID-keyed connections + declaration grants); until then the
  release build keeps the local patched gadget. Its publish job also
  needs a base repack: the gadget snapcraft.yaml builds with
  base: core26 (snapcraft cannot build the unknown core26-desktop
  base), but the model's base is core26-desktop and ubuntu-image
  validates they agree - so the publish job must repack meta/snap.yaml
  core26 -> core26-desktop before upload (the same
  fakeroot-unsquashfs/sed/mksquashfs trick as core-base-desktop's
  build-github.sh; disappears once the base moves to plain core26).
  Its FIRST store upload doubles as the proof that store auto-signing
  works for our gadget (checklist step 6).
- KDE snaps: unchanged - still blocked on the adoption-vs-KDE-handover
  decision above.

## Revised per-snap order and loop (2026-11-04)

Order: pipewire -> gnome-desktop-runtime -> ubuntu-desktop-session
-> ubuntu-desktop-init -> pc-desktop (last). snapd is out of our
hands (channel request above). Per snap:
1. Owner: rights + SNAPCRAFT_STORE_CREDENTIALS secret.
2. Commit the gated publish job to that repo's build-snap.yml.
3. Publish to 26/edge; verify with `snap info <name> 26/edge`; VM-test
   the artifact first by passing it as a local --snap in a throwaway
   build (no committed files touched).
4. Promote 26/edge -> 26/stable after VM verification.
5. Commit to ubuntu-core-desktop: release JSON entry/channel, bump
   revision/timestamp, re-sign (`snap sign -k test
   --update-timestamp`), refresh the committed .model; drop the snap
   from build-image.yaml's release-asset download + --snap list.
6. The dev build drops the local pass-through for that snap; dev boot
   verification (hard gate above), including the connection-policy
   watch.
7. Append the per-snap decision (mechanism/rights/channel) here.
At the end: resolution note, move this file to done/, and a docs note
for the store-publishing mechanism + signed-model history. Also:
docs/models.md documents the second model; build-image.yaml release
notes drop "snaps are unasserted and can never be refreshed" (only the
base + gadget stay unrefreshable once converted).

## Progress log

2026-11-04 (scaffold + pipewire wiring, both pushed):
- Release model committed (canonical/ubuntu-core-desktop desktop/26
  b9f2221): ubuntu-core-desktop-26-amd64.json (exact copy of the
  dangerous model with the -dangerous name/display-name dropped;
  pipewire/gnome-desktop-runtime entries get added at their
  conversion steps - gnome-desktop-runtime has no snap-id until its
  name is registered), signed
  ci/ubuntu-core-desktop-26-amd64.model (local `snap sign -k test
  --update-timestamp`, verified the sign-key-sha3-384 matches the
  committed ci/account-key.assert chain), docs/models.md updated
  (two models, why grade stays dangerous). NOT yet wired into
  build-image.yaml - that happens at the pipewire conversion, when
  the release model starts resolving from the store.
- pipewire publish job committed (canonical/pipewire-snap desktop/26
  145ad22): manual-only publish-26-edge job (needs: snap) downloads
  the same run's artifact and runs `snapcraft upload pipewire.snap
  --release=26/edge` with the SNAPCRAFT_STORE_CREDENTIALS secret.
  Verified the push run stays build-only (publish job skipped).
- Facts recorded for later steps: `snap sign -k test` works for the
  local user (same key chain); pipewire store snap-id
  cXXVv4NGwXqlxTVSdrjsuvrPGAHfRSRs (release JSON entry at
  conversion); gh auth = chris-bainbridge (push + workflow scopes).

## Blocked on owner (in order)

0. HOW TO OPEN STORE REQUESTS (verified 2026-11-04): the Snap Store's
   request tracker is the snapcraft Forum, category store-requests
   (https://forum.snapcraft.io/c/store-requests) - NOT RT, not
   Launchpad. Sign in with Ubuntu SSO (the chris-bainbridge snapcraft
   account); store admins action requests in-thread (~1-2 day
   turnaround). Subcategory map: tracks -> /tracks; collaborator
   grants + name registration -> top-level category ("other requests
   needing store admin handling"); snap-declaration allow-connect
   grants (the 20261029 item) -> /privileged-interfaces. Precedents:
   pc-kernel 26.04 track and avahi 26 track were both forum-
   requested; Mir team bundled five 26 track requests in one post;
   name transfers to Canonical also go through it. Track creation is
   NOT publisher self-serve in the dashboard - don't hunt for an
   "add track" button. ubuntu-desktop-init needs no forum request:
   seb128 is the publisher, ask him directly.
1. Collaborator grant on the "pipewire" name (Canonical-published);
   SNAPCRAFT_STORE_CREDENTIALS secret on canonical/pipewire-snap
   (snapcraft export-login, minimal scopes); create the "26" track
   on the name (dashboard) - snapcraft upload cannot create tracks
   non-interactively.
2. Trigger publish-26-edge; verify `snap info pipewire 26/edge`.
3. VM-verify the 26/edge artifact (pass it as --snap in a throwaway
   build), promote to 26/stable, then the conversion commit: pipewire
   entry in the release JSON + re-sign, drop pipewire from
   build-image.yaml's download list and --snap args, switch
   build-image.yaml to the release model, drop pipewire from the dev
   build's local `--snap` inputs, dev boot verification (hard gate).
4. Same rights pattern for the remaining snaps + gnome-desktop-runtime
   registration + seb128 collaboration (ubuntu-desktop-init).
