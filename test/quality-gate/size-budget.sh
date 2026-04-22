#!/usr/bin/env bash
#
# Quality Gate check #2: Size Budget.
#
# Reads the per-image size budget from the sidecar quality file and verifies
# the built image meets it. Fails closed when either compressed or
# uncompressed budget is exceeded.
#
# Usage:
#   size-budget.sh <image-ref> <quality-file>
#
# Example:
#   size-budget.sh localhost:5000/base-ubi9:latest specs/base-ubi9.quality.yaml

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
source "$here/lib.sh"

image=${1:?usage: size-budget.sh <image-ref> <quality-file>}
quality_file=${2:?usage: size-budget.sh <image-ref> <quality-file>}

qg::require yq
cli=$(qg::container_cli)

compressed_budget_mb=$(qg::read_quality "$quality_file" '.size-budget.compressed-mb')
uncompressed_budget_mb=$(qg::read_quality "$quality_file" '.size-budget.uncompressed-mb')

if [[ -z $compressed_budget_mb && -z $uncompressed_budget_mb ]]; then
  qg::warn "no size-budget declared in $quality_file — skipping"
  exit 0
fi

# Uncompressed: sum of all layer sizes from the image inspect output.
uncompressed_bytes=$(
  "$cli" image inspect "$image" --format '{{.Size}}'
)
uncompressed_mb=$(( uncompressed_bytes / 1024 / 1024 ))

# Compressed: sum the layer sizes from the manifest.
# docker manifest inspect returns the registry-side manifest, which is what
# actually gets pulled over the wire.
compressed_bytes=$(
  "$cli" manifest inspect "$image" 2>/dev/null \
    | jq '[.layers[].size] | add // 0'
)
compressed_mb=$(( compressed_bytes / 1024 / 1024 ))

fail=0

if [[ -n $uncompressed_budget_mb && $uncompressed_budget_mb != 0 ]]; then
  if (( uncompressed_mb > uncompressed_budget_mb )); then
    qg::fail "uncompressed size ${uncompressed_mb}MB exceeds budget ${uncompressed_budget_mb}MB"
    fail=1
  else
    qg::pass "uncompressed size ${uncompressed_mb}MB within budget ${uncompressed_budget_mb}MB"
  fi
fi

if [[ -n $compressed_budget_mb && $compressed_budget_mb != 0 && $compressed_mb != 0 ]]; then
  if (( compressed_mb > compressed_budget_mb )); then
    qg::fail "compressed size ${compressed_mb}MB exceeds budget ${compressed_budget_mb}MB"
    fail=1
  else
    qg::pass "compressed size ${compressed_mb}MB within budget ${compressed_budget_mb}MB"
  fi
elif [[ -n $compressed_budget_mb && $compressed_mb == 0 ]]; then
  qg::info "compressed size not available (image not pushed to registry) — skipping compressed budget"
fi

exit $fail
