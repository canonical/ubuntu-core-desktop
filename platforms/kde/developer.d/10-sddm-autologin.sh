#!/usr/bin/env bash
set -euo pipefail
[[ ${DEV_AUTOLOGIN} == 1 ]] || exit 0
config="${BASE_ROOT}/usr/share/factory/writable/system-data/etc/writable/sddm.conf"
mkdir -p "$(dirname "${config}")"
touch "${config}"
SECTION=Autologin KEY=User VALUE="${DEV_USER}" awk '
  BEGIN { section="Autologin"; key="User"; value=ENVIRON["VALUE"] }
  /^\[/ { if (in_section && !written) { print key "=" value; written=1 }; in_section=($0 == "[" section "]") }
  in_section && /^[[:space:]]*User=/ { if (!written) print key "=" value; written=1; next }
  { print }
  END { if (!written) { if (!in_section) print "[" section "]"; print key "=" value } }
' "${config}" >"${config}.tmp"
mv "${config}.tmp" "${config}"
SECTION=Autologin KEY=Session VALUE=plasma-desktop-session.desktop awk '
  BEGIN { section="Autologin"; key="Session"; value=ENVIRON["VALUE"] }
  /^\[/ { if (in_section && !written) { print key "=" value; written=1 }; in_section=($0 == "[" section "]") }
  in_section && /^[[:space:]]*Session=/ { if (!written) print key "=" value; written=1; next }
  { print }
  END { if (!written) { if (!in_section) print "[" section "]"; print key "=" value } }
' "${config}" >"${config}.tmp"
mv "${config}.tmp" "${config}"
