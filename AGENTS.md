# Terraform Package Guide

This directory contains the Terraform/OpenTofu module mirrored to `runs-on/terraform-aws-runs-on`.

## Rules

- Treat the monorepo root as the source of truth for CI, releases, and metadata. Do not reintroduce standalone tagging or GitHub release flows inside `terraform/`.
- Use the root monorepo `mise.toml` for Terraform and Terratest tools.
- Keep release-facing docs in sync:
  - `make sync-metadata` for versioned examples and release docs
  - `make docs` after changing `variables.tf`, `outputs.tf`, or module interfaces
- Keep monorepo `app_image` and `app_tag` defaults blank. The public mirror receives the released defaults during mirror publication.

## Common Commands

- `make quick`
- `make docs`
- `make sync-metadata`
- `make test-plan`
- `make test-basic-ci-image`

## Important Files

- `README.md`: public module docs with injected terraform-docs tables
- `variables.tf`: root module inputs; public defaults are injected only in the mirrored export
- `modules/*/README.md`: generated submodule docs
- `docs/`: narrative docs mirrored downstream
- `test/`: Terratest coverage for plan and AWS-backed scenarios
- `test/cmd/with-ci-image`: helper that builds a `runs-on-ci` image and injects `RUNS_ON_APP_IMAGE` / `RUNS_ON_APP_TAG`
