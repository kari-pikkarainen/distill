#!/usr/bin/env bash
#
# Run the benchmark for every profile in profiles.yaml and render a
# multi-section landing page. Reuses the per-image measurement logic in
# compare.sh.
#
# Usage:
#   run-profiles.sh [--profiles <file>] [--out <dir>]

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)

profiles_file="$here/profiles.yaml"
out="$here/report"

while (( $# )); do
  case $1 in
    --profiles) profiles_file=$2; shift 2 ;;
    --out)      out=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$out"
scanned_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Capture tooling provenance for the landing page.
if [[ -f /etc/devbench/versions.json ]]; then
  tooling_note="Pinned tool versions from distill-devbench image."
else
  tooling_note="Tool versions not pinned; run via distill-devbench for reproducible numbers."
fi

num_profiles=$(yq '.profiles | length' "$profiles_file")
echo "==> running $num_profiles profile(s), $scanned_at" >&2

# Run compare.sh once per profile.
for i in $(seq 0 $((num_profiles - 1))); do
  id=$(yq -r ".profiles[$i].id" "$profiles_file")
  title=$(yq -r ".profiles[$i].title" "$profiles_file")
  distill_image=$(yq -r ".profiles[$i].distill" "$profiles_file")
  competitors=()
  ncompetitors=$(yq ".profiles[$i].competitors | length" "$profiles_file")
  for j in $(seq 0 $((ncompetitors - 1))); do
    competitors+=("$(yq -r ".profiles[$i].competitors[$j].image" "$profiles_file")")
  done

  echo "" >&2
  echo "━━━ profile $((i+1))/$num_profiles: $title" >&2
  profile_out="$out/profiles/$id"
  mkdir -p "$profile_out"

  vs_args=()
  for c in "${competitors[@]}"; do
    vs_args+=("--vs" "$c")
  done

  # compare.sh uses bash 3.2 so we splat the array the safe way.
  "$here/compare.sh" \
    --distill "$distill_image" \
    "${vs_args[@]}" \
    --out "$profile_out" >/dev/null 2>&1 || echo "  (some measurements failed for profile $id; see $profile_out/)" >&2
done

# ── Landing page for the full profile set ─────────────────────────────────
html="$out/index.html"

