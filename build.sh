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
# auto-connect at boot, and which display manager/session command to
# configure) live in the desktop_* functions below, selected by --desktop.

set -e

usage() {
    cat <<'EOF'
Usage: build.sh --desktop gnome|kde --model-account-key <path> \
           --base-snap <path> --gadget-snap <path> --snapd-snap <path> \
           [--snap <path>]... [options]

Builds <build-dir>/pc.img (an Ubuntu Core Desktop disk image) using
ubuntu-image. The default build directory is "build". If --user is
given, also builds <build-dir>/seed.iso (a
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
                              Requires --password. Without this flag
                              no login account is configured and no
                              seed.iso is built (this is the default).
  --ssh-authorized-keys <path> File of SSH public keys (one per line)
                              to install into root's authorized_keys in
                              the image, and (if --user is also given)
                              into --user's via the seed.iso above.
                              Without this flag, neither has
                              authorized_keys (password login only).
  --root-password <password>  Root's login password, baked into the
                              image (as a SHA-512 crypt hash via
                              openssl passwd). Without this flag,
                              root's password stays locked (as the
                              base snap ships it), so no password
                              ends up hardcoded or defaulted. Does
                              not require --user/no seed.iso.
  --password <password>       --user's login password, created via the
                              seed.iso build-cloud-init.sh generates --
                              see --user above. Must be given together
                              with --user.
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
                              Without this flag no host key is baked
                              in; the image generates fresh host keys
                              on first boot (sshd-keygen.service), so
                              each build gets a new SSH identity.
  --autologin                 Bake in display-manager autologin for
                              --user (which becomes required). Without
                              this, the login prompt is used.
  --kde-session-snap <path>   KDE session snap supplying SDDM and its
                              greeter runtime (required for --desktop kde).
  --build-dir <name>          Output directory under the project root
                              (default: build); recreated on each build.
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
    "time-control", "timeserver-control", "timezone-control",
    "systemd-user-environment",
]

