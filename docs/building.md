# Building Ubuntu Core Desktop from Source

This guide covers the **GNOME and KDE images**: preparing the development
host, assembling an Ubuntu Core 26 image from component snaps, and testing
it in QEMU. For the contribution process, see
[CONTRIBUTING.md](../CONTRIBUTING.md); to try a prebuilt image, see the
[README](../README.md); for KDE-specific details see
[docs/building-kde.md](building-kde.md).

> **Development preview:** This procedure uses a **dangerous** model and
> unasserted snaps. Images are for development only, not production or
> security-sensitive use, and cannot receive normal Snap Store refreshes.

There are two ways to get an image:

- **Assemble from cached snaps (default).** `build.sh` downloads the
  component snaps published by each repository's CI into a local `snaps/`
  cache and assembles them. You get a working image in minutes without
  building anything.
- **Build a component from source.** Clone the one component you are
  changing into `local-sources/`; `build.sh` builds that snap and keeps
  using the cache for everything else.

The two modes compose: any subset of components can come from source, and
the rest from the cache, with no flags to pass.

Two directories matter: `snaps/` is a local cache of the published snaps,
downloaded automatically (gitignored); `local-sources/` is where you clone
the source of a component you want to modify — anything cloned there is
built instead of downloaded, and everything else keeps coming from the
cache (also gitignored). You only need to think about the second one when
changing a component.

## Build Environment

Use an **Ubuntu amd64 host** with a reliable internet connection, **at
least 30 GiB of free disk space** (more if you build components), and
preferably **8 GiB or more RAM**.

The standard workflow uses the committed development model and account-key
assertion. You do **not** need to configure a package cache or create your
own signing key.

Install the image-building and VM tools:

```bash
sudo snap install lxd
sudo snap install snapcraft --classic --channel=9.x/stable
sudo snap install ubuntu-image --classic
sudo apt update
sudo apt install git squashfs-tools dosfstools mtools fakeroot crudini zstd qemu-system-x86 ovmf
```

Initialize LXD for your user if it has not been initialized already, then
check that both tools are usable:

```bash
lxc info
snapcraft --version
```

`snapcraft pack` builds in an LXD container by default, which is how both
CI and `build-snap.sh` build. Use Snapcraft 9.x: the current `desktop/26`
sources were validated with 9.1.4. The snapd recipe still recommends 8.x,
so if a source revision fails with a Snapcraft compatibility error, retry
with `sudo snap install snapcraft --classic --channel=8.x/stable` and
report the mismatch.

## Quick Start: Assemble from Cached Snaps

```bash
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop.git
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

The image is written to `build/pc.img`.

`--desktop`, `--model-account-key` and `--model` are the only arguments
you need. `build.sh` calls [`build-snaps.sh`](../build-snaps.sh), which
downloads whatever is missing from the components' `desktop-26-latest`
GitHub releases, then fills in every snap argument you did not pass
(`--base-snap`, `--gadget-snap`, `--snapd-snap`, the `--snap` set, and the
KDE session/plasma snaps).

### Keeping the cache current

Nothing refreshes the cache on its own: the releases are rolling, so a
build stays reproducible until you ask for newer snaps.

```bash
./build-snaps.sh sync            # GNOME and KDE components
./build-snaps.sh sync --desktop gnome
./build-snaps.sh sync --force    # re-download everything
```

`sync` asks the GitHub API for each asset's sha256 digest and downloads
only the ones that actually moved, so it is cheap enough to run routinely.
Downloads are recorded in `snaps/.build-state/releases`, along with the
git state that produced each locally built snap.

## Work on One Component

Clone just the component you care about into `local-sources/`:

```bash
cd local-sources
git clone https://github.com/canonical/accountsservice-snap
```

The checkout must be the branch CI builds that component from: `desktop/26`
for most components, `main` for the five provider snaps (accountsservice,
provd, fprintd, boltd, geoclue). The default branch is right for all of
them except `ubuntu-desktop-provision`, whose default is `main` while CI
builds `desktop/26`; `build-snap.sh` warns when the checkout differs from
the branch CI uses.

Then run `./build.sh` exactly as above. That component is built from your
clone with [`build-snap.sh`](../build-snap.sh) while everything else still
comes from the cache. A build happens only when the tree changed — HEAD,
the diff against HEAD, or the contents of untracked files — so rerunning
is cheap:

```bash
./build-snap.sh --list                    # components you can override
./build-snap.sh accountsservice-snap      # build it now, or no-op if unchanged
./build-snap.sh accountsservice-snap --force
```

Every build ends with `snapcraft clean`, whether it succeeded or failed,
so no half-built LXD instance is left behind. To stop using your clone,
delete it from `local-sources/` and the cache takes over again.

Cache and override directories are gitignored, so neither shows up in
`git status`.

## Build Every Component from Source

This is the long way round: useful when changing several components at
once, or when debugging a build. It is what the snap repositories' own CI
does.

### Clone the Repositories

Keep the snap sources and this assembly repository in a common parent
directory:

```bash
mkdir -p ~/ucd-build
cd ~/ucd-build

