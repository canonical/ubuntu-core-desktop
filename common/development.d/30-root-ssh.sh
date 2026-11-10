#!/usr/bin/env bash
set -euo pipefail
factory_ssh="${BASE_ROOT}/usr/share/factory/writable/system-data/etc/ssh"
mkdir -p "${factory_ssh}"
if ! grep -Eq '^[[:space:]]*PermitRootLogin[[:space:]]+' "${factory_ssh}/sshd_config" 2>/dev/null; then
  printf '\nPermitRootLogin yes\n' >>"${factory_ssh}/sshd_config"
else
  sed -i 's/^[[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin yes/' "${factory_ssh}/sshd_config"
fi
