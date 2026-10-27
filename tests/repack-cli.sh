#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repack="${repo_root}/steps/repack.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/bin" "${tmp_dir}/inputs" "${tmp_dir}/capture" \
  "${tmp_dir}/fixtures/gadget/meta" "${tmp_dir}/fixtures/gadget" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/ssh" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/root" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/sudoers.d" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/writable/gdm3" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/usr/share/wayland-sessions" \
  "${tmp_dir}/fixtures/base/etc/ssh" "${tmp_dir}/fixtures/base/root" \
  "${tmp_dir}/fixtures/base/etc" \
  "${tmp_dir}/fixtures/base/etc/sudoers.d" \
  "${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/writable/gdm3" \
  "${tmp_dir}/fixtures/base/usr/lib/systemd/system" \
  "${tmp_dir}/fixtures/base/usr/share/wayland-sessions" \
  "${tmp_dir}/fixtures/base/usr/bin" "${tmp_dir}/out/snaps"
printf 'base snap\n' >"${tmp_dir}/inputs/base.snap"
printf 'gadget snap\n' >"${tmp_dir}/inputs/gadget.snap"
printf 'unrelated output\n' >"${tmp_dir}/out/keep.txt"
printf 'stale base\n' >"${tmp_dir}/out/snaps/base.snap"
printf 'stale gadget\n' >"${tmp_dir}/out/snaps/gadget.snap"
printf 'base: core26\n' >"${tmp_dir}/fixtures/gadget/meta/snap.yaml"
printf 'volumes:\n  - name: BIOS Boot\ndefaults:\n  system:\n    service:\n      ssh:\n        listen-address: 0.0.0.0\n' >"${tmp_dir}/fixtures/gadget/meta/gadget.yaml"
printf 'systemd.journald.forward_to_console=1 systemd.journald.max_level_console=err console=ttyS0,115200n8\n' \
  >"${tmp_dir}/fixtures/gadget/cmdline.extra"
printf 'PermitRootLogin prohibit-password\n' \
  >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/ssh/sshd_config"
printf 'PermitRootLogin prohibit-password\n' >"${tmp_dir}/fixtures/base/etc/ssh/sshd_config"
printf 'root:*:20000:0:99999:7:::\n' >"${tmp_dir}/fixtures/base/etc/shadow"
printf 'alice:*:20000:0:99999:7:::\n' >>"${tmp_dir}/fixtures/base/etc/shadow"
printf 'root:*:20000:0:99999:7:::\n' \
  >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/shadow"
printf 'alice:*:20000:0:99999:7:::\n' \
  >>"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/shadow"
printf '[daemon]\nInitialSetupEnable=true\n' \
  >"${tmp_dir}/fixtures/base/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
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
[[ ${help_output} == *"--platform"* && ${help_output} == *"--base-snap"* && \
  ${help_output} == *"--gadget-snap"* && ${help_output} == *"--out"* && \
  ${help_output} == *"--release"* && ${help_output} == *"--password"* && \
  ${help_output} == *"--ssh-authorized-keys"* && ${help_output} == *"--debug"* ]]

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
expect_failure "--user and --password must be provided together" \
  --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --user alice --out "${tmp_dir}/invalid"

expect_failure "--platform is required" --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --out "${tmp_dir}/invalid"
expect_failure "unknown platform: xfce" --platform xfce --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --out "${tmp_dir}/invalid"
NO_CLOUD_INIT=1 expect_failure "core26-desktop-cloudinit" --platform gnome \
  --base-snap "${tmp_dir}/inputs/base.snap" --gadget-snap "${tmp_dir}/inputs/gadget.snap" \
  --user alice --password secret --out "${tmp_dir}/invalid"
[[ ! -e ${tmp_dir}/invalid/work ]]

success_output="$("${repack}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --out "${tmp_dir}/out" 2>&1)"
[[ ${success_output} == *"repack: common/gadget.d/"* ]]
[[ ${success_output} == *"repack: common/base.d/"* ]]
[[ ${success_output} == *"repack: platforms/gnome/base.d/"* ]]
[[ ${success_output} == *"repack: common/development.d/"* ]]
[[ ${success_output} == *"no developer options; skipping developer pieces"* ]]
[[ ${success_output} != *"/developer.d/"* ]]
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

rm -rf -- "${tmp_dir}/capture/snaps-base" "${tmp_dir}/capture/snaps-gadget"
release_output="$("${repack}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --release --out "${tmp_dir}/out" 2>&1)"
[[ ${release_output} == *"repack: common/base.d/"* ]]
[[ ${release_output} == *"repack: common/gadget.d/40-release-cmdline.sh"* ]]
[[ ${release_output} == *"repack: common/gadget.d/50-release-ssh.sh"* ]]
[[ ${release_output} != *"repack: common/development.d/"* ]]
grep -q '^quiet splash$' "${tmp_dir}/capture/snaps-gadget/cmdline.extra"
grep -q 'listen-address: 127.0.0.1' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
! grep -q 'PermitRootLogin yes' "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/ssh/sshd_config"
[[ ! -e ${tmp_dir}/capture/snaps-base/etc/profile.d/serial-terminal.sh ]]

