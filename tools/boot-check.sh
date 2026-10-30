#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "${script_dir}")"
privileged_helper="${BOOT_CHECK_PRIVILEGED_HELPER:-/usr/local/sbin/core-desktop-boot-check-privileged}"

usage() {
  cat <<'EOF'
Usage: boot-check.sh --platform gnome|kde [--user NAME [--autologin]]
                      [--release] [--timeout SECONDS] [--out DIR]
                      pc.img [seed.iso]

Boot a copy of pc.img in QEMU, then check its journal and ubuntu-data
partition offline. QEMU runs for the full timeout (default: 600 seconds).

Options:
  --platform PLATFORM  Expected platform: gnome or kde (required)
  --user NAME          Expect the human user to be present
  --autologin          Also expect user@<uid>.service to have started
  --release            Check Release image boot settings
  --timeout SECONDS    QEMU runtime (positive integer, default: 600)
  --out DIR            Keep logs, journal, partition table, screenshot,
                       and report in DIR (default: a new temporary directory)
  --help               Show this help
EOF
}

quote_report_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "${value}"
}

die() {
  printf 'boot-check: %s\n' "$*" >&2
  exit 2
}

platform=""
user=""
user_set=0
autologin=0
release=0
timeout_seconds=600
out_dir=""
positionals=()

while (($#)); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --platform|--user|--timeout|--out)
      (($# >= 2)) || die "$1 requires a value"
      option="$1"
      value="$2"
      shift 2
      case "$option" in
        --platform) platform="$value" ;;
        --user) user="$value"; user_set=1 ;;
        --timeout) timeout_seconds="$value" ;;
        --out) out_dir="$value" ;;
      esac
      ;;
    --autologin)
      autologin=1
      shift
      ;;
    --release)
      release=1
      shift
      ;;
    --*) die "unknown option: $1" ;;
    *) positionals+=("$1"); shift ;;
  esac
done

