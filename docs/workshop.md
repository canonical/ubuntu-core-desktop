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

The definition declares three host-resource plugs; the `gpu` plug connects
automatically at launch and the other two are manual grants on a trusted
development host:

- `gpu` (auto): the host GPU devices (`/dev/dri`), so the graphical QEMU run
  renders the desktop compositor with hardware acceleration instead of
  software rendering.
- `desktop` (manual): the host Wayland/X11 socket, so the QEMU window can be
  shown on the host display:

  ```bash
  workshop connect \
    ubuntu-core-desktop/ubuntu-core-desktop:desktop \
    :desktop
  ```

- `kvm` (manual): the host `/dev/kvm`. Without it QEMU cannot use KVM
  acceleration and the run fails; image builds do not need it. Inspect the
  proposed connection and only grant it on a trusted development host (the
  current custom-device API identifies `/dev/kvm` by its `misc` subsystem):

  ```bash
  workshop connect \
    ubuntu-core-desktop/ubuntu-core-desktop:kvm \
    :custom-device
  workshop connections --all
  ```

  The `:custom-device` argument is required. If it is omitted, Workshop looks
  for a system slot named `kvm`, but the built-in slot is named
  `custom-device`.

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

On top of the component snaps, every image build fetches the model's store
snaps (`pc-kernel`, the core bases, `mesa-2404`, ...) from the Snap Store.
`build.sh` warns prominently before that download when no pkgproxy is
reachable (see below), and pauses briefly when run from a terminal.

## Run the Image

Boot the image with the repository's QEMU runner (user-mode networking is
required inside the container; the wrapper action selects it):

```bash
workshop run ubuntu-core-desktop -- run-qemu
```

The runner keeps its state in `build/` on the host disk: the serial console is
exposed on `build/serial.sock`, connectable directly from the host — this is
the tool for diagnosing a boot that fails before SSH is up:

```bash
nc -U build/serial.sock
```

The VNC display (`run-qemu --vnc`) is reachable from the host as
`localhost:5901` through the definition's tunnel pair, which forwards the
default display; pass `--vnc-display` only together with a matching change
to the definition's endpoints. Pass any `run-qemu.sh` option after the
action's arguments; arguments after a second `--` are passed through to
QEMU:

```bash
workshop run ubuntu-core-desktop -- run-qemu --vnc
workshop run ubuntu-core-desktop -- run-qemu -- -serial stdio
```

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

## Optional: reuse the host pkgproxy

A locally running [pkgproxy](https://github.com/zygoon/pkgproxy) caches the
Snap Store traffic that every image build generates (and apt packages for
`setup-base`). To share the host's proxy with the container, add a tunnel
pair to the definition: a plug on the project SDK (what the container
connects to) and a slot on the system SDK (the host's pkgproxy):

```yaml
sdks:
  - name: project-ubuntu-core-desktop
    plugs:
      pkgproxy:
        interface: tunnel
        endpoint: localhost:3142
  - name: system
    slots:
      pkgproxy:
        interface: tunnel
        endpoint: localhost:3142
```

Then `workshop refresh` and connect it (host-side slots are never
auto-connected):

```bash
workshop connect \
  ubuntu-core-desktop/ubuntu-core-desktop:pkgproxy \
  ubuntu-core-desktop/system:pkgproxy
```

With the tunnel connected, the container's `localhost:3142` is the host's
proxy, and `build.sh`'s reachability probe finds it: no warning, and the
store snap downloads come from the local cache. Do not configure a generic
`http_proxy` instead of this: pkgproxy refuses absolute-form requests from
Go module fetches (see docs/build-tools.md, "pkgproxy + snapcraft/LXD
builds").
