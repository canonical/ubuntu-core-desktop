#!/bin/bash
#
# Builds an Ubuntu Core Desktop (GNOME or KDE) disk image with
# ubuntu-image.
#
# This script deliberately takes every environment/host-specific value
# (test user, SSH keys, model signing-key assertion, and the snaps that
# make up the image) as a parameter rather than hardcoding them, so it
# can be published without leaking anyone's personal details. See
# usage() below for the full parameter list, or run with --help.
#
# GNOME and KDE share the same overall flow (unsquash/patch the gadget
# and base snaps, inject SSH keys, sign the model, run ubuntu-image);
# the handful of steps that genuinely differ between them (which
# gadget.yaml connections to add, which session-snap interfaces to
# auto-connect at boot, and which session command --autologin should
# launch) live in the desktop_* functions below, selected by --desktop.

set -e

usage() {
    cat <<'EOF'
Usage: build.sh --desktop gnome|kde --model-account-key <path> \
           --base-snap <path> --gadget-snap <path> --snapd-snap <path> \
           --ssh-host-key <path> \
           [--snap <path>]... [options]

Builds build/pc.img (an Ubuntu Core Desktop disk image) using
ubuntu-image. If --user is given, also builds build/seed.iso (a
cloud-init NoCloud seed -- see build-cloud-init.sh --help) that creates
that login account at first boot; attach it as a cdrom drive when
booting the image. Without --user, no seed.iso is built and
build/pc.img.nouser is dropped instead, so a boot script can tell not
to attach one.

Required:
  --desktop gnome|kde         Which desktop session this image is for.
                              Selects the session snap's interface
                              auto-connections and the --autologin
                              session command; everything else is
                              identical between the two.
  --password <password>      Root's login password, baked into the
                              image (as a SHA-512 crypt hash via
                              openssl passwd). Also used as --user's
                              password (if --user is given) via the
                              seed.iso build-cloud-init.sh generates --
                              see --user below. No default, so no
                              password ends up hardcoded in this
                              script.
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
                              ubuntu-core-desktop-26-amd64-dangerous.json
                              for --desktop gnome,
                              ubuntu-core-desktop-kde-26-amd64-dangerous.json
                              for --desktop kde)
  --user <name>                Configure a NOPASSWD-sudo login account
                              of this name inside the image (sudoers.d
                              entry), distinct from whatever account is
                              running this script, and build a
                              build/seed.iso (see build-cloud-init.sh)
                              that creates that account (with
                              --password and --ssh-authorized-keys,
                              if given) via cloud-init at first boot.
                              Without this flag no login account is
                              configured and no seed.iso is built (this
                              is the default).
  --ssh-authorized-keys <path> File of SSH public keys (one per line)
                              to install into root's authorized_keys in
                              the image, and (if --user is also given)
                              into --user's via the seed.iso above.
                              Without this flag, neither has
                              authorized_keys (password login only).
  --autologin                 Bake in GDM autologin for --user (which
                              becomes required). Without this, the
                              first-boot wizard/login prompt is used.
  --debug                     Verbose kernel/snapd console logging
                              instead of the quiet default.
  -h, --help                  Show this help and exit.
EOF
}

# --- Desktop-specific pieces -----------------------------------------
#
# Everything else in this script is identical between GNOME and KDE.
# The gadget connection functions are selected by --desktop and each is
# called once with the extracted gadget snap's gadget.yaml.

