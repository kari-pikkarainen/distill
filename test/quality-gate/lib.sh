#!/usr/bin/env bash
# Shared helpers for quality-gate scripts.
# Source this file from individual check scripts.

set -euo pipefail

# ── output helpers ──────────────────────────────────────────────────────────

if [[ -t 2 ]]; then
  _c_red=$'\033[31m'
  _c_grn=$'\033[32m'
  _c_ylw=$'\033[33m'
  _c_dim=$'\033[2m'
  _c_off=$'\033[0m'
else
  _c_red=""; _c_grn=""; _c_ylw=""; _c_dim=""; _c_off=""
fi

qg::pass() { echo "${_c_grn}✓${_c_off} $*" >&2; }
qg::fail() { echo "${_c_red}✗${_c_off} $*" >&2; }
qg::warn() { echo "${_c_ylw}!${_c_off} $*" >&2; }
qg::info() { echo "${_c_dim}·${_c_off} $*" >&2; }

qg::require() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    qg::fail "required tool not on PATH: $cmd"
    return 1
  fi
}

qg::read_quality() {
  local quality_file=$1 key=$2
  if ! [[ -f $quality_file ]]; then
    qg::fail "quality file not found: $quality_file"
    return 1
  fi
  yq -r "$key // \"\"" "$quality_file"
}

qg::container_cli() {
  if [[ -n ${DISTILL_CONTAINER_CLI:-} ]]; then
    echo "$DISTILL_CONTAINER_CLI"
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    echo docker
  elif command -v podman >/dev/null 2>&1; then
    echo podman
  else
    qg::fail "no container CLI found (docker or podman)"
    return 1
  fi
}
