#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_NAME=build
source "${repo_dir}/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: build.sh --platform NAME --base-snap FILE --gadget-snap FILE \
                --snapd-snap FILE --model-account-key FILE [options]

Build a Development image by repacking snaps, signing the model, and packing
the image with imagecraft. Release and developer options are not yet supported.

Required:
  --platform NAME          Platform directory under platforms/ (currently gnome)
  --base-snap FILE         Base snap to customize
  --gadget-snap FILE       Gadget snap to customize
  --snapd-snap FILE        Snapd snap included in the image
  --model-account-key FILE Account-key assertion for the model signer

Options:
  --model FILE             Model JSON or pre-signed .model (default: Platform model.json)
  --snap FILE              Extra local snap to include (repeatable)
  --image-size SIZE        Final image size (default: 20G)
  --build-dir DIR          Output directory (default: build/<platform>)
  --help                   Show this help
EOF
}

platform=""
base_snap=""
gadget_snap=""
snapd_snap=""
account_key=""
model=""
image_size=20G
build_dir=""
extra_snaps=()

while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --platform|--base-snap|--gadget-snap|--snapd-snap|--model-account-key|--model|--image-size|--build-dir|--snap)
      (($# >= 2)) || die "$1 requires a value"
      option="$1"
      value="$2"
      shift 2
      case "${option}" in
        --platform) platform="${value}" ;;
        --base-snap) base_snap="${value}" ;;
        --gadget-snap) gadget_snap="${value}" ;;
        --snapd-snap) snapd_snap="${value}" ;;
        --model-account-key) account_key="${value}" ;;
        --model) model="${value}" ;;
        --image-size) image_size="${value}" ;;
        --build-dir) build_dir="${value}" ;;
        --snap) extra_snaps+=("${value}") ;;
      esac
      ;;
    --release|--user|--password|--autologin|--root-password|--ssh-authorized-keys|--ssh-host-key|--debug|--input|--developer-*)
      die "unsupported option: $1 (not yet implemented for the GNOME Development CLI)" ;;
    --*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

[[ ${platform} =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "--platform is required and must be a simple name"
platform_dir="${repo_dir}/platforms/${platform}"
[[ -d ${platform_dir} ]] || die "unknown platform: ${platform}"
[[ ${platform} == gnome ]] || die "unsupported platform: ${platform} (this CLI currently builds GNOME only)"
require_file "${platform_dir}/platform.env"
require_file "${repo_dir}/image/imagecraft.yaml.in"
# shellcheck source=platforms/gnome/platform.env
source "${platform_dir}/platform.env"
[[ -n ${IMAGE_NAME:-} && -n ${IMAGE_SUMMARY:-} ]] \
  || die "${platform_dir}/platform.env must define IMAGE_NAME and IMAGE_SUMMARY"

[[ -n ${base_snap} ]] || die "--base-snap is required"
[[ -n ${gadget_snap} ]] || die "--gadget-snap is required"
[[ -n ${snapd_snap} ]] || die "--snapd-snap is required"
[[ -n ${account_key} ]] || die "--model-account-key is required"
[[ ${image_size} =~ ^[1-9][0-9]*(K|M|G|T)?$ ]] || die "invalid --image-size: ${image_size}"
[[ -n ${build_dir} ]] || build_dir="${repo_dir}/build/${platform}"

model="${model:-${platform_dir}/model.json}"
require_file "${base_snap}"
require_file "${gadget_snap}"
require_file "${snapd_snap}"
require_file "${account_key}"
require_file "${model}"
[[ ${model} == *.json || ${model} == *.model ]] \
  || die "model file must end in .json or .model: ${model}"
for extra_snap in "${extra_snaps[@]}"; do
  require_file "${extra_snap}"
done
snap_names=(base.snap gadget.snap)
for snap_path in "${snapd_snap}" "${extra_snaps[@]}"; do
  [[ ${snap_path} == *.snap ]] || die "local snap must end in .snap: ${snap_path}"
  snap_name="$(basename -- "${snap_path}")"
  for existing_name in "${snap_names[@]}"; do
    [[ ${snap_name} != "${existing_name}" ]] || die "duplicate local snap filename: ${snap_name}"
  done
  snap_names+=("${snap_name}")
done

[[ -d ${repo_dir}/steps && -x ${repo_dir}/steps/repack.sh && \
  -x ${repo_dir}/steps/sign-model.sh && -x ${repo_dir}/steps/pack-image.sh ]] \
  || die "required pipeline step is missing or not executable"
command -v fakeroot >/dev/null 2>&1 || die "required command not found: fakeroot"
command -v unsquashfs >/dev/null 2>&1 || die "required command not found: unsquashfs"
command -v mksquashfs >/dev/null 2>&1 || die "required command not found: mksquashfs"
if [[ ${model} == *.json ]]; then
  command -v snap >/dev/null 2>&1 || die "required command not found: snap"
fi
command -v imagecraft >/dev/null 2>&1 || die "required command not found: imagecraft"
command -v truncate >/dev/null 2>&1 || die "required command not found: truncate"

mkdir -p -- "${build_dir}"
build_dir="$(cd "${build_dir}" && pwd)"
info "building ${platform} Development image in ${build_dir}"

"${repo_dir}/steps/repack.sh" \
  --platform "${platform}" \
  --base-snap "${base_snap}" \
  --gadget-snap "${gadget_snap}" \
  --out "${build_dir}"

"${repo_dir}/steps/sign-model.sh" \
  --model "${model}" \
  --out "${build_dir}"

snaps=("${build_dir}/snaps/base.snap" "${build_dir}/snaps/gadget.snap" "${snapd_snap}")
snaps+=("${extra_snaps[@]}")
pack_args=(--platform "${platform}" --model-assert "${build_dir}/model.assert"
  --account-key "${account_key}" --image-size "${image_size}" --out "${build_dir}")
for snap_path in "${snaps[@]}"; do
  pack_args+=(--snap "${snap_path}")
done
"${repo_dir}/steps/pack-image.sh" "${pack_args[@]}"

info "built ${build_dir}/pc.img"
