#!/usr/bin/env bash
set -euo pipefail
cmdline_extra='systemd.journald.forward_to_console=1 systemd.journald.max_level_console=err console=ttyS0,115200n8'
printf '%s\n' "${cmdline_extra}" >"${GADGET_ROOT}/cmdline.extra"
