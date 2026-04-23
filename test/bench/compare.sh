#!/usr/bin/env bash
#
# Wave 0 benchmark runner — compare a distill-built image against the
# upstream alternatives it replaces.
#
# Measures:
#   - CVE count by severity (critical / high / medium / low)
#   - Package count
#   - Compressed and uncompressed size
#
# Produces:
#   - A JSON report per comparison pair (machine-readable)
#   - A single-page HTML summary served on :8080 when --serve is passed
#
# Usage:
#   compare.sh --distill <img> --vs <img> [--vs <img> ...] [--out <dir>] [--serve]
#
# Example:
#   compare.sh \
#     --distill localhost:5000/base-ubi9:latest \
#     --vs docker.io/redhat/ubi9:latest \
#     --vs registry.access.redhat.com/ubi9-minimal:latest \
#     --vs registry.access.redhat.com/ubi9-micro:latest \
#     --out test/bench/report

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

distill_image=""
declare -a competitors=()
out="$here/report"
serve=0

# Capture tooling versions. When running inside distill-devbench, tool
# versions are pinned and recorded with the benchmark. Outside, note that
# numbers are tool-version-dependent and may not be reproducible.
if [[ -f /etc/devbench/versions.json ]]; then
  tooling_json=$(cat /etc/devbench/versions.json)
else
  tooling_json='{"source": "native", "note": "Tool versions not pinned; run via distill-devbench for reproducible numbers"}'
fi

while (( $# )); do
  case $1 in
    --distill) distill_image=$2; shift 2 ;;
    --vs)      competitors+=("$2"); shift 2 ;;
    --out)     out=$2; shift 2 ;;
    --serve)   serve=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z $distill_image || ${#competitors[@]} -eq 0 ]]; then
  echo "usage: compare.sh --distill <img> --vs <img> [--vs <img> ...] [--out <dir>] [--serve]" >&2
  exit 2
fi

mkdir -p "$out"
cli=${DISTILL_CONTAINER_CLI:-docker}

scanned_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

measure() {
  local image=$1
  local label=$2
  echo "  measuring $label ($image) …" >&2

  # Pull if not present locally.
  "$cli" pull "$image" >/dev/null 2>&1 || true

  # CVE counts (Grype).
  local grype_out
  grype_out=$(mktemp)
  grype "$image" -o json > "$grype_out" 2>/dev/null || echo '{"matches":[]}' > "$grype_out"

  local critical high medium low total
  critical=$(jq '[.matches[]? | select(.vulnerability.severity=="Critical")] | length' "$grype_out")
  high=$(jq     '[.matches[]? | select(.vulnerability.severity=="High")]     | length' "$grype_out")
  medium=$(jq   '[.matches[]? | select(.vulnerability.severity=="Medium")]   | length' "$grype_out")
  low=$(jq      '[.matches[]? | select(.vulnerability.severity=="Low")]      | length' "$grype_out")
  total=$(jq    '.matches | length' "$grype_out")

  # Package count (Syft).
  local package_count
  package_count=$(syft "$image" -o json 2>/dev/null | jq '.artifacts | length' 2>/dev/null || echo 0)

  # Sizes.
  local uncompressed_mb compressed_mb
  uncompressed_mb=$((
    $("$cli" image inspect "$image" --format '{{.Size}}' 2>/dev/null || echo 0)
    / 1024 / 1024
  ))
  compressed_mb=$((
    $("$cli" manifest inspect "$image" 2>/dev/null | jq '[.layers[]?.size // 0] | add // 0')
    / 1024 / 1024
  ))

  # Image digest.
  local digest
  digest=$("$cli" image inspect "$image" --format '{{.Id}}' 2>/dev/null || echo "unknown")

  rm -f "$grype_out"

  jq -n \
    --arg image "$image" \
    --arg label "$label" \
    --arg digest "$digest" \
    --argjson critical "$critical" \
    --argjson high "$high" \
    --argjson medium "$medium" \
    --argjson low "$low" \
    --argjson total "$total" \
    --argjson package_count "$package_count" \
    --argjson uncompressed_mb "$uncompressed_mb" \
    --argjson compressed_mb "$compressed_mb" \
    '{
      image: $image,
      label: $label,
      digest: $digest,
      cves: {critical: $critical, high: $high, medium: $medium, low: $low, total: $total},
      packages: $package_count,
      size: {uncompressed_mb: $uncompressed_mb, compressed_mb: $compressed_mb}
    }'
}

