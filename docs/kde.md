# Building the KDE Ubuntu Core Desktop Image

This guide covers the current **KDE image**: downloading a prebuilt image, building the component snaps, assembling an Ubuntu Core 26 image, and testing it in QEMU. For the GNOME image, see [docs/building.md](building.md); for the contribution process, see [CONTRIBUTING.md](../CONTRIBUTING.md); for a general project overview, see the [README](../README.md).

> **Development preview:** This procedure uses a **dangerous** model and unasserted local snaps. Images are for development only, not production or security-sensitive use, and cannot receive normal Snap Store refreshes.

## About the KDE Image

The KDE image provides an **Ubuntu Core 26 image with a KDE Plasma 6.8.0 desktop session**, assembled from independently maintained snaps, with the session delivered as a confined snap rather than a traditional mutable installation.

It differs from the GNOME image in three ways:

- **Display manager.** The KDE image uses SDDM; the GNOME image uses GDM. Each image selects one display manager and its matching session. Installing another desktop session snap onto an existing image does not switch its display manager, and mixed manager/session configurations are not supported.
- **First boot.** There is no first-boot setup wizard. The login account is created at first boot by cloud-init from a companion **seed ISO** built alongside the image (see [`steps/seed.sh`](../steps/seed.sh)). The seed ISO **must** be attached as a virtual CD-ROM on first boot, or no user account will exist. The KDE image is therefore assembled from the **cloud-init variant** of the base snap, the only variant that includes cloud-init; the default variant leaves the seed ISO unprocessed.
- **Session snaps.** The Plasma session is delivered by three snaps: `plasma-desktop-session` provides the confined Plasma session and the SDDM display manager, `plasma-core26-desktop` provides the Plasma runtime content and theme assets, and `kf6-core26` provides the Qt 6 / KDE Frameworks runtime.

## Download a Prebuilt KDE Image