[[ -n ${platform} ]] || die "--platform is required"
[[ ${platform} == gnome || ${platform} == kde ]] || die "unknown platform: ${platform}"
[[ ${user_set} == 0 || -n ${user} ]] || die "--user must not be empty"
[[ ${autologin} == 0 || -n ${user} ]] || die "--autologin requires --user"
[[ ${timeout_seconds} =~ ^[1-9][0-9]*$ ]] || die "--timeout must be a positive integer"
((${#positionals[@]} >= 1 && ${#positionals[@]} <= 2)) \
  || die "expected pc.img and optional seed.iso"

image_path="${positionals[0]}"
seed_path="${positionals[1]:-}"
[[ -f ${image_path} ]] || die "image not found: ${image_path}"
image_path="$(realpath -- "${image_path}")"
if [[ -n ${seed_path} ]]; then
  [[ -f ${seed_path} ]] || die "seed ISO not found: ${seed_path}"
  seed_path="$(realpath -- "${seed_path}")"
fi

connections_file="${repo_dir}/platforms/${platform}/connections"
[[ -f ${connections_file} ]] || die "connections file not found: ${connections_file}"

for command_name in qemu-system-x86_64 sfdisk python3; do
  command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
done
if ((EUID != 0)); then
  command -v sudo >/dev/null 2>&1 || die "sudo is required for offline image inspection"
fi

firmware_code=""
firmware_vars=""
for firmware_suffix in _4M ""; do
  code="/usr/share/OVMF/OVMF_CODE${firmware_suffix}.fd"
  vars="/usr/share/OVMF/OVMF_VARS${firmware_suffix}.fd"
  if [[ -r ${code} && -r ${vars} ]]; then
    firmware_code="${code}"
    firmware_vars="${vars}"
    break
  fi
done
[[ -n ${firmware_code} ]] || die "matching OVMF_CODE and OVMF_VARS firmware files not found"

if [[ -z ${out_dir} ]]; then
  out_dir="$(mktemp -d "${TMPDIR:-/tmp}/boot-check.XXXXXXXX")"
else
  mkdir -m 0700 -p -- "${out_dir}"
  out_dir="$(cd "${out_dir}" && pwd)"
fi
[[ -O ${out_dir} ]] || die "output directory must be owned by the invoking user"
out_dir_mode="$(stat -c %a "${out_dir}")"
(( ((out_dir_mode / 10) % 10 & 2) == 0 && (out_dir_mode % 10 & 2) == 0 )) \
  || die "output directory must not be writable by other users; run chmod go-w '${out_dir}'"

report_path="${out_dir}/report.txt"
serial_path="${out_dir}/serial.log"
journal_path="${out_dir}/journal.log"
partition_table_path="${out_dir}/sfdisk.txt"
screenshot_path="${out_dir}/screenshot.ppm"
state_snapshot_path="${out_dir}/snapd-state.json"
image_copy="${out_dir}/pc.img.copy"
vars_copy="${out_dir}/OVMF_VARS.fd"
mount_dir="${out_dir}/ubuntu-data"
monitor_socket="${out_dir}/qemu-monitor.sock"
qemu_pid=""
mounted=0
failures=0

for artifact in \
  "${report_path}" "${serial_path}" "${journal_path}" "${partition_table_path}" \
  "${screenshot_path}" "${state_snapshot_path}" "${image_copy}" "${vars_copy}" "${mount_dir}" "${monitor_socket}"; do
  [[ ! -e ${artifact} && ! -L ${artifact} ]] \
    || die "output already contains a boot-check artifact: ${artifact}"
done

if ((EUID != 0)); then
  [[ -x ${privileged_helper} ]] || die "privileged helper is not installed: ${privileged_helper}"
fi

touch "${state_snapshot_path}"
chmod 0600 "${state_snapshot_path}"

mkdir -m 0700 -p -- "${mount_dir}"
: >"${report_path}"

cleanup() {
  local exit_status=$?
  trap - EXIT
  trap '' INT TERM
  if [[ -n ${qemu_pid} ]] && kill -0 "${qemu_pid}" 2>/dev/null; then
    kill -KILL "${qemu_pid}" 2>/dev/null || true
    wait "${qemu_pid}" 2>/dev/null || true
  elif [[ -n ${qemu_pid} ]]; then
    wait "${qemu_pid}" 2>/dev/null || true
  fi
  if [[ ${mounted} == 1 ]]; then
    run_privileged umount "${out_dir}" 2>/dev/null || true
  fi
  rm -f -- "${image_copy}" "${vars_copy}" "${monitor_socket}"
  rmdir "${mount_dir}" 2>/dev/null || true
  printf 'Artifacts: %s\n' "${out_dir}"
  exit "${exit_status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pass() {
  printf 'PASS: %s\n' "$(quote_report_value "$*")" | tee -a "${report_path}"
}

fail() {
  printf 'FAIL: %s\n' "$(quote_report_value "$*")" | tee -a "${report_path}"
  failures=$((failures + 1))
}

note() {
  printf 'INFO: %s\n' "$(quote_report_value "$*")" | tee -a "${report_path}"
}

qemu_running() {
  local process_state
  local process_stat
  [[ -n ${qemu_pid} ]] && kill -0 "${qemu_pid}" 2>/dev/null || return 1
  [[ -r /proc/${qemu_pid}/stat ]] || return 1
  IFS= read -r process_stat <"/proc/${qemu_pid}/stat"
  process_stat="${process_stat##*) }"
  process_state="${process_stat%% *}"
  [[ ${process_state} != Z ]]
}

run_privileged() {
  if ((EUID == 0)); then
    "${script_dir}/boot-check-privileged.py" "$@"
  else
    sudo "${privileged_helper}" "$@"
  fi
}

journalctl_result() {
  run_privileged journal "${out_dir}" "$@"
}

cp --reflink=auto --sparse=always -- "${image_path}" "${image_copy}"
cp -- "${firmware_vars}" "${vars_copy}"

qemu_args=(
  -machine accel=kvm -cpu host -smp 2 -m 4096
  -display none -vga virtio
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=${firmware_code}"
  -drive "if=pflash,format=raw,unit=1,file=${vars_copy}"
  -drive "file=${image_copy},format=raw,if=virtio,cache=none"
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0
  -serial "file:${serial_path}"
  -monitor "unix:${monitor_socket},server,nowait"
)
if [[ -n ${seed_path} ]]; then
  qemu_args+=( -drive "file=${seed_path},format=raw,if=virtio,media=cdrom,readonly=on" )
fi

note "Starting QEMU for ${timeout_seconds}s using a copy of ${image_path}"
qemu-system-x86_64 "${qemu_args[@]}" &
qemu_pid=$!
sleep "${timeout_seconds}"
if qemu_running; then
  pass "QEMU remained running for ${timeout_seconds}s"
else
  fail "QEMU exited before the ${timeout_seconds}s timeout"
fi

if python3 - "${monitor_socket}" "${screenshot_path}" <<'PY'
import socket
import sys

monitor_path, screenshot_path = sys.argv[1:]
escaped_path = screenshot_path.replace("\\", "\\\\").replace('"', '\\"')

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as monitor:
    monitor.settimeout(15)
    monitor.connect(monitor_path)

    def read_prompt():
        response = bytearray()
        while b"(qemu)" not in response:
            chunk = monitor.recv(1)
            if not chunk:
                break
            response.extend(chunk)
        return bytes(response)

    read_prompt()
    monitor.sendall(f'screendump "{escaped_path}"\n'.encode())
    response = read_prompt()
    if b"Error" in response or b"unknown command" in response:
        raise SystemExit(response.decode(errors="replace"))
    monitor.sendall(b"quit\n")
PY
then
  if [[ -s ${screenshot_path} ]]; then
    pass "QEMU screendump captured"
  else
    fail "QEMU screendump is empty"
  fi
else
  fail "could not capture screenshot and stop QEMU through its monitor"
fi
if [[ -n ${qemu_pid} ]]; then
  for _ in {1..20}; do
    qemu_running || break
    sleep 1
  done
  if qemu_running; then
    kill -KILL "${qemu_pid}" 2>/dev/null || true
    fail "QEMU did not stop after the monitor quit command"
  fi
  wait "${qemu_pid}" 2>/dev/null || true
  qemu_pid=""
fi

if sfdisk --dump "${image_copy}" >"${partition_table_path}" 2>&1; then
  pass "partition table captured with sfdisk"
else
  fail "could not read partition table with sfdisk"
fi

partition_data="$(python3 - "${partition_table_path}" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
last_match = re.search(r"^last-lba:\s*(\d+)\s*$", text, re.MULTILINE)
sector_match = re.search(r"^sector-size:\s*(\d+)\s*$", text, re.MULTILINE)
if not last_match:
    raise SystemExit(1)
sector_size = sector_match.group(1) if sector_match else "512"
for line in text.splitlines():
    if not re.search(r'name="ubuntu-data"', line):
        continue
    path = line.split(":", 1)[0].strip()
    number_match = re.search(r"(?:p)?(\d+)$", path)
    start_match = re.search(r"\bstart=\s*(\d+)", line)
    size_match = re.search(r"\bsize=\s*(\d+)", line)
    if number_match and start_match and size_match:
        print(number_match.group(1), start_match.group(1), size_match.group(1), last_match.group(1), sector_size)
        break
else:
    raise SystemExit(1)
PY
)" || partition_data=""

if [[ -n ${partition_data} ]]; then
  read -r data_partition_number data_start data_size disk_last_lba sector_size <<<"${partition_data}"
  if ((data_start + data_size - 1 == disk_last_lba)); then
    pass "ubuntu-data ends at the disk's last LBA (${disk_last_lba})"
  else
    fail "ubuntu-data ends at LBA $((data_start + data_size - 1)), not last LBA ${disk_last_lba}"
  fi
  partition_offset=$((data_start * sector_size))
  partition_size=$((data_size * sector_size))
  if run_privileged mount "${out_dir}" \
    "${partition_offset}" "${partition_size}"; then
    mounted=1
  else
    fail "could not loop-mount ubuntu-data read-only from the image copy"
  fi
else
  fail "ubuntu-data partition or last usable LBA not found in sfdisk output"
fi

if [[ ${mounted} == 1 ]]; then
  system_data="${mount_dir}/system-data"
  [[ -d ${system_data} ]] || system_data="${mount_dir}"
  journal_dir="${system_data}/var/log/journal"
  state_file="${system_data}/var/lib/snapd/state.json"
  state_snapshot_valid=0
  passwd_file="${system_data}/var/lib/extrausers/passwd"

  if [[ -f ${state_file} ]]; then
    if run_privileged copy-state "${out_dir}" "${state_snapshot_path}" && \
      python3 -m json.tool "${state_snapshot_path}" >/dev/null 2>&1; then
      state_snapshot_valid=1
    else
      fail "snapd state.json is invalid JSON; diagnostic snapshot: ${state_snapshot_path}"
    fi
  else
    fail "snapd state.json not found"
  fi

  if [[ -d ${journal_dir} ]]; then
    journalctl_result="$(journalctl_result all 2>&1 || true)"
    printf '%s\n' "${journalctl_result}" \
      | tee "${journal_path}" >/dev/null || true
    seeded_journal="$(journalctl_result seeded 2>/dev/null || true)"
    if grep -Eiq 'Finished.*(snapd\.seeded\.service|fully seeded)' <<<"${seeded_journal}"; then
      pass "snapd.seeded.service finished"
    else
      fail "snapd.seeded.service did not finish (see journal.log)"
    fi
    failed_units="$(journalctl_result errors 2>/dev/null \
      | python3 -c 'import re,sys; pattern=re.compile(r"Failed to start ([A-Za-z0-9_.@:-]+\.service)|(?:^| )([A-Za-z0-9_.@:-]+\.service)(?:\[[0-9]+\])?: (?:Failed|Main process exited|Dependency failed)"); units={match.group(1) or match.group(2) for line in sys.stdin for match in pattern.finditer(line)}; print("\n".join(sorted(units)) if units else "")' \
      || true)"
    if [[ -n ${failed_units} ]]; then
      note "Failed units (informational):"
      while IFS= read -r failed_unit; do note "  ${failed_unit}"; done <<<"${failed_units}"
    else
      note "Failed units (informational): none found in error-priority journal entries"
    fi
  else
    : >"${journal_path}"
    fail "journal directory not found under ubuntu-data"
  fi

  if ((state_snapshot_valid)); then
    connections_found=0
    while IFS= read -r connection_line || [[ -n ${connection_line} ]]; do
      connection_line="${connection_line%%#*}"
      read -r plug slot extra <<<"${connection_line}"
      [[ -n ${plug:-} ]] || continue
      [[ -n ${slot:-} && -z ${extra:-} ]] || {
        fail "invalid connection line: ${connection_line}"
        continue
      }
      connections_found=1
      if python3 - "${state_snapshot_path}" "${repo_dir}/platforms/${platform}/model.json" "${plug} ${slot}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as state_file, open(sys.argv[2], encoding="utf-8") as model_file:
    state = json.load(state_file)
    model = json.load(model_file)
snap_names = {snap["id"]: snap["name"] for snap in model["snaps"] if "id" in snap}

def state_endpoint(endpoint):
    snap, interface = endpoint.split(":", 1)
    # Gadget connections may use snap IDs; state records use installed names.
    snap = snap_names.get(snap, snap)
    # snapd persists implicit system slots under the legacy core name.
    if snap in {"system", "snapd"}:
        snap = "core"
    return f"{snap}:{interface}"

plug, slot = sys.argv[3].split()
connection_id = f"{state_endpoint(plug)} {state_endpoint(slot)}"
connection = state.get("data", {}).get("conns", {}).get(connection_id)
if connection is None or connection.get("undesired") is True:
    raise SystemExit(1)
PY
      then
        pass "connection ${plug} ${slot} is present and not undesired"
      else
        fail "connection ${plug} ${slot} is missing or marked undesired"
      fi
    done <"${connections_file}"
    if [[ ${connections_found} == 0 ]]; then
      fail "connections file contains no connection entries"
    fi
  fi

  if [[ ${platform} == gnome && -z ${user} ]]; then
    gdm_journal="$(journalctl_result gdm 2>/dev/null || true)"
    if [[ ${gdm_journal} == *"Started GNOME Display Manager"* || ${gdm_journal} == *"Started gdm.service"* ]]; then
      pass "gdm.service started"
    else
      fail "gdm.service did not start"
    fi
    if grep -Eiq 'ubuntu-desktop-init.*(session|wayland)|gnome-initial-setup|Started user@[0-9]+\.service.*gnome-initial-setup' "${journal_path}"; then
      pass "ubuntu-desktop-init wizard session started"
    else
      fail "ubuntu-desktop-init wizard session did not start"
    fi
  fi

  if [[ -n ${user} ]]; then
    passwd_line="$(run_privileged read-passwd "${out_dir}" "${user}" 2>/dev/null || true)"
    if [[ -n ${passwd_line} ]]; then
      pass "user ${user} is present in extrausers passwd"
      user_uid="$(cut -d: -f3 <<<"${passwd_line}")"
      if [[ ${autologin} == 1 ]]; then
        user_journal="$(journalctl_result user-manager "${user_uid}" 2>/dev/null || true)"
        if grep -Eiq "Started.*(user@${user_uid}\\.service|User Manager for UID ${user_uid})" <<<"${user_journal}"; then
          pass "user@${user_uid}.service started"
        else
          fail "user@${user_uid}.service did not start"
        fi
      fi
    else
      fail "user ${user} is not present in extrausers passwd"
      user_uid=""
    fi
  fi

  if [[ ${platform} == kde ]]; then
    sddm_journal="$(journalctl_result sddm 2>/dev/null || true)"
    if [[ ${sddm_journal} == *"Started Simple Desktop Display Manager"* || ${sddm_journal} == *"Started sddm.service"* ]]; then
      pass "sddm.service started"
    else
      fail "sddm.service did not start"
    fi
    gdm_masked=0
    gdm_mask="${system_data}/etc/systemd/system/gdm.service"
    if [[ -L ${gdm_mask} && $(readlink "${gdm_mask}") == /dev/null ]]; then
      gdm_masked=1
    fi
    if [[ ${gdm_masked} == 1 ]]; then
      pass "gdm.service is masked"
    else
      fail "gdm.service is not masked"
    fi
  fi

  if [[ ${release} == 1 ]]; then
    kernel_cmdline="$(journalctl_result kernel 2>/dev/null \
      | grep -F 'Kernel command line:' | tail -n 1 || true)"
    if [[ -n ${kernel_cmdline} && ${kernel_cmdline} != *"console=ttyS0,115200n8"* && \
      ${kernel_cmdline} != *"systemd.journald.forward_to_console=1"* ]]; then
      pass "Release kernel command line has no Development serial-console arguments"
    else
      fail "Release kernel command line contains Development serial-console arguments or was not recorded"
    fi
    ssh_development_listener=0
    ssh_listen_address=""
    if ((state_snapshot_valid)); then
      ssh_listen_address="$(python3 - "${state_snapshot_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as state_file:
    state = json.load(state_file)
config = state.get("data", {}).get("config", {}).get("system", {})
address = config.get("service.ssh.listen-address", "")
if isinstance(address, str) and address.startswith(":"):
    address = "0.0.0.0" if address[1:].isdigit() else ""
print(address)
PY
      )"
    fi
    ssh_config="${system_data}/etc/ssh/sshd_config.d/listen.conf"
    if [[ -f ${ssh_config} ]]; then
      ssh_listen_address="$(run_privileged read-ssh "${out_dir}" 2>/dev/null \
        | paste -sd ',' -)"
    elif [[ -n ${ssh_listen_address} ]]; then
      case "${ssh_listen_address}" in
        0.0.0.0) ssh_listen_address="0.0.0.0:8022,[::]:8022" ;;
        127.0.0.1) ssh_listen_address="127.0.0.1:8022,[::1]:8022" ;;
      esac
    fi
    if [[ -z ${ssh_listen_address} ]]; then
      fail "Release SSH listen-address could not be determined"
    elif [[ ${ssh_listen_address} != *0.0.0.0* ]]; then
      pass "Release SSH listen-address is not 0.0.0.0"
    else
      fail "Release SSH listen-address is 0.0.0.0"
    fi
  fi
else
  : >"${journal_path}"
fi

if [[ ! -s ${serial_path} ]]; then
  : >"${serial_path}"
fi
if [[ ! -s ${partition_table_path} ]]; then
  : >"${partition_table_path}"
fi
if [[ ! -s ${screenshot_path} ]]; then
  : >"${screenshot_path}"
fi

if ((failures == 0)); then
  printf 'PASS: all boot-check assertions passed\n' | tee -a "${report_path}"
else
  printf 'FAIL: %d boot-check assertion(s) failed\n' "${failures}" | tee -a "${report_path}"
fi

printf 'Journal: %s\nPartition table: %s\nScreenshot: %s\nReport: %s\n' \
  "${journal_path}" "${partition_table_path}" "${screenshot_path}" "${report_path}"
if ((failures == 0)); then
  exit 0
fi
exit 1
