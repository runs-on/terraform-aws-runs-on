# Development Guide

This Terraform module lives inside the RunsOn monorepo. The downstream repository `runs-on/terraform-aws-runs-on` is a passive mirror published from here.

## Prerequisites

Install the monorepo toolchain from the repository root:

```bash
cd .. && mise install
```

That root toolchain covers both Terraform and Terratest commands in this subtree.

## Common Commands

```bash
make fmt          # Format all .tf files
make validate     # Validate OpenTofu syntax
make lint         # Run TFLint
make docs         # Regenerate README tables with terraform-docs
make quick        # fmt-check + validate + lint
make test-plan    # Free Terratest plan checks
```

## Versioning And Release

- The canonical release version comes from the repository root [`../VERSION`](../VERSION).
- Use `make sync-metadata` or root `make sync-metadata` to refresh Terraform release-facing docs after a version bump.
- The monorepo copy intentionally leaves `app_image` and `app_tag` blank by default.
- The mirrored public repo gets the released `app_image` and `app_tag` injected during mirror publication after the release image is built.
- Do not create tags or GitHub releases from `terraform/`; use root `releasectl release final`.

## Testing

Tests in [`test/`](./test) use Terratest and deploy real AWS infrastructure. See [`test/README.md`](./test/README.md) for required environment variables, scenario costs, and cleanup expectations.

Useful targets:

```bash
make test-basic-ci-image
make test-basic
make test-private-ci-image
make test-private
make test-full-ci-image
make test-full
make test-integration-ci-image
make test-integration
make test-short
make test-all
```

- `make test-*-ci-image` builds and pushes a fresh `runs-on-ci` image, exports `RUNS_ON_APP_IMAGE` and `RUNS_ON_APP_TAG`, then runs the underlying Terratest target.
- `make test-basic`, `make test-private`, `make test-full`, and `make test-integration` are raw Terratest entrypoints. They expect the required environment variables to already be set and fail fast if they are missing.

## Cleanup

```bash
make clean
```
