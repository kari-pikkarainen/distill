# Examples

Each subdirectory contains an `image.yaml` spec and a `test.yaml`
[container-structure-test](https://github.com/GoogleContainerTools/container-structure-test)
configuration.

| Example | Distribution | Target size | Notes |
|---|---|---|---|
| [`rhel9-runtime/`](./rhel9-runtime/) | RHEL9 / UBI9 | ≤30MB | Base layer for all RHEL9-derived images |
| [`debian-runtime/`](./debian-runtime/) | Debian Bookworm | ≤20MB | APT backend validation |

## Building an example

```bash
# Build and load into Docker
dagger call build --spec=examples/rhel9-runtime/image.yaml export --path=./rhel9-runtime.tar
docker load < rhel9-runtime.tar

# Check the size
docker images | grep rhel9-runtime

# Run structure tests
devbox run test rhel9-runtime:latest examples/rhel9-runtime/test.yaml
```
