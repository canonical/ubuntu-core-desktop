# Building Ubuntu Core Desktop from Source

This guide covers the current **GNOME image**: preparing the development host, building component snaps, assembling an Ubuntu Core 26 image, and testing it in QEMU. For the contribution process, see [CONTRIBUTING.md](../CONTRIBUTING.md); to try a prebuilt image, see the [README](../README.md).

> **Development preview:** This procedure uses a **dangerous** model and unasserted local snaps. Images are for development only, not production or security-sensitive use, and cannot receive normal Snap Store refreshes.

The following procedure was validated on **15 October 2026**, reaching the GNOME welcome-language selector under QEMU/KVM with UEFI. This does **not** establish that account creation or a full graphical session was validated.

## Build Environment

Use an **Ubuntu amd64 host** with a reliable internet connection, **at least 30 GiB of free disk space**, and preferably **8 GiB or more RAM**. Building the component snaps downloads substantial source and package dependencies.

The standard workflow uses the committed development model and account-key assertion. You do **not** need to configure a package cache or create your own signing key.

Install the image-building and VM tools:

```bash
sudo snap install lxd
sudo snap install imagecraft --classic
sudo snap install snapcraft --classic --channel=9.x/stable
sudo apt update
sudo apt install git squashfs-tools dosfstools mtools fakeroot crudini zstd qemu-system-x86 ovmf
```

Initialize LXD for imagecraft's managed build environment if it has not already been initialized, then verify the tools are available:

```bash
lxd init --auto
lxc info
imagecraft --version
snapcraft --version
```

Imagecraft runs in managed mode using LXD; the build does not use destructive host mode. Build snaps explicitly in LXD containers with `snapcraft pack --use-lxd`. This avoids relying on Multipass or on whichever provider Snapcraft would otherwise choose. Use Snapcraft 9.x by default: all seven current `desktop/26` source builds were validated with Snapcraft 9.1.4 and `--use-lxd`. The snapd source recipe still recommends 8.x, so if a future source revision fails with a Snapcraft compatibility error, retry with `sudo snap install snapcraft --classic --channel=8.x/stable` and report the mismatch. Managed imagecraft on the GitHub-hosted `ubuntu-26.04` runner is not verified; the current CI workflows still use the old interface and are not updated by this change.

## Build the GNOME Image

### Clone the Repositories

Keep the snap sources and this assembly repository in a common parent directory. Each snap source repository is built independently:

```bash
mkdir -p ~/ucd-build
cd ~/ucd-build

git clone --branch desktop/26 --single-branch https://github.com/canonical/core-base-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/pc-amd64-gadget-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop-snapd.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-desktop-session-snap.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/gnome-desktop-runtime.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/pipewire-snap.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/ubuntu-desktop-provision.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop.git
```

The provisioning snap currently uses the `chris-bainbridge/ubuntu-desktop-provision` fork because its `desktop/26` branch contains required Snapcraft recipe changes. The canonical repository does not currently provide that branch.

### Build the Snaps

Run `snapcraft pack --use-lxd` from each snap repository root. Snapcraft detects the recipe in each repository; the snapd recipe is under `build-aux/snap/` and is also detected automatically. The `core-base-desktop` checkout's normal build produces the GNOME base. KDE needs the separate cloud-init variant: run `./build-github.sh cloud-init` from its repository root instead, then use that `core26-desktop-cloudinit.snap` for KDE builds.

```bash
cd ~/ucd-build/core-base-desktop
snapcraft pack --use-lxd

cd ~/ucd-build/pc-amd64-gadget-desktop
snapcraft pack --use-lxd

cd ~/ucd-build/ubuntu-core-desktop-snapd
snapcraft pack --use-lxd

cd ~/ucd-build/ubuntu-desktop-session-snap
snapcraft pack --use-lxd

cd ~/ucd-build/gnome-desktop-runtime
snapcraft pack --use-lxd

cd ~/ucd-build/pipewire-snap
snapcraft pack --use-lxd

cd ~/ucd-build/ubuntu-desktop-provision
snapcraft pack --use-lxd
```

Expected outputs (exact filenames include the recipe version):

- `core26-desktop_*.snap` (GNOME; KDE uses `core26-desktop-cloudinit_*.snap`)
- `pc-desktop_*.snap`
- `snapd_*.snap`
- `ubuntu-desktop-session_*.snap`
- `gnome-desktop-runtime_*.snap`
- `pipewire_*.snap`
- `ubuntu-desktop-init_*.snap`

Copy the generated snaps to stable filenames for image assembly. These commands assume one matching build artifact per pattern:

