module "compute" {
  source = "../../.."

  region                  = "us-east-1"
  account_id              = "123456789012"
  stack_name              = "test-stack"
  cost_allocation_tag     = "runs-on-stack-name"
  log_retention_days      = 7
  permission_boundary_arn = ""
  runner_custom_policy_arns = [
    "arn:aws:iam::123456789012:policy/${terraform_data.runner_custom_policy_name.id}",
  ]
  enable_bedrock     = false
  app_tag            = "v0.0.0-test"
  bootstrap_tag      = "v0.0.0-test"
  ipv6_enabled       = false
  runner_max_runtime = 360
  tags = {
    Environment          = "test"
    "runs-on-stack-name" = "test-stack"
  }

  network = {
    vpc_id             = "vpc-12345678"
    private_mode       = "false"
    public_subnet_ids  = ["subnet-12345678"]
    private_subnet_ids = []
    security_group_ids = ["sg-12345678"]
  }

  extras = {
    cache = {
      bucket_id   = "test-stack-cache"
      bucket_arn  = "arn:aws:s3:::test-stack-cache"
      bucket_name = "test-stack-cache"
    }
    efs = {
      enabled           = false
      file_system_id    = ""
      file_system_arn   = ""
      file_system_dns   = ""
      security_group_id = ""
    }
    ecr = {
      enabled         = false
      repository_arn  = ""
      repository_name = ""
      repository_url  = ""
    }
    pull_through_cache = {
      enabled                = false
      registry_url           = ""
      docker_hub_transparent = false
      rules                  = {}
    }
  }
}

resource "terraform_data" "runner_custom_policy_name" {
  input = "RunsOnRunnerCustom"
}