connections = [(f"{session}:{plug}", f"system:{plug}") for plug in simple_plugs]
connections.append((f"{session}:shell-config-files", "system:system-files"))
connections.append((f"{session}:user-dirs-defaults", "system:system-files"))
connections.append((f"{session}:gnome-content-launch", "system:system-files"))
connections.append((f"{session}:gdm-session-control", "system:gdm-session-control"))
connections.extend([
    (f"{session}:network-manager", "RmBXKl6HO6YOC2DE4G2q1JzWImC04EUy:service"),
    (f"{session}:bluez", "JmzJi9kQvHUWddZ32PDJpBRXUpGRxvNS:service"),
    # UDisks2/UPower moved out of the core base into their own provider
    # snaps (Stage 3B); the session monitor is a client of the provider's
    # standard interface slot instead of the implicit system slot.
    (f"{session}:udisks2", "udisks2:udisks2"),
    ("udisks2:polkit", "system:polkit"),
    ("udisks2:udisks2-client", "udisks2:udisks2"),
    ("udisks2:hardware-observe", "system:hardware-observe"),
    ("udisks2:mount-observe", "system:mount-observe"),
    ("udisks2:block-devices", "system:block-devices"),
    # UPower provider snap: the session's upower-observe plug (gsd-power)
    # connects to the provider's upower-observe slot; upowerd itself
    # needs hardware observation and BlueZ for battery reporting.
    (f"{session}:upower-observe", "upower:upower"),
    ("upower:hardware-observe", "system:hardware-observe"),
    ("upower:bluez", "JmzJi9kQvHUWddZ32PDJpBRXUpGRxvNS:service"),
    ("upower:upower-client", "upower:upower"),
    (f"{session}:dbus-portal-desktop",
     f"{session}:dbus-freedesktop-portal-desktop"),
    (f"{session}:dbus-portal-documents",
     f"{session}:dbus-freedesktop-portal-documents"),
    (f"{session}:dbus-portal-tracker",
     f"{session}:dbus-freedesktop-portal-tracker"),
    (f"{session}:dbus-portal-impl-gnome",
     f"{session}:dbus-freedesktop-impl-portal-gnome"),
    (f"{session}:dbus-gnome-shell-screenshot-client",
     f"{session}:dbus-gnome-shell-screenshot"),
    (f"{session}:dbus-gnome-shell-screencast-client",
     f"{session}:dbus-gnome-shell-screencast"),
    (f"{session}:dbus-gnome-mutter-screencast-client",
     f"{session}:dbus-gnome-mutter-screencast"),
    (f"{session}:dbus-portal-impl-gtk",
     f"{session}:dbus-freedesktop-impl-portal-gtk"),
    (f"{session}:dbus-portal-permission-store",
     f"{session}:dbus-freedesktop-impl-portal-permission-store"),
    (f"{session}:dbus-portal-secret",
     f"{session}:dbus-freedesktop-impl-portal-secret"),
    (f"{session}:gnome-desktop-runtime",
     "gnome-desktop-runtime:gnome-desktop-runtime"),
    (f"{session}:pipewire", "pipewire:pipewire"),
    (f"{session}:audio-playback", "pipewire:audio-playback"),
    ("pipewire:dbus-portal-desktop",
     f"{session}:dbus-freedesktop-portal-desktop"),
    ("pipewire:dbus-portal-permission-store",
     f"{session}:dbus-freedesktop-impl-portal-permission-store"),
    ("gnome-desktop-runtime:hardware-observe", "system:hardware-observe"),
    ("gnome-desktop-runtime:systemd-user-control",
     "system:systemd-user-control"),
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
    (f"{session}:pictures-directory", "snapd:personal-files"),
    (f"{session}:dot-local-share-nautilus", "snapd:personal-files"),
    (f"{session}:dot-local-share-gvfs-metadata", "snapd:personal-files"),
    (f"{session}:shell-session-locale-files", "snapd:personal-files"),
    (f"{session}:shell-startup-files", "snapd:personal-files"),
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

kde_sddm_integration() {
  local rootfs="$1"
  local kde_session_snap="$2"
  local runtime_root="${BUILD_DIR}/kde-session-snap-root"
  local factory_etc="${rootfs}/usr/share/factory/writable/system-data/etc"
  local triplet

  triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
  unsquashfs -d "${runtime_root}" "${kde_session_snap}" >/dev/null
  for path in \
    sddm/usr/bin/sddm \
    sddm/usr/bin/sddm-greeter-qt6 \
    "sddm/usr/lib/${triplet}/sddm/sddm-helper" \
    "sddm/usr/lib/${triplet}/sddm/sddm-helper-start-wayland" \
    sddm/usr/lib/sysusers.d/sddm.conf \
    sddm/usr/lib/tmpfiles.d/sddm.conf \
    sddm/etc/pam.d/sddm \
    sddm/etc/pam.d/sddm-autologin \
    sddm/etc/pam.d/sddm-greeter \
    sddm/etc/sddm/wayland-session
  do
    if [[ ! -e "${runtime_root}/${path}" ]]; then
      echo "KDE session snap is missing required SDDM runtime file: ${path}" >&2
      exit 1
    fi
  done

  # SDDM is a host system service, but its runtime is owned and shipped
  # by the KDE session snap. Keep PAM/account/service integration in the
  # selected image rather than adding desktop-specific packages to the
  # shared core-base-desktop snap.
  install -D -m 0644 "${runtime_root}/sddm/usr/lib/sysusers.d/sddm.conf" \
    "${rootfs}/usr/lib/sysusers.d/sddm.conf"
  install -D -m 0644 "${runtime_root}/sddm/usr/lib/tmpfiles.d/sddm.conf" \
    "${rootfs}/usr/lib/tmpfiles.d/sddm.conf"
  for pam_service in sddm sddm-autologin sddm-greeter; do
    install -D -m 0644 "${runtime_root}/sddm/etc/pam.d/${pam_service}" \
      "${rootfs}/etc/pam.d/${pam_service}"
    install -D -m 0644 "${runtime_root}/sddm/etc/pam.d/${pam_service}" \
      "${factory_etc}/pam.d/${pam_service}"
  done

  systemd-sysusers --root="${rootfs}" \
    "${rootfs}/usr/lib/sysusers.d/sddm.conf"
  for account_file in passwd shadow group gshadow; do
    cp -a "${rootfs}/etc/${account_file}" "${factory_etc}/${account_file}"
  done

  local sddm_home=/var/snap/plasma-desktop-session/common/sddm
  local sddm_home_path="${rootfs}/var/lib/sddm"
  if [[ -e ${sddm_home_path} && ! -L ${sddm_home_path} ]]; then
    echo "Unexpected existing SDDM home at ${sddm_home_path}" >&2
    return 1
  fi
  ln -sfn "${sddm_home}" "${sddm_home_path}"
  sed -i "s|/var/lib/sddm|${sddm_home}|g" \
    "${rootfs}/usr/lib/tmpfiles.d/sddm.conf"

  mkdir -p "${rootfs}/usr/lib/${triplet}/sddm"
  ln -sfn \
    "/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/sddm/sddm-helper-start-wayland" \
    "${rootfs}/usr/lib/${triplet}/sddm/sddm-helper-start-wayland"
  cat >"${rootfs}/usr/lib/${triplet}/sddm/sddm-helper" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH=/snap/kf6-core26/current/usr/lib/${triplet}:/snap/plasma-core26-desktop/current/usr/lib/${triplet}:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}:/usr/lib/${triplet}:/usr/lib
export QT_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/plugins
export QT_QPA_PLATFORM_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins/platforms
export QML2_IMPORT_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/qml:/snap/kf6-core26/current/usr/lib/${triplet}/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qml
export QT_QPA_PLATFORM=wayland
export QT_QUICK_CONTROLS_STYLE=org.kde.desktop
exec /snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/sddm/sddm-helper "\$@"
EOF
  chmod 0755 "${rootfs}/usr/lib/${triplet}/sddm/sddm-helper"
  mkdir -p "${rootfs}/usr/libexec/sddm"
  cat >"${rootfs}/usr/libexec/sddm/sddm-kwin-wayland" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH=/snap/kf6-core26/current/usr/lib/${triplet}:/snap/plasma-core26-desktop/current/usr/lib/${triplet}:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}:/usr/lib/${triplet}:/usr/lib
export QT_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/plugins
export QT_QPA_PLATFORM_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins/platforms
export QML2_IMPORT_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/qml:/snap/kf6-core26/current/usr/lib/${triplet}/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qml
export XCURSOR_THEME=breeze_cursors
export XCURSOR_PATH=/snap/plasma-core26-desktop/current/usr/share/icons:/snap/kf6-core26/current/usr/share/icons
export LIBINPUT_QUIRKS_DIR=/snap/plasma-core26-desktop/current/usr/share/libinput
export PIPEWIRE_CONFIG_DIR=/snap/plasma-core26-desktop/current/usr/share/pipewire
exec /snap/plasma-core26-desktop/current/usr/bin/kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF
  chmod 0755 "${rootfs}/usr/libexec/sddm/sddm-kwin-wayland"
  ln -sfn /snap/plasma-desktop-session/current/sddm/usr/bin/sddm-greeter-qt6 \
    "${rootfs}/usr/bin/sddm-greeter-qt6"
  if [[ -e "${rootfs}/usr/share/sddm" && ! -L "${rootfs}/usr/share/sddm" ]]; then
    rm -rf "${rootfs}/usr/share/sddm"
  fi
  mkdir -p "${rootfs}/usr/share"
  ln -sfn /snap/plasma-core26-desktop/current/usr/share/sddm \
    "${rootfs}/usr/share/sddm"
  mkdir -p "${rootfs}/usr/share/wallpapers"
  if [[ -e "${rootfs}/usr/share/wallpapers/Next" \
    && ! -L "${rootfs}/usr/share/wallpapers/Next" ]]; then
    echo "Unexpected existing Breeze wallpaper path: ${rootfs}/usr/share/wallpapers/Next" >&2
    return 1
  fi
  # The Breeze theme references Next, which is not shipped in our content snaps.
  ln -sfn /snap/plasma-core26-desktop/current/usr/share/wallpapers/Altai \
    "${rootfs}/usr/share/wallpapers/Next"

  local sddm_conf
  for sddm_conf in \
    "${rootfs}/etc/writable/sddm.conf" \
    "${factory_etc}/writable/sddm.conf"
  do
    mkdir -p "$(dirname "${sddm_conf}")"
    crudini --set "${sddm_conf}" General DisplayServer wayland
    crudini --set "${sddm_conf}" Wayland CompositorCommand \
      /usr/libexec/sddm/sddm-kwin-wayland
    crudini --set "${sddm_conf}" Wayland SessionDir /usr/share/wayland-sessions
    crudini --set "${sddm_conf}" Wayland SessionCommand \
      /snap/plasma-desktop-session/current/sddm/etc/sddm/wayland-session
    crudini --set "${sddm_conf}" Theme ThemeDir /usr/share/sddm/themes
    crudini --set "${sddm_conf}" Theme Current breeze
    if [[ ${autologin} == 1 ]]; then
      crudini --set "${sddm_conf}" Autologin User "${user}"
      crudini --set "${sddm_conf}" Autologin Session plasma-desktop-session.desktop
    else
      crudini --del "${sddm_conf}" Autologin User
      crudini --del "${sddm_conf}" Autologin Session
    fi
  done
  ln -sfn writable/sddm.conf "${rootfs}/etc/sddm.conf"
  ln -sfn writable/sddm.conf "${factory_etc}/sddm.conf"

  local cursor_config
  for cursor_config in \
    "${rootfs}/etc/xdg/kcminputrc" \
    "${factory_etc}/xdg/kcminputrc"
  do
    mkdir -p "$(dirname "${cursor_config}")"
    crudini --set "${cursor_config}" Mouse cursorTheme breeze_cursors
  done

  cat >"${rootfs}/usr/lib/systemd/system/sddm.service" <<EOF
[Unit]
Description=Simple Desktop Display Manager
After=systemd-user-sessions.service systemd-logind.service snapd.seeded.service cloud-config.service plymouth-quit-wait.service plymouth-quit.service
Conflicts=getty@tty1.service gdm.service

[Service]
ExecStartPre=/usr/bin/install -d -o sddm -g sddm -m 0750 /var/snap/plasma-desktop-session/common/sddm
ExecStartPre=/usr/bin/test -x /snap/plasma-desktop-session/current/sddm/usr/bin/sddm
ExecStart=/snap/plasma-desktop-session/current/sddm/usr/bin/sddm
Restart=always
RestartSec=1s
EnvironmentFile=-/etc/default/locale
Environment=LD_LIBRARY_PATH=/snap/kf6-core26/current/usr/lib/${triplet}:/snap/plasma-core26-desktop/current/usr/lib/${triplet}:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}:/usr/lib/${triplet}:/usr/lib
Environment=QT_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/plugins
Environment=QT_QPA_PLATFORM_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins/platforms
Environment=QML2_IMPORT_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/qml:/snap/kf6-core26/current/usr/lib/${triplet}/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qml
Environment=XDG_CONFIG_DIRS=/snap/kf6-core26/current/etc/xdg:/snap/plasma-core26-desktop/current/etc/xdg:/etc/xdg
Environment=XDG_DATA_DIRS=/snap/kf6-core26/current/usr/share:/snap/plasma-core26-desktop/current/usr/share:/usr/share
Environment=XCURSOR_THEME=breeze_cursors
Environment=XCURSOR_PATH=/snap/plasma-core26-desktop/current/usr/share/icons:/snap/kf6-core26/current/usr/share/icons
Environment=QT_QPA_PLATFORM=wayland
Environment=KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
Environment=QT_QUICK_CONTROLS_STYLE=org.kde.desktop
Environment=XKB_CONFIG_ROOT=/snap/kf6-core26/current/usr/share/X11/xkb
Environment=XLOCALEDIR=/snap/kf6-core26/current/usr/share/X11/locale

