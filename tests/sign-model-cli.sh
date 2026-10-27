#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sign_model="${repo_root}/steps/sign-model.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/bin" "${tmp_dir}/platforms/gnome"
cp "${repo_root}/platforms/gnome/model.json" "${tmp_dir}/platforms/gnome/model.json"
printf 'signed model assertion\n' >"${tmp_dir}/presigned.model"
printf 'keep this output\n' >"${tmp_dir}/other-output"
mkdir -p "${tmp_dir}/build/project"
printf 'keep the packed image\n' >"${tmp_dir}/build/pc.img"
printf 'keep the staged project\n' >"${tmp_dir}/build/project/imagecraft.yaml"
printf 'stale model assertion\n' >"${tmp_dir}/build/model.assert"

cat >"${tmp_dir}/bin/snap" <<'SH'
#!/usr/bin/env bash
[[ $1 == sign && $2 == -k && $3 == test-key && $4 == --update-timestamp ]] || exit 10
cat "${5}"
printf '\nsigned by test stub\n'
SH
chmod +x "${tmp_dir}/bin/snap"
export PATH="${tmp_dir}/bin:${PATH}"

help_output="$("${sign_model}" --help)"
[[ ${help_output} == *"--platform"* && ${help_output} == *"--model"* && ${help_output} == *"--out"* ]]

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("${sign_model}" "$@" 2>&1)"; then
    printf 'expected failure: %s\n' "${expected}" >&2
    exit 1
  fi
  [[ ${output} == *"${expected}"* ]] || {
    printf 'missing error %q in output:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  }
}

expect_failure "--platform or --model is required" --out "${tmp_dir}/invalid"
expect_failure "unknown platform: xfce" --platform xfce --out "${tmp_dir}/invalid"
expect_failure "model file not found" --model "${tmp_dir}/missing.json" --out "${tmp_dir}/invalid"

SNAP_SIGN_KEY=test-key "${sign_model}" --platform gnome --out "${tmp_dir}/build"
if cmp "${tmp_dir}/platforms/gnome/model.json" "${tmp_dir}/build/model.assert" >/dev/null; then
  printf 'expected default model to be signed\n' >&2
  exit 1
fi
grep -q '^signed by test stub$' "${tmp_dir}/build/model.assert"
[[ $(<"${tmp_dir}/other-output") == 'keep this output' ]]
[[ $(<"${tmp_dir}/build/pc.img") == 'keep the packed image' ]]
[[ $(<"${tmp_dir}/build/project/imagecraft.yaml") == 'keep the staged project' ]]
[[ $(<"${tmp_dir}/build/model.assert") != 'stale model assertion' ]]

SNAP_SIGN_KEY=test-key "${sign_model}" --model "${tmp_dir}/platforms/gnome/model.json" --out "${tmp_dir}/build"
grep -q '^signed by test stub$' "${tmp_dir}/build/model.assert"
[[ $(<"${tmp_dir}/other-output") == 'keep this output' ]]

"${sign_model}" --model "${tmp_dir}/presigned.model" --out "${tmp_dir}/build"
cmp "${tmp_dir}/presigned.model" "${tmp_dir}/build/model.assert"
[[ $(<"${tmp_dir}/other-output") == 'keep this output' ]]
[[ $(<"${tmp_dir}/build/pc.img") == 'keep the packed image' ]]
[[ $(<"${tmp_dir}/build/project/imagecraft.yaml") == 'keep the staged project' ]]

printf 'sign-model CLI tests passed\n'