# Patch squashfs-root/meta/gadget.yaml so the session snap's plugs get
# their connections during image seeding. Both desktops use snap-name
# endpoints for locally built snaps without a SnapID, while retaining
# store-ID references for asserted system providers.
gnome_gadget_connections() {
    local gadget_yaml="$1"
    local sid=LVkazk0JLrL0ivuHRlv3wp3bK1nAgwtN
    if ! grep -q '^connections:' "${gadget_yaml}"; then
        printf '\nconnections:\n' >> "${gadget_yaml}"
    fi
    python3 - "${gadget_yaml}" "${sid}" <<'PYEOF'
import sys

path, sid = sys.argv[1], sys.argv[2]
session = "ubuntu-desktop-session"
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

simple_plugs = [
    "account-control", "bluetooth-control", "desktop-launch", "fuse-device",
    "hardware-observe", "home", "hostname-control", "locale-control",
    "login-session-control", "login-session-observe", "mount-observe",
    "network-control", "network-observe", "polkit-agent",
    "process-control", "shutdown", "system-observe", "systemd-user-control",
    "time-control", "timeserver-control", "timezone-control", "upower-observe",
    "systemd-user-environment",
]

connections = [(f"{session}:{plug}", f"system:{plug}") for plug in simple_plugs]
connections.append((f"{session}:shell-config-files", "system:system-files"))
connections.append((f"{session}:user-dirs-defaults", "system:system-files"))
connections.extend([
    (f"{session}:network-manager", "RmBXKl6HO6YOC2DE4G2q1JzWImC04EUy:service"),
    (f"{session}:bluez", "JmzJi9kQvHUWddZ32PDJpBRXUpGRxvNS:service"),
    (f"{session}:dbus-portal-desktop",
     f"{session}:dbus-freedesktop-portal-desktop"),
    (f"{session}:dbus-portal-documents",
     f"{session}:dbus-freedesktop-portal-documents"),
    (f"{session}:dbus-portal-tracker",
     f"{session}:dbus-freedesktop-portal-tracker"),
    (f"{session}:dbus-portal-impl-gnome",
     f"{session}:dbus-freedesktop-impl-portal-gnome"),
    (f"{session}:dbus-portal-impl-gtk",
     f"{session}:dbus-freedesktop-impl-portal-gtk"),
    (f"{session}:dbus-portal-permission-store",
     f"{session}:dbus-freedesktop-impl-portal-permission-store"),
    (f"{session}:dbus-portal-secret",
     f"{session}:dbus-freedesktop-impl-portal-secret"),
    (f"{sid}:systemd-user-control", "system:systemd-user-control"),
    (f"{session}:session-environment-broker-client",
     f"{session}:session-environment-broker-api"),
    ("snap-store:desktop", f"{session}:desktop"),
    ("snap-store:wayland", f"{session}:wayland"),
    ("snap-store:x11", f"{session}:x11"),
    ("firefox:desktop", f"{session}:desktop"),
    ("firefox:wayland", f"{session}:wayland"),
    ("firefox:x11", f"{session}:x11"),
    (f"{session}:wayland-client", f"{session}:wayland"),
    (f"{session}:dot-hidden", "snapd:personal-files"),
    (f"{session}:dot-local-share-nautilus", "snapd:personal-files"),
    (f"{session}:dot-local-share-gvfs-metadata", "snapd:personal-files"),
    (f"{session}:shell-session-locale-files", "snapd:personal-files"),
])

header = next(i for i, line in enumerate(lines) if line.strip() == "connections:")
end = next((i for i in range(header + 1, len(lines))
            if lines[i].strip() and not lines[i][0].isspace()
            and not lines[i].lstrip().startswith("#")), len(lines))
block = lines[header + 1:end]

def has_connection(plug, slot):
    for i, line in enumerate(block):
        if line.strip() != f"- plug: {plug}":
            continue
        for following in block[i + 1:]:
            if following.strip() and not following.startswith("    "):
                break
            if following.strip() == f"slot: {slot}":
                return True
    return False

new_lines = []
for plug, slot in connections:
    if not has_connection(plug, slot):
        new_lines.extend([f"  - plug: {plug}\n", f"    slot: {slot}\n"])

lines[header + 1:header + 1] = new_lines
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYEOF
}

