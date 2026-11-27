# ubuntu-core-desktop: GNOME/KDE image build and run scripts

Three tiers of build, slowest/most-complete to fastest/narrowest:

1. Full rebuild of every component snap plus the VM image (GNOME or
   KDE): build every dependency repo (tier 2) — these can run
   concurrently — and finish by building the image (tier 3). For a
   from-scratch build, force a full `snapcraft clean` (wipes part
   state and recreates the LXD build container/VM; ccache is
   untouched) in every dependency repo first, instead of relying on
   snapcraft's incremental part cache.
2. Rebuilding a single changed snap: each component repo (e.g.
   `pc-amd64-gadget-desktop`, `core-base-desktop`,
   `ubuntu-core-desktop-snapd`, `ubuntu-desktop-session-snap`,
   `ubuntu-desktop-provision`, `gnome-desktop-content`,
   `plasma-core-desktop`, `plasma-desktop-session`, `kf6-core26`,
   etc.) has its own build — `snapcraft pack` in that repo, or
   `./build-snap.sh <component>` from this repo (see docs/building.md).
   A local pkgproxy (apt/snap caching proxy) speeds up package
   fetches — but NOT via a generic `http_proxy`, which breaks Go
   module fetches; see the pkgproxy section below. Use the single
   repo's build directly when only that component changed, rather
   than the full tier-1 rebuild.
3. Rebuilding/booting just the VM image (once the snaps it needs are
   already built): `./build.sh --desktop gnome` (or `--desktop kde`),
   then boot the image under QEMU (below). Resolve every input snap
   (session snap, content snaps, first-boot wizard snap) directly
   from its source repo's build output by latest mtime — never from
   a stale local copy. For the GNOME/KDE session snap specifically,
   also check the built snap's embedded git revision against that
   repo's current HEAD and refuse to proceed (rerun that repo's
   build first) if they don't match, so a stale session snap can't
   silently get baked into the image.

`build.sh --help` documents the current flags in full; notable ones:

- Core flags: `--desktop gnome|kde`, `--model-account-key`,
  `--base-snap`, `--gadget-snap`, `--snapd-snap`. Which of these are
  hard-required has shifted over time (the snap inputs now default
  to the `snaps/` cache and there is an `--arch amd64|arm64` flag) —
  `build.sh --help` is authoritative; see docs/building.md.
- Password flags are split in two, both optional (no build-time user
  is required at all — a minimal invocation passes only
  `--model-account-key` plus the input snaps, no personal values):
  - `--root-password <pw>`: root's login password baked into the
    image (SHA-512 crypt). Image-only, needs no
    `--user`. Omit it and root keeps the base's locked
    shadow entry (`root:*`) — no root password login at all on that
    build; rely on the first-boot wizard instead (see
    gdm-graphical-session.md).
  - `--password <pw>` + `--user <name>` (required together — each
    errors if given without the other): `<name>`'s login password.
    `--user` provisioning is factory-seeded straight into extrausers
    at build time, and `build/pc.img.nouser` is ALWAYS dropped
    alongside `pc.img` regardless of `--user` — run setups never
    branch on its presence to decide between a seeded user and the
    first-boot wizard. See core-base-desktop.md for
    the base-snap-side variant pinning this depends on (the base
    must be built with `SNAP_BUILD_VARIANT=desktop` or the stock
    Debian `custom.conf`/autologin wiring is missing).
    `--ssh-authorized-keys` works independently of `--user` for
    root's authorized_keys.
- `--ssh-host-key` is optional: when omitted, no HostKey
  directive is added/copied and the base's `sshd-keygen.service`
  (`ConditionFirstBoot=yes`) generates a fresh host key every
  build — each no-host-key build gets a new SSH identity. When
  used, generate once with
  `ssh-keygen -t ed25519 -N '' -f dev/ssh_host_ed25519_key`; keep
  it outside the `build/` tree so it survives `rm -rf build`.
  `PermitRootLogin yes` is appended to sshd_config either way.
- Other optional flags: repeatable `--snap <path>` for extra
  unmodified snaps, `--model <path>` (defaults to the gnome/kde
  dangerous model JSON in the repo root), `--autologin` (requires
  `--user`), `--kde-session-snap` (required for `--desktop kde`),
  `--build-dir` (default `build`, recreated every run), `--debug`
  (verbose kernel/snapd console logging).
