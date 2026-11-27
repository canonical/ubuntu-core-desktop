# core-base-desktop: snapcraft/LXD build + chisel-vs-apt overlap

Repo: core-base-desktop, branch 26-chisel. This is a different repo
from ubuntu-core-desktop (see build-tools.md) - it builds the actual
core26-desktop base snap itself, not a gadget/session on top of it.

UPDATE (2026-11-12, supersedes the paragraph this replaces): the base
went through a "thin" refactor (core-base-variant work,
desktop-variant/26 branch, commit d2979fc) that changed what "variant"
means here. The base now carries almost the ENTIRE desktop payload
(gdm.service, display-manager.service, the gdm PAM stacks, the gdm user,
/etc/gdm3, the user-unit routing graph, gdm D-Bus policy,
wayland-sessions, provd, GNOME initial-setup wiring, ...) ONLY in the
`desktop` variant (`variants/desktop/`, applied by
`apply-variant-payload.sh` when `SNAP_BUILD_VARIANT=desktop` — see
`variants/README.md`). The `cloud-init` variant ships cloud-init and NO
desktop payload at all, and is not used by current image builds
(build.sh's `--user` provisioning doesn't use cloud-init —
see build-tools.md). Any desktop image MUST be built with
`SNAP_BUILD_VARIANT=desktop`; the wrong-variant failure signature is a
VM that reaches graphical.target with no display manager at all (no gdm
user, no gdm.service, `snap list` shows the base suffixed `+cloud-init`)
— check a built core.snap's `meta/snap.yaml` `version:` suffix
(`+desktop` vs `+cloud-init`) or `unsquashfs -l core.snap | grep
systemd/system/gdm.service` before assuming a confinement/packaging bug.
The variant selection file `build-env` is gitignored, and craft-parts
only fingerprints TRACKED files — writing/removing `build-env` alone
does NOT retrigger a part rebuild, and the previous build's staged copy
persists across incremental builds. Always run a full `snapcraft clean`
before switching variants (or before a vanilla build after a variant
build); cleaning only the `hooks` part is not enough. The `hooks`
part's override-prime runs `make test` (hook-tests/*) against the primed
rootfs, so a wrong/leaking variant fails the build itself
(hook-tests/995-variant-payload checks the baked payload is applied
exactly once on desktop builds and never on regular ones).

