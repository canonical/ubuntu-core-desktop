#!/bin/bash
#
# Builds an Ubuntu Core Desktop (GNOME) disk image with ubuntu-image.
#
# This script deliberately takes every environment/host-specific value
# (test user, SSH keys, model signing-key assertion, and the snaps that
# make up the image) as a parameter rather than hardcoding them, so it
# can be published without leaking anyone's personal details. See
# usage() below for the full parameter list, or run with --help.

set -e

usage() {
    cat <<'EOF'
Usage: build-gnome.sh --model-account-key <path> --base-snap <path> \
           --gadget-snap <path> --snapd-snap <path> \
           --ssh-host-key <path> \
           [--snap <path>]... [options]

Builds build/pc.img (an Ubuntu Core Desktop disk image) using
ubuntu-image.

Required:
  --model-account-key <path>  Account-key assertion for the key that
                              signed the model (see --model). Needed so
                              ubuntu-image can validate the model's
                              signing chain. If you don't have one, you
                              can fetch the account-key assertion that
                              matches your model's "sign-key-sha3-384"
                              header with, e.g.:
                                snap known --remote account-key \
                                  public-key-sha3-384=<sign-key-sha3-384>
  --base-snap <path>          Core base snap to customize (e.g. a
                              core26-desktop build). There is no public
                              place to get this yet.
  --gadget-snap <path>        Gadget snap to customize (e.g. a
                              pc-desktop build). There is no public
                              place to get this yet.
  --snapd-snap <path>         snapd snap, included in the image
                              unmodified. There is no public place to
                              get this yet.
  --ssh-host-key <path>       Private ed25519 key (with matching
                              <path>.pub) baked into the image as its
                              persistent SSH host key, so rebuilt/
                              reflashed VMs keep the same SSH identity
                              instead of a new one every build. Keep
                              this outside the build tree (e.g. under a
                              gitignored dev/ dir) so it survives a
                              `rm -rf build`. Generate one once with:
                                ssh-keygen -t ed25519 -N '' \
                                  -f dev/ssh_host_ed25519_key

Optional:
  --snap <path>               Extra snap to include in the image
                              unmodified. Repeatable, e.g.:
                                --snap ubuntu-desktop-session.snap \
                                --snap ubuntu-desktop-init.snap
  --model <path>              Model assertion JSON to sign and build
                              from (default:
                              ubuntu-core-desktop-26-amd64-dangerous.json)
  --user <name>               Configure a NOPASSWD-sudo test user of
                              this name inside the image (sudoers.d
                              entry). Without this flag no test user is
                              configured (this is the default).
  --ssh-authorized-keys <path> File of SSH public keys (one per line)
                              to install into root's authorized_keys in
                              the image. Without this flag, root has no
                              authorized_keys (password login only).
  --autologin                 Bake in GDM autologin for --user (which
                              becomes required). Without this, the
                              first-boot wizard/login prompt is used.
  --debug                     Verbose kernel/snapd console logging
                              instead of the quiet default.
  -h, --help                  Show this help and exit.
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

orig_args=("$@")

cmdline_extra='systemd.journald.forward_to_console=1 systemd.journald.max_level_console=err console=ttyS0,115200n8'
debug=0
autologin=0
build_user=""
ssh_authorized_keys=""
ssh_host_key=""
model_account_key=""
model_json="ubuntu-core-desktop-26-amd64-dangerous.json"
base_snap=""
gadget_snap=""
snapd_snap=""
extra_snaps=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --debug) debug=1; shift ;;
        --autologin) autologin=1; shift ;;
        --user) build_user="$2"; shift 2 ;;
        --ssh-authorized-keys) ssh_authorized_keys="$2"; shift 2 ;;
        --ssh-host-key) ssh_host_key="$2"; shift 2 ;;
        --model-account-key) model_account_key="$2"; shift 2 ;;
        --model) model_json="$2"; shift 2 ;;
        --base-snap) base_snap="$2"; shift 2 ;;
        --gadget-snap) gadget_snap="$2"; shift 2 ;;
        --snapd-snap) snapd_snap="$2"; shift 2 ;;
        --snap) extra_snaps+=("$2"); shift 2 ;;
        *)
            echo "Unknown flag: ${1}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ${autologin} == 1 && -z ${build_user} ]]; then
    echo "--autologin requires --user <name> to be set." >&2
    exit 1