```bash
mkdir -p ~/ucd-build/snaps
cp ~/ucd-build/core-base-desktop/core26-desktop_*.snap ~/ucd-build/snaps/core26-desktop.snap
cp ~/ucd-build/pc-amd64-gadget-desktop/pc-desktop_*.snap ~/ucd-build/snaps/pc-desktop.snap
cp ~/ucd-build/ubuntu-core-desktop-snapd/snapd_*.snap ~/ucd-build/snaps/snapd.snap
cp ~/ucd-build/ubuntu-desktop-session-snap/ubuntu-desktop-session_*.snap ~/ucd-build/snaps/ubuntu-desktop-session.snap
cp ~/ucd-build/gnome-desktop-runtime/gnome-desktop-runtime_*.snap ~/ucd-build/snaps/gnome-desktop-runtime.snap
cp ~/ucd-build/pipewire-snap/pipewire_*.snap ~/ucd-build/snaps/pipewire.snap
cp ~/ucd-build/ubuntu-desktop-provision/ubuntu-desktop-init_*.snap ~/ucd-build/snaps/ubuntu-desktop-init.snap
```

**Check for stale build artifacts first.** If a wildcard matches multiple files, the corresponding `cp` command may fail. Select the intended current artifact explicitly or remove outdated build outputs before copying.

### Assemble the Image