render_html_prefix() {
  cat <<HTML
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>distill — benchmark (all profiles)</title>
<style>
  body { font: 15px/1.55 -apple-system, system-ui, sans-serif; margin: 2rem auto; max-width: 1100px; color: #222; }
  h1 { font-size: 1.7rem; margin-bottom: 0.2rem; }
  h2 { font-size: 1.2rem; margin-top: 3rem; padding-bottom: 0.3rem; border-bottom: 1px solid #ccc; }
  h3 { font-size: 1rem; margin: 1rem 0 0.5rem; color: #555; font-weight: 600; }
  table { width: 100%; border-collapse: collapse; margin: 0.6rem 0 1.2rem; font-size: 0.92rem; }
  th, td { text-align: left; padding: 0.4rem 0.6rem; border-bottom: 1px solid #eee; }
  th { background: #fafafa; font-weight: 600; }
  tr.distill { background: #e8f5e9; }
  tr.distill td { font-weight: 600; }
  .meta { color: #666; font-size: 0.88rem; }
  .use-case { background: #f8fafc; border-left: 3px solid #0969da; padding: 0.6rem 0.9rem; margin: 0.5rem 0 0.9rem; font-size: 0.93rem; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  code { background: #f4f4f4; padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.88em; }
  .profile-nav { margin: 1rem 0 1.5rem; }
  .profile-nav a { display: inline-block; margin-right: 0.8rem; padding: 0.25rem 0.6rem; border: 1px solid #ddd; border-radius: 4px; text-decoration: none; color: #222; font-size: 0.9rem; }
  .profile-nav a:hover { background: #eef; }
  .footer { color: #666; font-size: 0.85rem; margin-top: 3rem; padding-top: 1rem; border-top: 1px solid #eee; }
</style>

<h1>distill benchmark — all profiles</h1>
<p class="meta">Scanned at TIMESTAMP_PLACEHOLDER · TOOLING_PLACEHOLDER</p>
<nav class="profile-nav">NAV_PLACEHOLDER</nav>
HTML
}

render_html_prefix \
  | sed -e "s|TIMESTAMP_PLACEHOLDER|$scanned_at|" \
        -e "s|TOOLING_PLACEHOLDER|$tooling_note|" \
  > "$html"

# Build nav.
nav=""
for i in $(seq 0 $((num_profiles - 1))); do
  id=$(yq -r ".profiles[$i].id" "$profiles_file")
  title=$(yq -r ".profiles[$i].title" "$profiles_file")
  nav+="<a href=\"#profile-$id\">$title</a>"
done
# Replace NAV_PLACEHOLDER line.
awk -v nav="$nav" '{gsub("NAV_PLACEHOLDER", nav); print}' "$html" > "$html.tmp" && mv "$html.tmp" "$html"

# Render each profile section.
for i in $(seq 0 $((num_profiles - 1))); do
  id=$(yq -r ".profiles[$i].id" "$profiles_file")
  title=$(yq -r ".profiles[$i].title" "$profiles_file")
  use_case=$(yq -r ".profiles[$i].use-case" "$profiles_file")
  report_json="$out/profiles/$id/report.json"

  {
    echo "<h2 id=\"profile-$id\">$title</h2>"
    echo "<div class=\"use-case\">$(echo "$use_case" | sed 's/$/<br>/' )</div>"

    if [[ ! -f $report_json ]]; then
      echo "<p class=\"meta\">(measurement failed — see <code>$report_json</code>)</p>"
      continue
    fi

    # One row per image. distill highlighted first.
    echo "<table><thead><tr>"
    echo "  <th>Image</th>"
    echo "  <th class=\"num\">Crit</th>"
    echo "  <th class=\"num\">High</th>"
    echo "  <th class=\"num\">Med</th>"
    echo "  <th class=\"num\">Low</th>"
    echo "  <th class=\"num\">Total CVEs</th>"
    echo "  <th class=\"num\">Packages</th>"
    echo "  <th class=\"num\">Compressed</th>"
    echo "  <th class=\"num\">Uncompressed</th>"
    echo "</tr></thead><tbody>"

    # Distill row.
    jq -r '.distill |
      "<tr class=\"distill\"><td><code>" + .image + "</code></td>" +
      "<td class=\"num\">" + (.cves.critical|tostring) + "</td>" +
      "<td class=\"num\">" + (.cves.high|tostring) + "</td>" +
      "<td class=\"num\">" + (.cves.medium|tostring) + "</td>" +
      "<td class=\"num\">" + (.cves.low|tostring) + "</td>" +
      "<td class=\"num\"><strong>" + (.cves.total|tostring) + "</strong></td>" +
      "<td class=\"num\">" + (.packages|tostring) + "</td>" +
      "<td class=\"num\">" + (.size.compressed_mb|tostring) + " MB</td>" +
      "<td class=\"num\">" + (.size.uncompressed_mb|tostring) + " MB</td></tr>"' \
      "$report_json"

    # Competitor rows.
    jq -r '.competitors[] |
      "<tr><td><code>" + .image + "</code></td>" +
      "<td class=\"num\">" + (.cves.critical|tostring) + "</td>" +
      "<td class=\"num\">" + (.cves.high|tostring) + "</td>" +
      "<td class=\"num\">" + (.cves.medium|tostring) + "</td>" +
      "<td class=\"num\">" + (.cves.low|tostring) + "</td>" +
      "<td class=\"num\"><strong>" + (.cves.total|tostring) + "</strong></td>" +
      "<td class=\"num\">" + (.packages|tostring) + "</td>" +
      "<td class=\"num\">" + (.size.compressed_mb|tostring) + " MB</td>" +
      "<td class=\"num\">" + (.size.uncompressed_mb|tostring) + " MB</td></tr>"' \
      "$report_json"

    echo "</tbody></table>"
    echo "<p class=\"meta\">Raw data: <a href=\"profiles/$id/report.json\">report.json</a></p>"
  } >> "$html"
done

cat >> "$html" <<HTML

<div class="footer">
  <p>Reproduce locally: <code>devbox run bench-profiles</code>. Methodology:
  each image is pulled fresh, scanned with Grype, cataloged with Syft, and
  sized via the registry manifest. Grype/Syft versions are pinned in the
  distill-devbench container — when this page is generated inside that
  container, the tool versions appear in each per-profile report.json.</p>
</div>
</html>
HTML

echo "" >&2
echo "==> landing page: $html" >&2
echo "==> per-profile reports: $out/profiles/" >&2