git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop.git

# Shared by both desktops
git clone --branch desktop/26 --single-branch https://github.com/canonical/core-base-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/pc-amd64-gadget-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop-snapd.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/ubuntu-desktop-provision.git

# GNOME
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-desktop-session-snap.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/gnome-desktop-runtime.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/pipewire-snap.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-desktop-a11y.git
git clone --branch main --single-branch https://github.com/canonical/accountsservice-snap.git
git clone --branch main --single-branch https://github.com/canonical/provd-snap.git
git clone --branch main --single-branch https://github.com/canonical/fprintd-snap.git
git clone --branch main --single-branch https://github.com/canonical/boltd-snap.git
git clone --branch main --single-branch https://github.com/canonical/geoclue-snap.git

# KDE
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/plasma-desktop-session.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/plasma-core-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/kf6-core26.git
```

The provisioning snap, the three KDE snaps and `ubuntu-desktop-provision`
are currently maintained under the
[`chris-bainbridge`](https://github.com/chris-bainbridge) forks.

The five provider snaps (accountsservice, provd, fprintd, bolt, geoclue)
carry the desktop system daemons that the thin desktop-variant base no
longer ships, and are GNOME-only. `udisks2` and `upower` stay store snaps
resolved by the model. The provider repositories build from `main` rather
than a `desktop/26` branch.

### Build the Snaps

The recipes differ in five places; every other component is a plain
`snapcraft pack`:

- `core-base-desktop` builds the **desktop variant** of the base through
  `tools/build-variant.sh`. A plain `snapcraft pack` there produces a
  variant-less base with **no desktop payload** (it boots to a system with
  no display manager). If the checkout has previously built a different
  variant, run a full `snapcraft clean` first — cached part state can
  re-apply the other variant's settings and clobber the variant selection.
- `accountsservice-snap`, `provd-snap`, `plasma-core-desktop` and
  `plasma-desktop-session` declare `base: core26-desktop`, which
  snapcraft's schema rejects. Their `build-github.sh` swaps in a plain
  `core26` base for every snapcraft call, then patches the packed snap's
  metadata back to `core26-desktop`.
- `kf6-core26` has its own `build.sh` (it stages prebuilt KDE Neon
  packages rather than compiling).
- `ubuntu-desktop-a11y` keeps its recipe in a `snap/` subdirectory.
- `ubuntu-core-desktop-snapd` keeps its recipe under `build-aux/snap/`,
  which snapcraft finds automatically.

`./build-snap.sh` encodes all of this. The simplest way to build one
component by hand is to let it do the work — clone into that repository
and run:

```bash
cd ~/ucd-build/ubuntu-core-desktop
./build-snap.sh accountsservice-snap --source-dir ~/ucd-build/accountsservice-snap
```

or build everything for a desktop, copying each result into the image
repository's cache under the name assembly expects:

```bash
./build-snaps.sh --desktop gnome   # builds any component cloned in local-sources/
```

If you prefer to drive snapcraft yourself, the per-repository commands
are the ones each repository's CI runs (`build-variant.sh desktop`,
`build-github.sh`, `./build.sh`, or `snapcraft pack`), and the produced
snaps are:

- `core26-desktop_<version>+desktop_<arch>.snap` (the desktop-variant base)
- `pc-desktop_*.snap`
- `snapd_*.snap`
- `accountsservice_*.snap`, `provd_*.snap`, `fprintd_*.snap`,
  `bolt_*.snap`, `geoclue_*.snap`
- `ubuntu-desktop-a11y_*.snap`
- `ubuntu-desktop-session_*.snap`, `gnome-desktop-runtime_*.snap`,
  `pipewire_*.snap`
- `ubuntu-desktop-init_*.snap`
- `kf6-core26_*.snap`, `plasma-core-desktop_*.snap`,
  `plasma-desktop-session_*.snap`

**Check for stale build artifacts first.** If a wildcard matches multiple
files, a `cp` may pick the wrong one; select the current artifact
explicitly or remove outdated build outputs.

### Assemble the Image

Drop the snaps you built into `snaps/` under the names assembly uses, and
`build.sh` picks them up with no extra flags:

```bash
mkdir -p ~/ucd-build/ubuntu-core-desktop/snaps
cp ~/ucd-build/core-base-desktop/core26-desktop_*.snap  ~/ucd-build/ubuntu-core-desktop/snaps/core26-desktop-variant.snap
cp ~/ucd-build/pc-amd64-gadget-desktop/pc-desktop_*.snap ~/ucd-build/ubuntu-core-desktop/snaps/pc-desktop.snap
cp ~/ucd-build/ubuntu-core-desktop-snapd/snapd_*.snap    ~/ucd-build/ubuntu-core-desktop/snaps/snapd.snap
# ...and the rest, same pattern
```

Then run the Quick Start command. `--snaps-dir` points the cache somewhere
else, and `--no-build-snaps` requires every path to be passed explicitly
instead (that is what CI does).

The image is written to `build/pc.img`. The build script deletes and
recreates its build output directory on each run, so do not keep personal
keys or other files you need to preserve inside `build/`.

For a faster assembly-only test, skip building anything and let
`build-snaps.sh` download the exact assets CI consumes; see Quick Start.

## Test the Image in QEMU

Run the image with [`run-qemu.sh`](../run-qemu.sh):

```bash
./run-qemu.sh                # windowed when a display exists, headless otherwise
./run-qemu.sh --vnc          # serve the display over VNC instead
./run-qemu.sh --help         # all options (serial socket, MAC, bridge, ...)
```

The script boots `build/pc.img` with KVM, UEFI/OVMF and VirtIO devices
and exposes the VM's serial console on a unix socket (connect with
`nc -U /tmp/ucd-vm-serial.sock`; log in as root with the
`--root-password` password — see below). No seed ISO is attached
either way: `build.sh` bakes `--user` accounts straight into the image
and always drops a `build/pc.img.nouser` marker so boot scripts know
not to attach one; a build without `--user` boots the first-boot wizard.

To drive QEMU directly instead, the equivalent command is:

```bash
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

