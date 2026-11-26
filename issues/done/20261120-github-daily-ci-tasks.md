# CI: no daily builds, dated releases, or a11y snap CI (rolling *-latest)

Date: 2026-11-20

## Impact / Priority

Priority: High. It blocks producing any current GNOME image.

What a developer sees today:

- The releases page shows a GNOME image from 2026-11-08 and a KDE
  image from 2026-11-20. There is no GNOME image newer than Nov 8,
  and no way to get one, because the GNOME build is broken in CI.
- Someone installed the 20261108 release this week and did not have
  the a11y/wiring work committed on 2026-11-09..17. Nothing on the
  releases page said the build was 12 days stale, and nothing
  prevented picking it.
- The repo's "Latest" release badge currently points at a KDE
  release, so "just download the latest image" silently gets KDE.

Nothing here is an end-user regression by itself (this is a developer
preview), but every developer testing the image is exposed to stale
or wrong-flavour builds, and the GNOME line cannot be validated at
all until the a11y snap is published.

## Background: why the 12-day gap (2026-11-08 -> 2026-11-20)

Image releases are NOT produced by the cron. They are produced only
by "Publish dated release" steps, gated on
`github.event_name != 'pull_request'`, in
.github/workflows/build-image.yaml (143-158, arm64 340-355) and
build-image-kde.yaml (159-175). So a release appears only when
someone pushes to desktop/26.

Between those dates nobody pushed to desktop/26:

    2026-11-08 21:38:15Z  update by push   (6a8bac9, the Nov 8 work)
    2026-11-20 16:26:42Z  update by push   (0c3540a, authored Nov 17)
    2026-11-20 23:26:04Z  update by push   (65dac0e)

(.git/logs/refs/remotes/origin/desktop/26). The 13 commits dated
Nov 9..17 were authored over those days but sat unpushed locally,
so CI had nothing to build. This half of the problem is a push
habit, not a CI defect - but nothing surfaced it either.

