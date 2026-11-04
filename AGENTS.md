# Terraform guide

Modules and Lambdas mirrored to `runs-on/terraform-aws-runs-on`. Edit them and
open pull requests in `runs-on/monorepo`, never in the mirror. Paths under `..`
and `testdata/`, and the root Go tests, exist only in the monorepo.

## Read when relevant

- IAM policy changes or live Terratest scenarios: `DEVELOPMENT.md`.
- Adding or running plan tests (monorepo only): `../DEVELOPMENT.md` (Terraform
  Tests).

## Rules

- Stay valid on each module's `required_version` floor, not only on the
  mise-pinned OpenTofu 1.9 that CI runs. Both evaluate every operand of
  `&&`/`||`: guard with `try()`.
- Add `moved` blocks for each rename, module move, or new `count`, from every
  address since v3.0.0. Implied `x` -> `x[0]` moves stop once `x` leaves its
  module: chain `x` -> `x[0]` -> new address. Seed those old states in
  `modules/flex/test/plan_upgrade_test.go`; it plans only the Flex root.
- Delete resources by deleting their blocks; never add `removed` blocks. Without
  `lifecycle`, Terraform destroys and OpenTofu 1.7-1.9 forgets; OpenTofu before
  1.10 rejects `lifecycle` there.
- To use a newer AWS provider, raise the floor in that module, `modules/flex`,
  and `modules/fleet`, and replace the minimum-provider lock in
  `testdata/provider-locks/` and its `Makefile` path.
- `tofu test` asserts reach only the module's own resources and child-module
  outputs: test a child module's resources in its own `tests/` or in the Flex Go
  plan harness in `modules/flex/test`.
- In the monorepo, keep release-injected defaults literal: blank
  `app_image`/`app_tag` in `modules/flex/variables.tf` and test
  `runtime_image`/`app_tag` in `modules/fleet/variables.tf`; releases rewrite
  them by regex.
- After editing `lambdas/` or runner user-data, run
  `make -C .. cloudformation-sync`, then
  `python3 ../scripts/package-terraform-lambdas.py`.
- Never hand-edit the dashboard queries in
  `modules/control_plane/control_plane_{flex,fleet}/cloudwatch.tf` or the
  `AUTO-GENERATED` CSS blocks in `lambdas/github_apps_setup.js`: edit
  `../scripts/cloudwatch-queries.toml` or `../design/*.css`, then sync.
- `modules/runner/compute/user-data/` templates are also CloudFormation `!Sub`
  text: use `$VAR` for shell variables, and give each `${Name}` a value in
  CloudFormation and in `*_user_data_vars`.
- Root Go tests parse these files: Flex DynamoDB tables in
  `modules/control_plane/` must match CloudFormation's, and
  `fleet-catalog-contract` lists must match `../config/schema/runs_on.cue`.

## Commands

- `mise exec -- make init quick test-plan docs`, plus `make sync-metadata` after
  a version bump. The plan tests run tofu from temp dirs, where mise shims fall
  back to whatever tofu is on `PATH`.
