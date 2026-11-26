# Fix autologin setup broken by the move to the thin build

## Impact / Priority

Automatic-login setup was broken by the move to the thin build: an
image build seeded with a user (--user) died outright in build.sh's
crudini step (the thin base ships no /etc/writable/gdm3/custom.conf),
so no user-seeded thin build could complete at all. The goal was to
restore automatic login without reverting or damaging the thin build.
No priority stated in the original note. Impact derived from the
original note's described symptoms.

A plain image build for GNOME failed:

    ┃  + for gdm_conf in "${BUILD_DIR}/squashfs-root/etc/writable/gdm3/custom.conf"
    ┃  "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/
    ┃  writable/gdm3/custom.conf"
    ┃  + [[ -n your_username ]]
    ┃  + crudini --set build/squashfs-root/etc/writable/gdm3/custom.conf daemon
    ┃  InitialSetupEnable false
    ┃  [Errno 2] No such file or directory: 'build/squashfs-root/etc/writable/gdm3/
    ┃  custom.conf

Explanation:

- `+ [[ -n your_username ]]` — a plain personal-defaults image build
  for GNOME runs with the build wrapper's defaults (--user
  your_username + autologin), so the crudini block executes
- crudini then fails: the thin base ships no
  /etc/writable/gdm3/custom.conf — every previous thin bake used the
  nouser path, where both crudini conditionals are false and this
  block never executes. This invocation was the first thin+--user
  build ever run, exposing it
- With set -e, that's fatal — the build died there. So there were two
  stacked breaks: (1) the a11y guard (fixed), (2) this thin+user
  crudini gap (pre-existing, newly exposed)

## Update 2026-11-12 (fix applied)

- build.sh's gdm_conf loop now seeds the stock Debian custom.conf
  (mkdir -p + heredoc, byte-identical to the desktop variant's 447-byte
  file) when the base omits it, before crudini runs. Existing files are
  still edited in place (crudini preserves comments); verified both
  paths by replaying the loop against a fake tree.
- CAVEAT for the local build: the crudini gap only bites because the
  local core.snap was rebuilt today as the cloud-init variant, which
  ships NO desktop payload at all (no gdm.service, no
  /etc/gdm3/custom.conf symlink, no gdm-* PAM stacks, no gdm sysusers).
  The thin desktop-variant base (CI's desktop-26-thin-latest) ships all
  of those plus etc/writable/gdm3/custom.conf in both trees, so the fix
  is a no-op there. For automatic login to actually FUNCTION on a local
  thin build, the base must be the desktop variant - rebuild
  core-base-desktop with SNAP_BUILD_VARIANT=desktop (or restore the
  desktop-variant core.snap). The core-base-desktop snap build pinned
  SNAP_BUILD_VARIANT=cloud-init at the time (for cloud-init images), so
  this is a deliberate choice to make, not a mechanical revert.

## Resolution (2026-11-12, same day)

- The deliberate choice was made: the cloud-init flow no longer exists
  (build.sh --user is factory-seeded extrausers, no cloud-init, no
  seed.iso, pc.img.nouser always dropped), so the core-base-desktop
  snap build now pins SNAP_BUILD_VARIANT=desktop by default
  (env-overridable) instead of cloud-init. The thin build is
  untouched — the desktop variant IS the thin desktop variant.
- build.sh custom.conf seeding fix committed as 8837907 ("build.sh:
  seed the stock custom.conf when the base omits it"); the provider-
  snap error hint landed as de923d6.
- Rebuilt core.snap (20261112+desktop), rebuilt the image with a GNOME
  user build, booted it, and verified autologin end-to-end on the
  run-mode boot: gdm active, gdm-autologin PAM session opened for
  your_username, your_username user session on seat0,
  /run/user/1000/wayland-0 -> snap.ubuntu-desktop-session/wayland-0,
  gnome-shell label snap.ubuntu-desktop-session.gnome-shell (enforce),
  gnome-session-manager@ubuntu + org.gnome.Shell@ubuntu active, 15
  gsd-* daemons up, zero "GDM service failed to initiate" warnings
  from provd. Remaining unrelated noise: bluetoothd rfkill (no BT in
  VM), /dev/sr0 (no seed cdrom by design), localsearch-3 EXEC failure
  (known tracker/indexer gap, separate issue).
