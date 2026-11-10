#!/usr/bin/env bash
set -euo pipefail
# Removed by: ADR 0003
source "${LIB_DIR}/connections.sh"
apply_gadget_connections "${GADGET_ROOT}/meta/gadget.yaml" "${PLATFORM_DIR}/connections"
