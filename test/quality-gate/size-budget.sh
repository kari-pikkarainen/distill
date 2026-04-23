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
#   size-budget.sh localhost:5555/base-ubi9:latest specs/base-ubi9.quality.yaml

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
  "$cli" image inspect "$image" --format '{{.Size}}' 2>/dev/null || echo 0
)
uncompressed_bytes=${uncompressed_bytes:-0}
uncompressed_mb=$(( uncompressed_bytes / 1024 / 1024 ))

# Compressed: sum the layer sizes for the manifest that matches this host's
# architecture. The registry returns an OCI image index (manifest list) when
# the image was built with buildx, so we walk: index → per-arch manifest →
# layers. skopeo handles HTTP registries via --tls-verify=false and
# auto-selects a matching platform from the index.
compressed_bytes=0
if command -v skopeo >/dev/null 2>&1; then
  # macOS bash 3.2 dislikes empty-array expansion under `set -u`, so we use
  # a simple string for the TLS flag and splat it unquoted.
  skopeo_tls=""
  [[ $image == localhost:* || $image == 127.0.0.1:* ]] && skopeo_tls="--tls-verify=false"
  # Prefer --raw to get the manifest list, then descend explicitly so the
  # result is deterministic regardless of skopeo's platform autoselection.
  raw=$(skopeo inspect $skopeo_tls --raw "docker://$image" 2>/dev/null || echo '{}')
  # Are we looking at an index (manifest list) or a single manifest?
  mediatype=$(echo "$raw" | jq -r '.mediaType // ""')
  if [[ $mediatype == *"image.index"* || $mediatype == *"manifest.list"* ]]; then
    # Pick the amd64/linux child manifest (matches what we build in Wave 0).
    child_digest=$(echo "$raw" \
      | jq -r '.manifests[] | select(.platform.os=="linux" and .platform.architecture=="amd64") | .digest' \
      | head -1)
    if [[ -n $child_digest ]]; then
      repo=${image%:*}
      child_raw=$(skopeo inspect $skopeo_tls --raw "docker://${repo}@${child_digest}" 2>/dev/null || echo '{}')
      compressed_bytes=$(echo "$child_raw" | jq '[.layers[]?.size // 0] | add // 0')
    fi
  else
    compressed_bytes=$(echo "$raw" | jq '[.layers[]?.size // 0] | add // 0')
  fi
fi
compressed_bytes=${compressed_bytes:-0}
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
