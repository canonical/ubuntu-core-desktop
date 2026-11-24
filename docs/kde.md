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

Visit the [GitHub Releases page](https://github.com/canonical/ubuntu-core-desktop/releases), open the **Ubuntu Core Desktop 26 KDE** release (`kde-latest`), and download:

- `ubuntu-core-desktop-kde.img.zst`
- The corresponding `SHA256SUMS` file
- Optionally `manifest.txt`: the source commit and the snap versions in this image

That release is replaced by every green build on `desktop/26`, so it is never more than a day or two old.

GitHub release assets are capped at 2 GiB, and the KDE image (which carries more snaps than the GNOME image) can land just over that. A release may therefore ship the image split into `ubuntu-core-desktop-kde.img.zst.part00`, `.part01`, ... instead of a single `.img.zst`. Reassemble the parts before decompressing, then verify and extract:

```bash
cat ubuntu-core-desktop-kde.img.zst.part* > ubuntu-core-desktop-kde.img.zst
sha256sum -c SHA256SUMS
zstd -T0 -d --sparse ubuntu-core-desktop-kde.img.zst -o pc.img
```

The `--sparse` option avoids allocating the full 20 GiB disk image when decompressing.

## Build the KDE Image

### Build Environment

The build environment is the same as for the GNOME image; see
[docs/building.md](building.md#build-environment) for the required tools
and the Snapcraft/LXD setup.

### Quick Start: Assemble from Cached Snaps

```bash
git clone --branch desktop/26 --single-branch https://github.com/canonical/ubuntu-core-desktop.git
cd ubuntu-core-desktop
./build.sh --desktop kde \
  --model-account-key ci/account-key.assert \
  --model ci/ubuntu-core-desktop-kde-26-amd64-dangerous.model
```

`build.sh` downloads the KDE component snaps from their `desktop-26-latest`
GitHub releases into `snaps/`, then assembles them; no snap arguments are
needed. `./build-snaps.sh sync --desktop kde` refreshes the cache. See
[docs/building.md](building.md#quick-start-assemble-from-cached-snaps) for
the cache and override model in full.

The image is written to `build/pc.img`.

Without `--user`, no account is baked in: first boot runs the plasma-setup
wizard from the SDDM login screen to create the user account, and
`build/pc.img.nouser` is dropped so a run script knows not to attach a
seed ISO. Pass `--user <name>` together with `--password <password>`
(plus `--autologin` and/or `--ssh-authorized-keys <path>` if wanted) to
create the account at build time instead; see `./build.sh --help`.

The build script deletes and recreates its build output directory on each
run. Do not keep personal keys or other files you need to preserve inside
`build/`.

### Build the KDE Components from Source

The KDE image needs five snaps in addition to the shared base, gadget,
snapd and first-boot wizard: `plasma-desktop-session`, `plasma-core-desktop`
and `kf6-core26` (all currently under the
[`chris-bainbridge`](https://github.com/chris-bainbridge) forks).

Clone the one you are changing into `local-sources/`:

```bash
cd local-sources
git clone https://github.com/chris-bainbridge/plasma-desktop-session
```

Check that the checkout is on `desktop/26` (the branch CI builds these
from); `build-snap.sh` warns if it isn't.

and rerun `./build.sh --desktop kde ...`. `./build-snap.sh --list` shows
the component names; `./build-snap.sh plasma-desktop-session` builds one
by hand. Every other component keeps coming from the cache.

To build the whole KDE set yourself, use the same per-repository commands
as their CI (`./build-github.sh` for the two Plasma snaps, `./build.sh`
for `kf6-core26`, `tools/build-variant.sh desktop` for the base), then
copy the results into `snaps/` under the names assembly expects:

- `core26-desktop_*.snap` → `snaps/core26-desktop-variant.snap`
- `pc-desktop_*.snap` → `snaps/pc-desktop.snap`
- `snapd_*.snap` → `snaps/snapd.snap`
- `ubuntu-desktop-init_*.snap` → `snaps/ubuntu-desktop-init.snap`
- `plasma-desktop-session_*.snap` → `snaps/plasma-desktop-session.snap`
- `plasma-core-desktop_*.snap` → `snaps/plasma-core-desktop.snap`
- `kf6-core26_*.snap` → `snaps/kf6-core26.snap`

**Check for stale build artifacts first.** If a wildcard matches multiple
files, a `cp` may pick the wrong one; select the current artifact
explicitly or remove outdated build outputs.

`--kde-plasma-snap` selects the snap the build script extracts integration
files from; the same snap is also included in the image unmodified via
`--snap`, which is why `plasma-core-desktop.snap` appears in both places.

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