kde_gadget_connections() {
    local gadget_yaml="$1"
    if ! grep -q '^connections:' "${gadget_yaml}"; then
        printf '\nconnections:\n' >> "${gadget_yaml}"
    fi
    python3 - "${gadget_yaml}" <<'PYEOF'
import sys
path = sys.argv[1]
session = "plasma-desktop-session"
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

simple_plugs = [
    "desktop-launch", "hardware-observe", "home", "hostname-control",
    "locale-control", "login-session-observe", "login-session-control",
    "mount-observe", "network-control", "network-observe",
    "bluetooth-control", "upower-observe", "systemd-user-control",
    "polkit-agent", "opengl", "pulseaudio", "pipewire", "network-bind",
    "ssh-keys", "dot-hidden", "shell-session-locale-files",
]

connections = [(f"{session}:{plug}", f"system:{plug}") for plug in simple_plugs]
connections.extend([
    (f"{session}:avahi-control", "dVK2PZeOLKA7vf1WPCap9F8luxTk9Oll:avahi-control"),
    (f"{session}:network-manager", "RmBXKl6HO6YOC2DE4G2q1JzWImC04EUy:service"),
    (f"{session}:bluez", "JmzJi9kQvHUWddZ32PDJpBRXUpGRxvNS:service"),
    (f"{session}:shell-config-files", "system:system-files"),
    (f"{session}:cups-control", "m1eQacDdXCthEwWQrESei3Zao3d5gfJF:cups-control"),
    (f"{session}:x11", f"{session}:x11-server"),
    (f"{session}:wayland-client", f"{session}:wayland"),
    (f"{session}:plasma-core26", "plasma-core26-desktop:plasma-core26"),
    (f"{session}:kf6-core26", "kf6-core26:kf6-core26"),
])

header = next(i for i, line in enumerate(lines) if line.strip() == "connections:")
end = next((i for i in range(header + 1, len(lines))
            if lines[i].strip() and not lines[i][0].isspace()
            and not lines[i].lstrip().startswith("#")), len(lines))
block = lines[header + 1:end]

def has_connection(plug, slot):
    for i, line in enumerate(block):
        if line.strip() != f"- plug: {plug}":
            continue
        for following in block[i + 1:]:
            if following.strip() and not following.startswith("    "):
                break
            if following.strip() == f"slot: {slot}":
                return True
    return False

new_lines = []
for plug, slot in connections:
    if not has_connection(plug, slot):
        new_lines.extend([f"  - plug: {plug}\n", f"    slot: {slot}\n"])

lines[header + 1:header + 1] = new_lines
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYEOF
}

# ----------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

orig_args=("$@")

cmdline_extra='systemd.journald.forward_to_console=1 systemd.journald.max_level_console=err console=ttyS0,115200n8'
debug=0
autologin=0
user=""
password=""
ssh_authorized_keys=""
ssh_host_key=""
model_account_key=""
model_json=""
base_snap=""
gadget_snap=""
snapd_snap=""
extra_snaps=()
desktop=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --debug) debug=1; shift ;;
        --autologin) autologin=1; shift ;;
        --desktop) desktop="$2"; shift 2 ;;
        --user) user="$2"; shift 2 ;;
        --password) password="$2"; shift 2 ;;
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

case "${desktop}" in
    gnome)
        : "${model_json:=ubuntu-core-desktop-26-amd64-dangerous.json}"
        session_wrapper_args=(ubuntu-desktop-session ubuntu:GNOME)
        ;;
    kde)
        : "${model_json:=ubuntu-core-desktop-kde-26-amd64-dangerous.json}"
        session_wrapper_args=(plasma-desktop-session KDE)
        ;;
    "")
        echo "Missing required --desktop gnome|kde." >&2
        exit 1
        ;;
    *)
        echo "Invalid --desktop '${desktop}' (must be 'gnome' or 'kde')." >&2
        exit 1
        ;;
esac

if [[ ${autologin} == 1 && -z ${user} ]]; then
    echo "--autologin requires --user <name> to be set." >&2
    exit 1
