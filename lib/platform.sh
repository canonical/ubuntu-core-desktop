#!/usr/bin/env bash

declare_platform_inputs() {
  PLATFORM_INPUT_NAMES=()
  declare -gA PLATFORM_INPUT_PATHS=()
  declare -gA PLATFORM_INPUT_LOCAL=()
  local input_name local_name
  for input_name in ${PLATFORM_INPUTS:-}; do
    [[ ${input_name} =~ ^[a-z][a-z0-9_-]*$ ]] || die "invalid declared Platform input: ${input_name}"
    local_name="PLATFORM_INPUT_${input_name}_LOCAL"
    [[ ${!local_name:-} == yes || ${!local_name:-} == no ]] \
      || die "${local_name} must be yes or no"
    PLATFORM_INPUT_NAMES+=("${input_name}")
    PLATFORM_INPUT_LOCAL["${input_name}"]="${!local_name}"
  done
}

platform_input_list() {
  local input_name
  local result=""
  for input_name in "${PLATFORM_INPUT_NAMES[@]}"; do
    result+=" ${input_name}"
  done
  printf '%s' "${result# }"
}

parse_platform_inputs() {
  local -n input_values=$1
  local input input_name input_path declared
  local -A seen=()
  declared="$(platform_input_list)"
  for input in "${input_values[@]}"; do
    [[ ${input} == *=* ]] || die "invalid --input '${input}'; expected name=path (declared inputs: ${declared:-none})"
    input_name="${input%%=*}"
    input_path="${input#*=}"
    [[ -n ${input_name} && -n ${input_path} ]] \
      || die "invalid --input '${input}'; expected name=path (declared inputs: ${declared:-none})"
    [[ -n ${PLATFORM_INPUT_LOCAL[${input_name}]+x} ]] \
      || die "unknown input: ${input_name} (declared inputs: ${declared:-none})"
    [[ -z ${seen[${input_name}]:-} ]] \
      || die "duplicate input: ${input_name} (declared inputs: ${declared:-none})"
    require_file "${input_path}"
    seen["${input_name}"]=1
    PLATFORM_INPUT_PATHS["${input_name}"]="${input_path}"
  done
  for input_name in "${PLATFORM_INPUT_NAMES[@]}"; do
    [[ -n ${seen[${input_name}]:-} ]] \
      || die "missing declared input: ${input_name} (declared inputs: ${declared:-none})"
  done
}

export_platform_input_roots() {
  local input_name input_var root_var input_path input_root
  for input_name in "${PLATFORM_INPUT_NAMES[@]}"; do
    input_path="${PLATFORM_INPUT_PATHS[${input_name}]}"
    input_root="${INPUTS_ROOT}/${input_name}-root"
    mkdir -p -- "${input_root}"
    unsquashfs -d "${input_root}" "${input_path}" >/dev/null \
      || die "failed to unpack Platform input '${input_name}'; work tree kept at ${WORK_DIR}"
    input_var="INPUT_${input_name}"
    root_var="INPUT_${input_name}_ROOT"
    printf -v "${input_var}" '%s' "${input_path}"
    printf -v "${root_var}" '%s' "${input_root}"
    export "${input_var}" "${root_var}"
  done
}

validate_platform_inputs() {
  local input_name input_snap
  for input_name in "${PLATFORM_INPUT_NAMES[@]}"; do
    input_snap="${PLATFORM_INPUT_PATHS[${input_name}]}"
    [[ ${input_snap} == *.snap ]] || die "Platform input '${input_name}' must be a .snap: ${input_snap}"
  done
}
