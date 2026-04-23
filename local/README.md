# local/ — Wave 0 Local MVP Stack

Everything needed to run the full distill commercial pipeline on a
developer laptop — no cloud services, no external dependencies beyond
Docker or Podman.

This exists because composition bugs in supply-chain toolchains (Cosign +
OCI referrers + SBOM attachment + provenance attestation) are easier to
debug on localhost than on a cloud deployment.

## Layout

```
local/
├── registry/          Local OCI registry + optional pull-through caches
│   └── docker-compose.yml
├── keys/              Local Cosign keypair for Wave 0 signing
│   ├── generate.sh        generate the keypair
│   ├── cosign.key         private (gitignored)
│   └── cosign.pub         public (gitignored — each dev generates their own)
└── README.md          this file

Dockerfile.devbench    (at repo root) — pinned build/scan/sign environment
```

## Two ways to run Wave 0

### Option 1 — Devbox on the host (fastest iteration)

Requires devbox installed (`curl -fsSL https://get.jetify.com/devbox | bash`).

```bash
devbox run mvp-local       # spins up, builds, signs, scans, benchmarks, serves
devbox run mvp-local-down  # tears down registry
```

### Option 2 — Containerized devbench (reproducibility, no host tool install)

Requires only Docker. Every tool version is baked into the image digest and
recorded in every artifact produced.

```bash
# Build the devbench image once
docker build -f Dockerfile.devbench -t distill-devbench:local .

# Run the Wave 0 pipeline inside it
docker run --rm -it \
  -v "$PWD":/workspace \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /workspace \
  --network host \
  distill-devbench:local \
  ./scripts/mvp-local.sh
```

The `--network host` is needed so the script can reach the local registry
on `localhost:5555` from inside the devbench container. On macOS, Docker
Desktop emulates `host` networking differently — use
`-p 5555:5000` on the registry container and `host.docker.internal:5000`
as the push target instead.

Security note: `-v /var/run/docker.sock:/var/run/docker.sock` gives the
devbench container effective root on the host Docker daemon. That is
acceptable for local dev. For CI (Wave 1), the socket boundary becomes
the GitHub Actions runner lifetime, which is inherently ephemeral.

## Optional pull-through cache

When you're iterating and pulling the same base images repeatedly — or
when you want to demo an air-gap-ish setup to a design partner — enable
the pull-through cache services:

```bash
cd local/registry

# For higher Docker Hub rate limits (optional):
export DOCKERHUB_USER=<your-hub-username>
export DOCKERHUB_TOKEN=<hub-token>

# Start main registry + Docker Hub proxy + Red Hat proxy
docker compose --profile cache up -d

# Configure Docker to use the caches. Add to ~/.docker/daemon.json:
# {
#   "registry-mirrors": [
#     "http://localhost:5556"
#   ],
#   "insecure-registries": [
#     "localhost:5555",
#     "localhost:5556",
#     "localhost:5557"
#   ]
# }
# Then restart Docker Desktop.
```

Once configured, `docker pull ubuntu:24.04` transparently goes through the
local cache. First pull hits Docker Hub (counted against your rate limit);
every subsequent pull is local and free.

This mirrors the architecture we'll deploy in Wave 1 as the real pipeline's
pull-through cache — the local version is the reference.

## Teardown

```bash
devbox run mvp-local-down      # removes main registry + its data volume
cd local/registry && docker compose --profile cache down -v  # also removes caches
```

## Troubleshooting

**"docker push" fails with "http: server gave HTTP response to HTTPS
client"** — your Docker daemon is refusing plain HTTP. Add `localhost:5555`
to `insecure-registries` in `~/.docker/daemon.json` (Docker Desktop →
Settings → Docker Engine), then restart Docker.

**Registry health check fails** — port 5000 may be in use. Check with
`lsof -iTCP:5555 -sTCP:LISTEN`. The conflicting process is often macOS
AirPlay Receiver (disable under System Settings → General → AirDrop &
Handoff).

**Cosign signing prompts for a password** — the generator script creates
the key with an empty password by default. If you set `COSIGN_PASSWORD`
during `generate.sh` you must provide the same value when signing.

## Relationship to cloud deployment

The Wave 0 stack is not disposable work. Its components become the
reference architecture for the Enterprise tier self-hosted pipeline
(strategy Phase 3). Changes made here should make sense for a customer
who runs the whole rebuild pipeline in their own VPC.