Visit the [GitHub Releases page](https://github.com/canonical/ubuntu-core-desktop/releases) and download:

- The latest KDE image (`ubuntu-core-desktop-kde-YYYYMMDD.img.zst`)
- The companion seed ISO (`ubuntu-core-desktop-kde-YYYYMMDD-seed.iso`)
- The corresponding `SHA256SUMS` file

GitHub release assets are capped at 2 GiB, and the KDE image (which carries more snaps than the GNOME image) can land just over that. A release may therefore ship the image split into `ubuntu-core-desktop-kde-YYYYMMDD.img.zst.part00`, `.part01`, ... instead of a single `.img.zst`. Reassemble the parts before decompressing, then verify and extract (replace `YYYYMMDD` with the date in the filename):

```bash
cat ubuntu-core-desktop-kde-YYYYMMDD.img.zst.part* > ubuntu-core-desktop-kde-YYYYMMDD.img.zst
sha256sum -c SHA256SUMS
zstd -T0 -d --sparse ubuntu-core-desktop-kde-YYYYMMDD.img.zst -o pc.img
```

`sha256sum -c` may report missing files if `SHA256SUMS` lists other release assets; ensure the KDE archive and seed ISO report `OK` before proceeding. The `--sparse` option avoids allocating the full 20 GiB disk image when decompressing.

> **Warning:** The published image's seed ISO creates a `guest`/`guest` account with autologin enabled. **Anyone with access to a booted instance can log in.** Treat published images as disposable, and build your own image with a personal account (below) for anything else.

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

The base snap needs one KDE-specific step: select the **cloud-init variant** before packing. From `core-base-desktop`, run `./build-github.sh cloud-init`, which selects the variant and packs it as `core26-desktop-cloudinit.snap`. Without this variant, the built image's seed ISO is never processed and no account is created at first boot.

```bash
cd ~/ucd-build/core-base-desktop
./build-github.sh cloud-init

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
cp ~/ucd-build/core-base-desktop/core26-desktop-cloudinit_*.snap ~/ucd-build/snaps/core26-desktop-cloudinit.snap
cp ~/ucd-build/pc-amd64-gadget-desktop/pc-desktop_*.snap ~/ucd-build/snaps/pc-desktop.snap
cp ~/ucd-build/ubuntu-core-desktop-snapd/snapd_*.snap ~/ucd-build/snaps/snapd.snap
cp ~/ucd-build/ubuntu-desktop-provision/ubuntu-desktop-init_*.snap ~/ucd-build/snaps/ubuntu-desktop-init.snap
cp ~/ucd-build/plasma-desktop-session/plasma-desktop-session_*.snap ~/ucd-build/snaps/plasma-desktop-session.snap
cp ~/ucd-build/plasma-core-desktop/plasma-core26-desktop_*.snap ~/ucd-build/snaps/plasma-core-desktop.snap
cp ~/ucd-build/kf6-core26/kf6-core26_*.snap ~/ucd-build/snaps/kf6-core26.snap
```

### Assemble the Image

The repository contains a pre-signed dangerous model and its account-key assertion under `ci/`. Use both so local assembly does not require creating or registering a personal model-signing key (see [docs/models.md](models.md)).

```bash
cd ~/ucd-build/ubuntu-core-desktop
./build.sh \
  --platform kde \
  --model-account-key ci/account-key.assert \
  --base-snap ~/ucd-build/snaps/core26-desktop-cloudinit.snap \
  --gadget-snap ~/ucd-build/snaps/pc-desktop.snap \
  --snapd-snap ~/ucd-build/snaps/snapd.snap \
  --input "session=$HOME/ucd-build/snaps/plasma-desktop-session.snap" \
  --input "plasma=$HOME/ucd-build/snaps/plasma-core-desktop.snap" \
  --snap ~/ucd-build/snaps/kf6-core26.snap \
  --snap ~/ucd-build/snaps/ubuntu-desktop-init.snap \
  --user alice \
  --password 'choose-a-password' \
  --model platforms/kde/model.signed
```

The image is written to `build/kde/pc.img` and the seed ISO to `build/kde/seed.iso`. The declared `session` and `plasma` inputs are both included in the image automatically; do not pass the plasma snap a second time with `--snap`. The `--user` and `--password` options create the account through the seed ISO.

A KDE image built without `--user` is not usable: there is no first-boot wizard, so without the seed ISO no account exists. The build warns when KDE is built without `--user`. `--user` requires `--password`, and it is refused if the base snap does not contain cloud-init; use the `core26-desktop-cloudinit` base snap. Add `--autologin` to log the account straight into the Plasma session, and `--ssh-authorized-keys <path>` to install SSH public keys for the account; see `./build.sh --help` for the full option list.

The build uses `build/kde` by default, separate from GNOME's `build/gnome` output. Each step clears only its own outputs.

For a faster assembly-only test, use the current `desktop-26-latest` snap assets downloaded by [`.github/workflows/build-image-kde.yaml`](../.github/workflows/build-image-kde.yaml). Note that the KDE image consumes the cloud-init base snap asset (`core26-desktop-cloudinit.snap`).

## Test the Image in QEMU

Create a writable UEFI variable store beside the image, then run QEMU/KVM. The seed ISO must be attached as a CD-ROM drive on first boot, or the account is not created:

```bash
cd ~/ucd-build/ubuntu-core-desktop
cp /usr/share/OVMF/OVMF_VARS_4M.fd build/kde/OVMF_VARS.fd
qemu-system-x86_64 \
  -machine accel=kvm -cpu host -smp 2 -m 4096 \
  -display gtk,gl=on \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,unit=1,file=build/kde/OVMF_VARS.fd \
  -drive file=build/kde/pc.img,format=raw,if=virtio,cache=none \
  -drive file=build/kde/seed.iso,if=virtio,format=raw,media=cdrom \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

Firmware filenames vary by distribution; use a matching pair and a writable copy of the variable-store file for each VM. If KVM is unavailable, replace `-machine accel=kvm -cpu host` with `-machine accel=tcg`; TCG is slower.

Allow the initial boot to complete; the system may restart once during initialization. cloud-init creates the account from the seed ISO, then SDDM presents the login screen — or logs the `--autologin` user directly into the Plasma session.

## Current Limitations

- Published and locally built images use a **dangerous-grade model** and include unasserted snaps. They cannot receive normal Snap Store refreshes and must not be used in production or security-sensitive environments.
- There is no first-boot account-creation wizard; the seed ISO built with `--user`/`--password` is required for any account to exist.
- Published images ship a `guest`/`guest` autologin seed ISO; treat any booted instance as publicly accessible.
- Update and recovery paths (rolling back to a previous image revision) are not yet tested.
