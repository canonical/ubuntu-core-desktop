#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "${script_dir}")"
STEP_NAME=pack-image
source "${repo_dir}/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: pack-image.sh --platform NAME --model-assert FILE --account-key FILE \
                     --snap FILE [--snap FILE ...] [--image-size SIZE] --out DIR

Render the shared imagecraft project, pack it in managed mode, and size OUT/pc.img.

Options:
  --platform NAME       Platform metadata in platforms/NAME/platform.env
  --model-assert FILE   Signed model assertion
  --account-key FILE    Account-key assertion
  --snap FILE           Local snap to include (repeatable)
  --image-size SIZE     Final image size (default: 20G)
  --out DIR             Build directory
  --help                Show this help
EOF
}

platform=""
model_assert=""
account_key=""
image_size=20G
out_dir=""
snaps=()
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --platform|--model-assert|--account-key|--image-size|--out|--snap)
      (($# >= 2)) || die "$1 requires a value"
      option="$1"
      value="$2"
      shift 2
      case "$option" in
        --platform) platform="$value" ;;
        --model-assert) model_assert="$value" ;;
        --account-key) account_key="$value" ;;
        --image-size) image_size="$value" ;;
        --out) out_dir="$value" ;;
        --snap) snaps+=("$value") ;;
      esac
      ;;
    --*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

[[ ${platform} =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "--platform is required and must be a simple name"
[[ -n ${model_assert} ]] || die "--model-assert is required"
[[ -n ${account_key} ]] || die "--account-key is required"
((${#snaps[@]} >= 3)) || die "at least three --snap values are required (base, gadget, snapd)"
[[ -n ${out_dir} ]] || die "--out is required"
[[ ${image_size} =~ ^[1-9][0-9]*(K|M|G|T)?$ ]] || die "invalid --image-size: ${image_size}"

platform_env="${repo_dir}/platforms/${platform}/platform.env"
template="${repo_dir}/image/imagecraft.yaml.in"
require_file "${platform_env}"
require_file "${template}"
require_file "${model_assert}"
require_file "${account_key}"
command -v imagecraft >/dev/null 2>&1 || die "required command not found: imagecraft"
command -v truncate >/dev/null 2>&1 || die "required command not found: truncate"

for snap_path in "${snaps[@]}"; do
  require_file "${snap_path}"
done

# platform.env is repository-owned scalar configuration for template metadata.
# shellcheck disable=SC1090
source "${platform_env}"
[[ -n ${IMAGE_NAME:-} && -n ${IMAGE_SUMMARY:-} ]] \
  || die "${platform_env} must define IMAGE_NAME and IMAGE_SUMMARY"
platform_label="${platform^^}"

mkdir -p -- "${out_dir}"
out_dir="$(cd "${out_dir}" && pwd)"
project_dir="${out_dir}/project"
image_path="${out_dir}/pc.img"
rm -rf -- "${project_dir}"
rm -f -- "${image_path}"
mkdir -p -- "${project_dir}/snaps"
cp -- "${model_assert}" "${project_dir}/model.assert"
cp -- "${account_key}" "${project_dir}/account-key.assert"

core_snap_lines=""
extra_snap_lines=""
declare -A copied_snap_names=()
for snap_index in "${!snaps[@]}"; do
  snap_path="${snaps[${snap_index}]}"
  snap_name="$(basename -- "${snap_path}")"
  [[ ${snap_name} == *.snap ]] || die "local snap must end in .snap: ${snap_path}"
  [[ -z ${copied_snap_names[${snap_name}]:-} ]] || die "duplicate local snap filename: ${snap_name}"
  copied_snap_names[${snap_name}]=1
  cp -- "${snap_path}" "${project_dir}/snaps/${snap_name}"
  if ((snap_index < 3)); then
    core_snap_lines+="      - snaps/${snap_name}"$'\n'
  else
    extra_snap_lines+="      - snaps/${snap_name}"$'\n'
  fi
done

rendered_template="${project_dir}/imagecraft.yaml"
while IFS= read -r line || [[ -n ${line} ]]; do
  case "${line}" in
    *'@IMAGE_NAME@'*) line="${line//@IMAGE_NAME@/${IMAGE_NAME}}" ;;
  esac
  case "${line}" in
    *'@IMAGE_SUMMARY@'*) line="${line//@IMAGE_SUMMARY@/${IMAGE_SUMMARY}}" ;;
  esac
  case "${line}" in
    *'@PLATFORM_LABEL@'*) line="${line//@PLATFORM_LABEL@/${platform_label}}" ;;
  esac
  case "${line}" in
    '@CORE_SNAPS@') printf '%s' "${core_snap_lines}" >>"${rendered_template}" ;;
    '@EXTRA_SNAPS@') printf '%s' "${extra_snap_lines}" >>"${rendered_template}" ;;
    *) printf '%s\n' "${line}" >>"${rendered_template}" ;;
  esac
done <"${template}"

info "packing ${platform} with ${#snaps[@]} local snaps in managed mode"
(
  cd "${project_dir}"
  imagecraft pack --use-lxd --verbose
  [[ -f pc.img ]] || die "imagecraft pack did not produce project/pc.img"
  packed_size="$(stat -c %s pc.img)"
  requested_size="$(numfmt --from=iec "${image_size}")"
  ((packed_size <= requested_size)) \
    || die "packed image is larger than requested --image-size (${packed_size} > ${requested_size} bytes)"
  truncate -s "${image_size}" pc.img
  mv -- pc.img "${image_path}"
)
