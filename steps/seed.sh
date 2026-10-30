#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "${script_dir}")"
STEP_NAME=seed
source "${repo_dir}/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: seed.sh --user NAME --password PASSWORD [--ssh-authorized-keys FILE] [--output FILE]

Build a NoCloud seed ISO. The password is stored as a SHA-512 crypt hash.

Options:
  --user NAME                   User to create
  --password PASSWORD           User password
  --ssh-authorized-keys FILE    Public keys for the user (optional)
  --output FILE                 Seed ISO path (default: seed.iso)
  --help                        Show this help
EOF
}

user=""
password=""
authorized_keys=""
output=seed.iso
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --user|--password|--ssh-authorized-keys|--output)
      (($# >= 2)) || die "$1 requires a value"
      option="$1"
      value="$2"
      shift 2
      case "${option}" in
        --user) user="${value}" ;;
        --password) password="${value}" ;;
        --ssh-authorized-keys) authorized_keys="${value}" ;;
        --output) output="${value}" ;;
      esac
      ;;
    --*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

[[ -n ${user} ]] || die "--user is required"
[[ ${user} =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "invalid --user name: ${user}"
[[ -n ${password} ]] || die "--password is required"
[[ -z ${authorized_keys} ]] || require_file "${authorized_keys}"
command -v openssl >/dev/null 2>&1 || die "required command not found: openssl"
if command -v cloud-localds >/dev/null 2>&1; then
  iso_builder=(cloud-localds)
elif command -v genisoimage >/dev/null 2>&1; then
  iso_builder=(genisoimage -output "${output}" -volid cidata -joliet -rock)
elif command -v mkisofs >/dev/null 2>&1; then
  iso_builder=(mkisofs -output "${output}" -volid cidata -joliet -rock)
elif command -v xorriso >/dev/null 2>&1; then
  iso_builder=(xorriso -as genisoimage -output "${output}" -volid cidata -joliet -rock)
else
  die "need one of cloud-localds, genisoimage, mkisofs, xorriso installed"
fi

password_hash="$(printf '%s\n' "${password}" | openssl passwd -6 -stdin)"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT
{
  cat <<EOF
#cloud-config
users:
  - name: ${user}
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: false
EOF
  if [[ -n ${authorized_keys} && -s ${authorized_keys} ]]; then
    key_count=0
    while IFS= read -r key || [[ -n ${key} ]]; do
      [[ ${key} =~ [^[:space:]] && ! ${key} =~ ^[[:space:]]*# ]] || continue
      if ((key_count == 0)); then
        printf '    ssh_authorized_keys:\n'
      fi
      printf '      - %s\n' "${key}"
      ((key_count += 1))
    done <"${authorized_keys}"
  fi
  cat <<EOF

chpasswd:
  users:
    - name: ${user}
      password: ${password_hash}
      type: hash
  expire: false

ssh_pwauth: true
ssh_deletekeys: false
EOF
} >"${work_dir}/user-data"
cat >"${work_dir}/meta-data" <<'EOF'
instance-id: core-desktop-seed
local-hostname: core-desktop
EOF

if [[ ${iso_builder[0]} == cloud-localds ]]; then
  "${iso_builder[@]}" "${output}" "${work_dir}/user-data" "${work_dir}/meta-data"
else
  "${iso_builder[@]}" "${work_dir}/user-data" "${work_dir}/meta-data"
fi
info "wrote NoCloud seed ISO: ${output}"