printf 'ssh-ed25519 AAAATEST test-key\n' >"${tmp_dir}/inputs/authorized_keys"
printf 'private host key fixture\n' >"${tmp_dir}/inputs/host-key"
printf 'ssh-ed25519 AAAAHOST test-host\n' >"${tmp_dir}/inputs/host-key.pub"
rm -rf -- "${tmp_dir}/capture/snaps-base" "${tmp_dir}/capture/snaps-gadget"
developer_output="$("${repack}" --platform gnome --base-snap "${tmp_dir}/inputs/base.snap" \
  --gadget-snap "${tmp_dir}/inputs/gadget.snap" --user alice --password user-secret \
  --autologin --root-password root-secret --ssh-authorized-keys "${tmp_dir}/inputs/authorized_keys" \
  --ssh-host-key "${tmp_dir}/inputs/host-key" --debug --out "${tmp_dir}/out" 2>&1)"
[[ ${developer_output} == *"repack: common/developer.d/"* ]]
[[ ${developer_output} == *"repack: platforms/gnome/developer.d/"* ]]
[[ ${developer_output} == *"warning: root password/authorized keys may be inaccessible"* ]]
grep -q '^snapd.debug=1 systemd.log_target=console systemd.journald.forward_to_console=1 console=ttyS0,115200n8$' \
  "${tmp_dir}/capture/snaps-gadget/cmdline.extra"
for path in \
  usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants/polkit-agent-helper.socket \
  usr/lib/systemd/system/gdm-homedirs.service \
  usr/lib/systemd/system/gdm.service.d/gdm-homedirs.conf \
  usr/bin/gnome-session.real \
  usr/bin/gnome-session \
  usr/share/factory/writable/system-data/root/.ssh/authorized_keys \
  usr/share/factory/writable/system-data/etc/ssh/sshd_config \
  usr/share/factory/writable/system-data/etc/ssh/ssh_host_ed25519_key \
  etc/shadow \
  usr/share/factory/writable/system-data/etc/shadow \
  usr/share/factory/writable/system-data/etc/sudoers.d/alice; do
  if [[ ! -e ${tmp_dir}/capture/snaps-base/${path} ]]; then
    printf 'missing repacked file: %s\n' "${path}" >&2
    exit 1
  fi
done
[[ -L ${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/systemd/system/sockets.target.wants/polkit-agent-helper.socket ]]
[[ -f ${tmp_dir}/capture/snaps-base/usr/lib/systemd/system/gdm-homedirs.service ]]
[[ -f ${tmp_dir}/capture/snaps-base/usr/lib/systemd/system/gdm.service.d/gdm-homedirs.conf ]]
[[ $(stat -c %a "${tmp_dir}/capture/snaps-base/usr/bin/gnome-session") == 755 ]]
grep -q 'core-desktop-session-wrapper.sh ubuntu-desktop-session ubuntu:GNOME' \
  "${tmp_dir}/capture/snaps-base/usr/bin/gnome-session"
! grep -q 'PermitRootLogin yes' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/ssh/sshd_config"
[[ ! -e ${tmp_dir}/capture/snaps-base/etc/profile.d/serial-terminal.sh ]]
grep -q 'alice ALL=(ALL) NOPASSWD: ALL' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/sudoers.d/alice"
[[ ! -e ${tmp_dir}/capture/snaps-base/etc/sudoers.d/alice ]]
grep -q 'AutomaticLogin=alice' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
[[ ! -e ${tmp_dir}/capture/snaps-base/etc/writable/gdm3/custom.conf && \
  ! -L ${tmp_dir}/capture/snaps-base/etc/writable/gdm3/custom.conf ]]
[[ ! -e ${tmp_dir}/capture/snaps-base/usr/lib/systemd/user/user-session-migration.service.d/kde-override.conf ]]
grep -q 'ssh-ed25519 AAAATEST test-key' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/root/.ssh/authorized_keys"
[[ ! -e ${tmp_dir}/capture/snaps-base/root/.ssh/authorized_keys ]]
grep -q 'HostKey /etc/ssh/ssh_host_ed25519_key' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/ssh/sshd_config"
[[ ! -e ${tmp_dir}/capture/snaps-base/etc/ssh/ssh_host_ed25519_key ]]
[[ $(stat -c %a "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/ssh/ssh_host_ed25519_key") == 600 ]]
grep -Eq '^root:\$6\$[^:]+:[^:]*:' "${tmp_dir}/capture/snaps-base/etc/shadow"
grep -q '^root:\*:' "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/shadow"
if grep -R -l -F 'root-secret' "${tmp_dir}/capture"; then
  printf 'root password leaked into captured snap contents\n' >&2
  exit 1
fi
if grep -R -l -F 'user-secret' "${tmp_dir}/capture"; then
  printf 'user password leaked into captured snap contents\n' >&2
  exit 1
fi
grep -q '^base: core26-desktop$' "${tmp_dir}/capture/snaps-gadget/meta/snap.yaml"
grep -q '^  - name: bios-boot$' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
grep -q 'listen-address: 0.0.0.0' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
grep -q 'console=ttyS0,115200n8' "${tmp_dir}/capture/snaps-gadget/cmdline.extra"
! grep -q 'gnome-desktop-runtime:hardware-observe' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
! grep -q 'firefox:' "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
! grep -q 'LVkazk0JLrL0ivuHRlv3wp3bK1nAgwtN:systemd-user-control' \
  "${tmp_dir}/capture/snaps-gadget/meta/gadget.yaml"
grep -q 'AutomaticLoginEnable=true' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
grep -q 'AutomaticLogin=alice' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
grep -q 'InitialSetupEnable=false' \
  "${tmp_dir}/capture/snaps-base/usr/share/factory/writable/system-data/etc/writable/gdm3/custom.conf"
! grep -R -Fq 'root-secret' "${tmp_dir}/capture"
! grep -R -Fq 'user-secret' "${tmp_dir}/capture"

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
