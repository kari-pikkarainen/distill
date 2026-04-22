# MVP Build Order — distill Registry

## Context

Two strategy documents now exist under `docs/`:

- `strategy.md` — commercial strategy, 4 product tiers, pricing, Phase 2 MVP scope
- `testing-strategy.md` — three-layer test bench (quality gate, benchmark, security)

The MVP ("Registry That Rebuilds") bundles ~15 work streams: registry infra,
15 image stacks, daily rebuild pipeline, 8-check quality gate, benchmark
harness, functional tests, landing page, Starter tier, Team tier, SOC 2
Type I audit, and supporting ops (status page, billing, auth).

This plan sequences those streams. The guiding principles:

1. **Prove end-to-end on one image before scaling to 15.** An architectural
   mistake on stack #1 that only shows up on stack #12 is months of rework.
2. **Quality gate first, then catalog.** Every new stack inherits the gate.
3. **Public benchmark page is the highest-leverage single deliverable.**
   Produces sales numbers, validates the strategy's "aha" demo claims,
   compounds marketing value.
4. **Starter (free) before Team (paid).** Usage signal before monetization.
   Billing is a distraction from product-market fit.
5. **Design-partner work runs in parallel, not gated by code milestones.**
6. **Audit evidence is a first-class product, not a byproduct.** Every image
   has a public audit URL and a signed, offline-verifiable evidence bundle
   from day one. "Send your auditor this link" is a headline feature, not a
   footnote. See the "Publishable Audit Evidence" section below.

## Current State (verified 2026-04-22)

**CLI is mature.** 9 commands: `build`, `publish`, `scan`, `attest`,
`provenance`, `init`, `doctor`, `version`, `mcp`. `publish` already does
build + scan + push + SBOM + provenance in one pipeline — it is effectively
a self-contained build worker. 6 example specs build cleanly in CI with
structure tests + SBOM + CVE scan.

**No registry infrastructure exists.** No `registry/`, `infra/`, `deploy/`,
`site/`, or `bench/` directories. Everything commercial-product-related is
greenfield.

## Cross-cutting Principle: Publishable Audit Evidence

Every artifact produced by the test bench and build pipeline must be
**visible to customers at a stable, citable URL**. The audit story is not
"we can produce evidence when you ask" — it is "here is the URL you send
your auditor."

### Why this is load-bearing

Competitors (Chainguard, Red Hat, Google distroless) publish vulnerability
summaries but not the full audit picture. The distill commercial pitch —
"swap your image, keep your compliance story" — only works if the audit
artifacts are permanent, timestamped, versioned, and signed. Chasing
artifacts during an audit is exactly the pain customers are buying their
way out of.

### Per-image audit page

Every image gets a stable URL:

```
distill.dev/images/<stack>                    → latest audit view
distill.dev/images/<stack>@sha256:<digest>    → specific build
distill.dev/images/<stack>/evidence.zip       → download bundle
distill.dev/images/<stack>/compliance/soc2    → SOC 2 control mapping
distill.dev/images/<stack>/compliance/pci-dss → PCI DSS control mapping
distill.dev/images/<stack>/compliance/stig    → DISA STIG profile
distill.dev/images/<stack>/compliance/fedramp → FedRAMP control mapping
```

Each audit page shows:

| Section | Content |
|---|---|
| Identity | digest, tags, arches, base distro + release, spec version |
| Contents | full SBOM (SPDX + CycloneDX), package count, size |
| Vulnerabilities | raw output from Grype + Trivy + Clair with CVE IDs, severity, affected packages, timestamp per scanner DB |
| Provenance | SLSA attestation: build environment, inputs (spec digest, base image digest), outputs (image digest, SBOM digest), builder identity |
| Signatures | Cosign signature + Rekor transparency-log entry + Fulcio cert chain |
| Quality gate | Each of the 8 checks: pass/fail, timestamp, raw output |
| Rebuild history | Timeline of builds for this stack: digest per rebuild, SBOM diff vs. prior build, CVE delta |
| Reproducibility | Proof that the last two builds produced identical digests |
| Benchmarks | Side-by-side vs. stock distro, competitor images, historical trend |
| **Compliance mapping** | Per-framework table: which controls this image satisfies, with links to specific artifacts as evidence |

