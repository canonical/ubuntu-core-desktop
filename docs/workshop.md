# Build in Canonical Workshop

The repository includes a [Workshop](https://ubuntu.com/workshop) definition
that provides the image assembly and QEMU dependencies in an isolated LXD
container. This path assembles the image from the prebuilt component snaps. It
does not configure nested LXD for building component snaps cloned under
`local-sources/`.

## Launch the Workshop

Install the host prerequisites and launch the environment from this repository:

```bash
sudo snap install --channel=6/stable lxd
sudo snap install --classic workshop

workshop launch ubuntu-core-desktop
```

Workshop does not grant access to the host display automatically. Connect it
before running graphical QEMU:

```bash
workshop connect \
  ubuntu-core-desktop/ubuntu-core-desktop:desktop \
  :desktop
```

## Build an Image

Assemble either desktop image:

```bash
gh auth login

GH_TOKEN="$(gh auth token)" \
  workshop run --env GH_TOKEN ubuntu-core-desktop -- build-gnome
# or
GH_TOKEN="$(gh auth token)" \
  workshop run --env GH_TOKEN ubuntu-core-desktop -- build-kde
```

The first build downloads several hundred megabytes of component snaps. The
result is `build/pc.img`, as with a build performed directly on the host. Allow
at least 30 GiB of free host disk space because the project directory, cache,
and build output remain on the host. `build-snaps.sh` uses GitHub CLI to read
the component releases. `--env GH_TOKEN` passes the authenticated host token
only to that Workshop action; the token is not stored in the definition or
project directory.

## Run the Image

Boot the image with graphical QEMU:

```bash
workshop run ubuntu-core-desktop -- run-qemu
```

The runner keeps writable UEFI state in `build/OVMF_VARS.fd`. Pass
`--reset-firmware` to restore it from the installed OVMF template. Additional
arguments after a second `--` are passed to QEMU:

```bash
workshop run ubuntu-core-desktop -- run-qemu --reset-firmware
workshop run ubuntu-core-desktop -- run-qemu -- -serial stdio
```

By default the runner uses KVM when `/dev/kvm` is available and writable, and
otherwise falls back to the substantially slower TCG emulator. KVM access is a
separate manual host-device grant. The current Workshop custom-device API
identifies `/dev/kvm` by its `misc` kernel subsystem, so inspect the proposed
connection and only grant it on a trusted development host:

```bash
workshop connect \
  ubuntu-core-desktop/ubuntu-core-desktop:kvm \
  :custom-device
workshop connections --all
workshop run ubuntu-core-desktop -- run-qemu --accel kvm
```

The `:custom-device` argument is required. If it is omitted, Workshop looks for
a system slot named `kvm`, but the built-in slot is named `custom-device`.

Use `--accel tcg` to force software emulation.

## Maintain the Workshop

Refresh the rolling component snap cache with:

```bash
GH_TOKEN="$(gh auth token)" \
  workshop run --env GH_TOKEN ubuntu-core-desktop -- sync-snaps
```

The Workshop actions and SDK definition are tracked under `.workshop/`. The
per-machine `.workshop.lock` created at launch is intentionally gitignored.
Use `workshop stop ubuntu-core-desktop` when finished, or
`workshop remove ubuntu-core-desktop` to remove the environment. Neither
command removes the repository's `snaps/` cache or `build/` output.
