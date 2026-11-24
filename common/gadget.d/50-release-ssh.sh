#!/usr/bin/env bash
set -euo pipefail

if [[ ${RELEASE} == 1 ]]; then
  sed -i 's/listen-address: 0\.0\.0\.0/listen-address: 127.0.0.1/' \
    "${GADGET_ROOT}/meta/gadget.yaml"
fi
