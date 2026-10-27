#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "${script_dir}")"
STEP_NAME=repack
source "${repo_dir}/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: repack.sh --platform NAME --base-snap FILE --gadget-snap FILE --out DIR [--user NAME]

Repack the base and gadget snaps by applying common and Platform pieces.

Options:
  --platform NAME     Platform metadata and pieces
  --base-snap FILE    Stock base snap
  --gadget-snap FILE  Stock gadget snap
  --out DIR           Build directory
  --user NAME         Require a cloud-init-enabled base
  --help              Show this help
EOF
}

platform=""
base_snap=""
gadget_snap=""
out_dir=""
user=""
orig_args=("$@")
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --platform|--base-snap|--gadget-snap|--out|--user)
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
require_file "${base_snap}"
require_file "${gadget_snap}"
for tool in fakeroot unsquashfs mksquashfs; do
  command -v "${tool}" >/dev/null 2>&1 || die "required command not found: ${tool}"
done

if [[ -z ${FAKEROOTKEY:-} ]]; then
  exec fakeroot -- "$0" "${orig_args[@]}"
fi

base_listing="$(unsquashfs -l "${base_snap}")" || die "failed to inspect base snap for cloud-init"
if [[ -n ${user} ]] && ! grep -Eq '(^|/)etc/cloud/cloud\.cfg$' <<<"${base_listing}"; then
  die "--user requires a base snap with cloud-init"
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
export RELEASE=0
export DEV_USER="${DEV_USER:-}"
export DEV_PASSWORD_HASH="${DEV_PASSWORD_HASH:-}"
export DEV_AUTOLOGIN="${DEV_AUTOLOGIN:-}"
export DEV_ROOT_PASSWORD_HASH="${DEV_ROOT_PASSWORD_HASH:-}"
export DEV_SSH_AUTHORIZED_KEYS="${DEV_SSH_AUTHORIZED_KEYS:-}"
export DEV_SSH_HOST_KEY="${DEV_SSH_HOST_KEY:-}"
export DEV_DEBUG="${DEV_DEBUG:-}"

mkdir -p -- "${gadget_root}" "${base_root}"
unsquashfs -d "${gadget_root}" "${gadget_snap}" >/dev/null \
  || die "failed to unpack gadget snap; work tree kept at ${work_dir}"
unsquashfs -d "${base_root}" "${base_snap}" >/dev/null \
  || die "failed to unpack base snap; work tree kept at ${work_dir}"

run_layer "${repo_dir}/common/gadget.d"
run_layer "${repo_dir}/common/base.d"
run_layer "${PLATFORM_DIR}/base.d"
run_layer "${repo_dir}/common/development.d"

mksquashfs "${gadget_root}" "${gadget_output}" -noappend -comp zstd -Xcompression-level 1 \
  || die "failed to repack gadget snap; work tree kept at ${work_dir}"
mksquashfs "${base_root}" "${base_output}" -noappend -comp zstd -Xcompression-level 1 \
  || die "failed to repack base snap; work tree kept at ${work_dir}"
rm -rf -- "${work_dir}"
