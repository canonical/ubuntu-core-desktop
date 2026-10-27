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

printf 'gadget connections tests passed\n'