- Consequence for VM testing: a no-`--root-password` build has NO
  way to log in as root via the serial console (see "VM access
  notes" below) — it relies entirely on the first-boot wizard
  (`ubuntu-desktop-init`/`plasma-setup`) to create a user.
- Default kernel cmdline extra (written to `cmdline.extra` in the
  unsquashed gadget) is `systemd.journald.forward_to_console=1
  systemd.journald.max_level_console=err console=ttyS0,115200n8`;
  `--debug` switches it to `snapd.debug=1 systemd.log_target=console
  systemd.journald.forward_to_console=1 console=ttyS0,115200n8`.
- Final image lands at `build/pc.img`; `build/` is gitignored and
  recreated on every build.

## Running the image under QEMU

Boot the image with `./run-qemu.sh` (see building.md's "Test the
Image in QEMU"). It handles the seed attachment (`pc.img.nouser` vs
`seed.iso`), a per-tree flock lock so a second concurrent launch
errors out instead of racing, display selection (SDL window, VNC via
`--vnc`, or headless EGL), the serial unix socket, and the LXD
bridge wait. Pin each VM's MAC (`--mac`) so its DHCP address can be
found via the ARP table (below).

VM bridge setups differ — don't assume two of them share one bridge
(confirmed 2026-10-27). LXD's bridge is SOCKET-ACTIVATED, not a boot
device — after a host reboot it does not exist until something
talks to LXD (e.g. any `lxc` command, or a snapcraft build); a VM
configured on it fails with "failed to get mtu of bridge <bridge>:
No such device" until then. Run any `lxc` command first (e.g.
`lxc version`/`lxc list`), or `systemctl enable snap.lxd.daemon` to
get it at boot — unrelated to being docked/undocked. A Wi-Fi uplink
can't be enslaved to a bridge, so VM bridges on such hosts are
always NAT-based (a plain bridge + hand-rolled dnsmasq was tried
and reverted as overhead vs. just using LXD's bridge).

`-netdev bridge` requires the setuid-root helper
`/usr/lib/qemu/qemu-bridge-helper` (CAP_NET_ADMIN to TUNSETIFF/
enslave the tap). Ubuntu's `qemu-system-common` package ships that
binary MODE 755 (not setuid) — the setuid bit is not shipped and
must be added manually, and `unattended-upgrades` replacing the
package silently resets the mode, re-breaking VM networking with
"failed to create tun device: Operation not permitted" / "bridge
helper failed". Fix:
`sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper` — re-apply after
any `qemu-system-common` upgrade (check the binary's ctime vs.
`/var/log/apt/history.log` to confirm an upgrade reset it).
`/etc/qemu/bridge.conf` also needs an `allow <bridge>` line per
bridge; a missing allow line fails differently (not EPERM) from the
missing-setuid case.

Long builds/runs (snapcraft packs, `ubuntu-image`, long-running VM
sessions) DIE when backgrounded with a plain `nohup ... &` at the
agent tool-call boundary — confirmed twice. Use
`setsid nohup <cmd> > log 2>&1 < /dev/null & disown` for anything
that must outlive one tool call. A snapcraft run killed mid-setup
leaves its LXD instance half-configured; if no part state is worth
keeping, `lxc delete <instance> --project snapcraft` and rerun
(retrying in place fails with "Failed to add disk to instance ...
device already exists").

## Other current gotchas

- Gadget naming matters: if a local gadget gets renamed away from
  what the model/recipe expects (e.g. `pc-desktop` -> `pc`),
  `ubuntu-image` silently ignores the local one and fetches the
  store's gadget instead, which can drag in an unexpected base.
  Keep local gadget snap names matching the model.
- Snapcraft: with `base: core24` set in `snap/snapcraft.yaml`,
  Snapcraft 9 rejects also having `build-base: core24` present —
  omit `build-base` in that case.
- If a build fails with a filesystem permissions error, check
  directory ownership before assuming a code bug — build dirs can
  end up owned by a different user.
- If builds run as a dedicated build user, give that user
  `umask 0002` so files it creates stay group-writable:

  ```bash
  if [[ "$(id -un)" == "your_username" ]]; then
      umask 0002
  fi
  ```

- Before assuming a base snap (core22/core24/etc.) can be dropped
  from a model, check
  `grep '^base:' /snap/<name>/current/meta/snap.yaml` for every
  currently-installed snap, not just the one you're focused on —
  multiple unrelated snaps can share the same base dependency.
- Before bumping a snap's channel to match a target Core release,
  check the store first with `snap info <name>` (lists all
  published channels) — not every snap in a model has a channel
  for every release track yet; don't guess/bump a channel name
  without confirming it's real.

## Finding a test VM's IP when it isn't already documented

Test VMs are launched with QEMU bridge networking (see above), not
a fixed static IP or SSH port-forward. Rather than trying to set
up a port-forward, find the DHCP-leased IP directly by matching
the VM's MAC (from the `-device virtio-net-pci,mac=...` argument
on the QEMU command line) against the host's ARP/neighbour table:

```bash
ip neigh show dev <bridge> 2>/dev/null | grep <mac>
```

or `arp -an`. See kde-internals.md for a separate, still-current
core24 KDE reference build (different repo,
`ubuntu-core-desktop-kde`).

### VM access notes

- Serial console (the main boot-diagnostics tool): `run-qemu.sh`
  exposes the VM's serial port on a unix socket
  (`/tmp/ucd-vm-serial.sock` by default; `--serial-socket` to change).
  Connect with:
    nc -U /tmp/ucd-vm-serial.sock
  or
    socat -,raw,echo=0,escape=0x1d UNIX-CONNECT:/tmp/ucd-vm-serial.sock
  (CTRL-] to exit). Log in as `root` with the `--root-password`
  password on images built with that flag — this works even when
  sshd never comes up, which is what makes it the tool for
  diagnosing boot failures (see boot-diagnostics.md). A
  no-`--root-password` build has no root password at all (the base's
  locked shadow entry `root:*`); it relies entirely on the first-boot
  wizard. Nouser builds also have no baked SSH host key (clear stale
  `known_hosts` entries each rebuild).
