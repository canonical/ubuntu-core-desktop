#!/usr/bin/env bash
set -euo pipefail
[[ ${DEV_DEBUG} == 1 ]] || exit 0
printf '%s\n' 'snapd.debug=1 systemd.log_target=console systemd.journald.forward_to_console=1 console=ttyS0,115200n8' \
  >"${GADGET_ROOT}/cmdline.extra"
