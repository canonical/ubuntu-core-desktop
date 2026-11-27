#!/bin/bash

# Boot a built Ubuntu Core Desktop image under QEMU.
#
# Usage: ./run-qemu.sh [--vnc] [--vnc-display N] [--build-dir DIR]
#                      [--image PATH] [--net bridge|user]
#                      [--mac ADDR] [--bridge NAME]
#                      [--serial-socket PATH] [--help]
#
# The default image is <build-dir>/pc.img. build.sh bakes --user
# accounts straight into the image (no seed ISO either way) and ALWAYS
# drops pc.img.nouser alongside pc.img as the marker that no seed is
# to be attached; a build without --user boots the first-boot wizard.
# A seed.iso left over from an older build is attached for
# compatibility. If neither marker exists, the build has not been run
# (or used a different --build-dir).

set -e

prog=$(basename "$0")
usage() {
    cat <<EOF
Usage: $prog [options]

Boot a built Ubuntu Core Desktop image under QEMU (KVM, UEFI/OVMF,
VirtIO). One VM per tree: a lock file prevents a second concurrent
launch.

Options:
  --vnc               Serve the display over VNC (localhost, no
                      password) instead of opening a window. Combine
                      with --vnc-display to choose the display number.
  --vnc-display N     VNC display number when --vnc is used (default 1,
                      i.e. connect to localhost:1).
  --build-dir DIR     Directory build.sh wrote the image into
                      (default: build).
  --image PATH        Boot this image instead of <build-dir>/pc.img.
  --net MODE          VM networking: "bridge" (default, attach to a host
                      bridge with --bridge/--mac) or "user" (slirp, no
                      host setup; needed in containers, where there is
                      no bridge and no /dev/net/tun).
  --mac ADDR          VM network MAC address
                      (default: 52:54:00:a1:b2:c5). Bridge mode only.
  --bridge NAME       Network bridge to attach the VM to
                      (default: lxdbr0). Bridge mode only.
  --serial-socket PATH  Unix socket for the VM serial console
                      (default: /tmp/ucd-vm-serial.sock). Connect with:
                        nc -U PATH
                        socat -,raw,echo=0,escape=0x1d UNIX-CONNECT:PATH
  -- QEMU-ARGS        Everything after -- is appended to the QEMU
                      command, e.g. -- -device usb-tablet.
  -h, --help          Show this help and exit.

Serial console: log in as root with the --root-password password on
images built with that flag (useful for diagnosing boot failures when
SSH is not up yet). See docs/build-tools.md ("VM access notes").
EOF
}

usage_error() {
    echo "Error: $*" >&2
    echo >&2
    usage >&2
    exit 2
}

