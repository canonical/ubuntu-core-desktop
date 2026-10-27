#!/usr/bin/env bash
set -euo pipefail
sed -i 's/listen-address: 127\.0\.0\.1/listen-address: 0.0.0.0/' "${GADGET_ROOT}/meta/gadget.yaml"
