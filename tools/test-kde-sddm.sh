#!/bin/bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root (for example: sudo $0 [desktop-user])." >&2
  exit 1
fi

desktop_user="${1:-}"

fail() {
  echo "KDE SDDM integration check failed: $*" >&2
  exit 1
}

systemctl is-enabled --quiet sddm.service \
  || fail "sddm.service is not enabled"
systemctl is-active --quiet sddm.service \
  || fail "sddm.service is not active"
[[ $(systemctl is-enabled gdm.service 2>/dev/null || true) == masked ]] \
  || fail "gdm.service is not masked"
! systemctl is-active --quiet gdm.service \
  || fail "gdm.service is active alongside SDDM"
[[ $(readlink -f /etc/systemd/system/display-manager.service) == \
    /usr/lib/systemd/system/sddm.service ]] \
  || fail "display-manager.service does not resolve to SDDM"
[[ -x /snap/plasma-desktop-session/current/sddm/usr/bin/sddm ]] \
  || fail "SDDM runtime is missing from plasma-desktop-session"
[[ -r /usr/share/sddm/themes/breeze/theme.conf ]] \
  || fail "Breeze SDDM theme is not visible at /usr/share/sddm"
[[ -r /usr/share/wallpapers/Next/contents/images/5120x2880.png ]] \
  || fail "Breeze's configured wallpaper is not available"
if find /snap/plasma-desktop-session/current/sddm/usr/lib \
  \( -type f -o -type l \) -name 'libQt6*.so*' -print -quit | grep -q .; then
  fail "Qt libraries are still bundled in the SDDM runtime"
fi
sddm_pid="$(systemctl show sddm.service -p MainPID --value)"
[[ ${sddm_pid} =~ ^[1-9][0-9]*$ && -r /proc/${sddm_pid}/maps ]] \
  || fail "SDDM process is not available for Qt runtime verification"
sddm_maps="$(cat "/proc/${sddm_pid}/maps")"
grep -Fq 'libQt6Core.so.6.11.1' <<<"${sddm_maps}" \
  || fail "SDDM is not using the Qt 6.11.1 runtime"
! grep -Eq 'libQt6[^/]*\.so\.6\.10\.2' <<<"${sddm_maps}" \
  || fail "SDDM is still using Qt 6.10.2"
grep -Eq '^[[:space:]]*Current[[:space:]]*=[[:space:]]*breeze$' \
  /etc/writable/sddm.conf \
  || fail "Breeze is not selected as the SDDM theme"
grep -Eq '^cursorTheme[[:space:]]*=[[:space:]]*breeze_cursors$' \
  /etc/xdg/kcminputrc \
  || fail "KDE's system cursor theme is not set to breeze_cursors"
for layout_path in /usr/share/libinput /usr/share/pipewire; do
  [[ ! -L ${layout_path} ]] \
    || fail "${layout_path} must not conflict with confined snap layouts"
done
[[ -d /run/sddm ]] || fail "SDDM runtime directory was not created"

if [[ -n ${desktop_user} ]]; then
  session_id=""
  plasma_started=0
  for _ in $(seq 1 120); do
    session_id=""
    while read -r candidate _; do
      [[ -n ${candidate} ]] || continue
      service="$(loginctl show-session "${candidate}" -p Service --value)"
      if [[ $(loginctl show-session "${candidate}" -p Name --value) == "${desktop_user}" \
         && ( ${service} == sddm || ${service} == sddm-autologin ) \
         && $(loginctl show-session "${candidate}" -p Type --value) == wayland ]]; then
        session_id="${candidate}"
        break
      fi
    done < <(loginctl list-sessions --no-legend)
    if [[ -n ${session_id} ]] \
      && pgrep -u "${desktop_user}" -f 'startplasma-wayland' >/dev/null; then
      plasma_started=1
      break
    fi
    sleep 1
  done
  [[ -n ${session_id} ]] \
    || fail "no SDDM-created Wayland session found for ${desktop_user}"
  [[ ${plasma_started} == 1 ]] || fail "Plasma did not start for ${desktop_user}"
  user_runtime="/run/user/$(id -u "${desktop_user}")"
  session_bus="unix:path=${user_runtime}/bus"
  migration_exec="$(runuser -u "${desktop_user}" -- env \
    XDG_RUNTIME_DIR="${user_runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${session_bus}" \
    systemctl --user show user-session-migration.service -p ExecStart --value)"
  [[ ${migration_exec} == *"/usr/bin/user-session-migration"* ]] \
    || fail "user-session-migration does not use the installed system binary"
  migration_result="$(runuser -u "${desktop_user}" -- env \
    XDG_RUNTIME_DIR="${user_runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${session_bus}" \
    systemctl --user show user-session-migration.service -p Result --value)"
  [[ ${migration_result} == success ]] \
    || fail "user-session-migration did not complete successfully"

  ksmserver_ready=0
  for _ in $(seq 1 120); do
    if runuser -u "${desktop_user}" -- env \
      XDG_RUNTIME_DIR="${user_runtime}" \
      DBUS_SESSION_BUS_ADDRESS="${session_bus}" \
      busctl --user --no-pager list \
      | awk '$1 == "org.kde.ksmserver" && $2 != "-" { found = 1 } END { exit !found }'; then
      ksmserver_ready=1
      break
    fi
    sleep 1
  done
  [[ ${ksmserver_ready} == 1 ]] \
    || fail "KDE session manager did not acquire org.kde.ksmserver"

  boot_errors="$(journalctl -b --no-pager -o cat)"
  if grep -Eq \
    'drkonqi-sentry-postman\.path: Refusing to start|user-session-migration\.service: (Failed at step EXEC|Failed with result)|Failed to load the device quirks|pw\.conf: can.t load config client\.conf|Failed to load overview:.*org\.kde\.milou|Failed to load cursor theme|snap\.plasma-desktop-session\.plasma-polkit-agent\.service: Failed|snap-update-ns failed with code 1|cannot create symbolic link "/usr/share/(libinput|pipewire)"|Plugin uses incompatible Qt library' \
    <<<"${boot_errors}"; then
    fail "KDE boot journal still contains a fixed desktop-session error"
  fi
else
  initial_greeter_pids="$(pgrep -u sddm -f 'sddm-greeter-qt6' | sort || true)"
  [[ -n ${initial_greeter_pids} ]] \
    || fail "SDDM greeter is not running; pass a desktop username to check autologin"
  sleep 10
  current_greeter_pids="$(pgrep -u sddm -f 'sddm-greeter-qt6' | sort || true)"
  [[ ${current_greeter_pids} == "${initial_greeter_pids}" ]] \
    || fail "SDDM greeter restarted or exited during the 10-second stability check"
fi

echo "KDE SDDM boot, Qt 6.11.1, Breeze theme, manager selection, and ${desktop_user:-greeter} checks passed."
