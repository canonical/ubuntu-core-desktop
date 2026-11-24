#!/usr/bin/env bash
set -euo pipefail
[[ -n ${DEV_USER} ]] || exit 0

gdm_conf="${BASE_ROOT}/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
mkdir -p "$(dirname "${gdm_conf}")"
touch "${gdm_conf}"
if ! grep -Fq '[daemon]' "${gdm_conf}"; then
  printf '[daemon]\n' >>"${gdm_conf}"
fi
if grep -Eq '^[[:space:]]*InitialSetupEnable=' "${gdm_conf}"; then
  sed -i 's/^[[:space:]]*InitialSetupEnable=.*/InitialSetupEnable=false/' "${gdm_conf}"
else
  sed -i '/^\[daemon\]$/a InitialSetupEnable=false' "${gdm_conf}"
fi
if [[ ${DEV_AUTOLOGIN} == 1 ]]; then
  for setting in AutomaticLoginEnable AutomaticLogin; do
    sed -i "/^[[:space:]]*${setting}=/d" "${gdm_conf}"
  done
  sed -i "/^\[daemon\]$/a AutomaticLoginEnable=true\nAutomaticLogin=${DEV_USER}" "${gdm_conf}"
fi
