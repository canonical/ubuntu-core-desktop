#!/usr/bin/env bash
set -euo pipefail
# Removed by: ADR 0003
session_bin="${BASE_ROOT}/usr/bin/gnome-session"
mv -- "${session_bin}" "${session_bin}.real"
cat >"${session_bin}" <<'EOF'
#!/bin/sh
if [ -n "$SNAP_NAME" ]; then
  exec /usr/bin/gnome-session.real "$@"
else
  case "$(id -un)" in
    gdm|gdm-greeter|gdm-greeter-[0-9]*|gnome-initial-setup|gnome-initial-setup-[0-9]*)
      exec /usr/bin/gnome-session.real "$@"
      ;;
    *)
      exec /usr/bin/core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME
      ;;
  esac
fi
EOF
chmod 0755 "${session_bin}"
