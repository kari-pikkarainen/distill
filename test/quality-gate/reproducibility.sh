#!/usr/bin/env bash
#
# Quality Gate check #6: Reproducibility.
#
# Builds the image twice in quick succession and verifies the output digests
# match. Non-determinism in container builds almost always comes from
# embedded timestamps or non-stable ordering — catching it here means we
# can make "reproducible builds" a real claim, not an aspiration.
#
# Usage:
#   reproducibility.sh <spec-file> [runs]
#
# Runs defaults to 2 (the minimum meaningful check). Set higher for a soak
# test (e.g. 3 at Wave 0 exit).

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
source "$here/lib.sh"

spec=${1:?usage: reproducibility.sh <spec-file> [runs]}
runs=${2:-2}

if ! [[ -f $spec ]]; then
  qg::fail "spec not found: $spec"
  exit 1
fi

qg::require jq
qg::require distill
cli=$(qg::container_cli)

image_ref=$(
  yq -r '.destination.image + ":" + (.destination.releasever // "latest")' "$spec"
)

platform=${DISTILL_PLATFORM:-linux/amd64}

# Deterministic timestamp for the build — if caller hasn't set
# SOURCE_DATE_EPOCH, derive it from the spec file so the same spec
# always produces the same epoch, a different spec produces a
# different one.
if [[ -z ${SOURCE_DATE_EPOCH:-} ]]; then
  # Spec content hash → epoch between 2000-01-01 and 2038-01-01.
  spec_hash=$(sha256sum "$spec" | cut -c1-8)
  # Decimal value of first 8 hex chars, mod (2038-2000 in seconds).
  spec_int=$((0x$spec_hash))
  range=$((2147472000 - 946684800))
  export SOURCE_DATE_EPOCH=$((946684800 + (spec_int % range)))
fi

qg::info "reproducibility soak: $runs build(s) of $spec on $platform"
qg::info "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"

digests=()
for (( i=1; i<=runs; i++ )); do
  qg::info "build $i/$runs …"
  if ! distill build --spec "$spec" --platform "$platform" >/dev/null 2>&1; then
    qg::fail "build $i failed"
    exit 1
  fi
  digest=$("$cli" image inspect "$image_ref" --format '{{.Id}}')
  qg::info "    → $digest"
  digests+=("$digest")
done

unique=$(printf '%s\n' "${digests[@]}" | sort -u | wc -l | tr -d ' ')

if [[ $unique -eq 1 ]]; then
  qg::pass "$runs builds produced identical digest ${digests[0]}"
  exit 0
fi

qg::fail "$runs builds produced $unique distinct digests:"
for d in "${digests[@]}"; do
  echo "    $d" >&2
done

if command -v diffoscope >/dev/null 2>&1; then
  qg::info "diffoscope is available — run it manually on the two image tarballs to diagnose"
else
  qg::info "install diffoscope to diagnose non-determinism"
fi

exit 1