[Install]
Alias=display-manager.service
WantedBy=graphical.target
EOF

  # The base image is GNOME-capable. Mask GDM and select SDDM only in
  # this KDE image; installing another session later does not switch the
  # system display manager.
  rm -f "${rootfs}/usr/lib/systemd/system/display-manager.service"
  ln -s sddm.service "${rootfs}/usr/lib/systemd/system/display-manager.service"
  for etc_root in "${rootfs}/etc" "${factory_etc}"; do
    mkdir -p "${etc_root}/systemd/system"
    rm -rf "${etc_root}/systemd/system/gdm.service.d"
    find "${etc_root}/systemd/system" -type l \
      \( -name gdm.service -o -name display-manager.service \) -delete
    ln -sfn /dev/null "${etc_root}/systemd/system/gdm.service"
    ln -sfn /usr/lib/systemd/system/sddm.service \
      "${etc_root}/systemd/system/display-manager.service"
    mkdir -p "${etc_root}/systemd/system/graphical.target.wants"
    ln -sfn /usr/lib/systemd/system/sddm.service \
      "${etc_root}/systemd/system/graphical.target.wants/sddm.service"
    mkdir -p "${etc_root}/systemd/user/user-session-migration.service.d"
    cat >"${etc_root}/systemd/user/user-session-migration.service.d/kde-override.conf" <<'EOF'
