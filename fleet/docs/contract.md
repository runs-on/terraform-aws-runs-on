# Fleet Contract Notes

The `terraform/fleet` subtree is the separate RunsOn Fleet product surface. It does not provision the Flex webhook ingress, workflow-job queue, or workflow-job DynamoDB tables.

## Inputs

- `github_app_id`
- `github_app_private_key`
- `github_enterprise_pat`
- `github_base_url`
- `enterprise`
- `environment`
- `app_size`
- `runners`
- `images`
- `pools`

## Boundary shape

The module supports one active boundary per runtime instance:

- GitHub App organization mode: `github_app_id` + `github_app_private_key`
- enterprise PAT mode: `github_enterprise_pat` + `enterprise`

`github_base_url` is optional and defaults to `https://github.com`. For GHES, set a host-root URL such as `https://ghe.example.com`.

The runtime discovers GitHub App installations directly from GitHub in organization mode. It does not require a separate Terraform `github_installations` input. The rendered runtime secret still uses the internal `github_private_key` field name because that schema is owned by the Fleet runtime.

`app_size` uses the same `small`/`medium`/`high`/`xhigh` contract as Flex. It drives the Fleet ECS task sizing, launch-related EC2 rate-limit assumptions, and the bounded post-fleet registration/finalization concurrency inside the worker. `RUNS_ON_APP_PROVISIONING_CONCURRENCY` and `RUNS_ON_APP_REGISTRATION_CONCURRENCY` can override the app-size-derived worker counts when set through `extra_env_vars`.

## Workflow contract

The intended workflow label contract is:

`runs-on: runs-on/pool=<pool-name>/env=<environment>`

`runner_group` remains optional per `pools.<pool-name>`. The runtime owns the actual runner group and scale set lifecycle; Terraform only persists the desired pool catalog and secret material needed to bootstrap it.