fi
if [[ -z ${model_account_key} ]]; then
    echo "Missing required --model-account-key <path>." >&2
    echo "See 'build-gnome.sh --help' for how to obtain one." >&2
    exit 1
fi
if [[ -z ${base_snap} ]]; then
    echo "Missing required --base-snap <path>." >&2
    exit 1
fi
if [[ -z ${gadget_snap} ]]; then
    echo "Missing required --gadget-snap <path>." >&2
    exit 1
fi
if [[ -z ${snapd_snap} ]]; then
    echo "Missing required --snapd-snap <path>." >&2
    exit 1
fi
if [[ -z ${ssh_host_key} ]]; then
    echo "Missing required --ssh-host-key <path>." >&2
    echo "This should be a persistent ed25519 private key (with a" >&2
    echo "matching <path>.pub) baked into the image as its SSH host" >&2
    echo "key, so re-flashed/rebuilt VMs keep the same SSH identity" >&2
    echo "instead of your ssh client warning about a changed host key" >&2
    echo "on every rebuild. Generate one once with, e.g.:" >&2
    echo "  ssh-keygen -t ed25519 -N '' -f dev/ssh_host_ed25519_key" >&2
    exit 1
fi
if [[ ! -e "${ssh_host_key}.pub" ]]; then
    echo "File not found: ${ssh_host_key}.pub (--ssh-host-key expects a" >&2
    echo "private key path with a matching '.pub' file alongside it)" >&2
    exit 1
fi
for f in "${model_account_key}" "${base_snap}" "${gadget_snap}" "${snapd_snap}" "${ssh_host_key}" "${model_json}" "${extra_snaps[@]:-}"; do
    if [[ -n "${f}" && ! -e "${f}" ]]; then
        echo "File not found: ${f}" >&2
        exit 1
    fi
done

if [[ -z ${FAKEROOTKEY:-} ]]; then
    exec fakeroot -- "$0" "${orig_args[@]}"
fi

if [[ ${debug} == 1 ]]; then
    cmdline_extra='snapd.debug=1 systemd.log_target=console systemd.journald.forward_to_console=1 console=ttyS0,115200n8'
fi

set -x

BUILD_DIR=build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

rm -rf "${BUILD_DIR}/squashfs-root" "${BUILD_DIR}/gadget.snap"
unsquashfs -d "${BUILD_DIR}/squashfs-root" "${gadget_snap}"
printf '%s\n' "${cmdline_extra}" \
  | tee "${BUILD_DIR}/squashfs-root/cmdline.extra" > /dev/null
# Model base is core26-desktop (built from core-base-desktop), so the
# gadget must declare the same base or ubuntu-image rejects it.
sed -i \
  -e 's/^base: core26$/base: core26-desktop/' \
  -e 's/^base: core24-desktop$/base: core26-desktop/' \
  "${BUILD_DIR}/squashfs-root/meta/snap.yaml"
sed -i 's/listen-address: 127.0.0.1/listen-address: 0.0.0.0/' "${BUILD_DIR}/squashfs-root/meta/gadget.yaml"

# Connect the ubuntu-desktop-session snap's systemd-user-control plug so
# gnome-session-init-worker's systemd --user D-Bus calls are permitted by
# AppArmor (see core-base-desktop/todo-gnome-session.txt). The downloaded
# store gadget snap doesn't ship this connection yet; add it here rather
# than waiting on a new gadget snap release.
if ! grep -q 'plug:.*:systemd-user-control' "${BUILD_DIR}/squashfs-root/meta/gadget.yaml"; then
  if grep -q '^connections:' "${BUILD_DIR}/squashfs-root/meta/gadget.yaml"; then
    sed -i '/^connections:$/a\  - plug: LVkazk0JLrL0ivuHRlv3wp3bK1nAgwtN:systemd-user-control' \
      "${BUILD_DIR}/squashfs-root/meta/gadget.yaml"
  else
    cat >> "${BUILD_DIR}/squashfs-root/meta/gadget.yaml" << 'EOF'