The daily cron is DEAD CODE. Both workflows declare
`on: schedule` - build-image.yaml:8-9 `0 5 * * *`,
build-image-kde.yaml:8-11 `0 6 * * *` - but the repo has ZERO
schedule-event runs in its entire history (~80 runs: push 34+22,
pull_request 3+2, pull_request_target 3, workflow_dispatch 5+1+2,
debug-runner-du 9). Scheduled workflows are only evaluated from the
DEFAULT BRANCH; the default branch is `main`, and main's
.github/workflows/build-image.yaml has no `on.schedule` at all (and
would build main's old-generation image, not desktop/26). So the
cron on desktop/26 can never fire. Same root cause as the known
gotcha that new/renamed workflow files only get workflow_dispatch
registered from the default branch.

## Second finding: GNOME CI is red on both arches

Runs on 2026-11-20 for 0c3540a: build-image-kde SUCCESS
(44773459481), build-image FAILURE (44773460171) on both `image`
and `image-arm64`, at "Build image":

    ERROR: the GNOME image bakes gadget connections to these
    provider snaps, but none was provided via --snap:
      ubuntu-desktop-a11y
    Pass them like the CI does ...

build.sh:require_provider_snaps (commit 4939fa6, Nov 11) added
ubuntu-desktop-a11y to the required provider set (a11y bus +
provd:dbus-dconf connections are baked into gadget.yaml; a missing
provider silently drops the AppArmor grants). build-image.yaml was
never updated to download/pass it. So gnome-20261120 does not exist,
and the 23:26Z runs for 65dac0e fail the same way.

canonical/ubuntu-desktop-a11y itself has NO CI and no releases (and
is not in the Store): public repo, single branch desktop/26 @45e0dad,
snapcraft.yaml at snap/snapcraft.yaml, base `core26` (stock, so NO
core26-desktop base-swap trick is needed), `platforms:` amd64 only
(lines 55-58), `version: "0.1+git20261118"` hardcoded (line 3),
.gitignore ignores *.snap. Locally it is built by hand and picked up
by the no-user image build from the local ubuntu-desktop-a11y
checkout.

## Owner decisions (2026-11-20)

- Rolling *-latest releases only; no dated image releases. "Nobody
  is ever going to bisect from these images - they bisect source."
- Build ubuntu-desktop-a11y in CI and publish it as a GitHub release
  ASSET only. Do NOT publish it to the Snap Store.
- Pin build runners to 26.04 everywhere, including the existing snap
  repos still on ubuntu-latest / ubuntu-24.04-arm.
- Version strings should be stamped from git, not hardcoded.
- Fix the GNOME CI breakage as part of this work (it needs Phase 1).

## Tasks

### Phase 1 - CI for canonical/ubuntu-desktop-a11y (branch desktop/26)

1. Add the arm64 platform to snap/snapcraft.yaml (currently amd64
   only at lines 55-58):
       platforms:
         amd64: {build-on: [amd64], build-for: [amd64]}
         arm64: {build-on: [arm64], build-for: [arm64]}
2. Add .github/workflows/build-snap.yml, mirroring the simplest
   working producer in the family - chris-bainbridge/
   ubuntu-desktop-provision .github/workflows/build-snap.yml on
   desktop/26 (NOT provd-snap's hand-rolled LXD; there is no base
   swap to do here):
       on: pull_request, push: [desktop/26], workflow_dispatch
       permissions: contents: write
       matrix: ubuntu-26.04 / "" and ubuntu-26.04-arm / "-arm64"
       steps:
         - checkout
         - Stamp version (runs on the RUNNER, where git is reliable):
             sed -i "s/^version: .*/version: \"$(date -u +%Y%m%d)+git\$(git rev-parse --short HEAD)\"/" snap/snapcraft.yaml
           (do not commit it back; the yaml in the repo keeps its
           working default for local `snapcraft pack`)
         - uses: snapcore/action-build@v1
           with: {snapcraft-channel: edge}
         - cp "${{ steps.snapcraft.outputs.snap }}" \
              "ubuntu-desktop-a11y${{ matrix.suffix }}.snap"
         - publish (if not pull_request): gh release view
           desktop-26-latest || create; then
           gh release upload desktop-26-latest
             "ubuntu-desktop-a11y${{ matrix.suffix }}.snap" --clobber
         - actions/upload-artifact@v4, retention-days: 14
   NO store upload step. Sideloaded images never refresh, so the
   Store is not involved anywhere in this chain.
3. Optional cleanup in the same PR: the snapcraft.yaml header
   (lines 5-17) still says "THE REPO HAS NO REMOTE TODAY" /
   "OWNER ACTION REQUIRED" about the three URL fields; the repo now
   exists at canonical/ubuntu-desktop-a11y. Needs owner sign-off.
4. Verify: push -> green -> desktop-26-latest carries
   ubuntu-desktop-a11y.snap and ubuntu-desktop-a11y-arm64.snap.

### Phase 2 - Wire a11y into the image workflows (desktop/26)

build-image.yaml:
- amd64 wait loop (repo list, lines 36-55): add
  canonical/ubuntu-desktop-a11y
- amd64 download specs (57-75): add
      canonical/ubuntu-desktop-a11y:ubuntu-desktop-a11y.snap:ubuntu-desktop-a11y.snap
- amd64 build stanza (110-125): add --snap snaps/ubuntu-desktop-a11y.snap
- arm64 asset wait list (225-242): add
  canonical/ubuntu-desktop-a11y:ubuntu-desktop-a11y-arm64.snap
- arm64 download specs (263-281): add the -arm64 variant, saved as
  snaps/ubuntu-desktop-a11y.snap
- arm64 build stanza (305-322): add --snap snaps/ubuntu-desktop-a11y.snap
build.sh: delete the now-false "CI workflow wiring for
ubuntu-desktop-a11y is pending ... until the a11y snap repo
publishes desktop-26-latest" lines (494-496). Keep the rest of the
require_provider_snaps message and the check itself.
Verify: push -> build-image green on both arches.

### Phase 3 - Rolling image releases instead of dated tags

build-image.yaml `image` job:
- tag gnome-latest; asset name ubuntu-core-desktop-gnome.img.zst
  (no YYYYMMDD anywhere)
- gh release view || gh release create --latest
- gh release upload gnome-latest <img> SHA256SUMS --clobber
- gh release edit gnome-latest --title/--notes each run: build
  date, ${{ github.sha }}, run URL, decompress command
- add a small manifest.txt asset (seeded snap file names) so
  "which build is this?" is answerable without keeping images
- delete the same-day delete/recreate block (143-158)
- DELETE the "Expire old dated image releases" step (160-187)
`image-arm64` job: tag gnome-arm64-latest, asset
ubuntu-core-desktop-gnome-arm64.img.zst, --latest=false.
build-image-kde.yaml: tag kde-latest, asset
ubuntu-core-desktop-kde.img.zst[.partNN] (keep the 2GiB split),
--latest=false, delete the expiry step (177-204).
Then, one-off, once *-latest exists (frees ~8.4 GiB):
    gh release delete gnome-20261108 -R canonical/ubuntu-core-desktop --yes --cleanup-tag
    gh release delete kde-20261108 ...
    gh release delete kde-20261120 ...
    gh release delete gnome-arm64-20261108 ...
Docs: README.md:28-40 and docs/kde.md:19-32 - drop the YYYYMMDD
substitution and the "SHA256SUMS may list other release assets" note
(one image + SHA256SUMS + manifest per release now).
Caveat (accept): `gh release upload --clobber` deletes then
re-uploads, so the asset is briefly absent mid-publish. Downloaders
verify SHA256SUMS; the tag itself never disappears, and a FAILED
build leaves the previous image in place (publishing is a later
step).

### Phase 4 - A daily build that actually fires (on main)

Add .github/workflows/daily-image-dispatch.yaml to main:
    on: schedule: [{cron: "0 5 * * *"}], workflow_dispatch
    permissions: {actions: write, contents: read}
    job: resolve the two workflow IDs from
      GET /repos/$GITHUB_REPOSITORY/actions/workflows
      and POST /repos/$GITHUB_REPOSITORY/actions/workflows/<id>/dispatches
      with {"ref":"desktop/26"} for build-image and build-image-kde.
    Resolve by ID, not filename: build-image-kde.yaml does not exist
    on main, so a path/name lookup is not reliable.
NO PAT NEEDED: GITHUB_TOKEN-triggered events do not start runs EXCEPT
workflow_dispatch and repository_dispatch, which always do (GitHub
docs, "When GITHUB_TOKEN triggers workflow runs"). The repo has zero
Actions secrets today, keep it that way.
Then remove the inert `on: schedule` blocks from both desktop/26
workflows and leave a one-line comment pointing at the dispatcher.
Verify: trigger the dispatcher by hand once (workflow_dispatch on
itself), confirm two runs appear on desktop/26; then confirm the
05:00 UTC schedule.

### Phase 5 - Pin every build runner to 26.04 (15 repos, 15 files)

ubuntu-latest is 24.04 TODAY (actions/runner-images README: "Ubuntu
24.04 | x64 | ubuntu-latest or ubuntu-24.04"; confirmed in a real
job log: "Image: ubuntu-24.04", release ubuntu24/20261025.353). The
only Ubuntu labels are 22.04/24.04/26.04 (+ -arm variants); there is
no 26.10 or 27.10 image. `-latest` will migrate to 26.04 eventually,
with announcements - pin so that is a decision, not a surprise.

Change ubuntu-latest -> ubuntu-26.04 and ubuntu-24.04-arm ->
ubuntu-26.04-arm in the SNAP-PRODUCING workflow of each repo only
(leave spread matrices and other workflows alone):

    canonical/pc-amd64-gadget-desktop      .github/workflows/build-snap.yml
    canonical/pipewire-snap                .github/workflows/build-snap.yml
    canonical/provd-snap                   .github/workflows/build-snap.yml
    canonical/accountsservice-snap         .github/workflows/build-snap.yml
    canonical/fprintd-snap                 .github/workflows/build-snap.yml
    canonical/boltd-snap                   .github/workflows/build-snap.yml
    canonical/geoclue-snap                 .github/workflows/build-snap.yml
    canonical/ubuntu-desktop-session-snap  .github/workflows/build-snap.yml
    canonical/gnome-desktop-runtime        .github/workflows/build-snap.yml
    canonical/ubuntu-core-desktop-snapd    .github/workflows/build-snap-desktop26.yml
    canonical/core-base-desktop            .github/workflows/build-snap-variant.yml
    chris-bainbridge/ubuntu-desktop-provision .github/workflows/build-snap.yml (branch desktop/26)
    chris-bainbridge/kf6-core26            .github/workflows/build-snap.yml (amd64 only)
    chris-bainbridge/plasma-core-desktop   .github/workflows/build-snap.yml (amd64 only)
    chris-bainbridge/plasma-desktop-session .github/workflows/build-snap.yml (amd64 only)
plus canonical/ubuntu-desktop-a11y from Phase 1 (already 26.04).

Stage it: chris-bainbridge/ubuntu-desktop-provision FIRST, then one
canonical repo (provd-snap), then the rest. It builds a Flutter app
natively on the arm64 runner and Flutter's supported-host matrix is
conservative; a bad pin there is not a mechanical edit. A mass
rollout that breaks matters more than usual because build-image.yaml
waits 30 min (50 min for arm64) for these assets and then fails - a
broken snap repo takes the images down with it.

Also in Phase 5: fix gnome-desktop-runtime's hardcoded
`version: "0.1"` (same defect as a11y). Stamp
`$(date +%Y%m%d)+git<short-sha>` at pack time (host-side sed, or the
`.craft-version` trick the session snap uses).

## Facts established (do not re-derive)

- All 12 existing snap inputs are public, pushed, and publish a
  rolling desktop-26-latest release with amd64 AND arm64 assets
  (core-base-desktop uses desktop-26-thin-latest). Only
  ubuntu-desktop-a11y was missing.
- The arm64 ubuntu-desktop-init snap IS CI-built: chris-bainbridge/
  ubuntu-desktop-provision .github/workflows/build-snap.yml on
  branch desktop/26 (matrix ubuntu-latest + ubuntu-24.04-arm,
  snapcore/action-build, publishes desktop-26-latest). Last green
  2026-11-08 21:36Z. It is invisible from the default branch main,
  where that workflow does not exist - this is why an earlier pass
  wrongly concluded the arm64 asset was hand-uploaded.
- Version semantics: `version:` lands in meta/snap.yaml and in the
  packed file name (<name>_<version>_<arch>.snap). It is NOT
  load-bearing for our images: we download a fixed asset name, never
  publish to the store, and sideloaded snaps never refresh. It is
  pure provenance - which is exactly why a hardcoded/stale one is
  worth fixing (`snap list` in a booted image is the only way to
  tell which a11y build you are running).
- House conventions differ: deb-wrapping providers (provd,
  accountsservice, fprintd, bolt, geoclue) use the upstream deb
  version; ubuntu-desktop-session and plasma-desktop-session use
  $(date +%Y%m%d)+git<sha>; kf6-core26 and plasma-core-desktop use
  $(date +%Y%m%d)-deb; gnome-desktop-runtime and a11y were
  hardcoded. Source-built snaps (a11y) belong in the date+git group.
- Inside an LXD build instance `git rev-parse` is unreliable (a
  worktree's .git file points at an absolute host path); the session
  snap falls back to .craft-version. Stamping on the runner/host
  avoids the problem entirely - that is why the sed happens in a
  workflow step or in build-github.sh, never in override-build.
- Size maths: gnome 2.01 GB, kde 2.66 GB (2 parts), arm64 1.78 GB
  per day => ~6.4 GiB/day, ~90 GiB at the 14-day expiry.

## Acceptance

- canonical/ubuntu-desktop-a11y: desktop-26-latest has both assets.
- build-image + build-image-kde green on a desktop/26 push, and the
  releases are gnome-latest / kde-latest / gnome-arm64-latest with
  stable asset names; no gnome-YYYYMMDD/kde-YYYYMMDD tags remain.
- The releases page "Latest" badge is gnome-latest.
- A scheduled run at 05:00 UTC creates runs on desktop/26 without
  any manual push.
- All 15 existing snap-producer workflows, plus the new a11y one,
  run on ubuntu-26.04 / ubuntu-26.04-arm (KDE repos: amd64 only).

## Resolution (2026-11-21)

DONE, all phases. Commits: canonical/ubuntu-core-desktop ea1c7fc
(desktop/26, a11y wiring + rolling releases + docs), 5d4e827 (main,
daily dispatcher); canonical/ubuntu-desktop-a11y 49dd1ac (CI +
arm64 platform + version stamp).

State now: the releases are gnome-latest / kde-latest /
gnome-arm64-latest (gnome-latest carries the Latest badge), each
with a fixed asset name, SHA256SUMS and a manifest.txt naming the
source commit, run URL and every seeded snap version. The four
dated releases/tags are deleted (~8.4 GiB). The daily build is
dispatched from main at 05:00 UTC (verified by hand: daily-image
#44842595310 dispatched both workflows on desktop/26). All 15
snap producers have been rebuilt on the new runners and republished
their desktop-26-latest assets.

Three things that were NOT in the plan and matter:

1. ubuntu-desktop-a11y was the only image input with no CI at all.
   It now builds amd64+arm64 on 26.04/26.04-arm, stamps
   date+git<sha> from the runner, and publishes
   ubuntu-desktop-a11y.snap / -arm64.snap to desktop-26-latest.
   Never uploaded to the store, as instructed.

2. core-base-desktop's build-snap-variant.yml had an unterminated
   quote in its publish step ("...default switched.)""), so the step
   died before running ANYTHING: every push build had failed since
   2026-11-09 and desktop-26-thin-latest was frozen at the
   2026-11-08 base snap for 12 days. Pull-request runs passed
   because publishing is skipped for pull_request, so CI looked
   green while the image consumed a stale base. Fixed (79cf06b); the
   base is now 20261121+desktop. This is the same failure mode as
   the stale image: nothing marks an artifact as old.

3. sudo on the 26.04 runner image ignores -E ("preserving the entire
   environment is not supported, '-E' is ignored"). provd-snap and
   accountsservice-snap were passing SUFFIX through `sudo -E`, so
   their arm64 leg built the snap and then published provd.snap /
   accountsservice.snap under the wrong name; the upload step failed
   looking for the -arm64 asset. Both now derive the suffix from the
   packed file name. Any future workflow that relies on `sudo -E`
   preserving step env is broken on 26.04 - pass env explicitly or
   derive it.

Runner pinning: all of them on 26.04/26.04-arm. The three KDE snaps
(kf6-core26, plasma-core-desktop, plasma-desktop-session) were
briefly parked on 24.04 on 2026-11-21 while the KDE neon archive was
intermittently unreachable from GitHub runners ("Failed to refresh
package list: failed to run apt update", or a single failed
origin.archive.neon.kde.org fetch). That outage was transient and
NOT runner-specific (24.04 and 26.04 failed and then recovered
together; the archive's Release was current and its InRelease
verified from this host throughout), so they were moved back to
26.04 the same day. They keep the retry loop, because they are the
projects that install build-packages inside snapcraft's LXD instance
and therefore force that apt refresh.

Also noticed: actions/checkout@v4, actions/upload-artifact@v4 and
snapcore/action-build@v1 all target Node 20, which the runners now
force onto Node 24 (a deprecation annotation on every run). DONE:
checkout -> v5 and upload-artifact -> v6 in all 16 workflows (the
first majors that declare node24; v5 of upload-artifact is still
node20). snapcore/action-build cannot be bumped - v1.3.0, its newest
tag, still declares node20 - so that annotation stays until the
action is replaced by its ~3 inline steps (install LXD, install
snapcraft, snapcraft pack) or upstream updates it.
