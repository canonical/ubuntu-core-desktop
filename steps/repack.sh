#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "${script_dir}")"
STEP_NAME=repack
source "${repo_dir}/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: repack.sh --platform NAME --base-snap FILE --gadget-snap FILE --out DIR [--release] [developer options]

Repack the base and gadget snaps by applying common and Platform pieces.

Options:
  --platform NAME     Platform metadata and pieces
  --base-snap FILE    Stock base snap
  --gadget-snap FILE  Stock gadget snap
  --out DIR           Build directory
  --release           Skip Development image defaults
  --user NAME         Create a cloud-init user (requires --password)
  --password PASS     Password for --user
  --autologin         Log in automatically as --user
  --root-password PASS Set root's password
  --ssh-authorized-keys FILE  Install root authorized keys
  --ssh-host-key FILE Install an Ed25519 host key (requires FILE.pub)
  --debug             Enable verbose kernel and snapd logging
  --help              Show this help
EOF
}

platform=""
base_snap=""
gadget_snap=""
out_dir=""
user=""
password=""
autologin=0
root_password=""
ssh_authorized_keys=""
ssh_host_key=""
debug=0
release=0
orig_args=("$@")
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --release) release=1; shift ;;
    --autologin) autologin=1; shift ;;
    --debug) debug=1; shift ;;
    --platform|--base-snap|--gadget-snap|--out|--user|--password|--root-password|--ssh-authorized-keys|--ssh-host-key)
      (($# >= 2)) || die "$1 requires a value"
      option="$1"
      value="$2"
      shift 2
      case "${option}" in
        --platform) platform="${value}" ;;
        --base-snap) base_snap="${value}" ;;
        --gadget-snap) gadget_snap="${value}" ;;
        --out) out_dir="${value}" ;;
        --user) user="${value}" ;;
        --password) password="${value}" ;;
        --root-password) root_password="${value}" ;;
        --ssh-authorized-keys) ssh_authorized_keys="${value}" ;;
        --ssh-host-key) ssh_host_key="${value}" ;;
      esac
      ;;
    --*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

