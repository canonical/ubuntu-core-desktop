#!/usr/bin/env bash
set -euo pipefail
# Removed by: upstream: core-base-desktop
factory_wants="${BASE_ROOT}/usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants"
mkdir -p "${factory_wants}"
ln -sfn /usr/lib/systemd/system/polkit-agent-helper.socket "${factory_wants}/polkit-agent-helper.socket"
