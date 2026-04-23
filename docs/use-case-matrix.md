# Which image should I pick?

A decision guide for container base images, grounded in the Wave 0
benchmark measurements (2026-04-23). Re-run locally with
`devbox run bench-profiles`.

## The short version

| Use case | Best pick | Why |
|---|---|---|
| Static Go / Rust binary, no compliance mandate | `chainguard/static` or scratch | Fewest dependencies → fewest CVEs |
| Static binary, RHEL-family mandate | `ubi9-micro` or distill base | RHEL family + tiny footprint |
| Complex Go/Rust app with some OS deps, no compliance mandate | `chainguard/wolfi-base` | 2 CVEs, 6 MB |
| Complex Go/Rust app with some OS deps, **RHEL mandate** | **distill base-ubi9** | customizable; 3× fewer CVEs than `ubi9-minimal` |
| Java service, no compliance mandate | `chainguard/jre` | 2 CVEs vs. 81+ elsewhere |
| Java service, **RHEL mandate** | **distill java21-ubi9** | 35% fewer CVEs than Red Hat's own `ubi9/openjdk-21-runtime` |
| Java service with broad package requirements | `eclipse-temurin:21-jre` | Best community JRE on Debian |
| Dev/CI container with a shell | `ubi9-minimal` or `ubuntu:24.04` | Has `microdnf` / `apt` for add-hoc install |
| Anything going through FedRAMP/DoD | **distill** (Wave 2: FIPS variant) | Controlled chain-of-custody; currently Sovereign-tier roadmap |

## The measurements

### Base OS (minimal Linux userland)

| Image | CVEs | Packages | Size |
|---|---:|---:|---:|
| **distill base-ubi9** | **34** | **41** | **19 MB** |
| UBI9 stock | 334 | 206 | 76 MB |
| UBI9 minimal | 102 | 109 | 38 MB |
| UBI9 micro | 16 | 22 | 6 MB |
| Chainguard wolfi-base | 2 | 15 | 6 MB |

### Java 21 JRE (production runtime)

| Image | CVEs | Packages | Size |
|---|---:|---:|---:|
| **distill java21-ubi9** | **126** | **88** | **112 MB** |
| eclipse-temurin 21-jre (Debian) | 81 | 138 | 95 MB |
| Red Hat UBI9 openjdk-21-runtime | 193 | 135 | 133 MB |
| Chainguard JRE | 2 | 38 | 104 MB |

## What the numbers say

### distill beats Red Hat at Red Hat's own game

In the Java profile, distill's image has **35% fewer CVEs** (126 vs 193)
and **34% smaller** (112 MB vs 133 MB) than Red Hat's own
`ubi9/openjdk-21-runtime`. Both are built from the same RHEL OpenJDK
package. The difference: Red Hat's image ships with ~50 extra OS packages
(dev tools, locale data, shell utilities) that we declared out of the spec.

**This is the headline commercial claim.** Every Fortune 500 RHEL Java
deployment running `ubi9/openjdk-21-runtime` today can cut CVE count by a
third by switching to distill — *without changing their RHEL support
contract, distro packages, or audit-approved OS family.*

### Chainguard is the raw-CVE leader — and that's fine

Chainguard images report **2 CVEs** in both profiles. distill and every
other competitor ship 30–200. Chainguard wins this fight decisively.

But Chainguard ships on Wolfi — a custom Linux distribution. That matters
for organizations that are:

- Contractually required to use RHEL, UBI, or Debian
- Audited against frameworks that enumerate approved base distros
- Running existing vulnerability-tracking tooling tuned for RHEL or Debian CVE IDs
- Operating under a Red Hat subscription for support

For those organizations, "Chainguard has fewer CVEs" is not a question
their procurement or security-compliance team can accept as an answer —
the answer has to be "how do we reduce CVEs *in the base distro we're
already committed to?*" distill is the answer to that question.

### ubi9-micro is the "just make it small" champion for RHEL family

UBI9-micro ships only 22 packages and has 16 CVEs. If your workload is
a static binary that links only against glibc, `ubi9-micro` is the right
choice — distill can't beat it on pure size because you can't have
negative packages.

distill wins when your workload needs **anything** not in ubi9-micro's
fixed package set — `ca-certificates`, `tzdata`, `glibc-langpack-en`,
specific utility libraries — because distill adds only what you declare,
whereas stepping up to `ubi9-minimal` gets you 109 packages and 102 CVEs
for the privilege of installing one missing tool.

### Debian-based stock images are competitive but out-of-contract

`eclipse-temurin:21-jre` has solid numbers (81 CVEs, 95 MB) and is a fine
choice when there's no distro mandate. It's Debian Bookworm-based — which
excludes it from RHEL-mandated environments. It also doesn't come with a
SBOM or provenance attestation by default.

## Decision tree

```
┌──────────────────────────────────────────────────────────────────────┐
│ Does your org require RHEL, UBI, or a specific enterprise distro?    │
└──────────────────────────────────────────────────────────────────────┘
                 │                                     │
                yes                                    no
                 ▼                                     ▼
┌─────────────────────────────────┐   ┌─────────────────────────────────┐
│ Can the workload run on         │   │ Consider Chainguard images.     │
│ ubi9-micro (static, no extras)? │   │ 2 CVEs per image is unmatched.  │
└─────────────────────────────────┘   │                                 │
        │               │             │ Caveats:                        │
       yes              no            │  - commercial tier for version  │
        ▼               ▼             │    pinning + SLA ($$$)          │
┌──────────────┐  ┌─────────────┐    │  - wolfi, not RHEL/Debian/Ubuntu│
│ ubi9-micro   │  │ distill     │    │  - vendor lock-in to Chainguard │
│ (smallest)   │  │ (custom)    │    │    ecosystem                    │
└──────────────┘  └─────────────┘    └─────────────────────────────────┘
```

## When distill is the wrong choice

The strategy document is already explicit about this; restated here for
completeness:

- **If you don't need compliance-distro fidelity and want the absolute
  minimum CVEs**, Chainguard is a better fit. distill isn't trying to
  win this comparison — we lose it intentionally in exchange for RHEL
  compatibility.
- **If you need a dev container with package manager included**, use
  `ubi9` stock or `debian:bookworm` — distill's `runtime` variant
  deliberately strips those out.
- **If you just need a shell base and don't care about images at all**,
  Google distroless is well-known, well-supported, and free. It's
  Debian-based and has no SBOM/provenance — but if those don't matter
  to your org, it's a fine default.

## How to re-run these measurements

```bash
# Fetch, scan, measure every image in every profile. Takes ~3 minutes.
devbox run bench-profiles

# Results:
open http://localhost:8088/benchmarks/
```

Tool versions and CVE database dates are recorded in each
`report.json`. When this benchmark is run inside the `distill-devbench`
container, the tool versions are pinned to an image digest — so the
numbers above are reproducible, not just memorable.