Build/CI notes for the thin variant: its CI lives in
`.github/workflows/build-snap-variant.yml` (LXD provider,
`tools/build-variant.sh desktop`, a defensive `snapcraft clean` baked
in) and publishes to a rolling `desktop-26-thin-latest` GitHub release
on this same repo (the fat build's `build-snap.yml` keeps publishing to
`desktop-26-latest` from `desktop/26`); image CI consumes whichever tag
is current until the `desktop/26-thin` → `desktop/26` branch rename
lands. core26-desktop-BASED downstream snaps (accountsservice-snap,
provd-snap, plasma-desktop-session) cannot be built by plain
`snapcore/action-build`: snapcraft's schema rejects the base name
`core26-desktop`, so their CI must swap `base: core26` for the
snapcraft call, pack, then patch the built snap's `meta/snap.yaml` base
back to `core26-desktop` (unsquashfs/sed/mksquashfs — see
plasma-desktop-session's `build-github.sh`). Snaps on plain `core26`
need none of this. A worktree for this work may have `origin` pointing
at a personal fork rather than `canonical/core-base-desktop` — always
push a published branch to the canonical remote explicitly rather than
trusting a worktree's default `origin`.

## Build tooling

- The build is `snapcraft clean && snapcraft pack` (for the desktop
  variant: `tools/build-variant.sh desktop`, what CI runs — a plain
  `snapcraft pack` builds a variant-less base; see docs/building.md).
  A full build takes ~10+ minutes. Run it in the background, redirect
  output to a log file, and poll with long (~280s) delays;
  polling a backgrounded run without redirecting to a file returns
  nothing until you tail the file directly.
- Snapcraft uses LXD for this project (not multipass) - confirm via
  `lxc list --project snapcraft`. Instances are named like
  `snapcraft-core26-desktop-amd64-<id>`.
- When a build fails, the LXD instance is left STOPPED, not deleted.
  You can `lxc start <name> --project snapcraft` then `lxc exec
  <name> --project snapcraft -- bash -c '...'` to inspect the actual
  on-disk state (e.g. `/root/parts/<part>/install/...`,
  `/root/stage/...`, `/root/prime/...`) from the failed build. Always
  `lxc stop` it again afterward. Note an instance can be reused across
  multiple build attempts, so its filesystem reflects whichever run
  most recently touched it - match instance state against the
  specific failed log you're investigating, don't assume it's frozen
  at the failure you first saw it for.
- Snapcraft's stage-conflict check is fail-closed: it never silently
  picks a winner between two parts. If two parts stage different
  content/permissions at the same path it hard-errors ("Failed to
  stage: parts list the same file with different contents or
  permissions"); it only proceeds silently when the content is
  byte-identical.

## chisel-libs vs. apt-staged-package overlap

This base combines chisel slices (staged by the `chisel-libs` part,
which pulls a moving branch of chisel-ubuntu-core.git) with several
parts that stage plain .debs from the live Ubuntu archive
(`desktop-packages`, `gdm-packages`, `gnome-desktop-components`,
`system-setup-tool-packages`, `locale-packages`). Both resolve
overlapping core packages (systemd, coreutils, tzdata,
xkeyboard-config, python3, kmod, etc.). Because chisel-libs' branch
and the live archive move independently, previously-identical
overlapping files can drift apart over time and start hard-failing
the build with the stage-conflict error above. This is not a
regression in the usual sense - it's inherent to combining two
independently-moving upstreams, and the specific set of conflicting
paths can differ between builds run at different times.

Those 5 apt-staging parts relocate their whole stage-packages output
into a `base/` subdirectory (so it lands at the same relative path as
chisel-libs' own `base/` output) - this is what makes the paths
collide at all. The fix in place is `tools/resolve-base-conflicts.sh`,
called from each of those 5 parts' override-build with
`"${CRAFT_PROJECT_DIR}"/tools/resolve-base-conflicts.sh
"${CRAFT_PART_INSTALL}"/base`. It walks every path a part stages and,
wherever chisel-libs already staged the same path with genuinely
different content, gives chisel-libs unconditional priority (drops
the apt copy; for real directories that only differ in mode, aligns
permissions instead of dropping the directory, to avoid losing unique
content underneath it). Paths already identical on both sides are
left alone. It also indexes each part's `stage_packages/*.deb` cache
(a directory that sits as a sibling of `install/`) via `dpkg-deb -c`
to name the owning dpkg package in each conflict log line - cheap,
a few seconds even for hundreds of debs.

Gotchas worth knowing if extending this further:

- Symlink comparison must use the literal target text, not the
  resolved real path, to decide whether two copies truly match.
  Snapcraft's own stage-conflict check compares the literal symlink
  text, so two symlinks that resolve to the same real file but are
  *written* differently (e.g. systemd-sysv's relative
  `usr/sbin/halt -> ../bin/systemctl` vs. chisel-libs' absolute
  `usr/sbin/halt -> /usr/bin/systemctl`) still have to be resolved
  (drop one copy) even though they're functionally equivalent -
  otherwise snapcraft still hard-errors on them.
  `symlink_target_rel_to_base()`/`normalize_path()` in the script
  resolve both relative/absolute forms to a common base-relative path,
  used only to word the log line more accurately, not to skip
  resolving the conflict.
- Plain `[ -e "$target" ]` misses a dangling symlink (chisel-libs can
  stage a symlink whose target isn't materialized yet at this point in
  the build) - also check `[ -L "$target" ]`.
- Directory-vs-symlink type mismatches happen (e.g. `var/lock`/
  `var/run` staged as real directories by apt but as symlinks by
  chisel-libs) - `chmod` can't reconcile a type mismatch, must `rm -rf`
  and let chisel-libs' version stand.
- Bash: `declare -A arr; arr[""]=1` raises "bad array subscript" -
  guard against empty-string keys before an associative-array
  assignment (bit the per-part package-name index, since `dpkg-deb -c`
  lists the archive root as `./`, which normalizes to an empty
  string).
- `CRAFT_PROJECT_DIR` (already used elsewhere in snapcraft.yaml) is
  available inside override-build scripts and points at the repo root
  (where snapcraft.yaml lives) - use it to invoke repo-local helper
  scripts reliably regardless of the build's CWD.

## Changelog generation

Per-package changelog generation (`generate-changelog` part) was
deliberately disabled rather than fixed. It only ever worked for a
small hardcoded allowlist of packages; extending it to cover every
staged package would mean hundreds of network lookups against
Launchpad with no principled reason some packages get changelogs and
others don't. The long-term direction is to move most of this content
out of the base into separate snaps and use a plain core26 base
instead, so a working full changelog mechanism was judged not worth
building - if this comes up again, disabling (not patching) is the
established answer, unless the base's package set is first cut down
significantly.

## /etc/gdm3 must be a writable bind (wizard-phase autologin)

accounts-daemon (the wizard's "log in automatically" path) writes
/etc/gdm3/custom.conf with an ATOMIC write (temp file in the target's
own directory + rename over the target), which cannot go through the
/etc/writable symlink indirection — on a read-only squashfs
/etc/gdm3 it fails EROFS and the wizard's autologin choice never
lands. The full runtime chain (who writes it, GDM consuming autologin
only from custom.conf keys, the AppArmor grants for the snap-confined
accounts-daemon — landed in the snapd fork's builtin accountsservice
interface, canonical/ubuntu-core-desktop-snapd#46 — and the
/etc/writable copy going stale after the wizard-phase write) is in
gdm-graphical-session.md.

Packaging placement rules for the fix (PR core-base-desktop#92, mount
+ seeding live-verified 2026-11-23): bind
/writable/system-data/etc/gdm3 over /etc/gdm3 (an x-initrd.mount
entry), tmpfiles `C /writable/system-data/etc/gdm3`, and a factory
template for the tree — ALL in the DESKTOP-VARIANT fragments
(variants/desktop/fstab.d/, writable.conf.d/, and the desktop
`dirs+=()` case), NOT the base files: /etc/gdm3 ships only in
variants/desktop/static/etc/gdm3, so a base-level dirs entry fails
`cp -a` under `set -e` on regular/cloud-init builds. It belongs next
to the sibling /var/lib/gdm3 entries already in the desktop fragments.

systemd-tmpfiles `C` (copy_tree_at with
COPY_REFLINK|COPY_MERGE_EMPTY|COPY_HARDLINKS) PRESERVES symlinks
inside the copied tree, so the factory copy of etc/gdm3 keeps its
custom.conf -> ../writable/gdm3/custom.conf symlink intact and it
still resolves through the bind mount on first boot.
