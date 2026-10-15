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
sudo snap install snapcraft --classic --channel=9.x/stable
sudo snap install ubuntu-image --classic
sudo apt update
sudo apt install git squashfs-tools dosfstools mtools fakeroot crudini zstd qemu-system-x86 ovmf
```

Configure LXD for the user running Snapcraft if it has not already been initialized, then verify that LXD and Snapcraft are available:

```bash
lxc info
snapcraft --version
```

Build snaps explicitly in LXD containers with `snapcraft pack --use-lxd`. This avoids relying on Multipass or on whichever provider Snapcraft would otherwise choose. Use Snapcraft 9.x by default: all seven current `desktop/26` source builds were validated with Snapcraft 9.1.4 and `--use-lxd`. The snapd source recipe still recommends 8.x, so if a future source revision fails with a Snapcraft compatibility error, retry with `sudo snap install snapcraft --classic --channel=8.x/stable` and report the mismatch.

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

Run `snapcraft pack --use-lxd` from each snap repository root. Snapcraft detects the recipe in each repository; the snapd recipe is under `build-aux/snap/` and is also detected automatically.

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

- `core26-desktop_*.snap`
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

The repository contains a pre-signed dangerous model and its account-key assertion under `ci/`. Use both so local assembly does not require creating or registering a personal model-signing key.

```bash
cd ~/ucd-build/ubuntu-core-desktop
./build.sh \
  --desktop gnome \
  --model-account-key ci/account-key.assert \
  --base-snap ~/ucd-build/snaps/core26-desktop.snap \
  --gadget-snap ~/ucd-build/snaps/pc-desktop.snap \
  --snapd-snap ~/ucd-build/snaps/snapd.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-session.snap \
  --snap ~/ucd-build/snaps/gnome-desktop-runtime.snap \
  --snap ~/ucd-build/snaps/pipewire.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-init.snap \
  --model ci/ubuntu-core-desktop-26-amd64-dangerous.model
```

The image is written to `build/pc.img`. The GNOME runtime and PipeWire snaps must be passed explicitly; although the model names the session, these content snaps are not model entries and provide runtime and audio content required by the confined session.

The build script deletes and recreates its build output directory on each run. Do not keep personal keys or other files you need to preserve inside `build/`.

For a faster assembly-only test, use the current `desktop-26-latest` snap assets downloaded by `.github/workflows/build-image.yaml`. This validates assembly against published snap inputs but does not exercise building the snap source repositories.

## Test the Image in QEMU

Create a writable UEFI variable store beside the image, then run QEMU/KVM:

```bash
cd ~/ucd-build/ubuntu-core-desktop
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

Firmware filenames vary by distribution. Locate the matching OVMF code and variable-store files if the `_4M` paths above do not exist. Use a writable copy of the variable-store file for each VM. If KVM is unavailable, replace `-machine accel=kvm -cpu host` with `-machine accel=tcg`; TCG is slower.

On first boot, wait for snap seeding and initial setup to finish. The system can restart once during initialization. A successful first-boot test reaches the GNOME “Welcome to Ubuntu” language selector. Complete the wizard when testing account creation or the post-setup session. The validated configuration used 2 vCPUs, 4 GiB RAM, KVM acceleration, and UEFI.

For changes to `build.sh`, the model, or snap integration, run the relevant source-repository checks and review the CI assembly procedure in [`.github/workflows/build-image.yaml`](../.github/workflows/build-image.yaml). There is currently no standalone automated test suite for a full graphical boot.

When reporting your testing, distinguish between:

- **Syntax checks:** shell scripts pass `bash -n`.
- **Image assembly:** `build.sh` produces `build/pc.img`.
- **First boot:** the image reaches the GNOME welcome-language screen in QEMU.
- **End-to-end desktop:** account creation completes and a graphical session starts.

Report only the stages you actually tested, together with the QEMU configuration and any failures.

## Optional Advanced Setup

### Cache Build Dependencies

For repeated builds, an optional `pkgproxy` cache can reduce apt, Snap Store, and LXD downloads. Install `pkgproxy` and inspect the setup instructions from `pkgproxy.pkgproxyctl setup apt`, `pkgproxy.pkgproxyctl setup snap`, and `pkgproxy.pkgproxyctl setup lxd`. They produce host-specific configuration and can modify package or client settings; review their output before applying changes.

### Sign a Custom Model

The checked-in CI model is intended only to reproduce the experimental development image. To use a modified model, create a local test key using `snap create-key`, register it with `snapcraft register-key` using an Ubuntu One account, and retrieve the matching account-key assertion. See `./build.sh --help` and [`docs/models.md`](models.md) for the model-specific procedure. **Never commit or share private signing keys.**
