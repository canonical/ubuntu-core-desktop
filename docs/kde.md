# Building the KDE Ubuntu Core Desktop Image

This guide covers the current **KDE image**: downloading a prebuilt image, building the component snaps, assembling an Ubuntu Core 26 image, and testing it in QEMU. For the GNOME image, see [docs/building.md](building.md); for the contribution process, see [CONTRIBUTING.md](../CONTRIBUTING.md); for a general project overview, see the [README](../README.md).

> **Development preview:** This procedure uses a **dangerous** model and unasserted local snaps. Images are for development only, not production or security-sensitive use, and cannot receive normal Snap Store refreshes.

## About the KDE Image

The KDE image provides an **Ubuntu Core 26 image with a KDE Plasma 6.8.0 desktop session**, assembled from independently maintained snaps, with the session delivered as a confined snap rather than a traditional mutable installation.

It differs from the GNOME image in three ways:

- **Display manager.** The KDE image uses SDDM; the GNOME image uses GDM. Each image selects one display manager and its matching session. Installing another desktop session snap onto an existing image does not switch its display manager, and mixed manager/session configurations are not supported.
- **First boot.** First boot runs the **plasma-setup wizard**, the KDE equivalent of GNOME's `ubuntu-desktop-init`, which creates the user account (name, password, groups) from the SDDM login screen. No credentials are baked into the image and no seed ISO is built or shipped.
- **Session snaps.** The Plasma session is delivered by three snaps: `plasma-desktop-session` provides the confined Plasma session and the SDDM display manager, `plasma-core26-desktop` provides the Plasma runtime content and theme assets, and `kf6-core26` provides the Qt 6 / KDE Frameworks runtime.

## Download a Prebuilt KDE Image

