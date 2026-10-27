#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
boot_check="${repo_root}/tools/boot-check.sh"

help_output="$("${boot_check}" --help)"
[[ ${help_output} == *"--platform gnome|kde"* ]]
[[ ${help_output} == *"[--connections FILE]"* ]]

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("${boot_check}" "$@" 2>&1)"; then
    printf 'expected failure: %s\n' "${expected}" >&2
    exit 1
  fi
  [[ ${output} == *"${expected}"* ]] || {
    printf 'missing error %q in output:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  }
}

expect_failure "--platform is required" "${tmp_dir}/missing.img"
expect_failure "unknown platform: xfce" --platform xfce "${tmp_dir}/missing.img"
expect_failure "--autologin requires --user" --platform gnome --autologin "${tmp_dir}/missing.img"
expect_failure "--timeout must be a positive integer" --platform gnome --timeout 0 "${tmp_dir}/missing.img"
expect_failure "image not found" --platform gnome "${tmp_dir}/missing.img"
touch "${tmp_dir}/report.txt"
expect_failure "output already contains a boot-check artifact" --platform gnome \
  --out "${tmp_dir}" --connections "${tmp_dir}/report.txt" "${BASH_SOURCE[0]}"

printf 'boot-check CLI tests passed\n'
