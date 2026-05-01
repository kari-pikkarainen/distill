# Examples

Each subdirectory contains a `.distill.yaml` spec and a `test.yaml`
[container-structure-test](https://github.com/GoogleContainerTools/container-structure-test)
configuration. These are reference specs — useful for learning the schema
and exercising every supported distribution.

> Looking for the canonical product specs (used by the local end-to-end
> pipeline and intended to evolve into the published image catalog)? See
> [`../specs/`](../specs/). The two directories serve different intents:
> `examples/` covers every supported distro for testing; `specs/` is the
> commercial-product image set with sidecar quality budgets and CVE
> exception records.

| Example | Distribution | Target size | Notes |
|---|---|---|---|
| [`rhel9-runtime/`](./rhel9-runtime/) | RHEL9 / UBI9 | ≤30MB | Base layer for all RHEL9-derived images |
| [`centos-stream9-runtime/`](./centos-stream9-runtime/) | CentOS Stream 9 | ≤30MB | Upstream RHEL contributor distribution |
| [`rocky9-runtime/`](./rocky9-runtime/) | Rocky Linux 9 | ≤30MB | RHEL-compatible community rebuild |
| [`alma9-runtime/`](./alma9-runtime/) | AlmaLinux 9 | ≤30MB | RHEL-compatible community rebuild |
| [`debian-runtime/`](./debian-runtime/) | Debian Bookworm | ≤20MB | APT backend validation |
| [`ubuntu-runtime/`](./ubuntu-runtime/) | Ubuntu 24.04 | ≤20MB | Ubuntu LTS on the APT backend |

## Building an example

```bash
# Build all platforms declared in the spec
distill build --spec examples/rhel9-runtime/image.distill.yaml

# Build a single platform
distill build --spec examples/rhel9-runtime/image.distill.yaml --platform linux/amd64

# Run structure tests
container-structure-test test \
  --image distill-example-rhel9-runtime:latest \
  --config examples/rhel9-runtime/test.yaml
```
