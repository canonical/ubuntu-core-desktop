# First-boot installer never starts: provd socket path disagreement

Date: 2026-11-24

## Impact / Priority

Priority: HIGH. This is a hard brick of the only end-user install path.

A user booting the published GNOME image (build 2026-11-24T17:05:27Z,
commit 70479ee, provd.snap 0.1.5+t26handover) sees the first-boot
seeding splash for ~90s, then a plain GNOME "initial-setup" shell with
no wallpaper, no dock and NO WIZARD WINDOW. There is no other way in:
a nouser build has no baked account, no root password and no SSH keys,
so sshd refuses everyone (root and any user), and the console getty
has no usable account either. The image cannot be provisioned or used
at all.

This was reproduced end-to-end by the reporter on a real boot of the
downloaded artifact (not inferred from logs alone): journal of boot
aa4288c0 (test VM, 2026-11-24 17:56:40Z) shows the wizard unit waiting
and provd failing 6x, then giving up.

It was working before: the 2026-11-21 image (provd 0.1.5, built from
the resolute deb) and everything published before 2026-11-23 20:39Z is
consistent. The regression is a snap release, not the image build
logic.

## Status

FIXED 2026-11-24. Verified end to end on a local nouser boot (wizard
completed, user created, a11y handover recorded) and the published
GNOME image was rebuilt from the corrected snaps the same day.

## Fixes, all pushed and published

    canonical/provd-snap            main       dce0812
        provd-run system-files grant -> /run/gdm3/home/gnome-initial-setup
        (plus the two comments that still described the old path)
    chris-bainbridge/ubuntu-desktop-provision
                                    desktop/26 412b6d77d
        UI socket address, provd_chown_client comment/test, and the snap's
        own run-provd-socket grant. Content of upstream dd93e84ce's UI
        half only (see "no cherry-pick" below).
    canonical/core-base-desktop     desktop/26 2770945
        unit waits on $HOME/desktop-provision/init.socket, old
        tmpfiles.d/gnome-initial-setup.conf deleted,
        ExecStartPre=/usr/bin/mkdir -p %h/desktop-provision added to
        70-wizard-only.conf.

## Published image (gnome-latest, built 2026-11-24T22:00Z, run 45489871995)

    core26-desktop-variant 20261124+desktop
    provd 0.1.5+t26handover
    ubuntu-desktop-init 0+git.412b6d7
    (provd's version is stamped in the part and did NOT change with the
    plug fix, so the manifest cannot tell the fixed build from the broken
    one by version - the 22:00Z build is the fixed one.)

## Verification performed

- Local image built from the three rebuilt snaps, booted as nouser:
  provd served gRPC on the new path, ubuntu_init connected (established
  socket), zero "Start request repeated too quickly", session home
  /run/gdm3/home/gnome-initial-setup created by GDM, old
  /run/gnome-initial-setup gone. Wizard completed: account
  your_username created and logged in; /etc/dconf/channel/handover has
  ucd-handover-user=your_username and the wizard's a11y
  ucd-handover.ini, so the a11y handover work survived (the reason the
  old-provd pin was rejected).
- Four/five-way consistency check on the downloaded desktop-26-latest
  assets, amd64 and arm64: base unit, provd binary, provd plug, UI
  binary, UI plug all name the same socket. The script used is
  appended below, ready to adapt into the CI guard.
- CI: all three snap publishes green; the first image run failed the
  amd64 boot gate (snapd.seeded.service sat running for 13 min, twice,
  with KVM available, GDM and graphical.target queued behind it) and
  passed on rerun. That is the long-known flaky gate, not this fix:
  the same snap set seeds in ~90 s locally. arm64 published on the
  first run.

## Corrections and additions to the analysis below

