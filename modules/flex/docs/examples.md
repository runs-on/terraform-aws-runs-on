# Examples

## Basic

Minimal runnable deployment with a VPC, private subnets, an S3 gateway VPC endpoint, EFS, and ECR.

Create `variables.tf`:

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "stack_name" {
  description = "Name for the RunsOn stack"
  type        = string
  default     = "runs-on-v3"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.17.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.17.0.0/20", "10.17.16.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.17.128.0/20", "10.17.144.0/20"]
}

variable "github_organization" {
  description = "GitHub organization or username for RunsOn integration"
  type        = string
}

variable "license_key" {
  description = "RunsOn license key obtained from runs-on.com"
  type        = string
  sensitive   = true
}

variable "email" {
  description = "Email address for cost and alert reports"
  type        = string
}
```

Create `main.tf`:

```hcl
terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.stack_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = length(var.private_subnet_cidrs) > 0
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }
}

module "runs_on_flex" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  stack_name = var.stack_name

  github_organization = var.github_organization
  license_key         = var.license_key
  email               = var.email

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  private_mode        = "true"
  enable_efs          = true
  enable_ecr          = true
  enable_admin_routes = true
}

output "nat_ips" {
  description = "Public NAT Gateway IPs used by private runners"
  value       = module.vpc.nat_public_ips
}

output "getting_started" {
  description = "RunsOn post-apply setup instructions"
  value       = module.runs_on_flex.stack.getting_started
}
```

The S3 gateway endpoint is free and recommended for private subnet deployments. The NAT Gateway is still required because the Flex worker and runners need outbound internet access for GitHub and other public services.

## Private Networking

See [Private Networking](private-networking.md) for details on mode options.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id             = "vpc-xxxxxxxx"
  public_subnet_ids  = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]
  private_subnet_ids = ["subnet-priv1", "subnet-priv2", "subnet-priv3"]

  private_mode = "true"
}
```

## EFS Enabled

Enable shared persistent storage across all runners:

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_efs = true
}
```

## ECR Enabled

Enable image cache across workflow jobs, including Docker build cache:

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_ecr = true
}
```

## ECR Pull-Through Cache

Create, import, or look up ECR pull-through cache rules outside RunsOn, then pass the Terraform resource or data source object into the module. Pull-through cache rules are account/region-level ECR settings, so multiple RunsOn stacks in the same account and region can safely share the same rule reference.

Docker Hub can be transparent only when the referenced rule uses `ecr_repository_prefix = "ROOT"` and `upstream_registry_url = "registry-1.docker.io"`, and runners opt in with `extras=ecr-pull-through`. In that mode, portable image references such as `docker.io/library/node:22` are routed through ECR by Docker's native registry mirror support. Other providers should use explicit ECR cache references such as `<account>.dkr.ecr.<region>.amazonaws.com/ghcr/org/image:tag`.

Reference an existing rule:

```hcl
data "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = "ROOT"
}

module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  ecr_pull_through_cache_rules = {
    docker_hub = data.aws_ecr_pull_through_cache_rule.docker_hub
  }
}
```

Or create the regional rule outside RunsOn and pass the resource:

```hcl
variable "dockerhub_username" {
  type = string
}

variable "dockerhub_access_token" {
  type      = string
  sensitive = true
}

resource "aws_secretsmanager_secret" "dockerhub_pull_through" {
  name = "ecr-pullthroughcache/docker-hub"

  # Do not set kms_key_id. ECR requires the default aws/secretsmanager key.
}

resource "aws_secretsmanager_secret_version" "dockerhub_pull_through" {
  secret_id = aws_secretsmanager_secret.dockerhub_pull_through.id

  secret_string = jsonencode({
    username    = var.dockerhub_username
    accessToken = var.dockerhub_access_token
  })
}

resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = "ROOT"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = aws_secretsmanager_secret.dockerhub_pull_through.arn
}

module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  ecr_pull_through_cache_rules = {
    docker_hub = aws_ecr_pull_through_cache_rule.docker_hub
  }
}
```

Enable the runner-side ECR login and Docker Hub mirror per runner:

```yaml
runners:
  ci:
    image: ubuntu24-full-x64
    extras: ["ecr-pull-through"]
```

## WAF

See [WAF](waf.md) for managed webhook IP sync, user-managed ACL overrides, and GHES behavior.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_waf = true
  # public_ingress_web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/custom/abcd1234"
}
```

## GitHub App Configuration

See [GitHub App Config](github-app-config.md) for details.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  github_app_id             = 123456
  github_app_private_key    = file("path/to/private-key.pem")
  github_app_webhook_secret = "your-webhook-secret"
  github_app_client_id      = "Iv1.xxxxxxxxxxxx"
  github_app_client_secret  = "your-client-secret"
}
```

## Full Featured

All features enabled with VPC endpoints for improved security and reduced data transfer costs:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "runs-on-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
  public_subnets  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]

  enable_nat_gateway = true
  single_nat_gateway = true # 'false' for High Availability

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  create_security_group      = true
  security_group_name_prefix = "runs-on-vpc-endpoints-"
  security_group_description = "RunsOn VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    # S3 gateway endpoint is free and recommended
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }

    # Other interface endpoints below cost ~$7/mo/AZ each and are mostly useful for further isolation/compliance when using private networking.
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ec2 = {
      service             = "ec2"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    logs = {
      service             = "logs"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
  }
}

module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.1.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  private_mode     = "true"
  enable_efs       = true
  enable_ecr       = true
}
```