The repository contains a pre-signed dangerous model and its account-key assertion under `ci/`. Use both so local assembly does not require creating or registering a personal model-signing key. Any build using `--user` needs a base snap containing cloud-init so the seed ISO can create the account; use the cloud-init base variant described in [the KDE guide](kde.md#build-the-snaps) for user-seeded builds.

```bash
cd ~/ucd-build/ubuntu-core-desktop
./build.sh \
  --platform gnome \
  --model-account-key ci/account-key.assert \
  --base-snap ~/ucd-build/snaps/core26-desktop.snap \
  --gadget-snap ~/ucd-build/snaps/pc-desktop.snap \
  --snapd-snap ~/ucd-build/snaps/snapd.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-session.snap \
  --snap ~/ucd-build/snaps/gnome-desktop-runtime.snap \
  --snap ~/ucd-build/snaps/pipewire.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-init.snap \
  --model platforms/gnome/model.signed
```

The image is written to `build/gnome/pc.img` (20 GiB by default); `--image-size SIZE` changes its final size. The GNOME runtime and PipeWire snaps must be passed explicitly; although the model names the session, these content snaps are not model entries and provide runtime and audio content required by the confined session. Development defaults are included unless you pass `--release`.

The build uses `build/<platform>` by default and each step clears only its own outputs. GNOME and KDE outputs therefore stay separate, and unrelated files in a build directory are not deleted.

### Run an Individual Build Step

`build.sh` runs all required steps in order. To iterate on one stage, run its script directly with the output directory from the build. Each step validates its own inputs and clears only the outputs it owns:

| Script | Purpose | Main inputs | Outputs |
| --- | --- | --- | --- |
| `steps/repack.sh` | Apply gadget, base, development, and optional developer pieces. This is the only step that runs under `fakeroot`. | `--platform`, `--base-snap`, `--gadget-snap`, optional `--input NAME=FILE`, `--out`; it also accepts `--release` and developer options. | `<OUT>/snaps/base.snap`, `<OUT>/snaps/gadget.snap` |
| `steps/sign-model.sh` | Sign a Platform JSON model or copy a pre-signed model assertion. | `--platform NAME` or `--model FILE`, `--out` | `<OUT>/model.assert` |
| `steps/pack-image.sh` | Render the shared imagecraft project and pack an image in managed mode. | `--platform`, `--model-assert`, `--account-key`, one or more `--snap FILE`, `--out`; optional `--image-size` | `<OUT>/project/`, `<OUT>/pc.img` |
| `steps/seed.sh` | Create a NoCloud seed ISO for a developer user. The password is stored as a SHA-512 crypt hash. | `--user`, `--password`; optional `--ssh-authorized-keys`, `--output` | The requested ISO path, normally `<OUT>/seed.iso` |

For example, after preparing a build directory and its repacked snaps, sign the model and rerun only image packing with:

```bash
./steps/sign-model.sh --model platforms/gnome/model.signed --out build/gnome

./steps/pack-image.sh \
  --platform gnome \
  --model-assert build/gnome/model.assert \
  --account-key ci/account-key.assert \
  --snap build/gnome/snaps/base.snap \
  --snap build/gnome/snaps/gadget.snap \
  --snap ~/ucd-build/snaps/snapd.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-session.snap \
  --snap ~/ucd-build/snaps/gnome-desktop-runtime.snap \
  --snap ~/ucd-build/snaps/pipewire.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-init.snap \
  --out build/gnome
```

Platform-declared KDE inputs are passed to `repack.sh` as repeatable `--input NAME=FILE` arguments. The full options for every script are available from its `--help` output. Repacking or signing independently does not automatically rerun later steps; invoke the downstream step(s) whose inputs changed.

For a faster assembly-only test, use the current `desktop-26-latest` snap assets downloaded by `.github/workflows/build-image.yaml`. This validates assembly against published snap inputs but does not exercise building the snap source repositories. These workflows still use the old CLI and are known to break against the refactored build until migrated.

## Test the Image in QEMU

Create a writable UEFI variable store beside the image, then run QEMU/KVM:

```bash
cd ~/ucd-build/ubuntu-core-desktop
cp /usr/share/OVMF/OVMF_VARS_4M.fd build/gnome/OVMF_VARS.fd
qemu-system-x86_64 \
  -machine accel=kvm -cpu host -smp 2 -m 4096 \
  -display gtk,gl=on \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,unit=1,file=build/gnome/OVMF_VARS.fd \
  -drive file=build/gnome/pc.img,format=raw,if=virtio,cache=none \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

Firmware filenames vary by distribution. Locate the matching OVMF code and variable-store files if the `_4M` paths above do not exist. Use a writable copy of the variable-store file for each VM. If KVM is unavailable, replace `-machine accel=kvm -cpu host` with `-machine accel=tcg`; TCG is slower.

On first boot, wait for snap seeding and initial setup to finish. The system can restart once during initialization. A successful first-boot test reaches the GNOME “Welcome to Ubuntu” language selector. Complete the wizard when testing account creation or the post-setup session. The validated configuration used 2 vCPUs, 4 GiB RAM, KVM acceleration, and UEFI.

For changes to `build.sh`, the model, or snap integration, run the relevant source-repository checks. The repository's shell tests can be run with:

```bash
for test_script in tests/*.sh; do bash "$test_script" || exit; done
```

`tools/boot-check.sh` is a standalone automated boot test that checks an image offline after a QEMU run; consult its `--help` output for options. It requires KVM, OVMF, and permission to loop-mount the image's `ubuntu-data` partition (direct root access or working `sudo`), and normally runs for ten minutes per image. Keep its output directory on a path short enough for QEMU's Unix monitor socket limit. CI workflow changes are out of scope here; the existing workflows still call the old interface and will fail until migrated. Managed imagecraft on the GitHub-hosted runner also remains unverified.

When reporting your testing, distinguish between:

- **Syntax checks:** shell scripts pass `bash -n`.
- **Image assembly:** `build.sh` produces `build/gnome/pc.img`.
- **First boot:** the image reaches the GNOME welcome-language screen in QEMU.
- **End-to-end desktop:** account creation completes and a graphical session starts.

Report only the stages you actually tested, together with the QEMU configuration and any failures.

## Old-to-New CLI Mapping

The refactor changes the build interface. Use this mapping when updating scripts or CI; CI workflow changes are not included here.

| Old interface | New interface |
| --- | --- |
| `--desktop gnome\|kde` | `--platform gnome\|kde` |
| KDE `--kde-session-snap PATH` | KDE `--input session=PATH` |
| KDE `--kde-plasma-snap PATH` plus duplicate `--snap PATH` | KDE `--input plasma=PATH`; remove the duplicate `--snap` because the Platform declares this input as local |
| `--model ci/ubuntu-core-desktop-26-amd64-dangerous.model` | `--model platforms/gnome/model.signed` |
| `--model ci/ubuntu-core-desktop-kde-26-amd64-dangerous.model` | `--model platforms/kde/model.signed` |
| `--model-account-key ci/account-key.assert` | Unchanged |
| `--base-snap`, `--gadget-snap`, `--snapd-snap`, `--snap` | Unchanged |
| `--user`, `--password`, `--autologin`, `--root-password`, `--ssh-authorized-keys`, `--ssh-host-key`, `--debug` | Unchanged |
| `--build-dir NAME` under the project root | `--build-dir PATH`; default is `build/<platform>` |
| No release or size option | `--release` opts into Release defaults; `--image-size SIZE` sets final size (default `20G`) |
| `build/pc.img`, `build/seed.iso` | `build/<platform>/pc.img`, `build/<platform>/seed.iso` |
| Install `ubuntu-image` | Install imagecraft and initialize LXD for managed mode |

The existing `.github/workflows/build-image.yaml` and `build-image-kde.yaml` still use the old flags, model paths, output paths, and `ubuntu-image`; they will break until migrated. Whether managed imagecraft works on the GitHub-hosted runner is unverified.

## Optional Advanced Setup

### Cache Build Dependencies

For repeated builds, an optional `pkgproxy` cache can reduce apt, Snap Store, and LXD downloads. Install `pkgproxy` and inspect the setup instructions from `pkgproxy.pkgproxyctl setup apt`, `pkgproxy.pkgproxyctl setup snap`, and `pkgproxy.pkgproxyctl setup lxd`. They produce host-specific configuration and can modify package or client settings; review their output before applying changes.

### Sign a Custom Model

The checked-in CI model is intended only to reproduce the experimental development image. To use a modified model, create a local test key using `snap create-key`, register it with `snapcraft register-key` using an Ubuntu One account, and retrieve the matching account-key assertion. See `./build.sh --help` and [`docs/models.md`](models.md) for the model-specific procedure. **Never commit or share private signing keys.**
