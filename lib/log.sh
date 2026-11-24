#!/usr/bin/env bash

info() {
  printf '%s: %s\n' "${STEP_NAME:-build}" "$*"
}

warn() {
  printf '%s: warning: %s\n' "${STEP_NAME:-build}" "$*" >&2
}

die() {
  printf '%s: %s\n' "${STEP_NAME:-build}" "$*" >&2
  exit 1
}

require_file() {
  [[ -f $1 ]] || die "file not found: $1"
}