### Downloadable evidence bundle

`distill.dev/images/<stack>/evidence.zip` contains everything an auditor
needs without network access:

```
evidence.zip/
├── manifest.json               # what's in the bundle, signed
├── sbom.spdx.json              # SPDX SBOM
├── sbom-cyclonedx.json         # CycloneDX SBOM (some auditors prefer this)
├── scan-grype.json             # raw Grype output + DB timestamp
├── scan-trivy.json             # raw Trivy output + DB timestamp
├── scan-clair.json             # raw Clair output + DB timestamp
├── provenance.intoto.jsonl     # SLSA v1.0 attestation
├── signature.sig               # Cosign signature
├── cert.pem                    # Fulcio signing cert
├── rekor-entry.json            # transparency log entry
├── quality-gate.json           # which checks ran, which passed
├── compliance-map.json         # framework → control → evidence mapping
├── build-log.txt               # sanitized build log
├── reproducibility.json        # same-spec build digests match
├── README.md                   # how to verify the bundle
└── VERIFY.sh                   # script that re-checks signatures offline
```

### Non-negotiables for the audit story

1. **URLs never change.** A digest-specific audit URL must resolve forever
   (or explicitly 410-gone with a redirect to supersession info).
2. **Evidence is signed.** The manifest inside `evidence.zip` is Cosign-signed
   so auditors can verify the bundle wasn't tampered with after download.
3. **Compliance mapping is explicit, not implied.** Every control we claim
   to satisfy has a link to a specific artifact in the bundle, not a
   generic "we support SOC 2" label.
4. **Scanner DB timestamps are recorded.** "5 CVEs" is meaningless without
   "as scanned against Grype DB v1.2.3 on 2026-04-22T02:14Z" — CVE counts
   change as DBs update, and auditors will ask.
5. **Downloadable offline.** Auditors often work in restricted environments.
   The whole evidence bundle must verify without internet (except for the
   Rekor transparency-log cross-check, which is optional).

### Framework-to-control mapping

The `compliance-map.json` in every bundle implements the table from
`testing-strategy.md` §"Compliance Evidence Mapping". Example:

```json
{
  "image": "base-ubi9@sha256:abc...",
  "scanned_at": "2026-04-22T02:14:37Z",
  "controls": {
    "SOC2 CC7.1": {
      "satisfied": true,
      "evidence": ["scan-grype.json", "scan-trivy.json", "scan-clair.json"],
      "note": "Ensemble CVE scan on every build; findings blocked at critical/high"
    },
    "FedRAMP SI-2": {
      "satisfied": true,
      "evidence": ["quality-gate.json", "rebuild-history.json"],
      "note": "Daily rebuild with 48-hour CVE patch SLA documented"
    },
    "CIS Docker 4.6": {
      "satisfied": true,
      "evidence": ["quality-gate.json"],
      "note": "HEALTHCHECK declared; verified by Trivy config scan"
    },
    "DISA STIG V-235796": {
      "satisfied": true,
      "evidence": ["sbom.spdx.json", "quality-gate.json"],
      "note": "No unauthorized services — package manager absent, services declared in spec"
    }
  }
}
```

This is the single most valuable asset in the commercial product after the
image itself. It compresses weeks of auditor discovery into one download.

## Dependency Graph