connections:
  - plug: LVkazk0JLrL0ivuHRlv3wp3bK1nAgwtN:systemd-user-control
EOF
  fi
fi
mksquashfs "${BUILD_DIR}/squashfs-root" "${BUILD_DIR}/gadget.snap" -noappend -comp zstd -Xcompression-level 1

rm -rf "${BUILD_DIR}/squashfs-root" "${BUILD_DIR}/custom-core.snap"
unsquashfs -d "${BUILD_DIR}/squashfs-root" "${base_snap}"
# polkit requires this helper to retain its setuid-root bit so graphical
# authentication (for example, installing a snap from App Center) works.
chmod 4755 "${BUILD_DIR}/squashfs-root/usr/lib/polkit-1/polkit-agent-helper-1"
# /etc and /root are entirely writable-paths, seeded at first boot from
# usr/share/factory/writable/system-data/{etc,root} (see the gdm3/sudoers
# handling below) -- so the squashfs's own /etc/ssh and /root/.ssh are
# shadowed at runtime and never take effect unless we also write into the
# factory copies used to seed them.
for etc_ssh_dir in \
  "${BUILD_DIR}/squashfs-root/etc/ssh" \
  "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/ssh"
do
  cp "${ssh_host_key}" "${etc_ssh_dir}/ssh_host_ed25519_key"
  cp "${ssh_host_key}.pub" "${etc_ssh_dir}/ssh_host_ed25519_key.pub"
  # sshd refuses to load a private host key that is group/world readable
  # ("Permissions ... too open"), so the copy must be locked down
  # regardless of the source file's permissions on disk.
  chmod 600 "${etc_ssh_dir}/ssh_host_ed25519_key"
  chmod 644 "${etc_ssh_dir}/ssh_host_ed25519_key.pub"
  tee -a "${etc_ssh_dir}/sshd_config" > /dev/null << 'EOF'
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
EOF
done

for root_home_dir in \
  "${BUILD_DIR}/squashfs-root/root" \
  "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/root"
do
  mkdir -p "${root_home_dir}/.ssh"
  chmod 700 "${root_home_dir}/.ssh"
  if [[ -n ${ssh_authorized_keys} ]]; then
    cp "${ssh_authorized_keys}" "${root_home_dir}/.ssh/authorized_keys"
    chmod 600 "${root_home_dir}/.ssh/authorized_keys"
  fi
done

pw="$(openssl passwd -6 'x')"
usermod --prefix "$(pwd)/${BUILD_DIR}/squashfs-root" --password ${pw} root

# fix the serial console
./fix-console "${BUILD_DIR}/squashfs-root"

for gdm_conf in \
  "${BUILD_DIR}/squashfs-root/etc/writable/gdm3/custom.conf" \
  "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
do
  crudini --set "${gdm_conf}" daemon InitialSetupEnable false
  if [[ ${autologin} == 1 ]]; then
    crudini --set "${gdm_conf}" daemon AutomaticLoginEnable true
    crudini --set "${gdm_conf}" daemon AutomaticLogin "${build_user}"
  fi
done
# /etc is entirely a writable-path, seeded at first boot from
# usr/share/factory/writable/system-data/etc, so the squashfs's own
# /etc/sudoers.d is shadowed at runtime. Write to both, like the gdm3
# custom.conf above, and use the 0440 mode sudoers requires.
if [[ -n ${build_user} ]]; then
  for sudoers_dir in \
    "${BUILD_DIR}/squashfs-root/etc/sudoers.d" \
    "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/sudoers.d"
  do
    tee "${sudoers_dir}/${build_user}" >/dev/null <<EOF
