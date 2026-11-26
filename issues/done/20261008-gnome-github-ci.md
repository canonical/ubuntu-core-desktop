# GitHub CI to build and publish the GNOME daily VM image

## Impact / Priority

There was no automated build or public download of the current GNOME VM
image: the old cdimage edge dailies had been broken since January, and
nothing in the repo built or published a bootable image, so nobody
outside the build machine could try the desktop. Impact derived from
the original note's described symptoms.

GitHub CI for all of the snaps built by the GNOME image build: the aim
is that GitHub CI should be building a usable VM drive image (the final
output) and publishing it on GitHub for people to download and try.

In each of these directories there is a current branch desktop/26:

- core-base-desktop
- gnome-desktop-runtime
- pc-amd64-gadget-desktop
- pipewire-snap
- ubuntu-core-desktop-snapd
- ubuntu-desktop-session-snap

For each of these repo dirs, first check that desktop/26 contains all
the commits from the `dev` branch. If not, stop and report what hasn't
been merged from `dev`.

Once that is confirmed for each desktop/26 branch, set up GitHub CI to
build each snap.

Previously this was done with a workflow, something like:

    name: build-snap
    on:
      pull_request:
      push:
        branches:
          - main
          - 22
          - 24

    jobs:
      snap:
        runs-on: ubuntu-latest
        steps:
        - uses: actions/checkout@v4
        - uses: snapcore/action-build@v1
          id: snapcraft
          with:
	    snapcraft-channel: edge
        - uses: actions/upload-artifact@v4
          with:
            name: 'snap'
            path: ${{ steps.snapcraft.outputs.snap}}

Something like that is needed to build the desktop/26 branch of each
repo into a snap.

Things to consider:

1. Do not use or change any of the local build scripts. These are
   intended as local-only scripts for building on this machine. If
   extra scripts are needed, call them something informative like
   build-github.sh.

2. The ubuntu-image model for this is "dangerous" - This is fine for now
   as we're just distributing a preview image to developers.

3. The ubuntu-desktop-provision origin is actually the owner's fork.
   This is fine for now. Do not try to push to upstream.

4. Do not push any of the snaps to the store for now. Use whatever
   staging area facility GitHub provides for storing build artifacts
   like this.

