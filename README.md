# Ubuntu Core Desktop

Ubuntu Core Desktop explores a new foundation for Ubuntu desktops: a modular, confined system built on Ubuntu Core's transactional, snap-based architecture. The goal is to make desktop systems easier to assemble, manage, and update reliably across a range of devices and use cases.

The current developer preview provides an **Ubuntu Core 26 image with a GNOME desktop session**. The image is assembled from independently maintained snaps, with the desktop session delivered as a confined component rather than through a traditional mutable installation.

Potential uses include kiosks and information displays, managed workstations, and other purpose-built desktop environments. The project also provides a testbed for developing and evaluating desktop confinement, image composition, and update workflows.

> **Developer preview — not for production use.** This is an experimental image, not a supported general-purpose Ubuntu Desktop release. See [Current limitations](#current-limitations) before trying it.

## Get started

You can download a prebuilt GNOME image and run it in QEMU without installing Ubuntu Core Desktop on physical hardware.

### 1. Install the prerequisites

On an Ubuntu host, install QEMU, UEFI firmware, and the decompression utility:

```bash
sudo apt update
sudo apt install qemu-system-x86 ovmf zstd
```

For the configuration below, use a host with KVM acceleration available and enough resources to allocate **2 vCPUs and 4 GiB of RAM** to the guest.

### 2. Download and extract an image

Visit the [GitHub Releases page](https://github.com/canonical/ubuntu-core-desktop/releases) and download:

- The latest GNOME image (`ubuntu-core-desktop-gnome-YYYYMMDD.img.zst`)
- The corresponding `SHA256SUMS` file

From the directory containing the downloaded files, verify the archive and extract the disk image. Replace `YYYYMMDD` with the date in the filename:

```bash
sha256sum -c SHA256SUMS
zstd -T0 -d --sparse ubuntu-core-desktop-gnome-YYYYMMDD.img.zst -o pc.img
```

**Note:** `SHA256SUMS` may also list other release assets. If so, `sha256sum -c` can report missing files; ensure the downloaded GNOME archive reports `OK` before proceeding.

The `--sparse` option avoids allocating the full 20 GiB disk image when decompressing it.

### 3. Prepare UEFI firmware

Check the UEFI firmware files available on your host and create a writable copy of the variables file:

```bash
ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_VARS_4M.fd
cp /usr/share/OVMF/OVMF_VARS_4M.fd ./OVMF_VARS.fd
```

If your system provides only `OVMF_CODE.fd` and `OVMF_VARS.fd`, use that matching pair instead in the commands.

### 4. Boot the image

Run QEMU from the same directory as `pc.img` and `OVMF_VARS.fd`:

```bash
qemu-system-x86_64 \
  -machine accel=kvm -cpu host -smp 2 -m 4096 \
  -display gtk,gl=on \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,unit=1,file=./OVMF_VARS.fd \
  -drive file=pc.img,format=raw,if=virtio,cache=none \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0
```

This starts a graphical VM with KVM acceleration and QEMU user-mode networking.

If KVM is unavailable, replace `-machine accel=kvm -cpu host` with `-machine accel=tcg`. Software emulation will be significantly slower.

### 5. Complete first-boot setup

Allow the initial boot to complete; the system may restart once during initialization. The GNOME first-boot wizard (`ubuntu-desktop-init`) should then appear. Select your language and follow the prompts to create a user account.

The current image has been tested with QEMU/KVM, UEFI, 2 vCPUs, and 4 GiB of RAM **through the welcome-language screen**. Completion of the entire setup flow is not established by that test.

## Current limitations

Published images use a **dangerous-grade model** and include locally built, unasserted snaps. They cannot rely on normal Snap Store refreshes and must not be used in production or security-sensitive environments.

The image does not include a preconfigured username or password; account creation takes place during first boot. This preview currently focuses on GNOME and should not be interpreted as a feature-complete or supported desktop distribution.

## Build and contribute

To build an image from source, test changes, or contribute to the project, see [`CONTRIBUTING.md`](CONTRIBUTING.md) for the documented GNOME build and QEMU test procedure.

## Repository layout

This repository is responsible for image assembly. Most snap payloads are maintained in separate repositories.

- [`build.sh`](build.sh) customizes the base and gadget snaps, includes requested local snaps, and invokes `ubuntu-image`.
- [`.github/workflows/build-image.yaml`](.github/workflows/build-image.yaml) describes the CI image assembly inputs and release workflow.
- [`docs/models.md`](docs/models.md) explains the image model.

This README focuses on the GNOME developer preview; KDE-specific information is outside its scope.