```
                 ┌──────────────────────────────────────────┐
                 │ Wave 0: LOCAL dry run                    │
                 │ docker-compose registry + local quality  │
                 │ gate + local benchmark + devbox script   │
                 └────────────────────┬─────────────────────┘
                                      │
                                      ▼
                 ┌─────────────────────────────────────────┐
                 │ Pipeline proven on a laptop — no cloud  │ ← WAVE 0 EXIT
                 └────────────────────┬────────────────────┘
                                      │
                 ┌────────────────────┼────────────────────┐
                 ▼                    ▼                    ▼
          ┌─────────────┐     ┌──────────────┐    ┌──────────────────┐
          │ Quality     │     │ Registry     │    │ Benchmark v1     │
          │ Gate v1     │     │ (Zot on AWS) │    │ (1 image vs UBI) │
          └──────┬──────┘     └──────┬───────┘    └────────┬─────────┘
                 │                   │                     │
                 └───────────────────┼─────────────────────┘
                                     ▼
                 ┌─────────────────────────────────────────┐
                 │ End-to-end: base-ubi9 published + bench │ ← WAVE 1 EXIT
                 └─────────────────┬───────────────────────┘
                                   │
                ┌──────────────────┼──────────────────┐
                ▼                  ▼                  ▼
       ┌────────────────┐ ┌─────────────────┐ ┌──────────────────┐
       │ Upstream       │ │ More stacks     │ │ Landing page     │
       │ watcher +      │ │ (base-debian,   │ │ real (catalog,   │
       │ scheduler      │ │ java21, py312,  │ │ SBOM viewer,     │
       │ (daily rebuild)│ │ node22, go)     │ │ benchmark UI)    │
       └────────┬───────┘ └────────┬────────┘ └──────────┬───────┘
                │                  │                     │
                ▼                  ▼                     ▼
       ┌──────────────────────────────────────────────────┐
       │ 6 stacks live, daily rebuilds, Starter tier open │ ← WAVE 2 EXIT
       │ 3 design partners pulling images                 │
       └─────────────────────┬────────────────────────────┘
                             │
             ┌───────────────┼───────────────┐
             ▼               ▼               ▼
      ┌──────────┐  ┌─────────────┐  ┌─────────────────┐
      │ Auth +   │  │ Remaining 9 │  │ SOC 2 Type I    │
      │ billing  │  │ stacks      │  │ audit (started  │
      │ (Team)   │  │             │  │ in Wave 2)      │
      └────┬─────┘  └──────┬──────┘  └────────┬────────┘
           │               │                   │
           ▼               ▼                   ▼
      ┌──────────────────────────────────────────┐
      │ 15 stacks live, first paying customer    │ ← WAVE 3 EXIT
      │ Team tier launched, status page live     │
      └──────────────────────────────────────────┘
```

## Proposed Sequence — Four Waves, 28 weeks

Assumes ~3 engineers + 1 founder as per strategy doc.

### Wave 0 — Local Dry Run (weeks 0–2)

**Goal:** Prove the entire MVP pipeline end-to-end on a single developer
laptop with zero cloud infrastructure. This de-risks signing, SBOM,
provenance, and quality-gate integration before a dollar is spent on AWS.

**Why this exists:** The components of the MVP (CLI, OCI registry,
scanners, Cosign, landing page) have never been composed together. Finding
out in week 6 that Cosign's keyless flow doesn't work with the way we
deploy Zot is a cloud-spend and timeline disaster. Finding out in week 1
on a laptop is a Tuesday.

**Side benefit:** The local stack becomes the reference architecture for
Enterprise tier self-hosted customers (Phase 3). Work is not throwaway.

