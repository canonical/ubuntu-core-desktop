#!/usr/bin/env bash
set -euo pipefail
# Removed by: ADR 0003

runtime="${INPUT_session_ROOT}/sddm"
factory="${BASE_ROOT}/usr/share/factory/writable/system-data"
triplet="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
[[ -d ${INPUT_plasma_ROOT}/usr/share/wallpapers ]] || {
  printf 'KDE plasma input is missing usr/share/wallpapers\n' >&2
  exit 1
}

for path in \
  usr/bin/sddm usr/bin/sddm-greeter-qt6 \
  "usr/lib/${triplet}/sddm/sddm-helper" \
  "usr/lib/${triplet}/sddm/sddm-helper-start-wayland" \
  usr/lib/sysusers.d/sddm.conf usr/lib/tmpfiles.d/sddm.conf \
  etc/pam.d/sddm etc/pam.d/sddm-autologin etc/pam.d/sddm-greeter \
  etc/sddm/wayland-session
do
  [[ -e ${runtime}/${path} ]] || {
    printf 'KDE session input is missing SDDM runtime file: %s\n' "${path}" >&2
    exit 1
  }
done
[[ -f ${INPUT_plasma_ROOT}/usr/share/sddm/themes/breeze/theme.conf ]] || {
  printf 'KDE plasma input is missing SDDM Breeze theme: usr/share/sddm/themes/breeze/theme.conf\n' >&2
  exit 1
}
[[ -e ${INPUT_plasma_ROOT}/usr/share/wallpapers/Altai ]] || {
  printf 'KDE plasma input is missing wallpaper: usr/share/wallpapers/Altai\n' >&2
  exit 1
}
for path in usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/qt6/plugins usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/qt6/qml; do
  [[ -d ${INPUT_plasma_ROOT}/${path} ]] || {
    printf 'KDE plasma input is missing runtime directory: %s\n' "${path}" >&2
    exit 1
  }
done
install -D -m 0644 "${runtime}/usr/lib/sysusers.d/sddm.conf" \
  "${BASE_ROOT}/usr/lib/sysusers.d/sddm.conf"
install -D -m 0644 "${runtime}/usr/lib/tmpfiles.d/sddm.conf" \
  "${BASE_ROOT}/usr/lib/tmpfiles.d/sddm.conf"
for pam in sddm sddm-autologin sddm-greeter; do
  install -D -m 0644 "${runtime}/etc/pam.d/${pam}" "${BASE_ROOT}/etc/pam.d/${pam}"
done
systemd-sysusers --root="${BASE_ROOT}" "${BASE_ROOT}/usr/lib/sysusers.d/sddm.conf"

mkdir -p "${BASE_ROOT}/var/lib" "${BASE_ROOT}/var/snap/plasma-desktop-session/common"
if [[ -e ${BASE_ROOT}/var/lib/sddm && ! -L ${BASE_ROOT}/var/lib/sddm ]]; then
  printf 'Unexpected existing SDDM home: %s\n' "${BASE_ROOT}/var/lib/sddm" >&2
  exit 1
fi
ln -sfn /var/snap/plasma-desktop-session/common/sddm "${BASE_ROOT}/var/lib/sddm"
sed -i 's|/var/lib/sddm|/var/snap/plasma-desktop-session/common/sddm|g' \
  "${BASE_ROOT}/usr/lib/tmpfiles.d/sddm.conf"

mkdir -p "${BASE_ROOT}/usr/lib/${triplet}/sddm" "${BASE_ROOT}/usr/libexec/sddm"
ln -sfn "/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/sddm/sddm-helper-start-wayland" \
  "${BASE_ROOT}/usr/lib/${triplet}/sddm/sddm-helper-start-wayland"
cat >"${BASE_ROOT}/usr/lib/${triplet}/sddm/sddm-helper" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH=/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}:/snap/kf6-core26/current/usr/lib/${triplet}:/snap/plasma-core26-desktop/current/usr/lib/${triplet}:/usr/lib/${triplet}:/usr/lib
export QT_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/plugins
export QML2_IMPORT_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/qml:/snap/kf6-core26/current/usr/lib/${triplet}/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qml:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/qml
exec /snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/sddm/sddm-helper "\$@"
EOF
chmod 0755 "${BASE_ROOT}/usr/lib/${triplet}/sddm/sddm-helper"
ln -sfn /snap/plasma-desktop-session/current/sddm/usr/bin/sddm-greeter-qt6 \
  "${BASE_ROOT}/usr/bin/sddm-greeter-qt6"
