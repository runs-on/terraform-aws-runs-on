# Fleet Control Plane Module

Provisions the RunsOn Fleet runtime-specific resources on top of the shared runner platform.

## Runtime Shape

The Fleet control plane module deploys:

- the Fleet config secret
- the Fleet ECS/Fargate runtime service and log group
- the shared EC2-runner control-plane task role

## Important Outputs

- `config`
- `runtime`
- `workflow_contract`

## Notes

The public Terraform input is `github_app_private_key`, but the rendered runtime secret still persists the internal `github_private_key` field because that secret schema is owned by `pkg/fleet`.

## Module Documentation

<!-- BEGIN_TF_DOCS -->


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_runtime"></a> [runtime](#module\_runtime) | ../runtime | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_dynamodb_table.claims](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_secretsmanager_secret.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID | `string` | n/a | yes |
| <a name="input_catalog"></a> [catalog](#input\_catalog) | Runner image, runner, and pool catalogs | <pre>object({<br/>    images  = map(any)<br/>    runners = map(any)<br/>    pools   = map(any)<br/>  })</pre> | n/a | yes |
| <a name="input_compute"></a> [compute](#input\_compute) | Shared runner compute resources | <pre>object({<br/>    runner_iam = object({<br/>      role_arn     = string<br/>      role_name    = string<br/>      role_id      = string<br/>      profile_arn  = string<br/>      profile_name = string<br/>    })<br/>    runner_logs = object({<br/>      group_name          = string<br/>      group_arn           = string<br/>      resource_group_name = string<br/>      resource_group_arn  = string<br/>    })<br/>    launch_templates = object({<br/>      linux_default = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      linux_default_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_default = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_default_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      linux_private = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      linux_private_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_private = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>      windows_private_nested = object({<br/>        id             = string<br/>        latest_version = number<br/>      })<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_control_plane"></a> [control\_plane](#input\_control\_plane) | Fleet control plane settings published into the runtime secret | <pre>object({<br/>    environment         = string<br/>    private_mode        = string<br/>    cost_allocation_tag = string<br/>    app_tag             = string<br/>    runner_custom_tags  = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_extras"></a> [extras](#input\_extras) | Shared runner extras resources | <pre>object({<br/>    cache = object({<br/>      bucket_id   = string<br/>      bucket_name = string<br/>      bucket_arn  = string<br/>    })<br/>    efs = object({<br/>      enabled           = bool<br/>      file_system_id    = string<br/>      file_system_arn   = string<br/>      file_system_dns   = string<br/>      security_group_id = string<br/>    })<br/>    ecr = object({<br/>      enabled         = bool<br/>      repository_arn  = string<br/>      repository_name = string<br/>      repository_url  = string<br/>    })<br/>  })</pre> | n/a | yes |
| <a name="input_github"></a> [github](#input\_github) | GitHub authentication and host settings for the Fleet runtime | <pre>object({<br/>    app_id          = any<br/>    app_private_key = any<br/>    enterprise_pat  = any<br/>    base_url        = string<br/>    enterprise      = any<br/>  })</pre> | n/a | yes |
| <a name="input_network"></a> [network](#input\_network) | Shared runner networking resources | <pre>object({<br/>    vpc_id             = string<br/>    private_mode       = string<br/>    public_subnet_ids  = list(string)<br/>    private_subnet_ids = list(string)<br/>    security_group_ids = list(string)<br/>  })</pre> | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | n/a | yes |
| <a name="input_runtime"></a> [runtime](#input\_runtime) | Fleet ECS runtime settings | <pre>object({<br/>    image              = string<br/>    size               = string<br/>    log_retention_days = number<br/>    extra_env_vars     = map(string)<br/>  })</pre> | n/a | yes |
| <a name="input_stack_name"></a> [stack\_name](#input\_stack\_name) | Fleet stack name | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to Fleet resources | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_claims"></a> [claims](#output\_claims) | Fleet claim ledger table |
| <a name="output_config"></a> [config](#output\_config) | Fleet runtime configuration secret |
| <a name="output_runtime"></a> [runtime](#output\_runtime) | Fleet runtime ECS resources |
| <a name="output_workflow_contract"></a> [workflow\_contract](#output\_workflow\_contract) | Fleet workflow targeting contract |
<!-- END_TF_DOCS -->