Visit the [GitHub Releases page](https://github.com/canonical/ubuntu-core-desktop/releases) and download:

- The latest KDE image (`ubuntu-core-desktop-kde-YYYYMMDD.img.zst`)
- The corresponding `SHA256SUMS` file

GitHub release assets are capped at 2 GiB, and the KDE image (which carries more snaps than the GNOME image) can land just over that. A release may therefore ship the image split into `ubuntu-core-desktop-kde-YYYYMMDD.img.zst.part00`, `.part01`, ... instead of a single `.img.zst`. Reassemble the parts before decompressing, then verify and extract (replace `YYYYMMDD` with the date in the filename):

```bash
cat ubuntu-core-desktop-kde-YYYYMMDD.img.zst.part* > ubuntu-core-desktop-kde-YYYYMMDD.img.zst
sha256sum -c SHA256SUMS
zstd -T0 -d --sparse ubuntu-core-desktop-kde-YYYYMMDD.img.zst -o pc.img
```

`sha256sum -c` may report missing files if `SHA256SUMS` lists other release assets; ensure the KDE archive reports `OK` before proceeding. The `--sparse` option avoids allocating the full 20 GiB disk image when decompressing.

## Build the KDE Image

### Build Environment

The build environment is the same as for the GNOME image; see [docs/building.md](building.md#build-environment) for the required tools and the Snapcraft/LXD setup.

### Clone the Repositories

Keep the snap sources and this assembly repository in a common parent directory:

```bash
mkdir -p ~/ucd-build
cd ~/ucd-build

git clone --branch desktop/26 --single-branch https://github.com/canonical/core-base-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/pc-amd64-gadget-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop-snapd.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/ubuntu-desktop-provision.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/plasma-desktop-session.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/plasma-core-desktop.git
git clone --branch desktop/26 --single-branch https://github.com/chris-bainbridge/kf6-core26.git
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop.git
```

The provisioning snap and the Plasma snaps are currently maintained under the [`chris-bainbridge`](https://github.com/chris-bainbridge) forks; see [docs/building.md](building.md#clone-the-repositories) for the corresponding notes.

### Build the Snaps

```bash
cd ~/ucd-build/core-base-desktop
snapcraft pack --use-lxd

cd ~/ucd-build/pc-amd64-gadget-desktop
snapcraft pack --use-lxd

cd ~/ucd-build/ubuntu-core-desktop-snapd
snapcraft pack --use-lxd

cd ~/ucd-build/ubuntu-desktop-provision
snapcraft pack --use-lxd

cd ~/ucd-build/plasma-desktop-session
snapcraft pack --use-lxd

cd ~/ucd-build/plasma-core-desktop
snapcraft pack --use-lxd

cd ~/ucd-build/kf6-core26
snapcraft pack --use-lxd
```

Copy the generated snaps to stable filenames for image assembly. **Check for stale build artifacts first.** If a wildcard matches multiple files, the corresponding `cp` command may fail; select the intended current artifact explicitly or remove outdated build outputs before copying.

```bash
mkdir -p ~/ucd-build/snaps
cp ~/ucd-build/core-base-desktop/core26-desktop_*.snap ~/ucd-build/snaps/core26-desktop.snap
cp ~/ucd-build/pc-amd64-gadget-desktop/pc-desktop_*.snap ~/ucd-build/snaps/pc-desktop.snap
cp ~/ucd-build/ubuntu-core-desktop-snapd/snapd_*.snap ~/ucd-build/snaps/snapd.snap
cp ~/ucd-build/ubuntu-desktop-provision/ubuntu-desktop-init_*.snap ~/ucd-build/snaps/ubuntu-desktop-init.snap
cp ~/ucd-build/plasma-desktop-session/plasma-desktop-session_*.snap ~/ucd-build/snaps/plasma-desktop-session.snap
cp ~/ucd-build/plasma-core-desktop/plasma-core26-desktop_*.snap ~/ucd-build/snaps/plasma-core26-desktop.snap
cp ~/ucd-build/kf6-core26/kf6-core26_*.snap ~/ucd-build/snaps/kf6-core26.snap
```

### Assemble the Image

The repository contains a pre-signed dangerous model and its account-key assertion under `ci/`. Use both so local assembly does not require creating or registering a personal model-signing key (see [docs/models.md](models.md)).

```bash
cd ~/ucd-build/ubuntu-core-desktop
./build.sh \
  --desktop kde \
  --model-account-key ci/account-key.assert \
  --base-snap ~/ucd-build/snaps/core26-desktop.snap \
  --gadget-snap ~/ucd-build/snaps/pc-desktop.snap \
  --snapd-snap ~/ucd-build/snaps/snapd.snap \
  --kde-session-snap ~/ucd-build/snaps/plasma-desktop-session.snap \
  --kde-plasma-snap ~/ucd-build/snaps/plasma-core26-desktop.snap \
  --snap ~/ucd-build/snaps/plasma-core26-desktop.snap \
  --snap ~/ucd-build/snaps/kf6-core26.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-init.snap \
  --model ci/ubuntu-core-desktop-kde-26-amd64-dangerous.model
```

The image is written to `build/pc.img`. `--kde-plasma-snap` selects the snap the build script extracts integration files from; the same snap is also included in the image unmodified via `--snap`.

Without `--user`, no account is baked in: first boot runs the plasma-setup wizard from the SDDM login screen to create the user account, and `build/pc.img.nouser` is dropped so a run script knows not to attach a seed ISO. Pass `--user <name>` together with `--password <password>` (plus `--autologin` and/or `--ssh-authorized-keys <path>` if wanted) to create the account at first boot via cloud-init from a seed ISO instead; see `./build.sh --help` for the full option list.

The build script deletes and recreates its build output directory on each run. Do not keep personal keys or other files you need to preserve inside `build/`.

For a faster assembly-only test, use the current `desktop-26-latest` snap assets downloaded by [`.github/workflows/build-image-kde.yaml`](../.github/workflows/build-image-kde.yaml).

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

Firmware filenames vary by distribution; use a matching pair and a writable copy of the variable-store file for each VM. If KVM is unavailable, replace `-machine accel=kvm -cpu host` with `-machine accel=tcg`; TCG is slower.

Allow the initial boot to complete; the system may restart once during initialization. SDDM presents the login screen, and the first-boot plasma-setup wizard creates the user account from there.

## Current Limitations

- Published and locally built images use a **dangerous-grade model** and include unasserted snaps. They cannot receive normal Snap Store refreshes and must not be used in production or security-sensitive environments.
- Update and recovery paths (rolling back to a previous image revision) are not yet tested.