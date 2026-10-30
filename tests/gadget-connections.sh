#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

source "${repo_root}/lib/connections.sh"
gadget_yaml="${tmp_dir}/gadget.yaml"
cat >"${gadget_yaml}" <<'YAML'
volumes:
  pc:
    schema: gpt
connections:
  - plug: ubuntu-desktop-session:desktop-launch
    slot: system:desktop-launch
other-key: keep-me
YAML
cat >"${tmp_dir}/connections" <<'CONNECTIONS'
# Required desktop connections
ubuntu-desktop-session:desktop-launch system:desktop-launch
ubuntu-desktop-session:avahi-control avahi:avahi-control
CONNECTIONS

apply_gadget_connections "${gadget_yaml}" "${tmp_dir}/connections"
grep -Fq 'other-key: keep-me' "${gadget_yaml}"
[[ $(awk '/^connections:/{inside=1; next} inside && /^[^[:space:]#]/{exit} inside && /^  - plug:/{count++} END{print count+0}' "${gadget_yaml}") == 2 ]]
grep -Fq '  - plug: ubuntu-desktop-session:avahi-control' "${gadget_yaml}"
grep -Fq '    slot: avahi:avahi-control' "${gadget_yaml}"
cp "${gadget_yaml}" "${tmp_dir}/first-run.yaml"
apply_gadget_connections "${gadget_yaml}" "${tmp_dir}/connections"
cmp "${tmp_dir}/first-run.yaml" "${gadget_yaml}"

cat >"${gadget_yaml}" <<'YAML'
connections:
YAML
apply_gadget_connections "${gadget_yaml}" "${repo_root}/platforms/kde/connections"
for connection in \
  'plasma-desktop-session:dot-hidden' \
  'plasma-desktop-session:shell-session-locale-files' \
  'plasma-desktop-session:avahi-control' \
  'plasma-desktop-session:ssh-keys' \
  'plasma-desktop-session:plasma-core26' \
  'plasma-desktop-session:kf6-core26'; do
  grep -Fq "  - plug: ${connection}" "${gadget_yaml}"
done
grep -Fq 'slot: snapd:personal-files' "${gadget_yaml}"
grep -Fq 'slot: plasma-core26-desktop:plasma-core26' "${gadget_yaml}"
grep -Fq 'slot: kf6-core26:kf6-core26' "${gadget_yaml}"
! grep -Eq 'system:(upower-observe|pulseaudio|pipewire)|cups-control|:opengl|:network-bind' \
  "${repo_root}/platforms/kde/connections"

printf 'gadget connections tests passed\n'
