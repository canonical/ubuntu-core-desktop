#!/usr/bin/env bash

apply_gadget_connections() {
  local gadget_yaml="$1"
  local connections_file="$2"
  local additions
  local plug slot extra

  [[ -f ${gadget_yaml} ]] || { printf 'gadget.yaml not found: %s\n' "${gadget_yaml}" >&2; return 1; }
  [[ -f ${connections_file} ]] || { printf 'connections file not found: %s\n' "${connections_file}" >&2; return 1; }
  additions="$(mktemp)"
  while IFS=$' \t' read -r plug slot extra || [[ -n ${plug:-}${slot:-}${extra:-} ]]; do
    [[ -n ${plug:-} && ${plug} != \#* ]] || continue
    [[ -n ${slot:-} && -z ${extra:-} ]] || { rm -f -- "${additions}"; printf 'invalid connection line in %s\n' "${connections_file}" >&2; return 1; }
    if ! awk -v plug="${plug}" -v slot="${slot}" '
      /^[^[:space:]#]/ { if ($0 ~ /^connections:[[:space:]]*(#.*)?$/) in_connections=1; else if (in_connections) exit }
      in_connections && /^[[:space:]]*-[[:space:]]+plug:[[:space:]]*/ {
        current=$0; sub(/^[[:space:]]*-[[:space:]]+plug:[[:space:]]*/, "", current); active=(current == plug)
      }
      active && /^[[:space:]]+slot:[[:space:]]*/ {
        current=$0; sub(/^[[:space:]]+slot:[[:space:]]*/, "", current); if (current == slot) found=1; active=0
      }
      END { exit !found }
    ' "${gadget_yaml}"; then
      printf '  - plug: %s\n    slot: %s\n' "${plug}" "${slot}" >>"${additions}"
    fi
  done <"${connections_file}"

  [[ -s ${additions} ]] || { rm -f -- "${additions}"; return 0; }
  local tmp_yaml="${gadget_yaml}.tmp"
  awk -v additions="${additions}" '
    /^[^[:space:]#]/ {
      if (!seen && $0 ~ /^connections:[[:space:]]*(#.*)?$/) {
        seen=1
        print
        while ((getline line < additions) > 0) print line
        close(additions)
        next
      }
    }
    { print }
    END {
      if (!seen) {
        print "connections:"
        while ((getline line < additions) > 0) print line
        close(additions)
      }
    }
  ' "${gadget_yaml}" >"${tmp_yaml}"
  mv -- "${tmp_yaml}" "${gadget_yaml}"
  rm -f -- "${additions}"
}
