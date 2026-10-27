#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
boot_check="${repo_root}/tools/boot-check.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/bin" \
  "${tmp_dir}/out-gnome" "${tmp_dir}/out-kde"
printf 'input image is immutable\n' >"${tmp_dir}/pc.img"
printf 'seed placeholder\n' >"${tmp_dir}/seed.iso"
printf 'session:desktop ubuntu-desktop-init:desktop\n' >"${tmp_dir}/connections"

cat >"${tmp_dir}/bin/qemu-system-x86_64" <<'PY'
#!/usr/bin/env python3
import os
import socket
import sys
import time

args = sys.argv[1:]
monitor_path = next(arg.split("unix:", 1)[1].split(",", 1)[0] for arg in args if arg.startswith("unix:"))
serial_path = next(arg.split("file:", 1)[1] for arg in args if arg.startswith("file:"))
open(serial_path, "w", encoding="utf-8").write("mock serial output\n")
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(monitor_path)
    server.listen(1)
    connection, _ = server.accept()
    with connection:
        connection.sendall(b"QEMU monitor\r\n(qemu) ")
        pending = b""
        while True:
            data = connection.recv(4096)
            if not data:
                break
            pending += data
            while b"\n" in pending:
                command, pending = pending.split(b"\n", 1)
                if command.startswith(b"screendump "):
                    path = command.split(b'"', 2)[1].decode()
                    with open(path, "wb") as image:
                        image.write(b"P6\n1 1\n255\n\x00\x00\x00")
                    connection.sendall(b"\r\n(qemu) ")
                elif command == b"quit":
                    raise SystemExit(0)
                else:
                    connection.sendall(b"unknown command\r\n(qemu) ")
PY

cat >"${tmp_dir}/bin/sfdisk" <<'SH'
#!/usr/bin/env bash
cat <<'EOF'
label: gpt
device: test.img
unit: sectors
last-lba: 99999
sector-size: 512

test.img1 : start= 2048, size= 2048, type=21686148-6449-6E6F-744E-656564454649, name="bios-boot"
test.img2 : start= 4096, size= 95904, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="ubuntu-data"
EOF
SH

cat >"${tmp_dir}/bin/mount" <<'SH'
#!/usr/bin/env bash
fixture="${FIXTURE_ROOT}"
for argument in "$@"; do
  if [[ ${argument} == */ubuntu-data ]]; then
    case "${argument}" in
      */out-bad/ubuntu-data) fixture="${FIXTURE_ROOT%/gnome}/undesired" ;;
      *) fixture="${FIXTURE_ROOT}" ;;
    esac
    mkdir -p "${argument}"
    cp -a "${fixture}/." "$argument/"
    exit 0
  fi
done
exit 2
SH

cat >"${tmp_dir}/bin/umount" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat >"${tmp_dir}/bin/sudo" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == -v ]] && exit 0
exec "$@"
SH

cat >"${tmp_dir}/bin/journalctl" <<'SH'
#!/usr/bin/env bash
unit=""
priority=0
kernel=0
boot=""
while (($#)); do
  case "$1" in
    -u) unit="$2"; shift 2 ;;
    -p) priority=1; shift 2 ;;
    -b) boot="$2"; shift 2 ;;
    -D|-o) shift 2 ;;
    --*) shift ;;
    -k) kernel=1; shift ;;
    *) shift ;;
  esac
done
if [[ ${priority} == 1 ]]; then
  printf 'example.service: Failed with result exit-code\n'
elif [[ ${kernel} == 1 ]]; then
  if [[ ${boot} == 0 && ${JOURNAL_FIXTURE:-} == release-bad ]]; then
    printf 'Kernel command line: root=/dev/vda console=ttyS0 quiet splash\n'
  else
    printf 'Kernel command line: root=/dev/vda console=tty0 quiet splash\n'
  fi
elif [[ ${unit} == snapd.seeded.service ]]; then
  printf 'Finished snapd.seeded.service - Wait until snapd is fully seeded.\n'
elif [[ ${unit} == gdm.service ]]; then
  printf 'Started gdm.service - GNOME Display Manager.\n'
elif [[ ${unit} == sddm.service ]]; then
  printf 'Started sddm.service - Simple Desktop Display Manager.\n'
elif [[ ${unit} == user@1000.service ]]; then
  printf 'Started user@1000.service - User Manager for UID 1000.\n'
else
  printf 'Started user@60578.service - User Manager for UID 60578 (gnome-initial-setup).\n'
  printf 'example.service: Failed with result exit-code\n'
fi
SH

chmod +x "${tmp_dir}/bin/"*
export PATH="${tmp_dir}/bin:${PATH}"
export FIXTURE_ROOT="${tmp_dir}/fixture/gnome"