${build_user} ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 0440 "${sudoers_dir}/${build_user}"
  done
fi

# The gadget.yaml static connections are keyed by the *store's* snap-id
# for ubuntu-desktop-session, so none of them ever fire for our locally
# sideloaded (--dangerous) snap, which has no matching snap-id -- not
# just systemd-user-control, but ~24 interfaces the gadget would
# normally auto-connect for a store-published copy of this snap (see
# core-base-desktop/todo-gnome-session.txt and
# notes/todo/20260915-followup-confined-session-apparmor-gaps.txt).
# Work around this by connecting them ourselves on every boot via a
# oneshot systemd unit, independent of snap-id matching. Idempotent:
# `snap connect` is a no-op if already connected, and failure of one
# plug (e.g. its provider snap isn't installed) doesn't stop the rest.
# Written to both the squashfs and its writable-path factory copy, like
# the sudoers/gdm3 files above.
#
# This list was derived by diffing `snap connections ubuntu-desktop-session`
# between a working store-published Core 24 reference VM and this
# locally-sideloaded Core 26 build, and connecting everything the gadget
# connected there that has a locally-installed provider snap. It
# intentionally excludes avahi-control/bluez/cups-control/network-manager,
# whose provider snaps (avahi/bluez/cups/network-manager) aren't
# installed on this image.
for etc_dir in \
  "${BUILD_DIR}/squashfs-root/etc" \
  "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc"
do
  mkdir -p "${etc_dir}/systemd/system/multi-user.target.wants"
  tee "${etc_dir}/ensure-desktop-session-connections.sh" >/dev/null << 'EOF'
#!/bin/bash
# Snap-id-independent workaround: reconnect all interfaces the gadget
# would normally auto-connect for a store-published ubuntu-desktop-session,
# which never fire for our locally sideloaded (--dangerous) copy. See
# comment in go-build-desktop26 for how this list was derived.

# NOTE: interface connections below (particularly snap-store:x11 /
# firefox:x11 -> ubuntu-desktop-session:x11) used to intermittently corrupt
# /tmp/snap-private-tmp/snap.ubuntu-desktop-session's permissions (0700 ->
# 01777), causing snap-confine to die() with "unexpected ownership /
# permissions" and leaving both autologin and manual login stuck at GDM.
# Root cause was a snapd bug: cmd/snap-update-ns's MkPrefix applied the
# mode intended for the leaf of a missing mount-point chain uniformly to
# every intermediate directory it had to create, instead of consulting a
# mode hint per segment. Fixed upstream in ubuntu-core-desktop-snapd on
# branch fix-tmpdir-permissions-bug; snapd26.snap (built from that source)
# now creates these directories with the correct per-segment modes, so no
# workaround is needed here anymore.

for plug in \
  account-control \
  bluetooth-control \
  desktop-launch \
  hardware-observe \
  home \
  hostname-control \
  locale-control \
  login-session-control \
  login-session-observe \
  mount-observe \
  network-control \
  network-observe \
  dot-hidden \
  dot-local-share-nautilus \
  shell-session-locale-files \
  polkit-agent \
  process-control \
  shutdown \
  shell-config-files \
  system-observe \
  systemd-user-control \
  time-control \
  timeserver-control \
  timezone-control \
  upower-observe
do
  # snapd only processes one "connect-snap" change at a time; at boot it
  # may still be busy with its own seeding/auto-connect tasks, so a
  # `snap connect` issued here can transiently fail with "has
  # \"connect-snap\" change in progress" even though `snap connect`
  # normally blocks until its own change completes. Retry a few times
  # with a short backoff so a single boot-time race doesn't leave a
  # plug permanently unconnected until someone notices and reruns this
  # by hand.
  for attempt in 1 2 3 4 5; do
    if snap connect "ubuntu-desktop-session:${plug}"; then
      break
    fi
    sleep 3
  done
done