ln -sfn /snap/plasma-desktop-session/current/sddm/usr/share/sddm "${BASE_ROOT}/usr/share/sddm"

cat >"${BASE_ROOT}/usr/libexec/sddm/sddm-kwin-wayland" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH=/snap/kf6-core26/current/usr/lib/${triplet}:/snap/plasma-core26-desktop/current/usr/lib/${triplet}:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}:/usr/lib/${triplet}:/usr/lib
export QT_PLUGIN_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/plugins
export QML2_IMPORT_PATH=/snap/kf6-core26/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/qml:/snap/kf6-core26/current/usr/lib/${triplet}/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qml:/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/qml
export XCURSOR_THEME=breeze_cursors
export XCURSOR_PATH=/snap/plasma-core26-desktop/current/usr/share/icons:/snap/kf6-core26/current/usr/share/icons
export LIBINPUT_QUIRKS_DIR=/snap/plasma-core26-desktop/current/usr/share/libinput
export PIPEWIRE_CONFIG_DIR=/snap/plasma-core26-desktop/current/usr/share/pipewire
export XDG_CONFIG_DIRS=/snap/kf6-core26/current/etc/xdg:/snap/plasma-core26-desktop/current/etc/xdg:/etc/xdg
export XDG_DATA_DIRS=/snap/kf6-core26/current/usr/share:/snap/plasma-core26-desktop/current/usr/share:/usr/share
exec /snap/plasma-core26-desktop/current/usr/bin/kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF
chmod 0755 "${BASE_ROOT}/usr/libexec/sddm/sddm-kwin-wayland"

mkdir -p "${BASE_ROOT}/usr/share/wallpapers"
if [[ -e ${BASE_ROOT}/usr/share/wallpapers/Next && ! -L ${BASE_ROOT}/usr/share/wallpapers/Next ]]; then
  printf 'Unexpected existing wallpaper path: %s\n' "${BASE_ROOT}/usr/share/wallpapers/Next" >&2
  exit 1
fi
ln -sfn /snap/plasma-core26-desktop/current/usr/share/wallpapers/Altai \
  "${BASE_ROOT}/usr/share/wallpapers/Next"