fi
if [[ -z ${password} ]]; then
    echo "Missing required --password <password>." >&2
    echo "Sets root's login password inside the image. There is no" >&2
    echo "default so no password ends up hardcoded in this script." >&2
    exit 1
fi
if [[ -z ${model_account_key} ]]; then
    echo "Missing required --model-account-key <path>." >&2
    echo "See 'build.sh --help' for how to obtain one." >&2
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

"${desktop}_gadget_connections" "${BUILD_DIR}/squashfs-root/meta/gadget.yaml"
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

pw="$(openssl passwd -6 "${password}")"
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
    crudini --set "${gdm_conf}" daemon AutomaticLogin "${user}"
  fi
done
# /etc is entirely a writable-path, seeded at first boot from
# usr/share/factory/writable/system-data/etc, so the squashfs's own
# /etc/sudoers.d is shadowed at runtime. Write to both, like the gdm3
# custom.conf above, and use the 0440 mode sudoers requires.
if [[ -n ${user} ]]; then
  for sudoers_dir in \
    "${BUILD_DIR}/squashfs-root/etc/sudoers.d" \
    "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/sudoers.d"
  do
    tee "${sudoers_dir}/${user}" >/dev/null <<EOF
${user} ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 0440 "${sudoers_dir}/${user}"
  done
fi

# GNOME and KDE connections are declared in gadget.yaml and applied
# during image seeding by snapd.

# Bake a permanent, build-time equivalent of the
# tools/confined-autologin-test.sh runtime shim. GDM's Wayland session
# launcher (gdm-wayland-session, used for both autologin AND real
# password-prompt logins on X-GDM-SessionRegisters=true sessions like
# ours) unconditionally execs the literal `gnome-session` binary on
# PATH -- it does NOT run the .desktop file's own Exec= (which is
# core-desktop-session-wrapper.sh) and does NOT consult AccountsService's
# Session= key (see notes/library/gdm-graphical-session.txt). Without
# this shim, ANY login (not just --autologin) launches the plain
# unconfined upstream gnome-session, which then falls back to guessing
# a default session (observed to be "ubuntu" regardless of which
# desktop was actually built) instead of the confined session actually
# installed -- so this must be installed whenever a login --user is
# configured at all, not just for --autologin. The username check is
# required because GDM's own greeter also execs plain gnome-session and
# must not be intercepted.
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
if [[ -n ${user} ]]; then
  mv "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session" "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session.real"
  tee "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session" > /dev/null << EOF
#!/bin/sh
if [ -n "\$SNAP_NAME" ]; then
  exec /usr/bin/gnome-session.real "\$@"
elif [ "\$(id -un)" = "${user}" ]; then
  exec /usr/bin/core-desktop-session-wrapper.sh ${session_wrapper_args[*]}
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

if [[ -n ${user} ]]; then
  # The account itself is created by cloud-init at first boot from this
  # seed ISO -- build.sh only prepares its sudoers/autologin config
  # above, it doesn't create the account. Generate the seed here, from
  # the same already-validated --user/--password/--ssh-authorized-keys,
  # so the image and its companion seed ISO can never end up describing
  # two different accounts/passwords/keys (as they could when this was
  # a separate manual step). --ssh-authorized-keys defaults to /dev/null
  # (never non-empty) when build.sh's own --ssh-authorized-keys wasn't
  # given, matching build.sh's own "no keys -> password login only"
  # behavior for root above, rather than falling back to
  # build-cloud-init.sh's own unrelated default (./authorized_keys).
  ./build-cloud-init.sh \
    --user "${user}" \
    --password "${password}" \
    --ssh-authorized-keys "${ssh_authorized_keys:-/dev/null}" \
    --output "${BUILD_DIR}/seed.iso"
else
  touch "${BUILD_DIR}/pc.img.nouser"
fi

echo "Built ${BUILD_DIR}/pc.img"