- VNC display for GUI diagnosis: `run-qemu.sh --vnc` serves the
  display on localhost (display `:1` by default, `--vnc-display N` to
  change), typically with no password. Use it to watch a boot or the
  first-boot wizard graphically instead of relying only on the serial
  console; GDM typically appears within a couple of minutes of boot
  start. Two things worth knowing:
  - QEMU monitor screendumps (for automated screenshot grabbing):
    `screendump out.png -f png` — always the PNG form; the PPM form is
    corrupt for widths not divisible by 4 (a long-standing upstream
    pixman stride bug, still unpatched in current distro packages).
  - For any GUI testing over VNC, the guest needs a pointing device
    passed through (`-device qemu-xhci -device usb-tablet` in a
    hand-written command line); without one, VNC clicks never reach a
    Wayland session. See diagnostics-methodology.md for the full
    VNC/audio testing recipes.
- A fresh build writes ONLY the BIOS Boot + ubuntu-seed partitions
  (`--image-size` is padding, ignored below its computed
  minimum); first boot's initramfs creates ubuntu-boot/save/data
  and continues the SAME boot (UC26+ `canInstallAndRunAtOnce` —
  there is no separate install-mode-then-reboot cycle to wait
  through, and the boot-1 `/proc/cmdline` install label is stale,
  not evidence of being stuck — read the modeenv, not the
  cmdline). See boot-diagnostics.md for full partition-layout/
  size numbers, the `--minimal` post-build truncate flag, and
  device-serial-registration gate traps.

## Image size: --image-size / --minimal

- `--image-size <size>` (default 20G) is only a suggestion to
  `ubuntu-image`: below the computed minimum (declared structures
  sized to fit the actual seed content) it is silently ignored
  with a warning. A fresh build is seed-only (see above); the
  apparent 20G is unwritten padding, not real content — don't
  read image size as a proxy for disk usage.
- `--minimal` post-build truncates the image to the last real GPT
  partition's end + 1MiB and relocates the backup GPT header
  (`sgdisk -e`) — loses nothing (the trimmed padding was holes),
  but a minimal image is seed-only and NOT directly bootable as a
  fixed-size VM disk (no room for boot/save/data); resize or
  convert to qcow2 first. Never boot/test a "minimal" or "golden"
  image copy before copying it elsewhere — first boot writes the
  rest of the partition table and the seed vfat into the file, so
  a booted image is no longer byte-identical to the build output.

## fakeroot sessions: never share one with a static (Go) binary

`build.sh` re-execs itself under `fakeroot` for the
unsquashfs/edit/mksquashfs hacks that bake root-owned content into
the gadget/custom-core snaps as an unprivileged user. `fakeroot`'s
LD_PRELOAD design cannot interpose a statically-linked binary
(e.g. `ubuntu-image`, a Go binary): if one runs inside the same
fakeroot session as other tools, it can create/delete/recycle
inodes invisibly to `faked`'s stat cache, so faked silently serves
STALE type/mode/owner info to every interposed tool afterwards
(`du`, etc. seeing wrong file types — ENOTDIR-type errors on
provably-regular files is the signature). This is inherent to the
design, not a bug that gets fixed upstream soon (fakeroot in
Ubuntu as of 2026-11 still lacks the upstream partial fix, and
even that fix only catches type-flip inode reuse, not same-type
reuse with wrong uid/gid/mode). The durable fix: never run a
static binary inside a shared fakeroot session — lift it out
entirely (`env -u FAKEROOTKEY -u LD_PRELOAD ubuntu-image ...`),
keeping fakeroot only for its actual unsquashfs/mksquashfs job.