sddm_conf="${factory}/etc/writable/sddm.conf"
mkdir -p "$(dirname "${sddm_conf}")"
touch "${sddm_conf}"
set_ini() {
  local section="$1" key="$2" value="$3" file="$4"
  SECTION="${section}" KEY="${key}" VALUE="${value}" awk '
    BEGIN { section=ENVIRON["SECTION"]; key=ENVIRON["KEY"]; value=ENVIRON["VALUE"] }
    /^\[/ { if (in_section && !written) { print key "=" value; written=1 }; in_section=($0 == "[" section "]") }
    in_section && $0 ~ "^[[:space:]]*" key "=" { if (!written) print key "=" value; written=1; next }
    { print }
    END { if (!written) { if (!in_section) print "[" section "]"; print key "=" value } }
  ' "${file}" >"${file}.tmp"
  mv "${file}.tmp" "${file}"
}
set_ini General DisplayServer wayland "${sddm_conf}"
set_ini Wayland CompositorCommand /usr/libexec/sddm/sddm-kwin-wayland "${sddm_conf}"
set_ini Wayland SessionDir /usr/share/wayland-sessions "${sddm_conf}"
set_ini Wayland SessionCommand /snap/plasma-desktop-session/current/sddm/etc/sddm/wayland-session "${sddm_conf}"
set_ini Theme ThemeDir /snap/plasma-core26-desktop/current/usr/share/sddm/themes "${sddm_conf}"
set_ini Theme Current breeze "${sddm_conf}"
ln -sfn writable/sddm.conf "${BASE_ROOT}/etc/sddm.conf"

mkdir -p "${BASE_ROOT}/usr/lib/systemd/system"
cat >"${BASE_ROOT}/usr/lib/systemd/system/sddm.service" <<EOF
[Unit]
Description=Simple Desktop Display Manager
After=systemd-user-sessions.service systemd-logind.service snapd.seeded.service cloud-config.service
Conflicts=getty@tty1.service gdm.service

[Service]
ExecStartPre=/usr/bin/install -d -o sddm -g sddm -m 0750 /var/snap/plasma-desktop-session/common/sddm
ExecStart=/snap/plasma-desktop-session/current/sddm/usr/bin/sddm
Restart=always
RestartSec=1s
Environment=LD_LIBRARY_PATH=/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}:/snap/kf6-core26/current/usr/lib/${triplet}:/snap/plasma-core26-desktop/current/usr/lib/${triplet}:/usr/lib/${triplet}:/usr/lib
Environment=QT_PLUGIN_PATH=/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/plugins:/snap/kf6-core26/current/usr/lib/${triplet}/qt6/plugins:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/plugins
Environment=QML2_IMPORT_PATH=/snap/plasma-desktop-session/current/sddm/usr/lib/${triplet}/qt6/qml:/snap/kf6-core26/current/usr/lib/${triplet}/qt6/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qt6/qml:/snap/kf6-core26/current/usr/lib/${triplet}/qml:/snap/plasma-core26-desktop/current/usr/lib/${triplet}/qml
Environment=XDG_CONFIG_DIRS=/snap/kf6-core26/current/etc/xdg:/snap/plasma-core26-desktop/current/etc/xdg:/etc/xdg
Environment=XDG_DATA_DIRS=/snap/kf6-core26/current/usr/share:/snap/plasma-core26-desktop/current/usr/share:/usr/share
Environment=QT_QPA_PLATFORM=wayland
Environment=KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
Environment=QT_QUICK_CONTROLS_STYLE=org.kde.desktop
Environment=XKB_CONFIG_ROOT=/snap/kf6-core26/current/usr/share/X11/xkb
Environment=XLOCALEDIR=/snap/kf6-core26/current/usr/share/X11/locale
Environment=XCURSOR_THEME=breeze_cursors
Environment=XCURSOR_PATH=/snap/plasma-core26-desktop/current/usr/share/icons:/snap/kf6-core26/current/usr/share/icons
Environment=LIBINPUT_QUIRKS_DIR=/snap/plasma-core26-desktop/current/usr/share/libinput
Environment=PIPEWIRE_CONFIG_DIR=/snap/plasma-core26-desktop/current/usr/share/pipewire
Environment=XDG_CONFIG_DIRS=/snap/kf6-core26/current/etc/xdg:/snap/plasma-core26-desktop/current/etc/xdg:/etc/xdg
Environment=XDG_DATA_DIRS=/snap/kf6-core26/current/usr/share:/snap/plasma-core26-desktop/current/usr/share:/usr/share

[Install]
Alias=display-manager.service
WantedBy=graphical.target
EOF
mkdir -p "${factory}/etc/systemd/system/graphical.target.wants" \
  "${factory}/etc/systemd/system/user-session-migration.service.d"
rm -rf "${factory}/etc/systemd/system/gdm.service.d"
ln -sfn /dev/null "${factory}/etc/systemd/system/gdm.service"
ln -sfn /usr/lib/systemd/system/sddm.service \
  "${factory}/etc/systemd/system/display-manager.service"
ln -sfn /usr/lib/systemd/system/sddm.service \
  "${factory}/etc/systemd/system/graphical.target.wants/sddm.service"
mkdir -p "${BASE_ROOT}/etc/xdg"
cat >"${BASE_ROOT}/etc/xdg/kcminputrc" <<'EOF'
[Mouse]
cursorTheme=breeze_cursors
EOF

mkdir -p "${factory}/etc/systemd/user/user-session-migration.service.d"
cat >"${factory}/etc/systemd/user/user-session-migration.service.d/kde-override.conf" <<'EOF'
[Unit]
ConditionGroup=
ConditionGroup=!gdm
ConditionGroup=!sddm

[Service]
ExecStart=
ExecStart=/usr/bin/user-session-migration
EOF

rm -f -- "${factory}/usr/share/wayland-sessions/ubuntu.desktop"
