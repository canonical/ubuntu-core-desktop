#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "${script_dir}")"
STEP_NAME=sign-model
source "${repo_dir}/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: sign-model.sh (--platform NAME | --model FILE) --out DIR

Sign a Platform model JSON or copy a pre-signed .model assertion to OUT/model.assert.

Options:
  --platform NAME  Read platforms/NAME/model.json
  --model FILE     Use a .json model to sign or a pre-signed .model assertion
  --out DIR        Build directory
  --help           Show this help
EOF
}

platform=""
model=""
out_dir=""
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --platform|--model|--out)
      (($# >= 2)) || die "$1 requires a value"
      option="$1"
      value="$2"
      shift 2
      case "$option" in
        --platform) platform="$value" ;;
        --model) model="$value" ;;
        --out) out_dir="$value" ;;
      esac
      ;;
    --*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

[[ -n ${out_dir} ]] || die "--out is required"
[[ -z ${platform} || -z ${model} ]] || die "use either --platform or --model, not both"
if [[ -n ${platform} ]]; then
  [[ ${platform} =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "invalid platform name: ${platform}"
  [[ -d ${repo_dir}/platforms/${platform} ]] || die "unknown platform: ${platform}"
  model="${repo_dir}/platforms/${platform}/model.json"
fi
[[ -n ${model} ]] || die "--platform or --model is required"
[[ -f ${model} ]] || die "model file not found: ${model}"

case "${model}" in
  *.model) ;;
  *.json) ;;
  *) die "model file must end in .json or .model: ${model}" ;;
esac
command -v snap >/dev/null 2>&1 || [[ ${model} == *.model ]] || die "required command not found: snap"

mkdir -p -- "${out_dir}"
out_dir="$(cd "${out_dir}" && pwd)"
model_assert="${out_dir}/model.assert"
rm -f -- "${model_assert}"

if [[ ${model} == *.model ]]; then
  info "copying pre-signed model ${model}"
  cp -- "${model}" "${model_assert}"
else
  sign_key="${SNAP_SIGN_KEY:-test}"
  info "signing model ${model} with key ${sign_key}"
  snap sign -k "${sign_key}" --update-timestamp "${model}" >"${model_assert}"
fi
