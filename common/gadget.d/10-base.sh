#!/usr/bin/env bash
set -euo pipefail
# Removed by: upstream: pc-amd64-gadget-desktop
sed -i 's/^base: core26$/base: core26-desktop/' "${GADGET_ROOT}/meta/snap.yaml"
