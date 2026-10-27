#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build="${repo_root}/build.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/bin" "${tmp_dir}/inputs" "${tmp_dir}/captured" "${tmp_dir}/fixtures/gadget/meta" \
  "${tmp_dir}/fixtures/base/etc/cloud" \
  "${tmp_dir}/fixtures/base/etc" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/ssh" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc" \
  "${tmp_dir}/fixtures/base/etc/writable/gdm3" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/writable/gdm3" \
  "${tmp_dir}/out/gnome" "${tmp_dir}/out/kde"
for input in base gadget snapd account extra; do
  printf '%s input\n' "${input}" >"${tmp_dir}/inputs/${input}.snap"
done
printf 'model input\n' >"${tmp_dir}/inputs/model.json"
printf 'private key fixture\n' >"${tmp_dir}/inputs/host-key"
printf 'base: core26\n' >"${tmp_dir}/fixtures/gadget/meta/snap.yaml"
printf 'volumes:\n  - name: BIOS Boot\ndefaults:\n  system:\n    service:\n      ssh:\n        listen-address: 127.0.0.1\n' \
  >"${tmp_dir}/fixtures/gadget/meta/gadget.yaml"
printf 'quiet splash\n' >"${tmp_dir}/fixtures/gadget/cmdline.extra"
printf 'PermitRootLogin prohibit-password\n' \
  >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/ssh/sshd_config"
printf 'cloud-init fixture\n' >"${tmp_dir}/fixtures/base/etc/cloud/cloud.cfg"
printf 'root:*:20000:0:99999:7:::\n' >"${tmp_dir}/fixtures/base/etc/shadow"
printf 'root:*:20000:0:99999:7:::\n' \
  >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/shadow"
printf '[daemon]\nInitialSetupEnable=true\n' >"${tmp_dir}/fixtures/base/etc/writable/gdm3/custom.conf"
printf '[daemon]\nInitialSetupEnable=true\n' \
  >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
mkdir -p "${tmp_dir}/fixtures/base/usr/bin"
printf '#!/bin/sh\nexit 0\n' >"${tmp_dir}/fixtures/base/usr/bin/gnome-session"
chmod +x "${tmp_dir}/fixtures/base/usr/bin/gnome-session"
printf 'keep this output\n' >"${tmp_dir}/out/gnome/unrelated.txt"
printf 'keep KDE output\n' >"${tmp_dir}/out/kde/unrelated.txt"
printf 'stale seed\n' >"${tmp_dir}/out/gnome/seed.iso"

cat >"${tmp_dir}/bin/fakeroot" <<'SH'
#!/usr/bin/env bash
[[ $1 == -- ]] || exit 10
shift
export FAKEROOTKEY=1
exec "$@"
SH
cat >"${tmp_dir}/bin/unsquashfs" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == -l ]]; then
  printf 'squashfs-root/etc/cloud/cloud.cfg\n'
  exit 0
fi
[[ $1 == -d ]] || exit 10
dest=$2
case "$(basename "$3")" in
  base.snap) cp -a "${BASE_FIXTURE}/." "$dest/" ;;
  gadget.snap) cp -a "${GADGET_FIXTURE}/." "$dest/" ;;
  *) exit 11 ;;
esac
SH
cat >"${tmp_dir}/bin/mksquashfs" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
src=$1
dest=$2
mkdir -p "$(dirname "$dest")"
cp -a "$src" "${CAPTURED_ROOT}/$(basename "$dest" .snap)"
printf 'packed:%s\n' "$(basename "$dest")" >"$dest"
SH
cat >"${tmp_dir}/bin/snap" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == sign && $2 == -k && $4 == --update-timestamp ]] || exit 10
cat "$5"
printf 'signed model\n'
SH
cat >"${tmp_dir}/bin/imagecraft" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == pack && $2 == --use-lxd && $3 == --verbose ]] || exit 10
[[ -f imagecraft.yaml ]] || exit 11
printf 'fake image\n' >pc.img
SH
chmod +x "${tmp_dir}/bin/fakeroot" "${tmp_dir}/bin/unsquashfs" \
  "${tmp_dir}/bin/mksquashfs" "${tmp_dir}/bin/snap" "${tmp_dir}/bin/imagecraft"
export PATH="${tmp_dir}/bin:${PATH}"
export BASE_FIXTURE="${tmp_dir}/fixtures/base"
export GADGET_FIXTURE="${tmp_dir}/fixtures/gadget"
export CAPTURED_ROOT="${tmp_dir}/captured"

help_output="$("${build}" --help)"
[[ ${help_output} == *"--platform"* && ${help_output} == *"--base-snap"* && \
  ${help_output} == *"--gadget-snap"* && ${help_output} == *"--snapd-snap"* && \
  ${help_output} == *"--model-account-key"* && ${help_output} == *"--build-dir"* && \
  ${help_output} == *"--release"* && ${help_output} == *"--user"* && \
  ${help_output} == *"--password"* && ${help_output} == *"--autologin"* && \
  ${help_output} == *"--root-password"* && ${help_output} == *"--ssh-authorized-keys"* && \
  ${help_output} == *"--ssh-host-key"* && ${help_output} == *"--debug"* ]]

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("${build}" "$@" 2>&1)"; then
    printf 'expected failure: %s\n' "${expected}" >&2
    exit 1
  fi
  [[ ${output} == *"${expected}"* ]] || {
    printf 'missing error %q in output:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  }
}