build_dir="build"
image=""
net_mode="bridge"
vm_mac="52:54:00:a1:b2:c5"
vm_bridge="lxdbr0"
serial_socket="/tmp/ucd-vm-serial.sock"
vnc_display="1"
want_vnc=0
bridge_opts=0
qemu_extra=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vnc) want_vnc=1; shift ;;
        --vnc-display)
            [[ $# -ge 2 && $2 =~ ^[0-9]+$ ]] || usage_error "--vnc-display needs a number"
            vnc_display="$2"; shift 2 ;;
        --build-dir)
            [[ $# -ge 2 ]] || usage_error "--build-dir needs an argument"
            build_dir="$2"; shift 2 ;;
        --image)
            [[ $# -ge 2 ]] || usage_error "--image needs an argument"
            image="$2"; shift 2 ;;
        --net)
            [[ $# -ge 2 ]] || usage_error "--net needs an argument"
            net_mode="$2"; shift 2 ;;
        --mac)
            [[ $# -ge 2 && $2 =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]] \
                || usage_error "--mac needs a MAC address (xx:xx:xx:xx:xx:xx)"
            vm_mac="$2"; bridge_opts=1; shift 2 ;;
        --bridge)
            [[ $# -ge 2 ]] || usage_error "--bridge needs an argument"
            vm_bridge="$2"; bridge_opts=1; shift 2 ;;
        --serial-socket)
            [[ $# -ge 2 ]] || usage_error "--serial-socket needs an argument"
            serial_socket="$2"; shift 2 ;;
        --)
            shift
            qemu_extra=("$@")
            break ;;
        -h|--help) usage; exit 0 ;;
        *) usage_error "Unknown argument: $1" ;;
    esac
done

if [[ -z $image ]]; then
    image="${build_dir}/pc.img"
fi
case "${net_mode}" in
    bridge|user) ;;
    *) usage_error "--net must be 'bridge' or 'user'" ;;
esac
if [[ ${net_mode} == user && ${bridge_opts} == 1 ]]; then
    usage_error "--mac/--bridge are bridge-mode options and conflict with --net user"
fi
if [[ ! -e $image ]]; then
    usage_error "Image not found: $image (run ./build.sh first, or pass --build-dir/--image)"
fi

# Seed handling per build.sh's contract: no seed ISO either way
# (--user provisioning is baked into the image), and pc.img.nouser is
# always dropped as the "attach no seed" marker. Attach a seed.iso only
# when one is left over from an older build.
seed_args=()
if [[ -e ${build_dir}/pc.img.nouser ]]; then
    echo "${build_dir}/pc.img.nouser present -- booting without a seed"
elif [[ -e ${build_dir}/seed.iso ]]; then
    seed_args=(-drive file="${build_dir}/seed.iso",if=virtio,format=raw,media=cdrom)
elif [[ $image == "${build_dir}/pc.img" ]]; then
    usage_error "Neither ${build_dir}/pc.img.nouser nor ${build_dir}/seed.iso present -- run ./build.sh first (or point --build-dir at the build you want to boot)"
fi

# One VM at a time per tree.
lockfile="$(pwd)/.qemu-run.lock"
exec 9>"$lockfile"
if ! flock -n 9; then
    usage_error "QEMU is already running for this tree ($lockfile)"
fi

# Display: VNC on request, else SDL when a display exists, else a
# headless EGL display (the desktop compositor needs GL either way).
if [[ $want_vnc == 1 ]]; then
    display_args=(-display egl-headless,gl=on -vnc "127.0.0.1:${vnc_display}")
    echo "VNC: connect to localhost:${vnc_display}" >&2
elif [[ -n ${DISPLAY:-} ]]; then
    display_args=(-display sdl,gl=on)
    export SDL_VIDEODRIVER=wayland
else
    display_args=(-display egl-headless,gl=on)
fi

# Expose sound to the VM only when the host side can reach an audio
# server: QEMU's pipewire backend resolves the daemon socket via
# XDG_RUNTIME_DIR (set inside a desktop session, absent in an SSH
# shell), so unset means we cannot connect and the VM runs without
# audio. Checking the socket itself, not the variable, also covers an
# XDG_RUNTIME_DIR that exists but has no pipewire (e.g. a container's
# desktop-interface proxy socket): the VM runs muted rather than
# failing to start. The guest's pipewire snap picks up the emulated
# HDA card.
audio_args=()
if [[ -S ${XDG_RUNTIME_DIR:-/dev/null/nonexistent}/pipewire-0 ]]; then
    audio_args=(-audiodev pipewire,id=snd0 \
                -device intel-hda \
                -device hda-duplex,audiodev=snd0)
fi

rm -f "$serial_socket"
echo "Serial console: nc -U $serial_socket" >&2
echo "            or: socat -,raw,echo=0,escape=0x1d UNIX-CONNECT:$serial_socket" >&2
echo "                CTRL-] to exit"

# lxdbr0 is socket-activated: after a host reboot it does not exist
# until something talks to LXD (any lxc command or a snapcraft build).
# Nudge LXD, then wait briefly for the bridge to appear. User-mode
# networking has no bridge to wait for.
net_args=()
if [[ ${net_mode} == bridge ]]; then
    if ! ip link show "$vm_bridge" >/dev/null 2>&1; then
        lxc list >/dev/null 2>&1 || true
        for _ in $(seq 30); do
            ip link show "$vm_bridge" >/dev/null 2>&1 && break
            sleep 1
        done
        ip link show "$vm_bridge" >/dev/null 2>&1 || {
            usage_error "Bridge $vm_bridge not up after 30s (is LXD enabled?)"
        }
    fi
    net_args+=(-netdev "bridge,br=${vm_bridge},id=net0" \
               -device "virtio-net-pci,netdev=net0,mac=${vm_mac}")
else
    net_args+=(-netdev "user,id=net0" \
               -device virtio-net-pci,netdev=net0)
fi

exec qemu-system-x86_64 \
  -enable-kvm \
  -m 8192 \
  -smp 4 \
  -cpu host \
  -global isa-fdc.fdtypeA=none \
  -global isa-fdc.fdtypeB=none \
  -bios /usr/share/ovmf/OVMF.fd \
  -drive file="$image",if=virtio,format=raw \
  -device virtio-vga-gl,edid=on,xres=1050,yres=1050 \
  "${display_args[@]}" \
  "${audio_args[@]}" \
  "${net_args[@]}" \
  -serial "unix:${serial_socket},server=on,wait=off" \
  "${seed_args[@]}" \
  "${qemu_extra[@]}"