[Unit]
ConditionGroup=
ConditionGroup=!gdm
ConditionGroup=!sddm

[Service]
ExecStart=
ExecStart=/usr/bin/user-session-migration
EOF
  done
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
root_password=""
ssh_authorized_keys=""
ssh_host_key=""
model_account_key=""
model_json=""
base_snap=""
gadget_snap=""
snapd_snap=""
extra_snaps=()
desktop=""
kde_session_snap=""
build_dir="build"

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
        --root-password) root_password="$2"; shift 2 ;;
        --ssh-authorized-keys) ssh_authorized_keys="$2"; shift 2 ;;
        --ssh-host-key) ssh_host_key="$2"; shift 2 ;;
        --model-account-key) model_account_key="$2"; shift 2 ;;
        --model) model_json="$2"; shift 2 ;;
        --base-snap) base_snap="$2"; shift 2 ;;
        --gadget-snap) gadget_snap="$2"; shift 2 ;;
        --snapd-snap) snapd_snap="$2"; shift 2 ;;
        --kde-session-snap) kde_session_snap="$2"; shift 2 ;;
        --build-dir) build_dir="$2"; shift 2 ;;
        --snap) extra_snaps+=("$2"); shift 2 ;;
        *)
            echo "Unknown flag: ${1}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! ${build_dir} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "--build-dir must be a simple directory name under the project root." >&2
    exit 1
