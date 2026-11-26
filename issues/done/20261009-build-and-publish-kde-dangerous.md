# Build and publish the dangerous KDE image (ubuntu-core-desktop-kde-26-amd64)

Date: 2026-10-09 (rewritten 2026-10-13)
Follows: `20261009-build-and-publish-gnome-dangerous.md` (GNOME is DONE
and live: canonical/ubuntu-core-desktop release "gnome-20261010"; this
plan mirrors its working pipeline)
Model: canonical/ubuntu-core-desktop,
ubuntu-core-desktop-kde-26-amd64-dangerous.json/.model
(brand-id/authority UJySllegsYenHktWHqU1R1PAk9FzxMoj, same signing key
as the GNOME model - ci/account-key.assert already committed and covers
both)

## Impact / Priority

No published KDE developer-preview image existed at all, and the old
from-source KDE stack needed hours-long multi-stage compiles unsuitable
for GitHub-hosted CI, so KDE could not be built or distributed the way
the GNOME image was. Impact derived from the original note's described
symptoms.

## Why this rewrite

The previous version of this plan (2026-10-09) assumed the old
from-source KDE stack (kde-qt6-core-sdk -> kde-pyside6-core-sdk ->
kf6-core-sdk -> kf6-core26/plasma-core-desktop/plasma-desktop-session),
which needed hours-long multi-stage compiles unsuitable for ordinary
GitHub-hosted runners. That pipeline is gone. As of the current KDE
build setup, the three runtime snaps are plain snapcraft builds that
stage pre-built packages from the KDE Neon release/resolute apt suite
(Qt 6.11.1 / KF6 6.30 / Plasma 6.7.5) - no compilation. This means the
KDE snaps can now build on normal ubuntu-latest GitHub Actions runners,
exactly like the GNOME snaps.

## Repositories actually required now (verified against the KDE build)

Only THREE KDE-specific repos remain, all already on GitHub under
https://github.com/chris-bainbridge/ (owner-controlled "origin", not
canonical/), each with the desktop/26 branch already pushed:

1. kf6-core26 — KF6+Qt6 runtime content snap. Has a plain build.sh that
   is ALREADY CI-safe (no local-script dependency) - just `snapcraft
   pack` + copy to the fixed kf6-core26.snap name. Reuse as-is.
2. plasma-core-desktop — Plasma shell runtime content snap
   (plasma-core26-desktop). Needs a new build-github.sh (snapcraft pack
   + rename to plasma-core-desktop.snap, mirroring
   core-base-desktop/build-github.sh's pattern but WITHOUT its
   base-snap-rename repack step).
