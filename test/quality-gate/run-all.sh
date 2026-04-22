#!/usr/bin/env bash
#
# Run all in-line quality-gate checks against a published image.
#
# Reproducibility lives outside this orchestrator because it requires
# re-running the full build — invoke it separately via
# test/quality-gate/reproducibility.sh.
#
# Usage:
#   run-all.sh <image-ref> <quality-file> [--sbom <sbom.spdx.json>] [--key <cosign.pub>]
#
# Example:
#   run-all.sh localhost:5000/base-ubi9:latest specs/base-ubi9.quality.yaml \
#     --sbom evidence/sbom.spdx.json --key local/keys/cosign.pub

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
source "$here/lib.sh"

image=${1:?usage: run-all.sh <image-ref> <quality-file> [--sbom <file>] [--key <file>]}
quality_file=${2:?usage: run-all.sh <image-ref> <quality-file> [--sbom <file>] [--key <file>]}
shift 2

sbom=""
key_arg=()
while (( $# )); do
  case $1 in
    --sbom) sbom=$2; shift 2 ;;
    --key)  key_arg=(--key "$2"); shift 2 ;;
    *) qg::fail "unknown arg: $1"; exit 2 ;;
  esac
done

echo "Quality Gate :: $image" >&2
echo "──────────────────────────────────────────────────────────────" >&2

declare -i failures=0

run_check() {
  local name=$1; shift
  echo "" >&2
  echo "[${name}]" >&2
  if "$@"; then
    return 0
  fi
  failures+=1
  return 1
}

run_check "size-budget" \
  "$here/size-budget.sh" "$image" "$quality_file" || true

if [[ -n $sbom ]]; then
  run_check "sbom-completeness" \
    "$here/sbom-completeness.sh" "$image" "$sbom" || true
else
  qg::warn "--sbom not supplied, skipping sbom-completeness"
fi

run_check "cosign-verify" \
  "$here/cosign-verify.sh" "$image" "${key_arg[@]}" || true

echo "" >&2
echo "──────────────────────────────────────────────────────────────" >&2
if (( failures > 0 )); then
  qg::fail "quality gate: ${failures} check(s) failed"
  exit 1
fi
qg::pass "quality gate: all checks passed"