| # | Work | Owner | Days | Blocks |
|---|---|---|---|---|
| 0.1 | Local OCI registry via docker-compose (Zot or `registry:2`), anonymous pull, TLS via mkcert | Eng A | 1–3 | 0.3, 0.4 |
| 0.2 | Extend existing `examples.yml` quality-gate checks into a reusable `test/quality-gate/` script runnable locally: size budget, SBOM completeness, `cosign verify`, reproducibility (build twice + `diffoscope`) | Eng B | 1–5 | 0.3 |
| 0.3 | End-to-end local script: `distill publish` on `base-ubi9` → push to local registry → run quality gate → emit pass/fail | Eng A | 4–7 | 0.5 |
| 0.4 | Local signing: Cosign keyless with a test OIDC provider (or generated local keypair for fully offline mode); verify signature round-trips | Eng B | 5–8 | 0.3 |
| 0.5 | Local benchmark v0: Go script that pulls distill `base-ubi9` + `ubi9/ubi` + `ubi9-minimal` + `ubi9-micro`, runs Grype + size/package counts, emits a static HTML report served on `:8080` | Eng C | 4–10 | 0.7 |
| 0.6 | Local daily-rebuild simulation: shell script + cron (not real infra) that triggers `distill publish` on a timer, validates the scheduler logic before it becomes a real service | Eng A | 8–11 | — |
| 0.7 | `devbox.json` / Makefile: single command (`make mvp-local` or `devbox run mvp`) spins up the whole local stack from a clean checkout | Eng C | 7–14 | — |
| 0.8 | Reproducibility soak test: run the full local pipeline 3 times, verify bit-identical output each run; document any non-determinism discovered | Eng B | 10–14 | — |
| 0.9 | **Audit evidence generator v0:** after each local build, emit `evidence/` directory with sbom + scans + provenance + quality-gate.json + compliance-map.json. Render a single-page HTML audit report at `localhost:8080/images/base-ubi9` — this is the prototype of the customer-facing audit URL | Eng C | 8–14 | Wave 1.4 |

**Exit criteria (all must hold):**

- A developer with a clean checkout can run one command and get: a local
  registry populated with a signed, SBOM-attached, scanned `base-ubi9`
  image, plus a locally-served benchmark page showing real numbers vs.
  stock UBI9 images
- `cosign verify` and `cosign verify-attestation` both succeed against the
  locally-published image
- The quality gate fails closed when a known bad spec is substituted (e.g.
  spec that exceeds size budget, spec that installs a known-CVE package)
- Two consecutive runs of the pipeline produce bit-identical image digests
- The local stack can be torn down and re-run from scratch in under 10
  minutes

**Kill criteria:** If by end of week 2 the pipeline cannot be composed end
to end on a laptop, a fundamental assumption about Cosign / Sigstore / OCI
referrers / SBOM attachment is wrong. Diagnose and redesign *before* any
cloud infra is built. Slipping into week 3 is acceptable; pushing through
with cloud work when Wave 0 is failing is not.

### Wave 1 — End-to-End on Cloud (weeks 2–10)

**Goal:** Port the proven local pipeline to real cloud infrastructure.
`base-ubi9` published through the full commercial pipeline on
`registry.distill.dev`. If this works, the rest is scaling.

**Why this is faster than "Wave 1 without Wave 0":** Wave 0 already
produced the quality-gate script (1.1 below), the local benchmark Go code
(1.5), and validated that the signing chain works. Wave 1 is
cloud-deployment work, not original engineering.

| # | Work | Owner | Weeks | Blocks |
|---|---|---|---|---|
| 1.1 | Port Wave 0 quality gate into cloud CI: run on GitHub Actions against the cloud registry; add Trivy as second scanner alongside Grype | Eng A | 2–4 | 1.3 |
| 1.2 | Cloud registry deployment: Zot on ECS or EKS, `registry.distill.dev` DNS + TLS, anonymous pull allowed, CloudWatch/Prometheus monitoring | Eng B | 2–6 | 1.3 |
| 1.3 | Cloud build pipeline: GitHub Actions workflow that runs `distill publish` for `base-ubi9` → runs quality gate → pushes to registry on green; differs from Wave 0 only in the push target and the signing identity | Eng A | 5–7 | 1.4, 1.5 |
| 1.4 | Landing page v1 deployed: promote Wave 0's local static site to `distill.dev` (Cloudflare Pages or S3 + CloudFront); includes the full audit page for `base-ubi9` at `distill.dev/images/base-ubi9` with SBOM viewer, scan results, provenance, benchmark, and compliance mapping | Eng C | 6–10 | 1.5 |
| 1.5 | Benchmark harness v1 cloud: extend Wave 0's local Go runner into a scheduled GitHub Actions workflow that writes results to S3 and regenerates the public page | Eng A | 7–10 | 1.4 |
| 1.6 | **Evidence bundle v1:** the build pipeline publishes `evidence.zip` to S3 at a stable URL (`distill.dev/images/base-ubi9/evidence.zip`), signed by Cosign. Compliance mapping covers SOC 2 CC7.1 and DISA STIG baseline only in v1 | Eng C | 8–10 | — |
| 1.7 | Design-partner outreach begins (parallel track, started during Wave 0) | Founder | 0–10 | — |

