#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repack="${repo_root}/steps/repack.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/bin" "${tmp_dir}/inputs" "${tmp_dir}/capture" "${tmp_dir}/fixtures/gadget/meta" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/usr/share/wayland-sessions" \
  "${tmp_dir}/fixtures/base/usr/lib/systemd/system" \
  "${tmp_dir}/fixtures/base/usr/share/wayland-sessions" \
  "${tmp_dir}/fixtures/base/usr/bin" "${tmp_dir}/out/snaps"
printf 'base snap\n' >"${tmp_dir}/inputs/base.snap"
printf 'gadget snap\n' >"${tmp_dir}/inputs/gadget.snap"
printf 'unrelated output\n' >"${tmp_dir}/out/keep.txt"
printf 'stale base\n' >"${tmp_dir}/out/snaps/base.snap"
printf 'stale gadget\n' >"${tmp_dir}/out/snaps/gadget.snap"
printf 'base: core26\n' >"${tmp_dir}/fixtures/gadget/meta/snap.yaml"
printf 'volumes:\n  - name: BIOS Boot\ndefaults:\n  system:\n    service:\n      ssh:\n        listen-address: 127.0.0.1\n' >"${tmp_dir}/fixtures/gadget/meta/gadget.yaml"
printf 'factory base\n' >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants/.fixture"
printf 'base systemd\n' >"${tmp_dir}/fixtures/base/usr/lib/systemd/system/.fixture"
printf 'plasma session\n' >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/usr/share/wayland-sessions/plasma-desktop-session.desktop"
printf '#!/bin/sh\nexit 0\n' >"${tmp_dir}/fixtures/base/usr/bin/gnome-session"
chmod +x "${tmp_dir}/fixtures/base/usr/bin/gnome-session"

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
  if [[ ${NO_CLOUD_INIT:-0} == 1 ]]; then
    printf 'squashfs-root/etc/os-release\n'
  else
    printf 'squashfs-root/etc/cloud/cloud.cfg\n'
  fi
  exit 0
fi
[[ $1 == -d ]] || exit 10
dest=$2
snap=$3
case "$(basename "$snap")" in
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
cp -a "$src" "${CAPTURED_ROOT}/$(basename "$(dirname "$dest")")-$(basename "$dest" .snap)"
printf 'packed:%s\n' "$(basename "$(dirname "$dest")")-$(basename "$dest" .snap)" >"$dest"
SH
chmod +x "${tmp_dir}/bin/fakeroot" "${tmp_dir}/bin/unsquashfs" "${tmp_dir}/bin/mksquashfs"
export PATH="${tmp_dir}/bin:${PATH}"
export BASE_FIXTURE="${tmp_dir}/fixtures/base"
export GADGET_FIXTURE="${tmp_dir}/fixtures/gadget"
export CAPTURED_ROOT="${tmp_dir}/capture"

help_output="$("${repack}" --help)"
[[ ${help_output} == *"--platform"* && ${help_output} == *"--base-snap"* && ${help_output} == *"--gadget-snap"* && ${help_output} == *"--out"* ]]

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("${repack}" "$@" 2>&1)"; then
    printf 'expected failure: %s\n' "${expected}" >&2
    exit 1
  fi
  [[ ${output} == *"${expected}"* ]] || {
    printf 'missing error %q in output:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  }
}

expect_failure "--platform is required" --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --out "${tmp_dir}/invalid"
expect_failure "unknown platform: xfce" --platform xfce --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --out "${tmp_dir}/invalid"
NO_CLOUD_INIT=1 expect_failure "--user requires a base snap with cloud-init" --platform gnome \
  --base-snap "${tmp_dir}/inputs/base.snap" --gadget-snap "${tmp_dir}/inputs/gadget.snap" \
  --user alice --out "${tmp_dir}/invalid"

success_output="$("${repack}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --out "${tmp_dir}/out" 2>&1)"
[[ ${success_output} == *"repack: common/gadget.d/"* ]]
[[ ${success_output} == *"repack: common/base.d/"* ]]
[[ ${success_output} == *"repack: platforms/gnome/base.d/"* ]]
[[ ${success_output} == *"repack: common/development.d/"* ]]
[[ ${success_output} == *$'repack: common/gadget.d/10-base.sh\nrepack: common/gadget.d/20-bios-boot.sh\nrepack: common/gadget.d/30-connections.sh\nrepack: common/base.d/10-polkit-socket.sh\nrepack: platforms/gnome/base.d/10-gdm-homedirs.sh\nrepack: platforms/gnome/base.d/20-drop-plasma-session.sh\nrepack: platforms/gnome/base.d/30-gnome-session-wrapper.sh\nrepack: common/development.d/10-gadget-console.sh\nrepack: common/development.d/20-listen-address.sh\nrepack: common/development.d/30-root-ssh.sh\nrepack: common/development.d/40-serial-terminal.sh'* ]]
[[ $(<"${tmp_dir}/out/snaps/base.snap") == 'packed:snaps-base' ]]
[[ $(<"${tmp_dir}/out/snaps/gadget.snap") == 'packed:snaps-gadget' ]]
[[ $(<"${tmp_dir}/out/keep.txt") == 'unrelated output' ]]
[[ ! -e ${tmp_dir}/out/work ]]
grep -q '^base: core26-desktop$' "${tmp_dir}/capture/snaps-gadget/meta/snap.yaml"
grep -q '^  - name: bios-boot$' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
grep -q 'listen-address: 0.0.0.0' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
grep -q 'ubuntu-desktop-session:avahi-control' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
[[ -L ${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants/polkit-agent-helper.socket ]]
[[ -f ${tmp_dir}/capture/snaps-base/usr/lib/systemd/system/gdm-homedirs.service ]]
[[ -f ${tmp_dir}/capture/snaps-base/usr/lib/systemd/system/gdm.service.d/gdm-homedirs.conf ]]
[[ ! -e ${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/usr/share/wayland-sessions/plasma-desktop-session.desktop ]]
[[ -f ${tmp_dir}/capture/snaps-base/usr/bin/gnome-session.real ]]
[[ $(stat -c %a "${tmp_dir}/capture/snaps-base/usr/bin/gnome-session") == 755 ]]
grep -q 'core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME' "${tmp_dir}/capture/snaps-base/usr/bin/gnome-session"
grep -q 'console=ttyS0,115200n8' "${tmp_dir}/capture/snaps-gadget/cmdline.extra"
grep -q 'PermitRootLogin yes' "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/ssh/sshd_config"
grep -q 'stty rows 55 cols 86' "${tmp_dir}/capture/snaps-base/etc/profile.d/serial-terminal.sh"
! grep -q 'gnome-desktop-runtime:hardware-observe' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
! grep -q 'firefox:' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
! grep -q 'LVkazk0JLrL0ivuHRlv3wp3bK1nAgwtN:systemd-user-control' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"

rm -f "${tmp_dir}/fixtures/base/usr/bin/gnome-session"
failure_output=""
if failure_output="$("${repack}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --out "${tmp_dir}/out" 2>&1)"; then
  printf 'expected missing GNOME wrapper input to fail\n' >&2
  exit 1
fi
[[ ${failure_output} == *"repack: platforms/gnome/base.d/"* && ${failure_output} == *"failed (exit 1); work tree kept at"* ]]
[[ -d ${tmp_dir}/out/work ]]
[[ ! -e ${tmp_dir}/out/snaps/base.snap && ! -e ${tmp_dir}/out/snaps/gadget.snap ]]
[[ $(<"${tmp_dir}/out/keep.txt") == 'unrelated output' ]]

printf 'repack CLI tests passed\n'
