# Terraform Package Guide

This directory contains the Terraform/OpenTofu modules (`modules/flex`, `modules/fleet`, and their shared
submodules) mirrored to `runs-on/terraform-aws-runs-on`.

Make changes under `terraform/` in `runs-on/monorepo` and open pull requests
there. Do not edit or open implementation PRs in `runs-on/terraform-aws-runs-on`;
releases publish this directory to that public mirror.

## Rules

- Treat the monorepo root as the source of truth for CI, releases, and metadata. Do not reintroduce standalone tagging or GitHub release flows inside `terraform/`.
- Use the root monorepo `mise.toml` for Terraform and Terratest tools.
- Keep release-facing docs in sync:
  - `make sync-metadata` for versioned examples and release docs
  - `make docs` after changing `variables.tf`, `outputs.tf`, or module interfaces
- Keep flex `app_image` and `app_tag` defaults blank. Fleet intentionally defaults `app_tag` to `dev` (with a test `runtime_image`): the fleet worker publishes its own bundled agent binaries under `agents/<app_tag>` at startup, so control plane and runners stay self-consistent for any tag value. In both modules the public mirror receives the released defaults during mirror publication.

## Common Commands

- `make quick`
- `make docs`
- `make sync-metadata`
- `make test-plan`
- `make test-basic-ci-image`

## Important Files

- `README.md`: public docs with injected terraform-docs tables
- `modules/flex/variables.tf`, `modules/fleet/variables.tf`: product module inputs; public defaults are injected only in the mirrored export
- `modules/**/README.md`: generated module docs (`make docs`)
- `lambdas/`: canonical Lambda source files mirrored to the public Terraform repo
- `modules/flex/docs/`: narrative docs mirrored downstream
- `modules/flex/test/`: Terratest coverage for plan and AWS-backed scenarios
- `modules/flex/test/cmd/with-ci-image`: helper that builds a `runs-on-ci` image and injects `RUNS_ON_APP_IMAGE` / `RUNS_ON_APP_TAG`