Firmware filenames vary by distribution. Locate the matching OVMF code and
variable-store files if the `_4M` paths above do not exist. Use a writable
copy of the variable-store file for each VM. If KVM is unavailable, replace
`-machine accel=kvm -cpu host` with `-machine accel=tcg`; TCG is slower.

On first boot, wait for snap seeding and initial setup to finish. The
system can restart once during initialization. The GNOME image then reaches
the “Welcome to Ubuntu” language selector; the KDE image reaches SDDM and
runs the `plasma-setup` wizard from there. Either can be skipped by baking
an account in at build time (`--user` with `--password`, optionally
`--autologin`).

CI validates what it publishes: before publishing, the amd64 image jobs
build a throwaway image with a test account, boot it headless, and
require the desktop session to come up — a broken snap set blocks the
publish instead of shipping an image that will not boot. (The arm64 job
is not gated yet: no KVM on the arm64 runners.)

For changes to `build.sh`, the model, or snap integration, run the relevant
source-repository checks and review the CI assembly procedure in
[`.github/workflows/build-image.yaml`](../.github/workflows/build-image.yaml).
There is no standalone automated test suite for a full graphical boot.

When reporting testing, distinguish between:

- **Syntax checks:** shell scripts pass `bash -n`.
- **Image assembly:** `build.sh` produces `build/pc.img`.
- **First boot:** the image reaches the welcome/greeter screen in QEMU.
- **End-to-end desktop:** account creation completes and a graphical
  session starts.

Report only the stages you actually tested, together with the QEMU
configuration and any failures.

## Optional Advanced Setup

### Cache Build Dependencies (pkgproxy)

Any build that runs snapcraft downloads hundreds of megabytes of build
packages and snaps, and repeats that on every rebuild: building a
component from source without a cache is slow, and that is expected —
set the cache up rather than blaming the build system. Install and run
`pkgproxy` before source-building:

```bash
sudo snap install pkgproxy
pkgproxy.pkgproxyctl setup snapcraft | sh    # what snapcraft builds download
pkgproxy.pkgproxyctl setup lxd-remote | sh   # its build images
```

`setup snapcraft` covers the apt, Snap Store and Go-module downloads
snapcraft makes (the per-tool `setup apt`, `setup snap` and `setup go`
variants do the same for direct apt/snapd/Go use). Run a command without
the pipe first to see what it changes; the setup commands produce
host-specific configuration and can modify package or client settings,
so review their output before applying. `pkgproxyctl stats` shows what
the cache holds and how much downloading it saved.

### Sign a Custom Model

The checked-in CI model is intended only to reproduce the experimental
development image. To use a modified model, create a local test key using
`snap create-key`, register it with `snapcraft register-key` using an
Ubuntu One account, and retrieve the matching account-key assertion. See
`./build.sh --help` and [`docs/models.md`](models.md) for the
model-specific procedure. **Never commit or share private signing keys.**