**Exit criteria (all must hold):**
- `docker pull registry.distill.dev/base-ubi9:latest` works for anyone on the
  public internet
- `cosign verify` and `cosign verify-attestation --type spdxjson` both succeed
- Quality gate fails closed when artificially regressed (size over budget,
  intentional CVE)
- Landing page shows the image and real benchmark numbers
- **`distill.dev/images/base-ubi9` serves the full audit page with SBOM,
  scan results, provenance, signing chain, and compliance mapping for
  SOC 2 CC7.1 and DISA STIG baseline**
- **`distill.dev/images/base-ubi9/evidence.zip` downloads a Cosign-signed
  bundle that verifies offline via `VERIFY.sh`**
- One design partner has agreed in principle to pull images in Wave 2

**Kill criteria:** If Wave 1 stretches past week 12 despite Wave 0 having
succeeded, the cloud-specific integration (IAM, DNS, Sigstore OIDC mapping
for GitHub Actions) has a problem that the local stack hid. Diagnose at
that layer rather than piling more stacks on a shaky foundation.

---

### Wave 2 — Scale the Catalog + Daily Rebuilds (weeks 10–20)

**Goal:** 6 stacks live, daily rebuilds running, 3 design partners actively
pulling images.

| # | Work | Owner | Weeks | Blocks |
|---|---|---|---|---|
| 2.1 | Upstream watcher: poll distro repo metadata + NVD/OVAL feeds, emit events when packages/CVEs change (prototype this locally first in the Wave 0 stack to de-risk scheduler logic) | Eng A | 10–14 | 2.2 |
| 2.2 | Build scheduler: subscribes to watcher events, enqueues `distill publish` jobs per affected spec × arch, handles retries/failures | Eng A | 12–16 | — |
| 2.3 | Add 5 stacks: `base-debian`, `java21-ubi9`, `python312-debian`, `node22-ubuntu`, `go-static-ubi9` (pick the order by design-partner demand) | Eng B | 10–18 | 2.4, 2.5 |
| 2.4 | Per-stack functional smoke tests (Spring Boot hello on Java, Flask on Python, Express on Node, static binary on Go) | Eng B/C | 12–19 | — |
| 2.5 | Benchmark expands to all 6 stacks; add Chainguard comparison (respecting their TOS) | Eng A | 16–19 | — |
| 2.6 | Landing page v2: real image catalog; per-image audit pages for all 6 stacks at `distill.dev/images/<stack>` with full SBOM + scans + provenance + rebuild history + benchmark comparison | Eng C | 12–19 | 2.7, 2.11 |
| 2.7 | Starter tier public launch: anonymous pulls with per-IP rate limits, `:latest` only | Eng B | 18–20 | — |
| 2.8 | Version-pinned tags (e.g. `:21.0.4-ubi9`, `:2026-06-15`) | Eng B | 16–19 | — |
| 2.9 | SOC 2 Type I audit kickoff (engage auditor, gap analysis) | Founder | 14–20 | Wave 3.4 |
| 2.10 | 3 design partners onboarded, pulling images into non-prod | Founder | 10–20 | — |
| 2.11 | **Compliance mapping expanded:** SOC 2 (CC6, CC7, CC8), PCI DSS (6.3, 7, 10), HIPAA Security Rule (164.308, 164.312), CIS Docker Benchmark. Per-framework pages at `distill.dev/images/<stack>/compliance/<framework>`. Evidence bundles include the full mapping | Eng C | 14–20 | — |
| 2.12 | **Digest-stable audit URLs:** every rebuild publishes `distill.dev/images/<stack>@sha256:<digest>` as a permanent URL so auditors can cite a specific point-in-time image even after rebuilds | Eng C | 16–19 | — |

