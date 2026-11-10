#!/usr/bin/env bash
set -euo pipefail

if [[ ${RELEASE} == 1 ]]; then
  printf '%s\n' 'quiet splash' >"${GADGET_ROOT}/cmdline.extra"
fi
