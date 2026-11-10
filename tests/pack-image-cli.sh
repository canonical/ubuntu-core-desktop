#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pack_image="${repo_root}/steps/pack-image.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/bin" "${tmp_dir}/inputs" "${tmp_dir}/build"
printf 'model assertion\n' >"${tmp_dir}/inputs/model.assert"
printf 'account key\n' >"${tmp_dir}/inputs/account-key.assert"
printf 'pre-existing model output\n' >"${tmp_dir}/build/model.assert"
for snap in core26-desktop pc-desktop snapd ubuntu-desktop-session gnome-desktop-runtime pipewire ubuntu-desktop-init; do
  printf '%s snap\n' "${snap}" >"${tmp_dir}/inputs/${snap}.snap"
done
printf 'keep this output\n' >"${tmp_dir}/build/unrelated-output"

cat >"${tmp_dir}/bin/imagecraft" <<'SH'
#!/usr/bin/env bash
[[ $1 == pack ]] || exit 10
  [[ $2 == --use-lxd && $3 == --verbose ]] || exit 11
  [[ $# == 3 ]] || exit 12
  [[ -f imagecraft.yaml ]] || exit 13
  cp imagecraft.yaml "${CAPTURED_TEMPLATE}"
truncate -s 2G pc.img
SH
chmod +x "${tmp_dir}/bin/imagecraft"
export PATH="${tmp_dir}/bin:${PATH}"
export CAPTURED_TEMPLATE="${tmp_dir}/captured-imagecraft.yaml"

help_output="$("${pack_image}" --help)"
[[ ${help_output} == *"--platform"* && ${help_output} == *"--model-assert"* && ${help_output} == *"--account-key"* ]]
[[ ${help_output} == *"--image-size"* && ${help_output} == *"--out"* && ${help_output} == *"--snap"* ]]

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("${pack_image}" "$@" 2>&1)"; then
    printf 'expected failure: %s\n' "${expected}" >&2
    exit 1
  fi
  [[ ${output} == *"${expected}"* ]] || {
    printf 'missing error %q in output:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  }
}

expect_failure "--platform is required" --out "${tmp_dir}/invalid"
expect_failure "invalid --image-size" --platform gnome --image-size 1KiB \
  --model-assert "${tmp_dir}/inputs/model.assert" \
  --account-key "${tmp_dir}/inputs/account-key.assert" \
  --snap "${tmp_dir}/inputs/core26-desktop.snap" --snap "${tmp_dir}/inputs/pc-desktop.snap" \
  --snap "${tmp_dir}/inputs/snapd.snap" --out "${tmp_dir}/invalid"
expect_failure "file not found" --platform gnome \
  --model-assert "${tmp_dir}/missing.model" --account-key "${tmp_dir}/inputs/account-key.assert" \
  --snap "${tmp_dir}/inputs/core26-desktop.snap" --snap "${tmp_dir}/inputs/pc-desktop.snap" \
  --snap "${tmp_dir}/inputs/snapd.snap" --out "${tmp_dir}/invalid"

"${pack_image}" --platform gnome \
  --model-assert "${tmp_dir}/inputs/model.assert" \
  --account-key "${tmp_dir}/inputs/account-key.assert" \
  --snap "${tmp_dir}/inputs/core26-desktop.snap" \
  --snap "${tmp_dir}/inputs/pc-desktop.snap" \
  --snap "${tmp_dir}/inputs/snapd.snap" \
  --snap "${tmp_dir}/inputs/ubuntu-desktop-session.snap" \
  --snap "${tmp_dir}/inputs/gnome-desktop-runtime.snap" \
  --snap "${tmp_dir}/inputs/pipewire.snap" \
  --snap "${tmp_dir}/inputs/ubuntu-desktop-init.snap" \
  --out "${tmp_dir}/build"

[[ $(stat -c %s "${tmp_dir}/build/pc.img") == $((20 * 1024 * 1024 * 1024)) ]]
[[ -f ${tmp_dir}/build/project/imagecraft.yaml ]]
[[ -f ${tmp_dir}/build/project/model.assert && -f ${tmp_dir}/build/project/account-key.assert ]]
[[ $(<"${tmp_dir}/build/unrelated-output") == 'keep this output' ]]
[[ $(<"${tmp_dir}/build/model.assert") == 'pre-existing model output' ]]
for snap in core26-desktop pc-desktop snapd ubuntu-desktop-session gnome-desktop-runtime pipewire ubuntu-desktop-init; do
  [[ -f ${tmp_dir}/build/project/snaps/${snap}.snap ]]
  grep -Fq "snaps/${snap}.snap" "${tmp_dir}/build/project/imagecraft.yaml"
done
grep -Fq 'build-base: ubuntu@26.04' "${tmp_dir}/build/project/imagecraft.yaml"
grep -Fq 'size: 7000M' "${tmp_dir}/build/project/imagecraft.yaml"
grep -Fq 'size: 750M' "${tmp_dir}/build/project/imagecraft.yaml"
grep -Fq 'size: 32M' "${tmp_dir}/build/project/imagecraft.yaml"
grep -Fq 'size: 1G' "${tmp_dir}/build/project/imagecraft.yaml"
! grep -Fq 'boot-assets:' "${tmp_dir}/build/project/imagecraft.yaml"
! grep -Fq 'mbr:' "${tmp_dir}/build/project/imagecraft.yaml"
cmp "${tmp_dir}/captured-imagecraft.yaml" "${tmp_dir}/build/project/imagecraft.yaml"
reference_hash=79400dad6c3653b13f906ed0050941949b80239fdfcde32cb5cd02810df689e2
# Golden checksum from the ticket 08 hand-rendered project.
render_hash="$(sha256sum "${tmp_dir}/build/project/imagecraft.yaml" | cut -d' ' -f1)"
[[ ${render_hash} == ${reference_hash} ]]

"${pack_image}" --platform gnome \
  --model-assert "${tmp_dir}/inputs/model.assert" \
  --account-key "${tmp_dir}/inputs/account-key.assert" \
  --snap "${tmp_dir}/inputs/core26-desktop.snap" \
  --snap "${tmp_dir}/inputs/pc-desktop.snap" \
  --snap "${tmp_dir}/inputs/snapd.snap" \
  --snap "${tmp_dir}/inputs/ubuntu-desktop-session.snap" \
  --snap "${tmp_dir}/inputs/gnome-desktop-runtime.snap" \
  --snap "${tmp_dir}/inputs/pipewire.snap" \
  --snap "${tmp_dir}/inputs/ubuntu-desktop-init.snap" \
  --image-size 3G \
  --out "${tmp_dir}/build"
[[ $(stat -c %s "${tmp_dir}/build/pc.img") == $((3 * 1024 * 1024 * 1024)) ]]
[[ $(<"${tmp_dir}/build/unrelated-output") == 'keep this output' ]]
[[ $(<"${tmp_dir}/build/model.assert") == 'pre-existing model output' ]]
[[ ! -e ${tmp_dir}/build/project/pc.img ]]

expect_failure "packed image is larger than requested --image-size" --platform gnome \
  --model-assert "${tmp_dir}/inputs/model.assert" \
  --account-key "${tmp_dir}/inputs/account-key.assert" \
  --snap "${tmp_dir}/inputs/core26-desktop.snap" \
  --snap "${tmp_dir}/inputs/pc-desktop.snap" \
  --snap "${tmp_dir}/inputs/snapd.snap" \
  --image-size 1G \
  --out "${tmp_dir}/build"
[[ ! -e ${tmp_dir}/build/pc.img ]]
[[ -f ${tmp_dir}/build/project/imagecraft.yaml ]]

printf 'pack-image CLI tests passed\n'