# Snap Store 2/stable uses the Core 24 GNOME platform and needs explicit
# desktop-session slots when the custom gadget does not provide its usual
# static connections.
#
# App Center-installed apps (e.g. firefox) need the same treatment: the
# wayland/x11/desktop interfaces are snap-provided slots on
# ubuntu-desktop-session here (not implicit system slots), so snapd does
# not auto-connect them for arbitrary store snaps the way a stock Ubuntu
# Desktop host would. Without an explicit connection, an app launches but
# is denied access to the display and silently exits (AppArmor DENIED on
# connect to $XDG_RUNTIME_DIR/wayland-0), which looks like "nothing
# happens" when clicking Open in App Center. This loop only covers
# firefox as the currently-tested reference app; any other store app will
# hit the same silent failure until it is connected too -- the general
# fix belongs in snapd/App Center (auto-connect on install), not here.
#
# gnome-terminal-server's wayland-client plug is a same-snap connection
# (ubuntu-desktop-session:wayland-client -> ubuntu-desktop-session:wayland).
# The single-arg `snap connect ubuntu-desktop-session:wayland-client` form
# used in the loop above does NOT work for this: snapd's auto-resolution
# does not pick the plugging snap's own slot, and instead tried to resolve
# against the "snapd" pseudo-snap ("error: snap \"snapd\" has no \"wayland\"
# interface slots"), so this needs the explicit two-sided form like the
# snap-store/firefox connections below.
for connection in \
  "snap-store:desktop ubuntu-desktop-session:desktop" \
  "snap-store:wayland ubuntu-desktop-session:wayland" \
  "snap-store:x11 ubuntu-desktop-session:x11" \
  "firefox:desktop ubuntu-desktop-session:desktop" \
  "firefox:wayland ubuntu-desktop-session:wayland" \
  "firefox:x11 ubuntu-desktop-session:x11" \
  "ubuntu-desktop-session:wayland-client ubuntu-desktop-session:wayland"
do
  plug_snap="${connection%%:*}"
  # Skip entirely (no retries/backoff) if the plug side's snap isn't
  # even installed on this image (e.g. firefox/snap-store are optional
  # App-Center installs, not guaranteed present) -- retrying a
  # guaranteed-permanent "not installed" failure 5x with a 3s backoff
  # each just adds dead time (up to ~75s for all three firefox
  # connections) to every single boot, delaying GDM (see the
  # gdm.service.d wait-for-this-unit drop-in below) for no benefit.
  if [ "${plug_snap}" != "ubuntu-desktop-session" ] && ! snap list "${plug_snap}" >/dev/null 2>&1; then
    continue
  fi
  for attempt in 1 2 3 4 5; do
    if snap connect ${connection}; then
      break
    fi
    sleep 3
  done
done
EOF
  chmod 0755 "${etc_dir}/ensure-desktop-session-connections.sh"
  tee "${etc_dir}/systemd/system/ensure-desktop-session-connections.service" >/dev/null << 'EOF'
[Unit]
Description=Connect ubuntu-desktop-session interfaces (snap-id-independent workaround)
After=snapd.service snapd.seeded.service
Wants=snapd.service snapd.seeded.service

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/ensure-desktop-session-connections.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  ln -sf ../ensure-desktop-session-connections.service \
    "${etc_dir}/systemd/system/multi-user.target.wants/ensure-desktop-session-connections.service"

  # Make GDM wait for the interface-connection workaround above to
  # finish before it starts (and therefore before it can accept any
  # login). Without this, GDM can let a user log in while
  # ensure-desktop-session-connections.service is still mid-flight,
  # so ubuntu-desktop-session's AppArmor profile is only partially
  # updated (interfaces connect one at a time, each triggering a
  # profile reload) -- observed to deny gnome-session-service's write
  # to its systemd notify socket, which makes
  # gnome-session-manager@ubuntu.service hang for the full
  # StartupTimeoutSec (90s) and then get killed, and GDM report
  # "Session never registered, failing": the "grey screen after
  # password entry, logs back out" bug. A second login attempt after
  # the loop has finished works immediately because the profile is by
  # then complete. See
  # notes/done/20260917-post-login-grey-screen-gnome-session-timeout.txt.
  mkdir -p "${etc_dir}/systemd/system/gdm.service.d"
  tee "${etc_dir}/systemd/system/gdm.service.d/99-wait-for-session-connections.conf" >/dev/null << 'EOF'