1. The local `desktop/26` ref was NOT what CI builds: it pointed at
   75316ad85, 145 commits behind origin/desktop/26 (2c86af009, which is
   the commit the published UI snap's version 0+git.2c86af0 refers to).
   The branch also merged upstream/main at c04ce8f65. Fast-forward the
   local ref before committing on it, or the UI snap is built from a
   year-old tree.
2. There is a FIFTH hardcoded path, not in the four-way list below: the
   UI snap's own `run-provd-socket` system-files write plug in
   snap/snapcraft.yaml (packaging branch only; dd93e84ce could not touch
   it because snap/snapcraft.yaml does not exist upstream). It is
   unconnected on this image and the UI is raw-exec'd unconfined, so it
   is currently inert, but it was updated for consistency.
3. No cherry-pick is needed or wanted. dd93e84ce touches 9 files; the
   provd/, debian/launch-desktop-provision-init and ci.yml hunks do not
   apply to this snap (the daemon is packaged by the provd snap, built
   from core26-provd, and ci.yml only runs for main/ubuntu/** bases).
   Copying the three UI file contents plus the plug keeps a later merge
   of upstream/main a no-op for those files.
4. The "immediate unblock" pin is viable but was rejected (it drops the
   a11y handover + DeleteUser fixes, which is why ad86406 exists). Note
   for the record: the local cache copy named below had already been
   overwritten by `build-snaps.sh sync`, and canonical/provd-snap has
   only the rolling desktop-26-latest tag (asset clobbered), so CI could
   not pin it without publishing the blob somewhere. One copy of the old
   deb-built snap did survive from an earlier introspection task
   (15,171,584 B, provd 0.1.5, old socket + old plug; sha256
   b7f8c7d3..., i.e. re-squashed, not byte-identical to the note's
   c57f8365...). That was scratch and may be gone; it was not needed
   once the pin was rejected.
5. The tmpfiles.d deletion is sufficient: that file was the only copy.
   The thin core26 base ships no gnome-initial-setup files; the variant
   payload provides them (verified in the built snap).
6. The CI guard from the Verification section is NOT implemented yet;
   it remains a follow-up.

## Remaining follow-ups (none blocking)

- Add the consistency guard to build-image.yaml after "Download snap
  inputs" (five strings now: base unit, provd binary, provd plug, UI
  binary, UI plug), or a wizard-covering gate driven from the serial
  console. The existing gate builds --user gate --autologin and skips
  the wizard entirely, which is how this drift shipped.
- Refresh desktop/26 onto upstream/main (23 commits behind, including
  user-visible keyboard/mesh-WiFi/Wayland/Impeller fixes). The merge
  deletes .tool-versions (FVM, 6eb0470a5) and the snap's flutter-git
  part reads it, so the part needs to read .fvmrc first.
- Report upstream that provd should create its own socket directory
  before bind: dd93e84ce still relies on the deb launcher's mkdir, and
  the snap execs the daemon directly (the base has to pre-create it).
- `build-snap.sh`'s snap pickup uses `find` without `-H`, so a
  symlinked local-sources/<component> builds but is then reported as
  "built without producing a .snap". Real worktrees or clone avoid it.
- Pre-existing journal noise seen while verifying: gnome-keyring-daemon
  inheriting provd's confinement and being denied the session bus;
  missing /usr/share/gnome-initial-setup/initial-setup-dconf-defaults
  (provd "degraded performance" warning); ubuntu_init can't log to
  /var/log/installer because the directory does not exist.

## Root cause

Three components independently hardcode the provd gRPC socket path and
now disagree:

  1. provd.snap 0.1.5+t26handover (NEW):
     binds /run/gdm3/home/gnome-initial-setup/desktop-provision/init.socket
     (upstream ubuntu-desktop-provision commit dd93e84ce, "move provd
     socket to /run/gdm3/home/gnome-initial-setup", 2026-11-12).

  2. core26-desktop-variant.snap 20261123+desktop (OLD):
     variants/desktop/static/usr/lib/systemd/user/gnome-initial-setup.service
     does `mkdir -p /run/gnome-initial-setup/desktop-provision` and then
     `until [ -S /run/gnome-initial-setup/desktop-provision/init.socket ]`,
     so the Flutter UI (/snap/ubuntu-desktop-init/current/bin/ubuntu_init)
     is NEVER exec'd.

  3. ubuntu-desktop-init.snap 0+git.2c86af0 (OLD):
     the Dart UI (apps/ubuntu_init/lib/services/provd_address.dart and
     packages/provd_client) still dials the old
     /run/gnome-initial-setup/desktop-provision/init.socket.

  4. provd-snap's own confinement grant is also OLD: the strict snap's
     `provd-run` system-files plug writes to /run/gnome-initial-setup
     only. The generated profile on the image contains exactly
     "/run/gnome-initial-setup{,/,/**}" rwkl and nothing under
     /run/gdm3/home. So even with the directory created, provd would
     fail with EACCES (the current failure is ENOENT only because the
     parent directory does not exist).

Why it broke on 2026-11-23: canonical/provd-snap commit ad86406
("Build provd from the pinned source in CI and local packs", 20:17Z)
switched the snap from staging the universe provd 0.1.5 deb to building
provd from chris-bainbridge/ubuntu-desktop-provision@core26-provd
(fb2d845b2), to pick up the a11y-handover and DeleteUser fixes. That
branch also contains dd93e84ce, so the socket moved in that rebuild.
provd.snap (0.1.5+t26handover) was uploaded to the desktop-26-latest
release at 2026-11-23T20:39Z. The base (2026-11-23T16:30Z) and the UI
snap (2026-11-21T10:25Z) were not rebuilt, and today's image is the
first build to consume the new provd.

## Evidence (journal of the reported boot)

    provd.provd: ERROR can't create daemon: listen unix
    /run/gdm3/home/gnome-initial-setup/desktop-provision/init.socket:
    bind: no such file or directory          (17:58:11 .. 17:58:13, 6x)
    systemd: snap.provd.provd.service: Start request repeated too quickly
    systemd: Started gnome-initial-setup.service (17:58:16) then silence;
    zero ubuntu_init output in the whole boot.

The 90s before GDM (17:56:46 -> 17:58:10) is ordinary first-boot
seeding (core.start-snapd + snapd.seeded), not part of this bug.

Note the image is unSSHable, so this was introspected read-only from
the live disk: `dd` the ubuntu-data partition (offset from `sfdisk -d`)
to a scratch file, `debugfs -R rdump /system-data/var/log/journal`,
then `journalctl --file=...`. /etc is a tmpfs overlay while running, so
accounts created by GDM do not show up offline.

## Fix (new path everywhere - matches upstream stonking layout)

No single component change works; all four must agree. There is no
ordering that avoids broken images in between (base-new + UI-old hangs
at the socket connect; base-old + UI-new hangs on the wait loop), so
publish provd-snap, then ubuntu-desktop-init, then core-base-desktop,
then rebuild an image.

A. core-base-desktop, branch desktop/26
   variants/desktop/static/usr/lib/systemd/user/gnome-initial-setup.service
   - In ExecStart use the session home instead of the old tree, e.g.
     `mkdir -p "$$HOME/desktop-provision" "$$HOME/.cache"; until [ -S
     "$$HOME/desktop-provision/init.socket" ]; do sleep 1; done; exec ...`
     ($$HOME is already used there for XDG_CONFIG_HOME), or %h/...
     systemd specifiers. Update the unit comment.
   variants/desktop/static/usr/lib/tmpfiles.d/gnome-initial-setup.conf
   - Delete it (both `d /run/gnome-initial-setup...` lines): nothing
     else uses that tree once the unit moves, and the new parent
     (/run/gdm3/home/<session>) is created by GDM, not tmpfiles.
     Check `grep -rn /run/gnome-initial-setup` before deleting.

   variants/desktop/static/etc/systemd/user/
   snap.provd.provd.service.d/70-wizard-only.conf
   - Add `ExecStartPre=/usr/bin/mkdir -p %h/desktop-provision`.
     provd (user-scope daemon) starts BEFORE gnome-initial-setup.service
     on this boot (17:58:11 vs 17:58:16), so the unit's own mkdir is too
     late; without this, provd can burn its 5-restart start limit again
     even after the path is fixed.

B. canonical/provd-snap, main
   snap/snapcraft.yaml, plugs.provd-run.write
   - Change `/run/gnome-initial-setup` to
     `/run/gdm3/home/gnome-initial-setup` (or list both during the
     transition). system-files paths must be literal; the session
     account is the fixed name gnome-initial-setup with home
     /run/gdm3/home/gnome-initial-setup (verified on the image), so a
     literal path is correct. The plug auto-connects on this unasserted
     dangerous image (the generated profile proves it), so no gadget
     change is needed.
   - Rebuild/publish / repack the image with the new snap.
   - Separately, report upstream that provd should create its own
     socket directory before bind: the deb's
     launch-desktop-provision-init does
     `mkdir -p "$GIS_DIR/desktop-provision"`, but the snap daemon
     execs provd directly, so the snap depends on the base. This is
     what made the path move break silently.

C. chris-bainbridge/ubuntu-desktop-provision, branch desktop/26
   (this is what CI builds ubuntu-desktop-init.snap from; the branch
   does NOT contain dd93e84ce, only core26-provd/main do)
   - Cherry-pick dd93e84ce, or at minimum apply the two real changes:
     apps/ubuntu_init/lib/services/provd_address.dart and
     packages/provd_client/lib/src/provd_chown_client.dart (+ its test)
     to the new socket path; drop/skip the ci.yml and debian launcher
     hunks if they conflict (this variant does not use the launcher).
   - Push so the desktop-26-latest ubuntu-desktop-init.snap is rebuilt.

## Verification

- Rebuild the image from the updated snaps and boot a nouser image for
  real: after ~2min the wizard window must appear (ubuntu_init process
  and /run/gdm3/home/gnome-initial-setup/desktop-provision/init.socket
  present, no provd restarts in the journal). Complete the wizard,
  log in, confirm the desktop.
- Quick offline check of a built image (same technique as above): in
  the seed, `unsquashfs -cat` the base snap's unit, `strings` provd's
  /usr/libexec/provd and ubuntu-desktop-init's bin/lib/libapp.so, and
  the provd snap's meta/snap.yaml provd-run path - all four must name
  the same socket path.
- Cheap CI guard (ubuntu-core-desktop/.github/workflows/build-image.yaml,
  after "Download snap inputs"): extract those same four strings from
  the downloaded snaps and fail the job if they disagree. This exact
  three-way drift passed every existing check; the boot gate cannot
  catch it because it builds a throwaway image with `--user gate
  --autologin`, which skips the wizard entirely. A wizard-covering gate
  (boot the real nouser image and assert ubuntu_init/init.socket) would
  be better, but needs a non-SSH observation path (serial log).

## Immediate unblock (if a working image is needed before the full fix)

Pin the previous provd snap in the image build: the deb-built
provd_0.1.5 (old socket path, sha256:c57f8365...) is still in
ubuntu-core-desktop/snaps/provd.snap and matches both the current base
unit and the current UI snap. Costs the a11y-handover and DeleteUser
fixes.

## References

- upstream: canonical/ubuntu-desktop-provision dd93e84ce (socket move)
- provd-snap: ad86406 (source build switch), release desktop-26-latest
  provd.snap uploaded 2026-11-23T20:39Z
- core-base-desktop: unit unchanged since 378595c; tmpfiles creates
  only /run/gnome-initial-setup*
- related older issue:
  `20260916-provd-stale-desktop-provision-dir-blocks-gdm-restart.md`
  (same directory/ownership family, different bug: EACCES from a
  stale uid-owned dir, not the path move)

## Appendix: socket-path consistency check used for verification

Run against a directory holding the downloaded assets (or a local
snaps/ cache) named as the image workflow names them; exits non-zero on
any mismatch. Adapting this into build-image.yaml after "Download snap
inputs" is the cheap guard proposed above.

```bash
#!/bin/bash
# Offline four-way check of the wizard socket path in a built snap set.
# Usage: check-snaps.sh [snaps-dir]
set -u

dir="${1:-snaps}"
want=/run/gdm3/home/gnome-initial-setup/desktop-provision/init.socket
fail=0

check() {
    local label=$1 value=$2
    if [[ ${value} == "${want}" ]]; then
        printf '  OK   %-34s %s\n' "${label}" "${value}"
    else
        printf '  FAIL %-34s %s\n' "${label}" "${value:-<missing>}"
        fail=1
    fi
}

echo "== base unit (core26-desktop-variant.snap)"
unit=$(unsquashfs -cat "${dir}/core26-desktop-variant.snap" \
    usr/lib/systemd/user/gnome-initial-setup.service 2>/dev/null)
if grep -q 'until \[ -S "\$\$HOME/desktop-provision/init.socket" \]' <<<"${unit}"; then
    echo "  OK   unit waits for                     \$HOME/desktop-provision/init.socket"
else
    echo "  FAIL unit does not wait on \$HOME/desktop-provision/init.socket"; fail=1
fi
if grep -q '/run/gnome-initial-setup' <<<"${unit}"; then
    echo "  FAIL unit still references the old tree"; fail=1
else
    echo "  OK   unit has no old-tree reference"
fi
if unsquashfs -l "${dir}/core26-desktop-variant.snap" 2>/dev/null |
   grep -q 'usr/lib/tmpfiles.d/gnome-initial-setup.conf'; then
    echo "  FAIL old tmpfiles.d entry still shipped"; fail=1
else
    echo "  OK   old tmpfiles.d entry gone"
fi
dropin=$(unsquashfs -cat "${dir}/core26-desktop-variant.snap" \
    etc/systemd/user/snap.provd.provd.service.d/70-wizard-only.conf 2>/dev/null)
if grep -q 'ExecStartPre=/usr/bin/mkdir -p %h/desktop-provision' <<<"${dropin}"; then
    echo "  OK   provd drop-in pre-creates the directory"
else
    echo "  FAIL provd drop-in ExecStartPre missing"; fail=1
fi

echo "== provd binary + plug (provd.snap)"
check "provd binary binds" "$(unsquashfs -cat "${dir}/provd.snap" usr/libexec/provd 2>/dev/null |
    strings | grep -o '/run/[a-z0-9/._-]*init.socket' | sort -u)"
grant=$(unsquashfs -cat "${dir}/provd.snap" meta/snap.yaml 2>/dev/null |
    sed -n '/provd-run:/,/^  [a-z]/p' | grep -o '/run/[a-z0-9/._-]*')
if [[ ${grant} == /run/gdm3/home/gnome-initial-setup ]]; then
    echo "  OK   provd-run grant                    ${grant}"
else
    echo "  FAIL provd-run grant                    ${grant:-<missing>}"; fail=1
fi

echo "== UI binary + plug (ubuntu-desktop-init.snap)"
check "UI dials" "$(unsquashfs -cat "${dir}/ubuntu-desktop-init.snap" bin/lib/libapp.so 2>/dev/null |
    strings | grep -o '/run/[a-z0-9/._-]*init.socket' | sort -u)"
check "UI run-provd-socket grant" "$(unsquashfs -cat "${dir}/ubuntu-desktop-init.snap" meta/snap.yaml 2>/dev/null |
    grep -o '/run/[a-z0-9/._-]*init.socket' | sort -u)"

echo
if [[ ${fail} == 0 ]]; then echo "ALL CONSISTENT: ${want}"; else echo "INCONSISTENT (see FAIL above)"; fi
exit "${fail}"
```
