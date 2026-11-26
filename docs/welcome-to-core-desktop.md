# Welcome to Ubuntu Core Desktop!

This is the quick-start guide for building and running your own Ubuntu
Core 26 desktop image (GNOME or KDE). You don't need to build any snaps
to get started: the image is assembled from prebuilt component snaps that
each repository's CI publishes. Clone a component's source only when you
want to change it.

Everything below works from a clean checkout — nothing here depends on
anyone else's machine or local setup.

---

### How it fits together

The image is built from about sixteen independent snaps (base, gadget,
snapd, the desktop session, runtimes, and — on GNOME — the provider
daemons). Each is built and published by its own repository, and
`ubuntu-core-desktop` assembles them into a disk image.

There are two directories you'll meet:

- `snaps/` — a local cache of those published snaps, downloaded
  automatically. Gitignored.
- `local-sources/` — where you clone the source of a component you want
  to modify. Anything cloned there is built instead of downloaded.
  Everything else keeps coming from the cache. Also gitignored.

You only need to think about the second one when you're changing a
component.

---

### Step 0: Install the build tools

```
sudo snap install lxd
sudo snap install ubuntu-image --classic
sudo apt update
sudo apt install git squashfs-tools dosfstools mtools fakeroot crudini \
  zstd qemu-system-x86 ovmf
```

You also need `snapcraft` if you plan to build component snaps from
source (it defaults to building in an LXD container, which is how CI
does it):

```
sudo snap install snapcraft --classic --channel=9.x/stable
lxc info     # LXD must be initialised for your user
```

You do **not** need a model signing key. The repository ships a
pre-signed development model and its account-key assertion under `ci/`.

---

### Step 1: Get an image

```
git clone https://github.com/canonical/ubuntu-core-desktop -b desktop/26
cd ubuntu-core-desktop

# GNOME
./build.sh --desktop gnome \
  --model-account-key ci/account-key.assert \
  --model ci/ubuntu-core-desktop-26-amd64-dangerous.model

# or KDE
./build.sh --desktop kde \
  --model-account-key ci/account-key.assert \
  --model ci/ubuntu-core-desktop-kde-26-amd64-dangerous.model
```

That's the whole build. `build.sh` downloads whichever component snaps
are missing from the components' rolling `desktop-26-latest` GitHub
releases (a few hundred MB, once) and fills in every snap argument for
you. The result is `build/pc.img`.

To refresh the cached snaps later (the releases are rolling, so nothing
updates on its own):

```
./build-snaps.sh sync
```

`sync` compares each asset's sha256 against what you have and only
downloads what actually changed, so it's cheap enough to run regularly.

---

### Step 2: Run it

