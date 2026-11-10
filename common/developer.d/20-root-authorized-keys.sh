#!/usr/bin/env bash
set -euo pipefail
[[ -n ${DEV_SSH_AUTHORIZED_KEYS} ]] || exit 0

root_dir="${BASE_ROOT}/usr/share/factory/writable/system-data/root"
install -D -m 0600 "${DEV_SSH_AUTHORIZED_KEYS}" "${root_dir}/.ssh/authorized_keys"
chmod 0700 "${root_dir}/.ssh"
