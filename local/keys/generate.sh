#!/usr/bin/env bash
#
# Generate a local Cosign keypair for Wave 0 signing tests.
#
# This keypair is NOT the production keypair — it exists only so that the
# local dry-run pipeline can exercise the signature chain without requiring
# a Sigstore OIDC identity. Wave 1 replaces this with keyless signing
# backed by GitHub Actions OIDC.
#
# The generated private key is password-protected with COSIGN_PASSWORD (or
# prompts if not set). Do NOT commit the private key — .gitignore covers
# it.
#
# Usage:
#   local/keys/generate.sh

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$here"

if [[ -f cosign.key ]]; then
  echo "cosign.key already exists in $here — refusing to overwrite" >&2
  echo "delete it first if you want to regenerate" >&2
  exit 1
fi

# Default to an empty password for local dev if not set. The key never
# leaves this directory and is not used for anything outside Wave 0.
export COSIGN_PASSWORD=${COSIGN_PASSWORD:-}

cosign generate-key-pair

echo ""
echo "Generated cosign.key (private) and cosign.pub (public) in $here"
echo "cosign.key is gitignored — do not commit it."