fi

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
if [[ -n ${password} && -z ${user} ]]; then
    echo "--password requires --user <name> to be set." >&2
    exit 1
fi
if [[ -n ${user} && -z ${password} ]]; then
    echo "--user requires --password <password> to be set." >&2
    exit 1
fi
if [[ ${desktop} == kde && -z ${kde_session_snap} ]]; then
    echo "--desktop kde requires --kde-session-snap <path>." >&2
    exit 1
fi
if [[ ${desktop} != kde && -n ${kde_session_snap} ]]; then
    echo "--kde-session-snap is only valid with --desktop kde." >&2
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
if [[ -n ${ssh_host_key} && ! -e "${ssh_host_key}.pub" ]]; then
    echo "File not found: ${ssh_host_key}.pub (--ssh-host-key expects a" >&2
    echo "private key path with a matching '.pub' file alongside it)" >&2
    exit 1
fi
for f in "${model_account_key}" "${base_snap}" "${gadget_snap}" "${snapd_snap}" "${ssh_host_key}" "${model_json}" "${kde_session_snap}" "${extra_snaps[@]:-}"; do
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

BUILD_DIR="${build_dir}"
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
# Polkit 127 uses this socket-activated helper instead of requiring the
# polkit-agent-helper-1 binary to be setuid root. /etc is seeded from the
# factory writable tree, so enable the socket there for the first boot.
polkit_socket_wants="${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants"
mkdir -p "${polkit_socket_wants}"
ln -sfn /usr/lib/systemd/system/polkit-agent-helper.socket \
  "${polkit_socket_wants}/polkit-agent-helper.socket"
# /etc and /root are entirely writable-paths, seeded at first boot from
# usr/share/factory/writable/system-data/{etc,root} (see the gdm3/sudoers
# handling below) -- so the squashfs's own /etc/ssh and /root/.ssh are
# shadowed at runtime and never take effect unless we also write into the
# factory copies used to seed them.
for etc_ssh_dir in \
  "${BUILD_DIR}/squashfs-root/etc/ssh" \
  "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/ssh"
do
  if [[ -n ${ssh_host_key} ]]; then
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
  else
    # No baked host key: sshd-keygen.service generates the default key
    # set on first boot, so no HostKey directive is added.
    tee -a "${etc_ssh_dir}/sshd_config" > /dev/null << 'EOF'
PermitRootLogin yes
EOF
  fi
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

# Only set root's password when --root-password is given; without it, root
# keeps the locked password the base snap ships with, so no password
# is ever hardcoded or defaulted here.
if [[ -n ${root_password} ]]; then
  pw="$(openssl passwd -6 "${root_password}")"
  usermod --prefix "$(pwd)/${BUILD_DIR}/squashfs-root" --password "${pw}" root
fi

