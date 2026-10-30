#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_NAME=build
source "${repo_dir}/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: build.sh --platform NAME --base-snap FILE --gadget-snap FILE \
                --snapd-snap FILE --model-account-key FILE [--input name=path ...] [options]

Build a Development image by repacking snaps, signing the model, and packing
the image with imagecraft. Use --release to omit Development image defaults.

Required:
  --platform NAME          Platform directory under platforms/
  --base-snap FILE         Base snap to customize
  --gadget-snap FILE       Gadget snap to customize
  --snapd-snap FILE        Snapd snap included in the image
  --model-account-key FILE Account-key assertion for the model signer

Options:
  --model FILE             Model JSON or pre-signed assertion (default: Platform model)
  --snap FILE              Extra local snap to include (repeatable)
  --input NAME=FILE        Platform-declared input (repeatable)
  --release                Build a Release image without Development defaults
  --image-size SIZE        Final image size (default: 20G)
  --build-dir DIR          Output directory (default: build/<platform>)
  --user NAME              Create a cloud-init user (requires --password)
  --password PASSWORD      Password for --user
  --autologin              Log in automatically as --user
  --root-password PASSWORD Set root's password
  --ssh-authorized-keys FILE  Install root/user authorized keys
  --ssh-host-key FILE      Install an Ed25519 host key (requires FILE.pub)
  --debug                  Enable verbose kernel and snapd logging
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
release=0
extra_snaps=()
input_args=()
user=""
password=""
autologin=0
root_password=""
ssh_authorized_keys=""
ssh_host_key=""
debug=0

while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --release) release=1; shift ;;
    --autologin) autologin=1; shift ;;
    --debug) debug=1; shift ;;
    --platform|--base-snap|--gadget-snap|--snapd-snap|--model-account-key|--model|--image-size|--build-dir|--snap|--input)
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
        --input) input_args+=("${value}") ;;
      esac
      ;;
    --user|--password|--root-password|--ssh-authorized-keys|--ssh-host-key)
      (($# >= 2)) || die "$1 requires a value"
      option="$1"
      value="$2"
      shift 2
      case "${option}" in
        --user) user="${value}" ;;
        --password) password="${value}" ;;
        --root-password) root_password="${value}" ;;
        --ssh-authorized-keys) ssh_authorized_keys="${value}" ;;
        --ssh-host-key) ssh_host_key="${value}" ;;
      esac
      ;;
    --developer-*) die "unsupported option: $1" ;;
    --*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