5. The aim is to have a "daily VM" image published at a URL like:
   https://cdimage.ubuntu.com/ubuntu-core-desktop/26/dangerous/20261008/

   (for a similar setup used by a different project, see
   https://cdimage.ubuntu.com/ubuntu-core/26/dangerous-stable/)

   This was done in the past by this build system, so the permissions
   should be all set up, but there is no record of how it worked. The
   old (broken) builds are at
   https://cdimage.ubuntu.com/ubuntu-core-desktop/26/
   In particular, the 26/edge builds at
   https://cdimage.ubuntu.com/ubuntu-core-desktop/26/edge/ should be
   removed, as they no longer work and haven't been built since
   January.

   Call the daily build something like
   ubuntu-core-desktop-gnome-20261009.img.zst

   There should also be a corresponding SHA256SUMS file

6. The VM built by ubuntu-core-desktop should be compressed for
   publishing with zstd like:

    zstd -T0 -19 pc.img -o
    ubuntu-core-desktop-gnome.img.zst

## State of the system (verified 2026-10-09)

Branch gate (the "stop and report" check) PASSES for all six repos:
`dev` is an ancestor of `desktop/26` in every repo - in fact dev ==
desktop/26 exactly (0 commits either direction), and both are in sync
with origin/desktop/26. All dirty files in these repos are untracked
build artifacts/editor backups, nothing that needs committing for this
task. Push access confirmed: chris-bainbridge has push to every
canonical/* repo involved, and admin on the ubuntu-desktop-provision
fork. The ONLY branch not on GitHub yet is ubuntu-desktop-provision's
local `desktop/26` (origin there is chris-bainbridge's fork).

Per-repo build shapes on desktop/26 (what CI must replicate; local
build scripts stay untouched per item 1):

- pc-amd64-gadget-desktop: snapcraft.yaml at root, plain
  `snapcraft pack` -> pc-desktop_*.snap. Trivial.
- gnome-desktop-runtime: snap/snapcraft.yaml, plain `snapcraft pack`.
- pipewire-snap: snap/snapcraft.yaml, plain `snapcraft pack`.
- ubuntu-desktop-session-snap: snap/snapcraft.yaml, plain pack. Already
  has .github/workflows/build-snap.yml but it only triggers on
  main/22/24 - extend it with desktop/26.
- ubuntu-core-desktop-snapd: snapcraft.yaml at build-aux/snap/; plain
  `snapcraft pack` at the repo root finds it (upstream canonical/snapd
  CI builds it with plain snapcore/action-build, no args - proven
  path). Output snapd_*.snap. Repo is full of upstream workflows - add
  a NEW separate file, touch nothing existing.
- core-base-desktop: TWO extra steps beyond plain snapcraft:
  1. `SNAP_BUILD_VARIANT=cloud-init` must be written to a `build-env`
     file at the repo root BEFORE `snapcraft pack` (the build-env
     part's override-pull reads it; without it cloud-init is silently
     omitted from chisel slices and any downstream image that relies on
     cloud-init breaks).
  2. Post-build repack renaming the snap core26 -> core26-desktop in
     meta/snap.yaml (build.sh expects the base snap named
     core26-desktop). Exact working recipe: fakeroot -- unsquashfs -d
     squashfs-root -f X.snap; sed -i 's/^name: core26$/name:
     core26-desktop/' squashfs-root/meta/snap.yaml; mksquashfs
     squashfs-root out.snap -noappend -comp xz -no-fragments
     -no-progress -xattrs
- ubuntu-desktop-provision (fork, desktop/26): snap/snapcraft.yaml,
  name ubuntu-desktop-init. The two sed hacks previously used in local
  builds (source-commit pin to 6623407 and `cd packages/ubuntu_init` ->
  `cd apps/ubuntu_init`) are now NO-OPS - desktop/26 already has
  exactly those values committed. So CI = plain `snapcraft pack` +
  `mv ubuntu-desktop-*.snap ubuntu-desktop-init.snap`.

Image build inputs (from build.sh --help; build.sh is tracked on
desktop/26 of canonical/ubuntu-core-desktop):

- build.sh signs the model JSON itself with
  `snap sign -k "${SNAP_SIGN_KEY:-test}"` (build.sh:857) and needs
  --model-account-key <assertion> for the same key (public data; fetch
  once locally via `snap known --remote account-key
  public-key-sha3-384=<sign-key-sha3-384 from the model json>`).
- USER DECISION (2026-10-09): do NOT pass --user or --autologin. The
  published image ships with no pre-created login account and no
  seed.iso; the user sets up their account via the ubuntu-desktop-init
  first-boot wizard (ubuntu-desktop-provision snap, passed as --snap).
  build.sh will drop build/pc.img.nouser in this mode - that is the
  wanted behaviour. Keep --password (root's password, still required,
  bake from a repo secret).
- The seven locally built snaps: pc-desktop (gadget), core26-desktop
  (base), snapd, ubuntu-desktop-session, gnome-desktop-runtime,
  pipewire, ubuntu-desktop-init. Everything else in the model comes
  from the store via ubuntu-image --validation=ignore (dangerous grade,
  fine for a developer preview).

Publishing facts:

- There is NO cdimage machinery anywhere in ubuntu-core-desktop git
  history. The old build-image.yaml (and its 2025-era predecessor,
  commit ff8218b) only ever uploaded GitHub artifacts; the old Makefile
  did `ubuntu-image` + `tar czSf`. So the cdimage.ubuntu.com publishing
  came from outside this repo (owner says they don't remember how) -
  treat cdimage as needing owner input; GitHub Releases is the
  practical publishing target, with naming/compression already made
  cdimage-compatible (ubuntu-core-desktop-gnome-YYYYMMDD.img.zst +
  SHA256SUMS, zstd -T0 -19).

### Step 1: push the fork branch

`git push origin desktop/26` in ~/git/ubuntu-desktop-provision (fork
only; never upstream). Everything else is already pushed.

### Step 2: per-snap workflows (the six listed repos)

Add a new workflow `.github/workflows/build-snap.yml`
(ubuntu-desktop-session-snap: extend the existing build-snap.yml
instead) committed to desktop/26 in each repo:

    name: build-snap
    on:
      pull_request:
      push:
        branches:
          - desktop/26
      workflow_dispatch:
      schedule:
        - cron: "0 4 * * *"
    jobs:
      snap:
        runs-on: ubuntu-latest
        steps:
        - uses: actions/checkout@v4
        - uses: snapcore/action-build@v1
          id: snapcraft
          with:
            snapcraft-channel: edge
        - uses: actions/upload-artifact@v4
          with:
            name: snap
            path: ${{ steps.snapcraft.outputs.snap }}
            compression-level: 0
            retention-days: 14

Repo-specific variations:

- core-base-desktop: action-build alone is NOT enough. Commit a new
  `build-github.sh` (name chosen per item 1; local build scripts
  untouched) that does: write build-env (SNAP_BUILD_VARIANT=cloud-init)
  -> `snapcraft pack` -> the fakeroot unsquashfs/sed/mksquashfs
  core26->core26-desktop repack. Workflow: checkout, `sudo apt install
  fakeroot squashfs-tools`, run build-github.sh, upload artifact
  core26-desktop.snap. Leave the repo's existing workflows
  (release/tests/lxd-image) untouched.
- ubuntu-core-desktop-snapd: new separate file (e.g.
  build-snap-desktop26.yml) so nothing upstream collides; may pin
  snapcraft-channel: 8.x/stable like upstream's snap-builds.yaml if
  edge misbehaves (build-base: core22, so 8.x works there).
- snapcraft-channel: edge (snapcraft 9.x) is needed for the core26
  base/build-base repos (session, pipewire, gnome-desktop-runtime,
  gadget, core-base-desktop). If a specific repo fails on edge, pin
  that one repo individually.
- GitHub runners have LXD preinstalled and action-build works on
  ubuntu-latest for all these shapes; core-base-desktop and
  gnome-desktop-runtime are the heavy ones (chisel+apt downloads, no
  ccache on CI) - expect ~15-40 min each, still well inside limits. If
  a runner runs out of disk, add a standard cleanup step (rm -rf
  /usr/share/dotnet /opt/ghc etc.) before building.

Do the easy repos first (gadget, pipewire, gnome-desktop-runtime,
session-snap, snapd), verify each run goes green, then core-base-
desktop. Verify each artifact by downloading and checking
`unsquashfs -l` / meta/snap.yaml: base snap's name must be
core26-desktop; snapd's version must not contain "dirty".

### Step 3: image build workflow (canonical/ubuntu-core-desktop, desktop/26)

Replace the stub .github/workflows/build-image.yaml (keep the name)
with a real self-contained pipeline (builds the seven snaps itself
rather than downloading cross-repo artifacts - cross-repo artifact auth
via GITHUB_TOKEN doesn't work and a PAT secret is worse):

- Job `snaps`: a matrix (7 entries) that checks out each component repo
  at desktop/26 (six canonical repos + chris-bainbridge/
  ubuntu-desktop-provision) and builds with exactly the Step-2 recipes
  (action-build, or core-base-desktop's build-github.sh). Upload one
  artifact per snap.
- Job `image` (needs: snaps):
  1. checkout ubuntu-core-desktop@desktop/26; download the 7 artifacts.
  2. apt install squashfs-tools dosfstools mtools fakeroot crudini
     zstd; snap install --classic ubuntu-image.
  3. Import the model signing key from a repo secret
     (GPG_SIGN_KEY_TEST = armored private key of the local `test`
     snap-signing key - it is a test-only key for dangerous models;
     note the key must have a blank passphrase so `snap sign` never
     prompts). One-time local export: `gpg --armor --export-secret-keys
     <test-key-fpr>`; the matching account-key assertion is PUBLIC -
     commit it as a repo file (e.g. ci/account-key.assert) fetched once
     via `snap known --remote`.
  4. ssh host key: generate fresh on the runner
     (`ssh-keygen -t ed25519 -N '' -f dev/ssh_host_ed25519_key`) - CI
     images don't need a stable host identity.
  5. Run:

       SNAP_SIGN_KEY=test ./build.sh \
         --desktop gnome \
         --password "$IMAGE_PASSWORD" \
         --model-account-key ci/account-key.assert \
         --base-snap core26-desktop.snap \
         --gadget-snap pc-desktop.snap \
         --snapd-snap snapd.snap \
         --snap ubuntu-desktop-session.snap \
         --snap ubuntu-desktop-init.snap \
         --snap gnome-desktop-runtime_*.snap \
         --snap pipewire.snap

     Deliberately NO --user / NO --autologin (see user decision above):
     published images land on the ubuntu-desktop-init first-boot
     wizard. IMAGE_PASSWORD is a repo secret (root's password only).
  6. `zstd -T0 -19 build/pc.img -o
     ubuntu-core-desktop-gnome-$(date +%Y%m%d).img.zst`; `sha256sum
     ... > SHA256SUMS`.
  7. Upload artifact (retention 14d) AND publish: a rolling
     `gnome-daily` GitHub Release (contents: write permission) whose
     assets are the dated .img.zst + SHA256SUMS, re-uploaded each run
     (delete-then-reupload the asset). That gives a stable public URL
     plus dated filenames, without needing cdimage.

No KVM on standard ubuntu-latest runners, so CI cannot boot-test the
image. Instead, once the first CI build is green: pull the artifact,
boot it locally under QEMU (the local QEMU run setup pointed at the CI
image, no seed.iso attached), and confirm the first-boot wizard runs
and a desktop comes up after account creation - the real end-to-end
"usable VM" proof, per the project principles. Only then enable the
daily schedule cron.

### Step 4: cdimage (blocked on owner input)

- No in-repo mechanism exists (verified). Ask the owner: do they have
  (or remember) any cdimage upload path (host/script/credentials)? If
  yes, append a small rsync/scp step to the image job; if no, the
  GitHub `gnome-daily` Release URL is the published location and we
  flag cdimage as manual follow-up.
- Removing https://cdimage.ubuntu.com/ubuntu-core-desktop/26/edge/
  requires cdimage-side admin access - cannot be done from GitHub CI;
  raise with the owner / Canonical cdimage admins as a separate
  request.

## Execution order

1. Step 1 (push fork branch) - unblocks everything else.
2. Step 2 easy repos, verify green runs.
3. core-base-desktop build-github.sh + workflow, verify (incl. the
   core26-desktop rename check).
4. Step 3 secrets + image workflow; first build; local end-to-end boot
   test of the CI image through the first-boot wizard.
5. Enable schedule cron; ask owner the cdimage questions.

Open questions for the owner:

- OK to store the `test` snap-signing GPG private key as a
  canonical/ubuntu-core-desktop repo secret? (Alternative: generate a
  fresh CI-only key and self-build the account-key assertion chain -
  doable but fiddlier.)
- Rolling `gnome-daily` release vs dated tags per build?
- Any recollection of the old cdimage upload path?

## Resolution (2026-10-10)

DONE. Per-repo build-snap CI is live on desktop/26 in all six
canonical/* repos, each publishing a rolling "desktop-26-latest" GitHub
release (first green runs 2026-10-09/10); canonical/ubuntu-core-
desktop's build-image.yaml consumes those release assets and publishes
dated gnome-YYYYMMDD releases (first gnome-20261010; gnome-20261103
green as of 2026-11-03) - i.e. the stated aim ("GitHub CI builds a
usable VM image and publishes it for download") is met. Deviations from
the plan as written: Step 3's self-contained 7-snap matrix was
superseded the next day by the per-repo-release-assets design
(2026-10-09 owner decision, see
`20261009-build-and-publish-gnome-dangerous.md`); model signing uses a
pre-signed committed .model + ci/account-key.assert rather than the
GPG_SIGN_KEY_TEST secret; publishing uses dated tags (expiring after 14
days, f561e5c) instead of a rolling gnome-daily release.
cdimage.ubuntu.com publishing and removal of the dead 26/edge tree
remain blocked on cdimage-admin access and were explicitly deferred -
GitHub Releases is the publishing target.
