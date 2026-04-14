# distill

Build minimal, immutable OCI images from enterprise Linux base distributions.

Distill is a [Dagger](https://dagger.io) module that takes a declarative YAML spec and produces a minimal `FROM scratch` OCI image using a chroot bootstrap strategy. It is a distro-agnostic alternative to Google's [distroless](https://github.com/GoogleContainerTools/distroless) images for teams that need images rooted in RHEL, UBI, Debian, or Ubuntu.

## How it works

The core technique is straightforward:

1. Spin up a privileged build container from the target base image (UBI9, Debian, etc.)
2. Initialize a clean package database in an isolated chroot directory
3. Install exactly the listed packages into the chroot — no weak dependencies, no docs
4. Create non-root users and groups directly inside the chroot
5. Optionally remove the package manager itself for true immutability
6. Copy the populated chroot into a `FROM scratch` container

The package manager runs on the build host and installs *into* a directory. It is never present in the final image — not as a layer that was removed, but because it was never copied in.

## Why not just use a multi-stage Dockerfile?

```dockerfile
FROM ubi9 AS builder
RUN dnf install -y coreutils glibc ca-certificates && dnf clean all

FROM scratch
COPY --from=builder / /    # ← dnf, rpm, and all their dependencies come with this
```

`COPY --from` at the root level copies the entire builder filesystem — including the package manager. You cannot atomically remove it and copy the result in a single layer without leaving artifacts. The chroot approach avoids this entirely: the package manager installs *into* a clean directory on the build host and never touches the final image's filesystem.

This is the same reason Chainguard built [`apko`](https://github.com/chainguard-dev/apko) rather than using Dockerfiles. Distill is the equivalent for RPM and APT-based enterprise distributions.

## Supported distributions

| Distribution | Package Manager | Example `base.image` |
|---|---|---|
| RHEL / UBI 9 | DNF | `registry.access.redhat.com/ubi9/ubi` |
| CentOS Stream 9 | DNF | `quay.io/centos/centos:stream9` |
| Rocky Linux 9 | DNF | `rockylinux:9` |
| AlmaLinux 9 | DNF | `almalinux:9` |
| Debian Bookworm | APT | `debian:bookworm-slim` |
| Ubuntu 24.04 | APT | `ubuntu:24.04` |

## Getting started

### Prerequisites

- [Dagger](https://docs.dagger.io/install) v0.13+
- A container runtime (Docker or Podman)

### Write a spec

```yaml
# image.yaml
name: my-app-runtime
description: Minimal RHEL9 runtime for my application

base:
  image: registry.access.redhat.com/ubi9/ubi
  releasever: "9"

packages:
  - coreutils
  - glibc
  - libstdc++
  - ca-certificates
  - tzdata

accounts:
  groups:
    - name: appuser
      gid: 10001
  users:
    - name: appuser
      uid: 10001
      gid: 10001

image:
  cmd: ["/bin/bash"]
  env:
    LANG: en_US.UTF-8

immutable: true
```

### Build

```bash
# Build and export to a local tar archive
dagger call build --spec=image.yaml export --path=./my-app-runtime.tar

# Load it into Docker
docker load < my-app-runtime.tar

# Or build and push directly
dagger call build --spec=image.yaml publish --address=myregistry.io/my-app-runtime:latest
```

### Scan for CVEs

```bash
dagger call scan --image=myregistry.io/my-app-runtime:latest
```

### Generate an SBOM

```bash
dagger call attest --image=myregistry.io/my-app-runtime:latest
```

## ImageSpec reference

```yaml
name: string                   # required — image name
description: string            # optional — human-readable description

base:
  image: string                # required — OCI image ref for the build host
  releasever: string           # required — distro version (e.g. "9", "bookworm")
  packageManager: dnf | apt   # optional — inferred from base.image if omitted

packages:                      # required — list of packages to install
  - string

runtime:                       # optional — upstream language runtime
  type: nodejs | temurin | python
  version: string
  sha256: string

accounts:                      # optional — users and groups to create
  groups:
    - name: string
      gid: int
  users:
    - name: string
      uid: int
      gid: int
      shell: string            # default: /sbin/nologin
      groups: [string]         # additional groups

image:                         # optional — OCI image config
  cmd: [string]
  workdir: string
  env:
    KEY: value

immutable: bool                # default: true — remove package manager after install
```

## Development

This project uses [devbox](https://www.jetify.com/devbox) to manage the development environment.

```bash
# Enter the dev environment (installs all tools on first run)
devbox shell

# Wire up the Dagger Go module and download SDK dependencies
dagger develop

# Add the yaml dependency
go get gopkg.in/yaml.v3

# Build the example RHEL9 runtime image
dagger call build --spec=examples/rhel9-runtime/image.yaml

# Run structure tests against the built image
devbox run test <image:tag> examples/rhel9-runtime/test.yaml
```

## Examples

See the [`examples/`](./examples/) directory for ready-to-use specs:

- [`examples/rhel9-runtime/`](./examples/rhel9-runtime/) — minimal RHEL9 base, target ≤30MB
- [`examples/debian-runtime/`](./examples/debian-runtime/) — minimal Debian Bookworm base

## Comparison

| | Google distroless | ubi9-micro | distill |
|---|---|---|---|
| Customizable packages | No | No | Yes |
| Declarative spec | No | No | Yes |
| Package manager removed | Yes | Yes | Yes |
| Audit trail (RPM/dpkg DB) | No | No | Yes |
| SBOM at build time | No | No | Yes |
| Multi-distro | No (Debian only) | No (RHEL only) | Yes |
| Self-hostable build | No | No | Yes |
