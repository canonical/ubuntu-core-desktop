#!/usr/bin/env bash
set -euo pipefail
[[ -n ${DEV_ROOT_PASSWORD_HASH} ]] || exit 0

shadow_file="${BASE_ROOT}/etc/shadow"
[[ -f ${shadow_file} ]] || { printf 'root shadow file not found\n' >&2; exit 1; }
awk -F: -v OFS=: -v hash="${DEV_ROOT_PASSWORD_HASH}" \
  '$1 == "root" { $2 = hash; found = 1 } { print } END { if (!found) exit 1 }' \
  "${shadow_file}" >"${shadow_file}.tmp"
chmod --reference="${shadow_file}" "${shadow_file}.tmp"
mv -- "${shadow_file}.tmp" "${shadow_file}"
