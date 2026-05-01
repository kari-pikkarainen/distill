# distill — documentation

Strategic and design documents for distill as a commercial product. The
[top-level README](../README.md) covers the CLI itself; everything in this
directory describes the product, the test bench, the build plan, and the
hardening rationale.

## Read in this order if you're new

1. **[`strategy.md`](./strategy.md)** — Why distill exists commercially.
   Market opportunity, product tiers (CLI / Registry / Enterprise /
   Sovereign), pricing model with worked customer examples, MVP scope,
   competitive analysis, risks. Sets the direction every other doc serves.

2. **[`mvp-plan.md`](./mvp-plan.md)** — How we get there. Phased build
   order over 28 weeks with four waves, explicit kill-criteria per wave,
   dependency graph, file layout. Cross-cutting principles (publishable
   audit evidence, pinned build environment, dependency resilience).

3. **[`testing-strategy.md`](./testing-strategy.md)** — The test bench.
   Three layers: per-build quality gate (8 non-negotiable checks),
   nightly competitive benchmark harness, security program (ensemble
   scanning, CIS/STIG, pen test). Includes the compliance-evidence
   mapping for SOC 2 / FedRAMP / PCI / HIPAA / STIG / CIS controls.

## Read when answering specific questions

- **"Which distill image is right for my workload?"** —
  [`use-case-matrix.md`](./use-case-matrix.md). Decision guide with
  measured CVE counts, package counts, and sizes for distill vs. UBI9
  variants vs. Chainguard vs. eclipse-temurin.

- **"Are the images immutable, do they limit access, and can we reduce
  the CVEs?"** — [`image-hardening.md`](./image-hardening.md). Threat
  model, runtime security context recommendations, the empirical
  CVE floor for a TLS-capable RHEL image, and the "accept with rationale"
  exception pattern.

## Companion READMEs

These live alongside the code they describe rather than in this
directory:

- [`../local/README.md`](../local/README.md) — local registry,
  Cosign keypair, and pull-through cache setup
- [`../test/README.md`](../test/README.md) — quality-gate, benchmark,
  and audit-evidence layout
- [`../examples/README.md`](../examples/README.md) — example
  `.distill.yaml` specs with `container-structure-test` configurations
