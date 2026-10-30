#!/usr/bin/env bash
set -euo pipefail
# Removed by: ADR 0003
unit="${BASE_ROOT}/usr/lib/systemd/system/gdm-homedirs.service"
mkdir -p "$(dirname "${unit}")"
cat >"${unit}" <<'EOF'
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
dropin="${BASE_ROOT}/usr/lib/systemd/system/gdm.service.d/gdm-homedirs.conf"
mkdir -p "$(dirname "${dropin}")"
cat >"${dropin}" <<'EOF'
[Unit]
Requires=gdm-homedirs.service
After=gdm-homedirs.service
EOF