# fix the serial console
./fix-console "${BUILD_DIR}/squashfs-root"

if [[ ${desktop} == gnome ]]; then
  # Snapd validates homedirs in initramfs, before the regular root is
  # available. Configure it after seeding, once the path can be created.
  gdm_homedirs_unit="${BUILD_DIR}/squashfs-root/usr/lib/systemd/system/gdm-homedirs.service"
  mkdir -p "$(dirname "${gdm_homedirs_unit}")"
  cat > "${gdm_homedirs_unit}" <<'EOF'
[Unit]
Description=Configure GDM home directories in Snapd
Requires=snapd.seeded.service
After=snapd.seeded.service
Before=gdm.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/mkdir -p /run/gdm3/home
ExecStart=/usr/bin/snap set system homedirs=/run/gdm3/home
RemainAfterExit=yes
EOF
  gdm_dropin_dir="${BUILD_DIR}/squashfs-root/usr/lib/systemd/system/gdm.service.d"
  mkdir -p "${gdm_dropin_dir}"
  cat > "${gdm_dropin_dir}/gdm-homedirs.conf" <<'EOF'
[Unit]
Requires=gdm-homedirs.service
After=gdm-homedirs.service
EOF
  for gdm_conf in \
    "${BUILD_DIR}/squashfs-root/etc/writable/gdm3/custom.conf" \
    "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
  do
    # With a build-time user, cloud-init creates the account before GDM
    # starts, so GDM's initial setup has nothing to do -- disable it to
    # keep GDM on the plain greeter. Without --user, first boot must run
    # GDM's initial-setup session, which launches the ubuntu-desktop-init
    # first-boot wizard (via launch-desktop-provision-init), so
    # InitialSetupEnable is left at its gdm.schemas default (true).
    if [[ -n ${user} ]]; then
      crudini --set "${gdm_conf}" daemon InitialSetupEnable false
    fi
    if [[ ${autologin} == 1 ]]; then
      crudini --set "${gdm_conf}" daemon AutomaticLoginEnable true
      crudini --set "${gdm_conf}" daemon AutomaticLogin "${user}"
    fi
  done
  rm -f \
    "${BUILD_DIR}/squashfs-root/usr/share/wayland-sessions/plasma-desktop-session.desktop" \
    "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/usr/share/wayland-sessions/plasma-desktop-session.desktop"
else
  kde_sddm_integration "${BUILD_DIR}/squashfs-root" "${kde_session_snap}"
  rm -f \
    "${BUILD_DIR}/squashfs-root/usr/share/wayland-sessions/ubuntu-desktop-session.desktop" \
    "${BUILD_DIR}/squashfs-root/usr/share/factory/writable/system-data/usr/share/wayland-sessions/ubuntu-desktop-session.desktop"
fi
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
# installed -- so this must be installed in every GNOME image, including
# images where the first user is created during first-boot setup. The
# greeter and GDM's initial-setup session (which launches the
# ubuntu-desktop-init first-boot wizard) run under separate system
# accounts, so exempt their roles rather than baking the build-time user
# into the shim. GDM may run initial setup as the static
# "gnome-initial-setup" account or as its own transient
# "gnome-initial-setup-<n>" account, hence both patterns.
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
if [[ ${desktop} == gnome ]]; then
  mv "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session" "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session.real"
  tee "${BUILD_DIR}/squashfs-root/usr/bin/gnome-session" > /dev/null << EOF
#!/bin/sh
if [ -n "\$SNAP_NAME" ]; then
  exec /usr/bin/gnome-session.real "\$@"
else
  case "\$(id -un)" in
    gdm|gdm-greeter|gdm-greeter-[0-9]*|gnome-initial-setup|gnome-initial-setup-[0-9]*)
      exec /usr/bin/gnome-session.real "\$@"
      ;;
    *)
      exec /usr/bin/core-desktop-session-wrapper.sh ${session_wrapper_args[*]}
      ;;
  esac
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
if [[ ${desktop} == kde ]]; then
  snap_args+=(--snap "${kde_session_snap}")
fi
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
  # a separate manual step). --user and --password are required
  # together (validated above). --ssh-authorized-keys defaults to
  # /dev/null (never non-empty) when build.sh's own --ssh-authorized-
  # keys wasn't given, matching build.sh's own "no keys -> password
  # login only" behavior for root above, rather than falling back to
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