Diagnostic notes: Go's
`exec.Command(...).Output()`/`CombinedOutput()` discards child
stderr on success and on many failure paths too for some callers —
ubuntu-image's own error surfaced only "Error getting rootfs
size: exit status 1" with no detail; capture the real error with
a wrapper script earlier on PATH. `unshare -U -r`
(userns-as-root) is not a portable substitute for fakeroot on
GitHub runners
(`kernel.apparmor_restrict_unprivileged_userns=1` there blocks
it, and snap-confine fails creating a DBus transient scope inside
a userns anyway) even though it works on a typical dev host.

## Snapcraft version-string caching

Snapcraft caches the computed version string in part state. If a
snap's version comes from a part's override-build (e.g. git
rev-parse HEAD) or otherwise depends on repo state that snapcraft
does not fingerprint, a plain `snapcraft pack` after a commit
repacks with the OLD `<date>+git<rev>` name. An image build that
checks the session snap's embedded revision against the repo's
HEAD (as recommended above) then rejects the snap as "not built
from HEAD", blocking every image build.
`snapcraft clean <part-that-sets-the-version>` before packing
fixes it (only that part — heavy parts keep their cache). Same
class: a metadata/layout-only change repacks WITHOUT refreshing
the version string.

## pkgproxy + snapcraft/LXD builds: no generic http_proxy

Do NOT point `http_proxy` at pkgproxy (port 3142) for snapcraft
builds. Go then sends its GOPROXY request through the proxy as an
ABSOLUTE-form URI (GET http://<proxy>:3142/go/...), pkgproxy
dispatches absolute-form requests to its apt passthrough handler
(journal: handler=apt outcome=passthrough status=403), which
refuses to fetch a URI from the proxy itself — and a 403 does NOT
trigger Go's ",direct" fallback (only 404/410 do), so every module
fetch fails. Direct/origin-form /go/ requests hit the gomod
handler and work.

The right setup is `pkgproxyctl setup snapcraft` (see
docs/building.md for the public setup commands): apt, snapd and Go
are covered per-ecosystem with NO generic HTTP proxy (verified
end-to-end:
`go install github.com/canonical/chisel/cmd/chisel@latest` inside
a project instance, and full source builds of
ubuntu-desktop-session and core-base-desktop, including the
chisel-libs part that used to 403). Older workarounds (`lxc config
set <instance> environment.GOPROXY direct`, or
`build-environment: GOPROXY: direct` in the Go parts) still work
but bypass the cache.

LXD base-instance repair (2026-11-20, snapcraft 9): if the cached
base instance is gone, recreating it fails at "failed to inject
host's snap 'craft-sd'" — the instance's snapd is pointed at
pkgproxy by a SNAPPY_FORCE_API_URL drop-in whose /v2/snaps/refresh
POST returns 405, and the prerequisite `snapd` snap can only come
from the store. Repair: start the instance; remove that drop-in
and restart snapd; `snap install snapd` (direct network works);
push the host's `/var/lib/snapd/snaps/craft-sd_<rev>.snap` and
install it locally; set `setup: true` in
/etc/craft-instance.conf; stop the instance; `lxc config set
<instance> user.craft_providers.status FINISHED` (the validity
check requires status FINISHED AND state STOPPED, and reads the
setup flag from the clone's /etc/craft-instance.conf). Leave the
base instance in that state — snapcraft reuses it.

## CI housekeeping

- Both image workflows (build-image.yaml/build-image-kde.yaml)
  expire old dated image releases (delete
  gnome-YYYYMMDD/kde-YYYYMMDD releases + tags older than 14 days)
  — GitHub release assets never expire on their own, and daily
  ~2-4GiB images accumulate forever without this.
- Workflow logs are NOT downloadable while a job is still live
  (404); a cancelled run keeps its already-completed steps' logs.
  Structure multi-step debug workflows so each diagnostic is its
  own step, cancel once the step you need has finished, and
  harvest logs from the cancelled run.
- New/renamed workflow files only get `workflow_dispatch`
  registered from the default branch — debugging a workflow on a
  side branch needs an `on: push: branches:` trigger instead.

## Canonical Workshop (.workshop/ definition)

- `workshop launch` needs a zfs-capable kernel: workshop hardcodes
  the zfs LXD storage driver (btrfs only on WSL), so on a custom
  kernel without the zfs module it fails at launch with "suitable
  storage backend not found: error loading \"zfs\" module".
  Installing zfs-dkms fixes it where kernel headers/Module.symvers
  are available; otherwise use a stock kernel. LXD must be 6.10+.
