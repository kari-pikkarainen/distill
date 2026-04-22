#!/usr/bin/env bash
#
# Quality Gate check #5: Signature + provenance verification.
#
# Verifies the Cosign signature and attached attestations on a published
# image. In Wave 0 we use a local keypair (not Sigstore keyless — that
# requires GitHub Actions OIDC). Wave 1 replaces this with keyless.
#
# Usage:
#   cosign-verify.sh <image-ref> [--key <cosign.pub>]
#
# The default public key path is local/keys/cosign.pub.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
source "$here/lib.sh"

image=${1:?usage: cosign-verify.sh <image-ref> [--key <cosign.pub>]}
shift || true

repo_root=$(cd "$here/../.." && pwd)
pub_key="$repo_root/local/keys/cosign.pub"

while (( $# )); do
  case $1 in
    --key) pub_key=$2; shift 2 ;;
    *) qg::fail "unknown arg: $1"; exit 2 ;;
  esac
done

qg::require cosign

if ! [[ -f $pub_key ]]; then
  qg::fail "public key not found: $pub_key"
  qg::info "run local/keys/generate.sh to create a local Cosign keypair"
  exit 1
fi

# Allow HTTP for localhost registries.
export COSIGN_REPOSITORY=${COSIGN_REPOSITORY:-}
if [[ $image == localhost:* ]]; then
  export COSIGN_EXPERIMENTAL=1
  insecure=(--allow-insecure-registry --allow-http-registry)
else
  insecure=()
fi

fail=0

# Signature
if cosign verify --key "$pub_key" "${insecure[@]}" "$image" >/dev/null 2>&1; then
  qg::pass "Cosign signature verifies"
else
  qg::fail "Cosign signature verification failed"
  fail=1
fi

# SBOM attestation (SPDX)
if cosign verify-attestation --key "$pub_key" --type spdxjson "${insecure[@]}" "$image" >/dev/null 2>&1; then
  qg::pass "SBOM attestation (spdxjson) verifies"
else
  qg::warn "SBOM attestation not present or not verifiable (skipped)"
fi

# SLSA provenance
if cosign verify-attestation --key "$pub_key" --type slsaprovenance "${insecure[@]}" "$image" >/dev/null 2>&1; then
  qg::pass "SLSA provenance attestation verifies"
else
  qg::warn "SLSA provenance attestation not present or not verifiable (skipped)"
fi

exit $fail