```
cp /usr/share/OVMF/OVMF_VARS_4M.fd build/OVMF_VARS.fd

qemu-system-x86_64 \
  -machine accel=kvm -cpu host -smp 2 -m 4096 \
  -display gtk,gl=on \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,unit=1,file=build/OVMF_VARS.fd \
  -drive file=build/pc.img,format=raw,if=virtio,cache=none \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

Firmware paths vary by distribution — find your matching OVMF code/vars
pair if the `_4M` files don't exist. Without KVM, replace
`-machine accel=kvm -cpu host` with `-machine accel=tcg` (much slower).

Allow the first boot to finish; the system may restart once while it
seeds. Then:

- **GNOME**: the `ubuntu-desktop-init` wizard appears — pick your
  language, create your account, and you land in the desktop.
- **KDE**: SDDM appears and runs the `plasma-setup` wizard from the login
  screen; create your account and it logs you in.

No credentials are baked into the image, which is why first boot always
asks you to create an account.

---

### Step 3: Change something

Say you want to hack on AccountsService (GNOME) or the Plasma session
(KDE). Clone just that component:

```
cd local-sources
git clone https://github.com/canonical/accountsservice-snap
# or: git clone https://github.com/chris-bainbridge/plasma-desktop-session
```

Run `./build.sh` again with the same arguments. That component is now
built from your clone, everything else still comes from the cache, and
the image picks up your change.

One catch: the clone must be on the branch CI builds that component from
— `desktop/26` for most components, `main` for the five provider snaps
(accountsservice, provd, fprintd, boltd, geoclue). The default branch is
right everywhere except `ubuntu-desktop-provision`, whose default is
`main` while CI builds `desktop/26`:

```
git clone -b desktop/26 https://github.com/chris-bainbridge/ubuntu-desktop-provision
```

`./build-snap.sh` warns if the checkout doesn't match the branch CI uses.

Builds are incremental in the only sense that matters: a component is
rebuilt only when its tree changed since the last build (new commits,
edited files, or new untracked files). Rerunning with no changes does
nothing, so you can leave the clone there and iterate.

```
./build-snap.sh --list                     # components you can override
./build-snap.sh accountsservice-snap       # build just that one (no-op if unchanged)
./build-snap.sh accountsservice-snap --force
```

Every component build ends with `snapcraft clean`, so no half-built LXD
instance is left behind. To go back to the published snap, delete the
directory from `local-sources/`.

---

### What each component is

Shared by both images:

- `core-base-desktop` — the `core26-desktop` **desktop-variant** base
  snap. Build with `./tools/build-variant.sh desktop`, not a plain
  `snapcraft pack`, which produces a base with no desktop payload that
  boots to a system with no display manager.
- `pc-amd64-gadget-desktop` — the gadget snap (partition layout, boot
  config, interface connections).
- `ubuntu-core-desktop-snapd` — a snapd branch carrying desktop-specific
  changes that aren't upstream yet.
- `ubuntu-desktop-provision` — the first-boot wizard snap
  (`ubuntu-desktop-init`, and the backend KDE's `plasma-setup` uses). A
  `chris-bainbridge` fork for now.

GNOME only:

- `ubuntu-desktop-session-snap` — the confined GNOME session.
- `gnome-desktop-runtime` — GNOME content, exposed to the session
  through the content interface.
- `pipewire-snap` — audio server (PipeWire, WirePlumber, pipewire-pulse).
- `accountsservice-snap`, `provd-snap`, `fprintd-snap`, `boltd-snap`,
  `geoclue-snap` — the provider daemons (user accounts, the wizard
  backend, fingerprint, Thunderbolt, geolocation). These declare
  `base: core26-desktop`, which snapcraft's schema rejects, so they build
  with `./build-github.sh`, not a plain `snapcraft pack`.
- `ubuntu-desktop-a11y` — the accessibility bus, Orca and
  speech-dispatcher.

KDE only:

- `plasma-desktop-session` — the confined Plasma session and SDDM.
- `plasma-core-desktop` — Plasma runtime content and theme assets
  (also built with `./build-github.sh`).
- `kf6-core26` — Qt 6 / KDE Frameworks runtime, staged from KDE Neon
  packages. Has its own `./build.sh`.

`udisks2` and `upower` are store snaps resolved by the model; there is
nothing to build for them.

---

### Good to know

- **CI validates what it publishes.** Before publishing, the amd64 image
  jobs build a throwaway image with a test account, boot it headless and
  require the desktop session to come up. If the snap set is broken (for
  example a Qt version bump in `kf6-core26` that the Plasma snaps weren't
  rebuilt against), the publish is blocked instead of shipping an image
  that won't boot. (The arm64 job is not gated yet - no KVM on the arm64
  runners.)
- **Building a component downloads gigabytes.** If you are building snaps
  rather than using the cache, install `pkgproxy` first and point apt,
  snapd and LXD at it (`pkgproxy.pkgproxyctl setup apt|snap|lxd`); see
  "Cache Build Dependencies" in `docs/building.md`.
- **The snaps are rolling.** `desktop-26-latest` in each component repo
  is replaced on every green CI run, so a build is reproducible only
  until you run `./build-snaps.sh sync`.
- **Details live in the repo**: `docs/building.md` (both desktops, all
  build modes), `docs/building-kde.md` (KDE specifics), `docs/models.md` (model
  assertions), `CONTRIBUTING.md` (how to propose a change), and
  `./build.sh --help` for every flag.
- **Images are development previews.** They use a dangerous-grade model
  and unasserted snaps: no Snap Store refreshes, not for production.

If a build fails, check the component repo's `.github/workflows/` — CI
runs the same commands described here, so a red CI run is a good signal
that the problem is upstream rather than in your setup.

---

This document is maintained in the repository at
`docs/welcome-to-core-desktop.md` and copied into Mattermost when a
fresh copy is needed — fix it here rather than pasting edits into chat.
