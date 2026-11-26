# Build and publish the dangerous GNOME image (ubuntu-core-desktop-26-amd64)

Date: 2026-10-09
Follows: `20261008-gnome-github-ci.md` (detailed per-repo CI plan)
Model: canonical/ubuntu-core-desktop,
ubuntu-core-desktop-26-amd64-dangerous.json

## Impact / Priority

No one outside the build machine could download and boot a current
GNOME VM image: publishing of the old cdimage edge dailies had been
broken since January, and the snaps were not published anywhere, so the
project had no distributable developer-preview image at all. Impact
derived from the original note's described symptoms.

## Goal

Build and continuously publish a "dangerous" Ubuntu Core Desktop 26
GNOME VM image that anyone can download and boot, entirely from GitHub
- no Launchpad team membership, no Snap Store publishing, no
livecd-rootfs.

Everything lives under https://github.com/canonical/ubuntu-core-desktop
(owner has push rights) plus the six canonical/* snap source repos on
their desktop/26 branches. The detailed snap-CI mechanics are already
worked out in `20261008-gnome-github-ci.md`; this file is the top-level
plan plus the corrections/decisions made since that note.

## Facts established 2026-10-09 (this conversation)

- Model identity: authority/brand UJySllegsYenHktWHqU1R1PAk9FzxMoj
  (snapcraft account "chris-bainbridge"), signed by the registered
  "test" key, sign-key-sha3-384
  B55Ji_hfo6XxL5cQQpl6ONjVDelaVrcT-K-trKU1ZzzplG2q1mw-8aDRTWyXza5S.
  grade: dangerous is what permits local, store-absent snaps; no store
  approval is involved anywhere.
- The account-key assertion for that key is PUBLIC store data and can
  be committed to the repo:

      snap known --remote account-key \
        public-key-sha3-384=B55Ji_hfo6XxL5cQQpl6ONjVDelaVrcT-K-trKU1ZzzplG2q1mw-8aDRTWyXza5S

- All store-sourced snaps in the model resolve (verified): pc-kernel
  26/stable, snapd latest/stable, network-manager 26/stable, upower
  24/stable, core26/core24/bare, udisks2 26/stable, snap-store 2/stable,
  ubuntu-desktop-init latest/candidate. The ONLY non-store inputs are
  the seven locally built snaps (pc-desktop, core26-desktop, snapd,
  ubuntu-desktop-session, gnome-desktop-runtime, pipewire,
  ubuntu-desktop-init).
- The old cdimage.ubuntu.com/ubuntu-core-desktop/26/edge/ dailies were
  SUBIQUITY INSTALLER ISOs built by Launchpad from livecd-rootfs
  (PROJECT=ubuntu-core-installer SUBPROJECT=desktop) - a different
  artifact and a different pipeline from this VM image. They broke in
  26.04.27 and stopped 2026-01-26 ("the installer still fails for
  unclear reasons", livecd-rootfs 149a9921). Nothing in this plan
  depends on them; fixing livecd-rootfs/cdimage is deferred (see the
  snap-store long-term plan).
- cdimage publishing requires Canonical cdimage admin access
  regardless; GitHub Releases is the practical publish target for now.

## Plan

1. Push the one unpushed branch: ubuntu-desktop-provision fork
   desktop/26 (owner's fork; never upstream).

2. Per-snap CI on the six canonical/* repos (per
   `20261008-gnome-github-ci.md` Step 2): build-snap workflow on
   desktop/26 -> upload .snap as a RELEASE ASSET (not a workflow
   artifact - artifacts are not anonymously fetchable cross-repo,
   release assets are). Release convention: each repo keeps a rolling
   "desktop-26-latest" release whose assets are replaced on every green
   build, so the image workflow always consumes the newest snap and
   snaps are only rebuilt when their source actually changes. Special
   cases carried over: core-base-desktop needs build-github.sh for the
   core26->core26-desktop meta/snap.yaml rename repack (build.sh and
   the gadget expect the base snap named core26-desktop) - but NO
   SNAP_BUILD_VARIANT=cloud-init (2026-10-09 owner decision: the
   published image has no pre-created account and no seed.iso, so
   nothing consumes cloud-init). NOTE: every locally boot-tested
   core26-desktop snap DID include the cloud-init variant (the
   core-base-desktop local build writes it), so the first CI image must
   be boot-tested to confirm the no-cloud-init base changes nothing
   visible. ubuntu-core-desktop-snapd gets a new separate workflow
   file; snapcraft-channel edge (9.x) for core26-based repos.

3. build.sh change (canonical/ubuntu-core-desktop, desktop/26): accept
   a PRE-SIGNED model assertion (.model) and skip `snap sign` when one
   is supplied. Then no private key ever touches CI - the signed model
   is committed to the repo and only refreshed locally when the JSON
   changes (snap sign -k test --update-timestamp, commit). This
   resolves the "store GPG_SIGN_KEY_TEST as a repo secret?" open
   question from the 20261008 note in the simplest direction. (The
   key-as-secret variant remains a fallback if per-build timestamp
   freshness ever matters - it does not for seeding.)

4. Commit to the repo:

   - ci/account-key.assert (public, see above)
   - the signed ubuntu-core-desktop-26-amd64-dangerous.model
     (refresh procedure documented in the commit or docs/)

5. Replace the stub .github/workflows/build-image.yaml with a real
   workflow. Per the 2026-10-09 owner decision it CONSUMES the per-repo
   release assets rather than building the snaps itself (no daily
   re-build of unchanged snaps, no matrix job; this also supersedes the
   matrix design in `20261008-gnome-github-ci.md` Step 3). Job steps:
   checkout ubuntu-core-desktop@desktop/26; download the newest
   desktop-26-latest release assets of the seven repos (six canonical/*
   + chris-bainbridge/ubuntu-desktop-provision; plain GITHUB_TOKEN
   suffices for public repos); apt install squashfs-tools dosfstools
   mtools fakeroot crudini zstd; snap install --classic ubuntu-image;
   then run:

     ./build.sh --desktop gnome \
       --model-account-key ci/account-key.assert \
       --base-snap core26-desktop.snap \
       --gadget-snap pc-desktop.snap \
       --snapd-snap snapd.snap \
       --snap ubuntu-desktop-session.snap \
       --snap gnome-desktop-runtime.snap \
       --snap pipewire.snap \
       --snap ubuntu-desktop-init.snap \
       ci/ubuntu-core-desktop-26-amd64-dangerous.model

   Deliberately NO --user, NO --autologin and NO --root-password
   (2026-10-09 owner decision: no hardcoded or baked-in passwords
   anywhere): root stays locked and the published image boots into the
   GDM initial-setup -> ubuntu-desktop-init first-boot wizard, which
   creates the user account. build.sh drops build/pc.img.nouser in this
   mode - that is the wanted behaviour.

6. Compress and publish with DATED TAGS (2026-10-09 owner decision,
   replacing the rolling-release idea): zstd -T0 -19 build/pc.img -o
   ubuntu-core-desktop-gnome-YYYYMMDD.img.zst; SHA256SUMS alongside;
   create a GitHub release tagged gnome-YYYYMMDD (KDE later:
   kde-YYYYMMDD) whose assets are that day's .img.zst + SHA256SUMS. A
   same-day rebuild deletes and re-creates that date's tag/release so
   the tag always points at the newest run of that day. Dated tags make
   it trivial to see when a build was made and to pin/report against a
   specific one. Release notes carry the DANGEROUS label prominently:
   model signed by an individual's registered key, snaps unasserted and
   never refreshable, no baked credentials.

7. Verify end-to-end locally (no KVM in CI): download the CI image,
   boot under QEMU per README (no seed.iso), walk the first-boot
   wizard, confirm the confined GNOME session comes up. Only then
   enable the daily cron.

8. cdimage follow-up (owner/cdimage-admins, not GitHub): decide whether
   these VM images should also appear at
   cdimage.ubuntu.com/ubuntu-core-desktop/26/dangerous/ and whether the
   dead 26/edge/ tree should be removed. No in-repo mechanism exists;
   needs cdimage-side access.

## Decisions (2026-10-09, resolving the former open questions)

- Dated tags per build (gnome-YYYYMMDD), not a rolling release.
- The image workflow consumes per-repo desktop-26-latest release
  assets; snaps rebuild only when their source changes. Consequence:
  per-repo workflows (step 2) are the only snap build infrastructure;
  the `20261008-gnome-github-ci.md` Step 3 matrix design is superseded.
- No cloud-init variant in the CI-built base snap; no --user, no
  --autologin, no --root-password (nothing baked, wizard-only).
- One-time local exports still needed: the signed model (refreshed
  locally and committed when the JSON changes) and ci/account-key.assert.

## Resolution (2026-10-10)

DONE and live. Steps 1-7 complete: desktop/26 pushed (incl. the
ubuntu-desktop-provision fork branch); per-snap CI publishing
desktop-26-latest release assets on all repos; build.sh accepts a
pre-signed model; ci/account-key.assert + signed
ubuntu-core-desktop-26-amd64-dangerous.model committed; build-image.yaml
(cron 05:00 + push + workflow_dispatch) consumes the seven release
assets and runs build.sh with NO --user/--autologin/--root-password
(pc.img.nouser, first-boot wizard only) exactly as decided; publishes
zstd -T0 -19 images + SHA256SUMS under dated gnome-YYYYMMDD tags (first
gnome-20261010, latest gnome-20261103, green on desktop/26 as of
2026-11-03); end-to-end boot verified before enabling the cron. Step 8
(cdimage publishing / removing the dead 26/edge tree) remains blocked
on cdimage-admin access and is deferred - not a GitHub-side item; the
longer-term publishing direction is
`20261009-build-and-publish-on-the-snap-store.md`.