for scenario in gnome undesired; do
  mkdir -p "${tmp_dir}/fixture/${scenario}/system-data/var/log/journal" \
    "${tmp_dir}/fixture/${scenario}/system-data/var/lib/snapd" \
  "${tmp_dir}/fixture/${scenario}/system-data/var/lib/extrausers" \
    "${tmp_dir}/fixture/${scenario}/system-data/etc/systemd/system" \
    "${tmp_dir}/fixture/${scenario}/system-data/etc/ssh/sshd_config.d"
  printf 'alice:x:1000:1000:Alice:/home/alice:/bin/bash\n' \
    >"${tmp_dir}/fixture/${scenario}/system-data/var/lib/extrausers/passwd"
  printf '%s\n' 'fixture journal: gnome-initial-setup session started' \
    >"${tmp_dir}/fixture/${scenario}/system-data/var/log/journal/boot.log"
  ln -s /dev/null "${tmp_dir}/fixture/${scenario}/system-data/etc/systemd/system/gdm.service"
  if [[ ${scenario} == gnome ]]; then
    printf 'ListenAddress 127.0.0.1:8022\nListenAddress [::1]:8022\n' \
      >"${tmp_dir}/fixture/${scenario}/system-data/etc/ssh/sshd_config.d/listen.conf"
  fi
  if [[ ${scenario} == undesired ]]; then
    connection_state='{"interface":"desktop","undesired":true}'
  else
    connection_state='{"interface":"desktop"}'
  fi
  cat >"${tmp_dir}/fixture/${scenario}/system-data/var/lib/snapd/state.json" <<EOF
{"data":{"conns":{"session:desktop ubuntu-desktop-init:desktop":${connection_state}},"config":{"system":{"service.ssh.listen-address":"127.0.0.1"}}}}
EOF
done

"${boot_check}" --platform gnome --timeout 1 --out "${tmp_dir}/out-gnome" \
  --connections "${tmp_dir}/connections" "${tmp_dir}/pc.img" "${tmp_dir}/seed.iso"
grep -q '^PASS: snapd.seeded.service finished$' "${tmp_dir}/out-gnome/report.txt"
grep -q '^PASS: ubuntu-desktop-init wizard session started$' "${tmp_dir}/out-gnome/report.txt"
grep -q '^INFO:   example.service$' "${tmp_dir}/out-gnome/report.txt"
[[ -s ${tmp_dir}/out-gnome/serial.log ]]
[[ -s ${tmp_dir}/out-gnome/journal.log ]]
[[ -s ${tmp_dir}/out-gnome/sfdisk.txt ]]
[[ -s ${tmp_dir}/out-gnome/screenshot.ppm ]]
[[ ! -e ${tmp_dir}/out-gnome/pc.img.copy ]]

"${boot_check}" --platform kde --user alice --autologin --release --timeout 1 \
  --out "${tmp_dir}/out-kde" --connections "${tmp_dir}/connections" "${tmp_dir}/pc.img"
grep -q '^PASS: user alice is present in extrausers passwd$' "${tmp_dir}/out-kde/report.txt"
grep -q '^PASS: user@1000.service started$' "${tmp_dir}/out-kde/report.txt"
grep -q '^PASS: sddm.service started$' "${tmp_dir}/out-kde/report.txt"
grep -q '^PASS: gdm.service is masked$' "${tmp_dir}/out-kde/report.txt"
grep -q '^PASS: Release kernel command line has no console=ttyS0$' "${tmp_dir}/out-kde/report.txt"
grep -q '^PASS: Release SSH listen-address is not 0.0.0.0$' "${tmp_dir}/out-kde/report.txt"

export FIXTURE_ROOT="${tmp_dir}/fixture/gnome"
if JOURNAL_FIXTURE=release-bad "${boot_check}" --platform kde --release --timeout 1 --out "${tmp_dir}/out-release-bad" \
  --connections "${tmp_dir}/connections" "${tmp_dir}/pc.img"; then
  printf 'expected the development serial console to fail the release assertion\n' >&2
  exit 1
fi
grep -q '^FAIL: Release kernel command line contains console=ttyS0 or was not recorded$' \
  "${tmp_dir}/out-release-bad/report.txt"

export FIXTURE_ROOT="${tmp_dir}/fixture/gnome"
if "${boot_check}" --platform gnome --timeout 1 --out "${tmp_dir}/out-bad" \
  --connections "${tmp_dir}/connections" "${tmp_dir}/pc.img"; then
  printf 'expected the undesirable connection to fail\n' >&2
  exit 1
fi
grep -q '^FAIL: connection session:desktop ubuntu-desktop-init:desktop is missing or marked undesired$' \
  "${tmp_dir}/out-bad/report.txt"

printf 'boot-check offline assertion tests passed\n'
