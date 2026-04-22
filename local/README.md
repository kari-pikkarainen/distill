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
├── registry/          Local OCI registry (docker-compose)
│   └── docker-compose.yml
├── keys/              Local Cosign keypair for Wave 0 signing
│   ├── generate.sh        generate the keypair
│   ├── cosign.key         private (gitignored)
│   └── cosign.pub         public (gitignored — each dev generates their own)
└── README.md          this file
```

## Bootstrap

```bash
# One-shot: spin up everything and run the full Wave 0 pipeline.
devbox run mvp-local

# Or the equivalent pieces by hand:
cd local/registry && docker compose up -d    # start registry
cd ../keys && ./generate.sh                   # generate signing keypair
cd ../..
devbox run build-cli                          # build distill
distill build --spec specs/base-ubi9.distill.yaml --platform linux/amd64
docker push localhost:5000/base-ubi9:latest
cosign sign --key local/keys/cosign.key \
  --allow-insecure-registry --allow-http-registry \
  localhost:5000/base-ubi9:latest
```

## Teardown

```bash
devbox run mvp-local-down      # removes container + volume
```

## Troubleshooting

**"docker push" fails with "http: server gave HTTP response to HTTPS
client"** — your Docker daemon is refusing plain HTTP. Add `localhost:5000`
to `insecure-registries` in `~/.docker/daemon.json` (Docker Desktop →
Settings → Docker Engine), then restart Docker.

**Registry health check fails** — port 5000 may be in use. Check with
`lsof -iTCP:5000 -sTCP:LISTEN`. The conflicting process is often macOS
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
