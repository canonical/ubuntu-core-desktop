#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
seed="${repo_root}/steps/seed.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT
mkdir -p "${tmp_dir}/bin"
printf 'ssh-ed25519 AAAATEST test-key\n' >"${tmp_dir}/authorized_keys"

cat >"${tmp_dir}/bin/genisoimage" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == -output && $3 == -volid && $4 == cidata ]] || exit 10
output=$2
shift 6
cp "$1" "${CAPTURED_USER_DATA}"
cp "$2" "${CAPTURED_META_DATA}"
printf 'fixture ISO\n' >"${output}"
SH
chmod +x "${tmp_dir}/bin/genisoimage"
export PATH="${tmp_dir}/bin:${PATH}"
export CAPTURED_USER_DATA="${tmp_dir}/user-data"
export CAPTURED_META_DATA="${tmp_dir}/meta-data"

help_output="$("${seed}" --help)"
[[ ${help_output} == *"--user"* && ${help_output} == *"--password"* && \
  ${help_output} == *"--ssh-authorized-keys"* && ${help_output} == *"--output"* ]]

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("${seed}" "$@" 2>&1)"; then
    printf 'expected failure: %s\n' "${expected}" >&2
    exit 1
  fi
  [[ ${output} == *"${expected}"* ]] || {
    printf 'missing error %q in output:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  }
}
expect_failure "--user is required" --password secret
expect_failure "--password is required" --user alice

"${seed}" --user alice --password user-secret \
  --ssh-authorized-keys "${tmp_dir}/authorized_keys" --output "${tmp_dir}/seed.iso"
[[ -f ${tmp_dir}/seed.iso ]]
grep -q '^      type: hash$' "${tmp_dir}/user-data"
grep -q '^      password: \$6\$' "${tmp_dir}/user-data"
grep -Fq 'ssh-ed25519 AAAATEST test-key' "${tmp_dir}/user-data"
! grep -Fq 'user-secret' "${tmp_dir}/user-data"
grep -Eq '^      password: \$6\$[^[:space:]]+$' "${tmp_dir}/user-data"

if command -v isoinfo >/dev/null 2>&1 && command -v genisoimage >/dev/null 2>&1; then
  PATH="$(getconf PATH)" "${seed}" --user alice --password user-secret \
    --output "${tmp_dir}/real-seed.iso"
  iso_user_data="$(isoinfo -i "${tmp_dir}/real-seed.iso" -R -x /user-data)"
  [[ ${iso_user_data} == *'type: hash'* && ${iso_user_data} == *'password: $6$'* ]]
  [[ ${iso_user_data} != *'user-secret'* ]]
fi

printf 'seed CLI tests passed\n'