echo "==> Wave 0 benchmark ($scanned_at)" >&2
echo "distill target: $distill_image" >&2
echo "comparing against: ${competitors[*]}" >&2
echo "" >&2

distill_json=$(measure "$distill_image" "distill")

competitor_entries=()
for competitor in "${competitors[@]}"; do
  entry=$(measure "$competitor" "$competitor")
  competitor_entries+=("$entry")
done

# Assemble the full report.
report="$out/report.json"
{
  echo '{'
  echo '  "scanned_at": "'"$scanned_at"'",'
  echo '  "tooling": '
  echo "$tooling_json"
  echo '  ,'
  echo '  "distill": '
  echo "$distill_json"
  echo '  ,'
  echo '  "competitors": ['
  local_first=1
  for entry in "${competitor_entries[@]}"; do
    if (( local_first )); then local_first=0; else echo ','; fi
    echo "$entry"
  done
  echo '  ]'
  echo '}'
} | jq '.' > "$report"

echo "" >&2
echo "==> report written to $report" >&2

# Render an HTML summary.
html="$out/index.html"
cat > "$html" <<HTML
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>distill benchmark — ${distill_image##*/}</title>
<style>
  body { font: 15px/1.5 -apple-system, system-ui, sans-serif; margin: 2rem auto; max-width: 960px; color: #222; }
  h1 { font-size: 1.6rem; }
  h2 { font-size: 1.15rem; margin-top: 2.5rem; border-bottom: 1px solid #ddd; padding-bottom: 0.3rem; }
  table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
  th, td { text-align: left; padding: 0.4rem 0.6rem; border-bottom: 1px solid #eee; }
  th { background: #fafafa; }
  tr.distill { background: #e8f5e9; font-weight: 600; }
  .meta { color: #666; font-size: 0.9rem; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  code { background: #f4f4f4; padding: 0.1rem 0.3rem; border-radius: 3px; }
</style>

<h1>distill benchmark — <code>${distill_image##*/}</code></h1>
<p class="meta">Scanned at $scanned_at · machine-readable data:
  <a href="report.json">report.json</a></p>

<h2>Summary</h2>
<table>
  <thead><tr>
    <th>Image</th>
    <th class="num">Crit</th>
    <th class="num">High</th>
    <th class="num">Med</th>
    <th class="num">Low</th>
    <th class="num">Total CVEs</th>
    <th class="num">Packages</th>
    <th class="num">Compressed</th>
    <th class="num">Uncompressed</th>
  </tr></thead>
  <tbody>
HTML

# Row renderer.
render_row() {
  local entry=$1 cls=$2
  jq -r --arg cls "$cls" '
    "<tr class=\""+$cls+"\">" +
    "<td><code>"+.image+"</code></td>" +
    "<td class=\"num\">"+(.cves.critical|tostring)+"</td>" +
    "<td class=\"num\">"+(.cves.high|tostring)+"</td>" +
    "<td class=\"num\">"+(.cves.medium|tostring)+"</td>" +
    "<td class=\"num\">"+(.cves.low|tostring)+"</td>" +
    "<td class=\"num\"><strong>"+(.cves.total|tostring)+"</strong></td>" +
    "<td class=\"num\">"+(.packages|tostring)+"</td>" +
    "<td class=\"num\">"+(.size.compressed_mb|tostring)+" MB</td>" +
    "<td class=\"num\">"+(.size.uncompressed_mb|tostring)+" MB</td>" +
    "</tr>"' <<< "$entry"
}

render_row "$distill_json" "distill" >> "$html"
for entry in "${competitor_entries[@]}"; do
  render_row "$entry" "" >> "$html"
done

cat >> "$html" <<HTML
  </tbody>
</table>

<h2>Methodology</h2>
<p>Every number on this page is produced by <code>test/bench/compare.sh</code>
in the distill repository. Each image is pulled fresh, scanned with Grype,
cataloged with Syft, and inspected via the container runtime. Grype and Syft
versions are pinned in <code>devbox.json</code> so the measurements are
reproducible.</p>

<p>To re-run this comparison yourself:</p>
<pre><code>git clone git@github.com:damnhandy/distill.git
cd distill
devbox run bench</code></pre>

<p>If you can reproduce these numbers, the numbers are trustworthy. If you
can't, either your setup differs (we want to know) or our numbers are wrong
(we want to know).</p>
</html>
HTML

echo "==> HTML summary rendered to $html" >&2

if (( serve )); then
  echo "==> serving $out on http://localhost:8080" >&2
  cd "$out"
  python3 -m http.server 8080
fi
