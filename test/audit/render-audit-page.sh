#!/usr/bin/env bash
#
# Render an auditor-facing HTML page from a generated evidence bundle.
# Produces `index.html` next to the bundle files so a directory listing
# is replaced with a structured summary — without hiding the raw JSON.
#
# Usage:
#   render-audit-page.sh <evidence-dir>

set -euo pipefail

evidence=${1:?usage: render-audit-page.sh <evidence-dir>}

if [[ ! -f $evidence/compliance-map.json ]]; then
  echo "not an evidence bundle: $evidence (missing compliance-map.json)" >&2
  exit 1
fi

cd "$evidence"

image=$(jq -r '.image' compliance-map.json)
image_digest=$(jq -r '.image_digest' compliance-map.json)
scanned_at=$(jq -r '.scanned_at' compliance-map.json)
crit=$(jq '.cve_summary.critical' compliance-map.json)
high=$(jq '.cve_summary.high' compliance-map.json)
med=$(jq '.cve_summary.medium' compliance-map.json)
low=$(jq '.cve_summary.low' compliance-map.json)

# Compliance rows (key → satisfied/description/evidence/note)
compliance_rows=$(
  jq -r '.controls | to_entries[] |
    "<tr><td><strong>" + .key + "</strong></td>" +
    "<td class=\"" + (if .value.satisfied then "pass" else "fail" end) + "\">" +
      (if .value.satisfied then "✓ satisfied" else "✗ not satisfied" end) +
    "</td>" +
    "<td>" + .value.description + "</td>" +
    "<td>" + (.value.evidence | map("<a href=\"" + . + "\">" + . + "</a>") | join(", ")) + "</td>" +
    "<td class=\"note\">" + (.value.note // "") + "</td></tr>"' \
    compliance-map.json
)

# SBOM stats for sidebar
sbom_pkgs=$(jq '.packages | length' sbom.spdx.json 2>/dev/null || echo "?")
sbom_relationships=$(jq '.relationships | length // 0' sbom.spdx.json 2>/dev/null || echo "?")

# Spec + tooling
spec=$(jq -r '.spec' image-info.json 2>/dev/null || echo "?")
spec_digest=$(jq -r '.spec_digest' image-info.json 2>/dev/null || echo "?")
distill_version=$(jq -r '.distill_version' image-info.json 2>/dev/null || echo "?")
tooling_source=$(jq -r '.tooling.source // "unknown"' image-info.json 2>/dev/null || echo "?")

cat > index.html <<HTML
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>Audit — $(basename "$(dirname "$(pwd)")" 2>/dev/null || basename "$(pwd)")</title>
<style>
  body { font: 15px/1.55 -apple-system, system-ui, sans-serif; margin: 2rem auto; max-width: 1100px; color: #222; }
  h1 { font-size: 1.6rem; margin: 0; }
  h2 { font-size: 1.15rem; margin-top: 2.2rem; padding-bottom: 0.3rem; border-bottom: 1px solid #ccc; }
  .identity { background: #f4f6f8; padding: 0.8rem 1rem; border-radius: 6px; margin: 0.8rem 0 1.5rem; font-size: 0.9rem; }
  .identity dt { font-weight: 600; color: #555; display: inline-block; min-width: 120px; }
  .identity dd { display: inline; margin: 0; }
  .identity dl > div { padding: 0.15rem 0; }
  code { background: #eef0f3; padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.88em; }
  .cve-summary { display: flex; gap: 0.7rem; margin: 0.8rem 0; }
  .cve-cell { flex: 1; text-align: center; padding: 0.9rem 0.5rem; border-radius: 6px; border: 1px solid #ddd; background: #fafbfc; }
  .cve-cell.crit { border-color: #cc0000; }
  .cve-cell.high { border-color: #ff8800; }
  .cve-cell.med  { border-color: #d4a800; }
  .cve-cell.low  { border-color: #999; }
  .cve-cell .n { font-size: 1.8rem; font-weight: 600; display: block; font-variant-numeric: tabular-nums; }
  .cve-cell .lbl { font-size: 0.8rem; text-transform: uppercase; color: #666; letter-spacing: 0.05em; }
  table { width: 100%; border-collapse: collapse; font-size: 0.92rem; margin: 0.4rem 0 1rem; }
  th, td { text-align: left; padding: 0.5rem 0.6rem; border-bottom: 1px solid #eee; vertical-align: top; }
  th { background: #fafafa; }
  td.pass { color: #0a7a0a; font-weight: 600; white-space: nowrap; }
  td.fail { color: #cc0000; font-weight: 600; white-space: nowrap; }
  td.note { color: #666; font-size: 0.9em; }
  .verify-block { background: #1e293b; color: #e2e8f0; padding: 0.9rem 1.1rem; border-radius: 6px; font-family: "SF Mono", Menlo, Consolas, monospace; font-size: 0.88em; line-height: 1.5; white-space: pre-wrap; overflow-x: auto; }
  .files-list a { display: inline-block; margin: 0.15rem 0.5rem 0.15rem 0; padding: 0.2rem 0.55rem; border: 1px solid #d6dae0; border-radius: 4px; text-decoration: none; color: #333; font-size: 0.88em; }
  .files-list a:hover { background: #eef; }
  .meta { color: #666; font-size: 0.87rem; }
</style>

<h1>Audit Evidence — <code>$image</code></h1>
<p class="meta">Scanned at <time>$scanned_at</time>. Bundle is tamper-evident
(SHA-256 per file, Cosign-signed manifest).</p>

<section class="identity">
  <dl>
    <div><dt>Image digest:</dt> <dd><code>$image_digest</code></dd></div>
    <div><dt>Spec file:</dt> <dd><code>$spec</code></dd></div>
    <div><dt>Spec digest:</dt> <dd><code>$spec_digest</code></dd></div>
    <div><dt>distill version:</dt> <dd><code>$distill_version</code></dd></div>
    <div><dt>Tool provenance:</dt> <dd>$tooling_source</dd></div>
  </dl>
</section>

<h2>CVE summary</h2>
<div class="cve-summary">
  <div class="cve-cell crit"><span class="n">$crit</span><span class="lbl">Critical</span></div>
  <div class="cve-cell high"><span class="n">$high</span><span class="lbl">High</span></div>
  <div class="cve-cell med"><span class="n">$med</span><span class="lbl">Medium</span></div>
  <div class="cve-cell low"><span class="n">$low</span><span class="lbl">Low</span></div>
</div>
<p class="meta">Raw scanner output: <a href="scan-grype.json">scan-grype.json</a> (Grype). Ensemble with Trivy + Clair in Wave 1.</p>

<h2>Compliance framework mapping</h2>
<table>
  <thead><tr>
    <th>Control</th>
    <th>Status</th>
    <th>Description</th>
    <th>Evidence</th>
    <th>Note</th>
  </tr></thead>
  <tbody>
    $compliance_rows
  </tbody>
</table>
<p class="meta">Coverage expands across waves: Wave 0 = SOC 2 CC7/CC8 + STIG baseline + CIS Docker 5.29. Wave 2 adds SOC 2 CC6, PCI DSS 6/7/10, HIPAA 164.308/164.312, and the full CIS Docker benchmark. Wave 3 adds FedRAMP Moderate/High.</p>

<h2>Verify this bundle offline</h2>
<div class="verify-block">\$ ./VERIFY.sh --key /path/to/cosign.pub

verifying evidence bundle in ...
1. re-hashing files and comparing to manifest …
   ✓ all files match their recorded hashes
2. verifying manifest signature …
   ✓ manifest signature verifies against ...
VERIFY OK</div>
<p class="meta">VERIFY.sh is offline-only: <code>sha256sum</code>, <code>jq</code>, and optionally <code>cosign</code>. No network, no Rekor lookup required (though Rekor is authoritative for Wave 1+ keyless signatures).</p>

<h2>Package inventory (SBOM)</h2>
<p>$sbom_pkgs packages, $sbom_relationships relationships. Two formats:
<a href="sbom.spdx.json">sbom.spdx.json</a> (SPDX 2.3) ·
<a href="sbom-cyclonedx.json">sbom-cyclonedx.json</a> (CycloneDX 1.5).</p>

<h2>All bundle files</h2>
<p class="files-list">
  <a href="compliance-map.json">compliance-map.json</a>
  <a href="image-info.json">image-info.json</a>
  <a href="sbom.spdx.json">sbom.spdx.json</a>
  <a href="sbom-cyclonedx.json">sbom-cyclonedx.json</a>
  <a href="scan-grype.json">scan-grype.json</a>
  <a href="provenance.json">provenance.json</a>
  <a href="quality-gate.json">quality-gate.json</a>
  <a href="manifest.json">manifest.json</a>
  <a href="manifest.sig">manifest.sig</a>
  <a href="manifest.bundle">manifest.bundle</a>
  <a href="VERIFY.sh">VERIFY.sh</a>
  <a href="README.md">README.md</a>
</p>

<p class="meta" style="margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #eee;">
  This page is generated from <code>compliance-map.json</code> and <code>image-info.json</code>
  by <code>test/audit/render-audit-page.sh</code>. The raw JSON is the authoritative
  evidence; this HTML is a presentational view for humans.
</p>
</html>
HTML

echo "rendered: $evidence/index.html"