[[ ${platform} =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "--platform is required and must be a simple name"
platform_dir="${repo_dir}/platforms/${platform}"
[[ -d ${platform_dir} ]] || die "unknown platform: ${platform}"
require_file "${platform_dir}/platform.env"
require_file "${repo_dir}/image/imagecraft.yaml.in"
source "${platform_dir}/platform.env"
[[ -n ${IMAGE_NAME:-} && -n ${IMAGE_SUMMARY:-} ]] \
  || die "${platform_dir}/platform.env must define IMAGE_NAME and IMAGE_SUMMARY"
source "${repo_dir}/lib/platform.sh"
declare_platform_inputs
parse_platform_inputs input_args
validate_platform_inputs

[[ -n ${base_snap} ]] || die "--base-snap is required"
[[ -n ${gadget_snap} ]] || die "--gadget-snap is required"
[[ -n ${snapd_snap} ]] || die "--snapd-snap is required"
[[ -n ${account_key} ]] || die "--model-account-key is required"
[[ -z ${user} && -z ${password} || -n ${user} && -n ${password} ]] \
  || die "--user and --password must be provided together"
((autologin == 0)) || [[ -n ${user} ]] || die "--autologin requires --user"
[[ -z ${user} || ${user} =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "invalid --user name: ${user}"
[[ ${image_size} =~ ^[1-9][0-9]*(K|M|G|T)?$ ]] || die "invalid --image-size: ${image_size}"
[[ -n ${build_dir} ]] || build_dir="${repo_dir}/build/${platform}"

if [[ -z ${model} ]]; then
  if [[ -f ${platform_dir}/model.json ]]; then
    model="${platform_dir}/model.json"
  elif [[ -f ${platform_dir}/model.signed ]]; then
    model="${platform_dir}/model.signed"
  else
    die "Platform has no model.json or model.signed: ${platform_dir}"
  fi
fi
require_file "${base_snap}"
require_file "${gadget_snap}"
require_file "${snapd_snap}"
require_file "${account_key}"
require_file "${model}"
[[ -z ${ssh_authorized_keys} ]] || require_file "${ssh_authorized_keys}"
if [[ -n ${ssh_host_key} ]]; then
  require_file "${ssh_host_key}"
  [[ -f ${ssh_host_key}.pub ]] || die "--ssh-host-key expects a matching .pub file: ${ssh_host_key}.pub"
fi
[[ ${model} == *.json || ${model} == *.model || ${model} == *.signed ]] \
  || die "model file must end in .json, .model, or .signed: ${model}"
for extra_snap in "${extra_snaps[@]}"; do
  require_file "${extra_snap}"
done
snap_names=(base.snap gadget.snap)
for snap_path in "${snapd_snap}" "${extra_snaps[@]}" "${PLATFORM_INPUT_PATHS[@]}"; do
  [[ ${snap_path} == *.snap ]] || die "local snap must end in .snap: ${snap_path}"
  snap_name="$(basename -- "${snap_path}")"
  for existing_name in "${snap_names[@]}"; do
    [[ ${snap_name} != "${existing_name}" ]] || die "duplicate local snap filename: ${snap_name}"
  done
  snap_names+=("${snap_name}")
done

[[ -d ${repo_dir}/steps && -x ${repo_dir}/steps/repack.sh && \
  -x ${repo_dir}/steps/sign-model.sh && -x ${repo_dir}/steps/pack-image.sh && \
  -x ${repo_dir}/steps/seed.sh ]] \
  || die "required pipeline step is missing or not executable"
command -v fakeroot >/dev/null 2>&1 || die "required command not found: fakeroot"
command -v unsquashfs >/dev/null 2>&1 || die "required command not found: unsquashfs"
command -v mksquashfs >/dev/null 2>&1 || die "required command not found: mksquashfs"
if [[ ${model} == *.json ]]; then
  command -v snap >/dev/null 2>&1 || die "required command not found: snap"
fi
command -v imagecraft >/dev/null 2>&1 || die "required command not found: imagecraft"
command -v truncate >/dev/null 2>&1 || die "required command not found: truncate"
if [[ -n ${password} || -n ${root_password} ]]; then
  command -v openssl >/dev/null 2>&1 || die "required command not found: openssl"
fi

mkdir -p -- "${build_dir}"
build_dir="$(cd "${build_dir}" && pwd)"
[[ -n ${user} ]] || rm -f -- "${build_dir}/seed.iso"
if ((release)); then
  image_type=Release
else
  image_type=Development
fi
info "building ${platform} ${image_type} image in ${build_dir}"
if [[ ${FIRST_BOOT_WIZARD} == no && -z ${user} ]]; then
  warn "${IMAGE_NAME} has no first-boot wizard; build with --user to create an account"
fi

repack_args=(
  --platform "${platform}" \
  --base-snap "${base_snap}" \
  --gadget-snap "${gadget_snap}" \
  --out "${build_dir}"
)
for input_name in "${PLATFORM_INPUT_NAMES[@]}"; do
  repack_args+=(--input "${input_name}=${PLATFORM_INPUT_PATHS[${input_name}]}")
done
((release == 0)) || repack_args+=(--release)
[[ -z ${user} ]] || repack_args+=(--user "${user}")
[[ -z ${password} ]] || repack_args+=(--password "${password}")
((autologin == 0)) || repack_args+=(--autologin)
[[ -z ${root_password} ]] || repack_args+=(--root-password "${root_password}")
[[ -z ${ssh_authorized_keys} ]] || repack_args+=(--ssh-authorized-keys "${ssh_authorized_keys}")
[[ -z ${ssh_host_key} ]] || repack_args+=(--ssh-host-key "${ssh_host_key}")
((debug == 0)) || repack_args+=(--debug)
"${repo_dir}/steps/repack.sh" "${repack_args[@]}"

"${repo_dir}/steps/sign-model.sh" \
  --model "${model}" \
  --out "${build_dir}"

snaps=("${build_dir}/snaps/base.snap" "${build_dir}/snaps/gadget.snap" "${snapd_snap}")
snaps+=("${extra_snaps[@]}")
for input_name in "${PLATFORM_INPUT_NAMES[@]}"; do
  if [[ ${PLATFORM_INPUT_LOCAL[${input_name}]} == yes ]]; then
    snaps+=("${PLATFORM_INPUT_PATHS[${input_name}]}")
  fi
done
pack_args=(--platform "${platform}" --model-assert "${build_dir}/model.assert"
  --account-key "${account_key}" --image-size "${image_size}" --out "${build_dir}")
for snap_path in "${snaps[@]}"; do
  pack_args+=(--snap "${snap_path}")
done
"${repo_dir}/steps/pack-image.sh" "${pack_args[@]}"

if [[ -n ${user} ]]; then
  seed_args=(--user "${user}" --password "${password}" --output "${build_dir}/seed.iso")
  [[ -z ${ssh_authorized_keys} ]] || seed_args+=(--ssh-authorized-keys "${ssh_authorized_keys}")
  "${repo_dir}/steps/seed.sh" "${seed_args[@]}"
fi

if ((release)) && { [[ -n ${root_password} ]] || [[ -n ${ssh_authorized_keys} ]]; }; then
  warn "root password/authorized keys may be inaccessible on a Release image while SSH is loopback-only and root login is disabled"
fi
info "built ${build_dir}/pc.img"
[[ -z ${user} ]] || info "built ${build_dir}/seed.iso"
