# test/ — distill Test Bench

Three-layer test infrastructure supporting the strategy in
[`docs/testing-strategy.md`](../docs/testing-strategy.md).

## Layout

```
test/
├── quality-gate/     # Layer 1: per-build pass/fail checks (blocks publish)
│   ├── lib.sh            common helpers (colored output, tool checks)
│   ├── size-budget.sh    enforce compressed + uncompressed size limits
│   ├── sbom-completeness.sh   cross-check SBOM vs. RPM/dpkg DB
│   ├── cosign-verify.sh  verify signature + SBOM + SLSA attestations
│   ├── reproducibility.sh  build twice, verify identical digests
│   └── run-all.sh        orchestrator (calls every check except reproducibility)
├── bench/            # Layer 2: competitive benchmark (nightly)
│   ├── compare.sh        measure CVEs + packages + size; emit JSON + HTML
│   └── report/           output directory (generated, gitignored)
└── audit/            # Publishable audit evidence
    └── generate-evidence.sh  emit signed evidence bundle for an image
```

## Running locally

Every script is callable directly or via a devbox alias:

```bash
# One-command Wave 0 end-to-end
devbox run mvp-local

# Individual checks
devbox run quality-gate localhost:5000/base-ubi9:latest specs/base-ubi9.quality.yaml
devbox run bench
devbox run evidence localhost:5000/base-ubi9:latest specs/base-ubi9.distill.yaml evidence/base-ubi9/
devbox run reproducibility specs/base-ubi9.distill.yaml 3
```

## Why shell, not Go?

Wave 0 focuses on composing existing tools (`distill`, `grype`, `syft`,
`cosign`, `jq`, `yq`) rather than writing new code that re-implements them.
Shell is the right glue for this — it's transparent, easy to audit, and
every step is debuggable in isolation.

Wave 2+ may promote some of these to subcommands of the `distill` CLI
(`distill verify`, `distill bench`) so they work on customer machines
without a bash toolchain — but the shell scripts remain the source of
truth for what each check does.

## Relationship to the quality gate in `testing-strategy.md`

The [testing strategy](../docs/testing-strategy.md) defines 8 non-negotiable
quality-gate checks. This directory implements them as follows:

| # | Check | Status |
|---|---|---|
| 1 | Structure tests | Already in `examples/*/test.yaml` via `container-structure-test` |
| 2 | Size budget | `quality-gate/size-budget.sh` |
| 3 | SBOM completeness | `quality-gate/sbom-completeness.sh` |
| 4 | CVE gate (ensemble) | Partial — Grype via `test/bench/compare.sh` and `distill scan`; Trivy + Clair in Wave 1 |
| 5 | Signature + provenance verify | `quality-gate/cosign-verify.sh` |
| 6 | Reproducibility | `quality-gate/reproducibility.sh` |
| 7 | Functional smoke | Partial — structure tests cover minimal smoke; per-stack functional tests in Wave 2 |
| 8 | Multi-arch parity | Partial — CI matrix in Wave 1 |