expect_failure "--platform is required" --base-snap "${tmp_dir}/inputs/base.snap"
expect_failure "unknown platform: xfce" --platform xfce
expect_failure "file not found" --platform gnome --base-snap "${tmp_dir}/missing.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --snapd-snap "${tmp_dir}/inputs/snapd.snap" \
  --model-account-key "${tmp_dir}/inputs/account.snap" --build-dir "${tmp_dir}/not-created"
[[ ! -e ${tmp_dir}/not-created ]]
build_inputs=(--platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --snapd-snap "${tmp_dir}/inputs/snapd.snap" \
  --model-account-key "${tmp_dir}/inputs/account.snap")
expect_failure "--user and --password must be provided together" \
  "${build_inputs[@]}" --user alice
expect_failure "--user and --password must be provided together" \
  "${build_inputs[@]}" --password secret
expect_failure "--autologin requires --user" "${build_inputs[@]}" --autologin
expect_failure "--ssh-host-key expects a matching .pub file" \
  "${build_inputs[@]}" --ssh-host-key "${tmp_dir}/inputs/host-key"

pipeline_output="$("${build}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --snapd-snap "${tmp_dir}/inputs/snapd.snap" \
  --model-account-key "${tmp_dir}/inputs/account.snap" \
  --snap "${tmp_dir}/inputs/extra.snap" --build-dir "${tmp_dir}/out/gnome" 2>&1)"
[[ ${pipeline_output} == *'repack: common/development.d/40-serial-terminal.sh'*'sign-model:'*'pack-image:'*'build: built '* ]]
[[ ${pipeline_output} == *'no developer options; skipping developer pieces'* ]]
[[ ${pipeline_output} != *'/developer.d/'* ]]
[[ ! -e ${tmp_dir}/out/gnome/seed.iso ]]

[[ -f ${tmp_dir}/out/gnome/snaps/base.snap ]]
[[ -f ${tmp_dir}/out/gnome/snaps/gadget.snap ]]
[[ -f ${tmp_dir}/out/gnome/model.assert ]]
[[ -f ${tmp_dir}/out/gnome/pc.img ]]
[[ $(<"${tmp_dir}/out/gnome/unrelated.txt") == 'keep this output' ]]
[[ $(<"${tmp_dir}/out/kde/unrelated.txt") == 'keep KDE output' ]]
[[ $(<"${tmp_dir}/out/gnome/snaps/base.snap") == 'packed:base.snap' ]]
grep -q 'snaps/extra.snap' "${tmp_dir}/out/gnome/project/imagecraft.yaml"

printf 'ssh-ed25519 AAAATEST test-key\n' >"${tmp_dir}/inputs/authorized_keys"
printf 'private host key fixture\n' >"${tmp_dir}/inputs/host-key"
printf 'ssh-ed25519 AAAAHOST test-host\n' >"${tmp_dir}/inputs/host-key.pub"
developer_output="$("${build}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --snapd-snap "${tmp_dir}/inputs/snapd.snap" \
  --model-account-key "${tmp_dir}/inputs/account.snap" --user alice --password user-secret \
  --root-password root-secret --ssh-authorized-keys "${tmp_dir}/inputs/authorized_keys" \
  --ssh-host-key "${tmp_dir}/inputs/host-key" --autologin \
  --build-dir "${tmp_dir}/out/developer" 2>&1)"
[[ ${developer_output} == *'seed: wrote NoCloud seed ISO:'* ]]
[[ ${developer_output} == *'build: built '*'/seed.iso'* ]]
[[ ${developer_output} == *'repack: common/developer.d/'* && \
  ${developer_output} == *'repack: platforms/gnome/developer.d/'* ]]
grep -R -q 'AutomaticLogin=alice' "${tmp_dir}/captured/base"
grep -q 'console=ttyS0,115200n8' \
  "${tmp_dir}/captured/gadget/cmdline.extra"
[[ -f ${tmp_dir}/out/developer/seed.iso ]]
! grep -R -Fq 'user-secret' "${tmp_dir}/captured"
! grep -R -Fq 'root-secret' "${tmp_dir}/captured"

rm -rf -- "${tmp_dir}/captured/base" "${tmp_dir}/captured/gadget"
release_output="$("${build}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --snapd-snap "${tmp_dir}/inputs/snapd.snap" \
  --model-account-key "${tmp_dir}/inputs/account.snap" --release \
  --root-password root-secret --ssh-authorized-keys "${tmp_dir}/inputs/authorized_keys" \
  --build-dir "${tmp_dir}/out/release" 2>&1)"
[[ ${release_output} == *"building gnome Release image"* ]]
[[ ${release_output} == *"warning: root password/authorized keys may be inaccessible"* ]]
[[ ${release_output} == *'build: warning: root password/authorized keys may be inaccessible'* ]]
[[ ${release_output} != *"repack: common/development.d/"* ]]
grep -q '^quiet splash$' "${tmp_dir}/captured/gadget/cmdline.extra"
grep -q 'listen-address: 127.0.0.1' "${tmp_dir}/captured/gadget/meta/gadget.yaml"
! grep -q 'PermitRootLogin yes' "${tmp_dir}/captured/base/usr/share/factory/writable/system-data/etc/ssh/sshd_config"
[[ ! -e ${tmp_dir}/captured/base/etc/profile.d/serial-terminal.sh ]]

printf 'build CLI tests passed\n'
