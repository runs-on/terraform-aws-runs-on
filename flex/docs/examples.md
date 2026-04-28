# Examples

## Basic

Standard deployment with smart defaults:

```hcl
module "runs_on" {
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]
}

output "runs_on_ingress_url" {
  description = "RunsOn setup and webhook ingress URL"
  value       = module.runs_on.ingress.url
}

output "runs_on_getting_started" {
  description = "RunsOn post-apply setup instructions"
  value       = module.runs_on.stack.getting_started
}
```

Terraform only prints outputs declared by the root configuration being applied. If you do not add those output blocks, retrieve the same values from whatever root outputs you have exposed, or add them and run `terraform apply` again.

## With VPC Module

Using the popular `terraform-aws-modules/vpc` module:

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
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "runs-on-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
  public_subnets  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]

  # NAT Gateway for private subnets (required for private networking)
  # enable_nat_gateway = true
  # single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "runs-on" {
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets
}
```

## Private Networking

See [Private Networking](private-networking.md) for details on mode options.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

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
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

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
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_ecr = true
}
```

## WAF

See [WAF](waf.md) for managed webhook IP sync, user-managed ACL overrides, and GHES behavior.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

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
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

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
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.1"

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