[[ ${platform} =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "--platform is required and must be a simple name"
[[ -d ${repo_dir}/platforms/${platform} ]] || die "unknown platform: ${platform}"
[[ -n ${base_snap} ]] || die "--base-snap is required"
[[ -n ${gadget_snap} ]] || die "--gadget-snap is required"
[[ -n ${out_dir} ]] || die "--out is required"
[[ -z ${user} && -z ${password} || -n ${user} && -n ${password} ]] \
  || die "--user and --password must be provided together"
((autologin == 0)) || [[ -n ${user} ]] || die "--autologin requires --user"
[[ -z ${user} || ${user} =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "invalid --user name: ${user}"
require_file "${base_snap}"
require_file "${gadget_snap}"
[[ -z ${ssh_authorized_keys} ]] || require_file "${ssh_authorized_keys}"
if [[ -n ${ssh_host_key} ]]; then
  require_file "${ssh_host_key}"
  [[ -f ${ssh_host_key}.pub ]] || die "--ssh-host-key expects a matching .pub file: ${ssh_host_key}.pub"
fi
for tool in fakeroot unsquashfs mksquashfs; do
  command -v "${tool}" >/dev/null 2>&1 || die "required command not found: ${tool}"
done
if [[ -n ${password} || -n ${root_password} ]]; then
  command -v openssl >/dev/null 2>&1 || die "required command not found: openssl"
fi

if [[ -z ${FAKEROOTKEY:-} ]]; then
  exec fakeroot -- "$0" "${orig_args[@]}"
fi

base_listing="$(unsquashfs -l "${base_snap}")" || die "failed to inspect base snap for cloud-init"
if [[ -n ${user} ]] && ! grep -Eq '(^|/)etc/cloud/cloud\.cfg$' <<<"${base_listing}"; then
  die "--user requires a base snap with cloud-init; use the core26-desktop-cloudinit base snap"
fi

developer_enabled=0
[[ -z ${user}${password}${root_password}${ssh_authorized_keys}${ssh_host_key} ]] && ((debug == 0)) && ((autologin == 0)) || developer_enabled=1
if ((release)) && { [[ -n ${root_password}${ssh_authorized_keys} ]]; }; then
  warn "root password/authorized keys may be inaccessible on a Release image while SSH is loopback-only and root login is disabled"
fi

mkdir -p -- "${out_dir}/snaps"
out_dir="$(cd "${out_dir}" && pwd)"
work_dir="${out_dir}/work"
gadget_root="${work_dir}/gadget-root"
base_root="${work_dir}/base-root"
gadget_output="${out_dir}/snaps/gadget.snap"
base_output="${out_dir}/snaps/base.snap"
rm -rf -- "${work_dir}"
rm -f -- "${gadget_output}" "${base_output}"
mkdir -p -- "${work_dir}"

run_piece() {
  local piece="$1"
  local relative="${piece#${repo_dir}/}"
  local status
  info "${relative}"
  set +e
  "${piece}"
  status=$?
  set -e
  if ((status != 0)); then
    printf 'repack: %s failed (exit %s); work tree kept at %s\n' \
      "${relative}" "${status}" "${work_dir}" >&2
    exit "${status}"
  fi
}

run_layer() {
  local layer_dir="$1"
  local piece
  local pieces=()
  [[ -d ${layer_dir} ]] || return 0
  while IFS= read -r piece; do pieces+=("${piece}"); done < <(LC_ALL=C compgen -G "${layer_dir}/*.sh" | LC_ALL=C sort || true)
  for piece in "${pieces[@]}"; do
    [[ -x ${piece} ]] || die "piece is not executable: ${piece#${repo_dir}/}"
    run_piece "${piece}"
  done
}

export GADGET_ROOT="${gadget_root}"
export BASE_ROOT="${base_root}"
export PLATFORM_DIR="${repo_dir}/platforms/${platform}"
export LIB_DIR="${repo_dir}/lib"
export RELEASE="${release}"
export DEV_USER="${user}"
export DEV_PASSWORD_HASH=""
export DEV_AUTOLOGIN="${autologin}"
export DEV_ROOT_PASSWORD_HASH=""
export DEV_SSH_AUTHORIZED_KEYS="${ssh_authorized_keys}"
export DEV_SSH_HOST_KEY="${ssh_host_key}"
export DEV_DEBUG="${debug}"
if [[ -n ${password} ]]; then
  DEV_PASSWORD_HASH="$(printf '%s\n' "${password}" | openssl passwd -6 -stdin)"
  export DEV_PASSWORD_HASH
fi
if [[ -n ${root_password} ]]; then
  DEV_ROOT_PASSWORD_HASH="$(printf '%s\n' "${root_password}" | openssl passwd -6 -stdin)"
  export DEV_ROOT_PASSWORD_HASH
fi

mkdir -p -- "${gadget_root}" "${base_root}"
unsquashfs -d "${gadget_root}" "${gadget_snap}" >/dev/null \
  || die "failed to unpack gadget snap; work tree kept at ${work_dir}"
unsquashfs -d "${base_root}" "${base_snap}" >/dev/null \
  || die "failed to unpack base snap; work tree kept at ${work_dir}"

run_layer "${repo_dir}/common/gadget.d"
run_layer "${repo_dir}/common/base.d"
run_layer "${PLATFORM_DIR}/base.d"
if ((RELEASE == 0)); then
  run_layer "${repo_dir}/common/development.d"
fi
if ((developer_enabled)); then
  run_layer "${repo_dir}/common/developer.d"
  run_layer "${PLATFORM_DIR}/developer.d"
else
  info "no developer options; skipping developer pieces"
fi

mksquashfs "${gadget_root}" "${gadget_output}" -noappend -comp zstd -Xcompression-level 1 \
  || die "failed to repack gadget snap; work tree kept at ${work_dir}"
mksquashfs "${base_root}" "${base_output}" -noappend -comp zstd -Xcompression-level 1 \
  || die "failed to repack base snap; work tree kept at ${work_dir}"
rm -rf -- "${work_dir}"
