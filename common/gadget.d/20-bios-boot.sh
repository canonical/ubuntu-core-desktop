#!/usr/bin/env bash
set -euo pipefail
# Removed by: upstream: imagecraft
sed -i 's/^\([[:space:]]*- name: \)BIOS Boot$/\1bios-boot/' "${GADGET_ROOT}/meta/gadget.yaml"