**Exit criteria:**
- 6 image stacks published, rebuilt daily
- Upstream watcher correctly detects new UBI9 / Debian patches and triggers
  rebuilds within 24h of upstream availability
- Landing page shows live catalog with per-stack benchmarks
- **Every image has a per-image audit page at `distill.dev/images/<stack>`
  with full SBOM, scans, provenance, rebuild history, and compliance
  mapping for SOC 2 + PCI DSS + HIPAA + CIS + STIG baselines**
- **`evidence.zip` verifies offline for every image**
- **Digest-stable URLs resolve for every historical build (not just latest)**
- 3 design partners pulling images from Starter tier in non-prod
- At least 1 partner has asked for a stack not yet in the catalog (validation
  signal #4 from the strategy's MVP gate)
- **At least 1 design partner has shown a distill audit page to their
  auditor or security team** (this is the strongest possible validation
  signal for the positioning)

**Kill criteria:** If by week 20 no design partner is pulling regularly, the
positioning or catalog choice is wrong. Re-evaluate before investing in Team
tier / billing.

---

### Wave 3 — Monetize + Complete Catalog (weeks 20–28)

**Goal:** First paying customer, 15 stacks live, SOC 2 Type I in progress.

| # | Work | Owner | Weeks | Blocks |
|---|---|---|---|---|
| 3.1 | Registry auth: tokens for authenticated pulls, integration with billing tier | Eng B | 20–23 | 3.2, 3.3 |
| 3.2 | Billing integration: Stripe subscription for self-serve Team tier; manual invoicing acceptable for first 3–5 enterprise deals | Eng B | 22–25 | 3.6 |
| 3.3 | Add remaining 9 stacks: `java17-ubi9`, `python312-ubi9`, `dotnet8-ubi9`, `nginx-debian`, `redis7-debian`, `postgres16-ubi9`, `mariadb-ubi9`, `python310-debian`, `node20-ubuntu` (re-prioritize based on design-partner asks) | Eng A/C | 20–27 | — |
| 3.4 | SOC 2 Type I evidence collection (policies, test-bench outputs, pen test planning) | Founder + Eng | 20–28 | — |
| 3.5 | Status page (`status.distill.dev`), incident runbook, on-call rotation | Eng A | 24–26 | 3.6 |
| 3.6 | Team tier public launch: version pinning, CVE SLA, email support, TOS + MSA template | Founder + Eng B | 25–28 | — |
| 3.7 | Convert at least 1 design partner from Starter → paid Team | Founder | 22–28 | — |
| 3.8 | **FedRAMP control mapping added** to compliance framework catalog (AC, AU, IA, SI, SA, CM controls); `distill.dev/images/<stack>/compliance/fedramp` goes live for all 15 stacks — enables Sovereign tier sales conversations | Eng C | 22–26 | — |
| 3.9 | **Auditor-ready evidence bundle v2:** add `VERIFY.sh` script that re-runs signature verification, SBOM hash check, and provenance verification fully offline; add `manifest.json` signing; package all 15 stacks' bundles at stable URLs | Eng B | 24–27 | — |

**Exit criteria:**
- 15 image stacks published and rebuilt daily
- Team tier available for self-serve signup
- At least 1 paying customer at ~$20–30k/year design-partner rate
- SOC 2 Type I audit in progress with test-bench providing evidence
- Status page live with real uptime metrics

**Kill criteria:** If nobody converts from Starter → Team by week 28, the
willingness-to-pay assumption is wrong. Pivot strategy before investing in
Phase 3 (Enterprise).

## Critical files to modify or create

### Existing (modify)

- `.github/workflows/examples.yml` — extend with Wave 0.2 quality-gate
  checks (size budget, SBOM completeness, `cosign verify`, reproducibility)
- `cmd/` — add `distill verify` command for local quality-gate runs
  (built in Wave 0, referenced in `testing-strategy.md`)
- `internal/spec/spec.go` — add optional `quality:` section for size-budget
  field (Wave 0)
- `devbox.json` — extend with Wave 0.7 `mvp` script to orchestrate the local
  stack

### New (create)

- `infra/registry/` — Terraform or CDK for Zot deployment
- `infra/build-scheduler/` — upstream watcher + scheduler (Go service)
- `specs/` — canonical image specs for the 15 stacks (separate from
  `examples/` which stays as single-distro reference specs)
- `test/functional/<stack>/` — per-stack functional tests
- `test/bench/` — benchmark harness (see `testing-strategy.md` layout)
- `site/` — landing page, catalog, SBOM viewer, benchmark page
- `.github/workflows/benchmark.yml` — nightly benchmark harness
- `.github/workflows/compliance-nightly.yml` — CIS + STIG nightly (Wave 3)

## Reuse / leverage existing code

- `distill publish` is the build worker — no new build-farm code needed,
  just a scheduler that invokes it per spec × arch
- `internal/builder/oci.go` handles OCI image construction and can remain
  unchanged through all three waves
- `examples/*/test.yaml` structure-test patterns extend directly into the
  per-stack quality gate (test #1)
- Existing goreleaser + Cosign keyless signing on the CLI is the template for
  registry image signing (Wave 1.3)
- `.github/workflows/examples.yml` is the de-risking ground for Wave 1.1
  before the registry pipeline exists

## Verification

**Wave 0 end-to-end test (run locally at exit):**

```bash
# Clean checkout on any developer laptop
git clone git@github.com:damnhandy/distill.git && cd distill
devbox run mvp            # or `make mvp-local`

# After ~5 minutes, the local stack is up
curl -sSf https://localhost:5000/v2/_catalog | jq .
# → {"repositories":["base-ubi9"]}

# Pull the locally-published image
docker pull localhost:5000/base-ubi9:latest

# Verify signature round-trips (local Sigstore or keypair)
cosign verify localhost:5000/base-ubi9:latest \
  --key test-keys/cosign.pub

# Scan and compare
grype localhost:5000/base-ubi9:latest
grype registry.access.redhat.com/ubi9/ubi

# Local benchmark page
open http://localhost:8080/benchmarks/base-ubi9

# Reproducibility soak (part of exit criteria)
./test/quality-gate/reproducibility.sh base-ubi9 3
# → exit 0 means three consecutive builds produced identical digests

# Local audit page and evidence bundle
open http://localhost:8080/images/base-ubi9           # HTML audit view
curl -sSf http://localhost:8080/images/base-ubi9/evidence.zip -o evidence.zip
unzip -l evidence.zip | grep -q compliance-map.json
# and offline verify
cd /tmp && unzip evidence.zip && ./VERIFY.sh          # exits 0 when all sigs/hashes verify
```

**Wave 1 end-to-end test (run manually at exit):**

```bash
# From an unrelated machine
docker pull registry.distill.dev/base-ubi9:latest
cosign verify --certificate-identity-regexp "https://github.com/damnhandy/distill" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  registry.distill.dev/base-ubi9:latest
cosign verify-attestation --type spdxjson ... registry.distill.dev/base-ubi9:latest
grype registry.distill.dev/base-ubi9:latest --fail-on critical
curl -s https://distill.dev/benchmarks/base-ubi9 | grep -q "CVE count"

# Public audit page and evidence bundle
curl -sSf https://distill.dev/images/base-ubi9 | grep -q "Compliance"
curl -sSf https://distill.dev/images/base-ubi9/evidence.zip -o evidence.zip
unzip evidence.zip -d evidence/
./evidence/VERIFY.sh            # offline signature + hash re-check must pass
jq '.controls | keys' evidence/compliance-map.json   # SOC2 CC7.1 + STIG baseline present
```

**Wave 2 end-to-end test:**

```bash
for stack in base-ubi9 base-debian java21-ubi9 python312-debian node22-ubuntu go-static-ubi9; do
  docker pull registry.distill.dev/$stack:latest
  # quality-gate verify
  distill verify registry.distill.dev/$stack:latest
  # functional smoke
  ./test/functional/${stack%-*}/run.sh registry.distill.dev/$stack:latest
  # per-image audit page is live and has full compliance mapping
  curl -sSf "https://distill.dev/images/$stack" | grep -q "SOC 2"
  curl -sSf "https://distill.dev/images/$stack/compliance/pci-dss" | grep -q "6.3"
  curl -sSf "https://distill.dev/images/$stack/evidence.zip" -o /tmp/$stack-evidence.zip
  (cd /tmp && unzip -o $stack-evidence.zip -d $stack-ev && ./$stack-ev/VERIFY.sh)
done

# Verify daily rebuild happened in last 24h
curl -s https://registry.distill.dev/v2/base-ubi9/tags/list | jq '.tags[] | select(test("^20"))'

# Digest-stable audit URL resolves for a past build
DIGEST=$(docker buildx imagetools inspect registry.distill.dev/base-ubi9:latest --format '{{.Manifest.Digest}}')
curl -sSf "https://distill.dev/images/base-ubi9@${DIGEST}" | grep -q "$DIGEST"
```

**Wave 3 end-to-end test:**

```bash
# Auth flow
docker login registry.distill.dev -u $USER -p $TOKEN
docker pull registry.distill.dev/java21-ubi9:21.0.4  # version-pinned

# All 15 stacks published
for stack in $(curl -s https://distill.dev/catalog | jq -r '.[].name'); do
  docker manifest inspect registry.distill.dev/$stack:latest >/dev/null
done | wc -l  # should be 15

# Every stack has a FedRAMP compliance page (Sovereign tier enabler)
for stack in $(curl -s https://distill.dev/catalog | jq -r '.[].name'); do
  curl -sSf "https://distill.dev/images/$stack/compliance/fedramp" | grep -q "AC-2"
done

# Status page returns 200, shows real data
curl -s https://status.distill.dev/ | grep -q "Operational"
```

## Open questions for the user

1. **Team size assumption** — the plan assumes ~3 engineers + 1 founder
   (from the strategy doc). If actual capacity is smaller, Wave 3 slips; if
   larger, we can parallelize more aggressively within each wave.
2. **Priority tie-breaker** — if Wave 2 is running hot, do we drop stacks
   (ship 4 instead of 6) or slip Starter tier launch? The plan currently
   assumes we drop stacks.
3. **Design-partner pipeline** — are candidates already identified, or is
   the parallel outreach during Wave 0/1 starting from scratch? Affects
   Wave 2 exit risk.
4. **Capital position** — Wave 3 includes ~$30–50k for SOC 2 Type I and
   will need hosting budget through all three waves. Bootstrap or funded?
5. **Sequencing preference within waves** — do you want this re-organized by
   track (infra / images / site / compliance) instead of by wave? Track-based
   makes parallelism clearer; wave-based makes dependencies clearer.

## What this plan does NOT cover

- **Phase 3 (Enterprise tier)** — policy engine, spec inheritance, private
  repo integration, self-hosted pipeline option. That is post-MVP and
  deserves its own plan. Note: Wave 0's local stack becomes the *reference
  architecture* for the self-hosted pipeline option, so this work is not
  throwaway.
- **Phase 4 (Sovereign / FedRAMP)** — FIPS builds, air-gapped bundle, FedRAMP
  evidence. Also post-MVP.
- **Layer 3 of the test bench** (CIS/STIG automation, external pen test, bug
  bounty) — listed in `testing-strategy.md` as Phase 3 work; not part of this
  MVP.
- **Go-to-market execution** (content, conferences, SDR pipeline) — the
  strategy doc covers this; not a build-order concern.
