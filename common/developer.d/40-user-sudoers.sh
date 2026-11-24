#!/usr/bin/env bash
set -euo pipefail
[[ -n ${DEV_USER} ]] || exit 0

sudoers_dir="${BASE_ROOT}/usr/share/factory/writable/system-data/etc/sudoers.d"
install -d -m 0755 "${sudoers_dir}"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${DEV_USER}" >"${sudoers_dir}/${DEV_USER}"
chmod 0440 "${sudoers_dir}/${DEV_USER}"