3. plasma-desktop-session — Session snap + staged Neon sddm deb. Also
   needs a new build-github.sh (snapcraft pack, same shape as
   plasma-core-desktop's).

The old SDK repos (kde-qt6-core-sdk, kde-pyside6-core-sdk,
kf6-core-sdk) are NOT needed for this pipeline any more. They still
exist for reference/experimentation but nothing here depends on them.

Everything else needed is already covered by the GNOME plan's shared
repos: core-base-desktop, pc-amd64-gadget-desktop,
ubuntu-core-desktop-snapd, ubuntu-desktop-provision
(ubuntu-desktop-init) - all already building desktop-26-latest release
assets.

## First-boot account: solved, no wizard needed

The old plan's open issue ("SDDM has no first-boot account-creation
story") is resolved by NOT relying on one at all. Per the image build's
no-user/--autologin configuration (`build.sh` flags, tested locally for
KDE), the KDE image is built with a baked-in guest account instead of
the GNOME image's "no baked credentials, first-boot wizard creates the
user" approach:

    --autologin
    --user guest
    --password "guest"
    --desktop kde
    --model-account-key ci/account-key.assert
    --base-snap <core26-desktop.snap>
    --gadget-snap <pc-desktop.snap>
    --snapd-snap <snapd.snap>
    --snap <plasma-core26-desktop.snap>
    --snap <kf6-core26.snap>
    --snap <ubuntu-desktop-init.snap>
    --kde-session-snap <plasma-desktop-session.snap>
    --kde-plasma-snap <plasma-core26-desktop.snap>
    --model ci/ubuntu-core-desktop-kde-26-amd64-dangerous.model

build.sh already fully supports --autologin for the kde desktop target
(SDDM autologin config, pam.d patching - see build.sh:346-364,472,823)
and --kde-session-snap/--kde-plasma-snap are already wired (build.sh:
117-121, 601-662, 939+). This is a deliberate difference from the GNOME
image (which ships no baked account and relies on the GDM/
ubuntu-desktop-init first-boot wizard) and must be called out
prominently in the release notes alongside the "dangerous" label:
unasserted snaps, individually-signed model, AND a publicly known
guest/guest account.

## Plan

1. Per-snap CI on the three chris-bainbridge/* repos (desktop/26),
   mirroring canonical/core-base-desktop's build-snap.yml: checkout ->
   install squashfs-tools/fakeroot -> set up LXD (same iptables FORWARD
   ACCEPT workaround) -> snap install snapcraft --classic -> run the
   repo's CI build script -> publish the .snap as a release asset on a
   rolling "desktop-26-latest" release (same convention as the GNOME
   repos) -> upload-artifact for debugging.

   - kf6-core26: reuse build.sh unchanged.
   - plasma-core-desktop: add build-github.sh (snapcraft pack, rename
     output to plasma-core-desktop.snap - matches the fixed name the
     KDE build already expects).
   - plasma-desktop-session: add build-github.sh (snapcraft pack, keep
     the plasma-desktop-session.snap output name).
   These are owner-controlled repos (origin = chris-bainbridge), so no
   cross-org permission issues; GITHUB_TOKEN is sufficient.

2. Commit to canonical/ubuntu-core-desktop (desktop/26):

   - ci/ubuntu-core-desktop-kde-26-amd64-dangerous.model (pre-signed,
     same refresh procedure as the GNOME model; account-key.assert is
     already committed and shared between both models).

3. Add a `kde` image-build workflow (new file, e.g.
   .github/workflows/build-image-kde.yaml, or extend build-image.yaml
   with a second job) modeled directly on the GNOME job:

   - runs-on: ubuntu-26.04 (same du/calculate_rootfs_size fix as
     GNOME).
   - Download desktop-26-latest release assets from: canonical/
     pc-amd64-gadget-desktop, canonical/core-base-desktop, canonical/
     ubuntu-core-desktop-snapd, chris-bainbridge/
     ubuntu-desktop-provision, chris-bainbridge/kf6-core26,
     chris-bainbridge/plasma-core-desktop, chris-bainbridge/
     plasma-desktop-session - with the same wait-for-releases retry
     loop the GNOME job uses.
   - apt install squashfs-tools dosfstools mtools fakeroot crudini
     zstd; snap install --classic ubuntu-image.
   - Run build.sh with the args listed above (--autologin --user guest
     --password guest, --model ci/ubuntu-core-desktop-kde-26-amd64-
     dangerous.model). This drops build/pc.img (NOT pc.img.nouser,
     since --user is given) - no seed.iso needed/used.
   - Compress: zstd -T0 -19 build/pc.img -o
     "ubuntu-core-desktop-kde-$(date -u +%Y%m%d).img.zst"; sha256sum >
     SHA256SUMS. This filename/tag prefix ("kde-") is already distinct
     from GNOME's ("gnome-") by construction - no further uniquing
     needed, just don't accidentally reuse the GNOME tag or model name.
   - Release: dated tag kde-YYYYMMDD (same rolling/same-day-replace
     convention as GNOME), title "Ubuntu Core Desktop 26 KDE
     (dangerous)", notes stating clearly: DANGEROUS (unasserted snaps,
     individually-signed model) AND a baked-in guest/guest account with
     autologin - anyone with network/local access to a booted instance
     has a known-password account.
   - Trigger: push to desktop/26, workflow_dispatch, and a schedule
     (stagger the cron from GNOME's 05:00 slot, e.g. 06:00, so the two
     image builds don't contend for runner capacity).

4. Verify end-to-end locally first (no KVM in CI): download the CI
   image, boot under QEMU (as with the local KDE run setup: no
   seed.iso, since the account is baked into the image itself), confirm
   autologin into a confined Plasma/SDDM session as guest. Only then
   enable the schedule trigger.

5. Cross-snap version-skew check: the KDE build's check_version_skew
   (comparing meta/pkg-manifest.txt libqt6/libkf6/libplasma versions
   between kf6-core26 and plasma-core26-desktop) is local-only today.
   Consider porting it into the CI image workflow as a guard step
   before `./build.sh` runs, so a partial Neon-version bump across
   repos fails CI loudly instead of producing a boot-time ABI mismatch
   (the noble-vs-resolute libxkbcommon precedent is recorded in the
   project documentation). Not a hard blocker for the first green
   build, but do it before enabling the daily schedule.

## Explicitly out of scope / deferred

- Re-adding the from-source SDK chain (kde-qt6-core-sdk etc.) - not
  needed while the Neon-apt-package approach is the chosen
  architecture. Revisit only if that approach is abandoned.
- Any first-boot wizard / cloud-init seed.iso story for KDE -
  superseded by the baked guest/guest account decision above.
- Store/publisher-name questions (plasma-desktop-session already
  published by KDE upstream; kf6-core26/plasma-core26-desktop IDs
  private) - irrelevant to this dangerous/local-snap pipeline; revisit
  only if/when a store-asserted KDE image is planned (see
  `20261009-build-and-publish-on-the-snap-store.md`).
- cdimage.ubuntu.com publishing - same as the GNOME plan, needs
  cdimage-admin access outside GitHub; not attempted here.

## Resolution (2026-10-13)

DONE and live. Steps 1-4 complete: build-github.sh added to
plasma-core-desktop and plasma-desktop-session (kf6-core26 reused its
existing CI-safe build.sh), all three chris-bainbridge/* repos publish
desktop-26-latest release assets; ci/ubuntu-core-desktop-kde-26-amd64-
dangerous.model committed (account-key.assert shared with GNOME);
build-image-kde.yaml live on desktop/26 (cron 06:00, staggered from
GNOME's 05:00) publishing dated kde-YYYYMMDD releases (latest
kde-20261103, green as of 2026-11-03); image boot-verified. DEVIATION
from this plan: the baked guest/guest autologin account was later
dropped entirely - commit 6bd6595 "ci(kde): drop the seed ISO, use the
plasma-setup wizard"; the published KDE image now ships NO baked
credentials and boots the plasma-setup first-boot wizard (see
`20261013-kde-use-plasma-setup.md`), matching GNOME's
no-baked-credentials approach - so the release-notes guest-account
warning no longer applies. Step 5 (version-skew guard in CI) was NOT
ported; the deb-repack pipeline's local KDE build skew check remains
the guard. cdimage publishing deferred as above.