[Unit]
After=ensure-desktop-session-connections.service
Wants=ensure-desktop-session-connections.service
EOF
done

# --autologin: bake a permanent, build-time equivalent of the
# tools/confined-autologin-test.sh runtime shim. GDM's autologin path
# unconditionally execs the literal `gnome-session` binary on PATH and
# does NOT consult AccountsService's Session= key or any .desktop file
# (see notes/library/gdm-graphical-session.txt), so without this,
# autologin would launch the plain unconfined upstream gnome-session
# instead of the confined ubuntu-desktop-session. The username check
# is required because GDM's own greeter also execs plain gnome-session
# and must not be intercepted. Real (password-prompt) logins are
# unaffected: they go through the confined snap's own run-session.sh,
# never through this base-snap /usr/bin/gnome-session.
#
# The $SNAP_NAME check is required to avoid an infinite-loop-shaped bug:
# the confined ubuntu-desktop-session snap's own run-session.sh ends by
# calling plain `gnome-session` again to actually launch the session -
# and since this shim intercepts *every* invocation of that path, that
# internal, already-confined call would otherwise re-enter the wrapper
# and re-invoke `snap run ubuntu-desktop-session` a second time, this
# time from inside its own confinement. That second, confined `snap run`
# cannot read /sys/kernel/security/apparmor/features or
# /var/lib/snapd/system-key (AppArmor denies it), so its client-computed
# system-key comes back empty and is reported to snapd as a mismatch,
# triggering a security-profile regeneration (including snap-confine's
# own profile) concurrently with the still-launching session, which
# kills it ("cannot join mount namespace of pid 1") - see
# notes/todo/20260917-autologin-confined-session-timeout.txt for the
# full root-cause chain. $SNAP_NAME is set for every confined process,
# so checking it lets the internal call through to the real binary
# instead of looping back through the wrapper.
if [[ ${autologin} == 1 ]]; then
  mv "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session" "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session.real"
  tee "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session" > /dev/null << EOF
#!/bin/sh
if [ -n "\$SNAP_NAME" ]; then
  exec /usr/bin/gnome-session.real "\$@"
elif [ "\$(id -un)" = "${build_user}" ]; then
  exec /usr/bin/core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME
else
  exec /usr/bin/gnome-session.real "\$@"
fi
EOF
  chmod 0755 "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session"
fi

mksquashfs "${BUILD_DIR}/squashfs-root" "${BUILD_DIR}/custom-core.snap" -noappend -comp zstd -Xcompression-level 1
rm -rf "${BUILD_DIR}/squashfs-root"

# Sign the model assertion (see --model) with the local "test" brand key
# so ubuntu-image can build a --dangerous image from it. Override the
# signing key with the SNAP_SIGN_KEY environment variable if you have
# your own registered key.
snap sign -k "${SNAP_SIGN_KEY:-test}" --update-timestamp "${model_json}" \
  > "${BUILD_DIR}/$(basename "${model_json}" .json).model"

snap_args=(
  --snap "${BUILD_DIR}/custom-core.snap"
  --snap "${BUILD_DIR}/gadget.snap"
  --snap "${snapd_snap}"
)
for extra_snap in "${extra_snaps[@]:-}"; do
  [[ -n ${extra_snap} ]] && snap_args+=(--snap "${extra_snap}")
done

ubuntu-image snap -v \
  --assertion "${model_account_key}" \
  --validation=ignore \
  --output-dir "${BUILD_DIR}" \
  --image-size 20G \
  "${snap_args[@]}" \
  "${BUILD_DIR}/$(basename "${model_json}" .json).model"

if [[ -z ${build_user} ]]; then
  touch "${BUILD_DIR}/pc.img.nouser"
fi

echo "Built ${BUILD_DIR}/pc.img"

