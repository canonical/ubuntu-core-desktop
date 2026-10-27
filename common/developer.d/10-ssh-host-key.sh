#!/usr/bin/env bash
set -euo pipefail
[[ -n ${DEV_SSH_HOST_KEY} ]] || exit 0

ssh_dir="${BASE_ROOT}/usr/share/factory/writable/system-data/etc/ssh"
mkdir -p "${ssh_dir}"
install -m 0600 "${DEV_SSH_HOST_KEY}" "${ssh_dir}/ssh_host_ed25519_key"
install -m 0644 "${DEV_SSH_HOST_KEY}.pub" "${ssh_dir}/ssh_host_ed25519_key.pub"
config="${ssh_dir}/sshd_config"
touch "${config}"
if ! grep -Fxq 'HostKey /etc/ssh/ssh_host_ed25519_key' "${config}"; then
  printf '\nHostKey /etc/ssh/ssh_host_ed25519_key\n' >>"${config}"
fi
