# Examples

## Basic

Standard deployment with smart defaults:

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]
}
```

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
  version = "~> 5.0"

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
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

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
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

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
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

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
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_ecr = true
}
```

## WAF

See [WAF](waf.md) for setup order and important warnings.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_waf = true
  # waf_allowed_ipv4_cidrs = ["203.0.113.50/32"]
}
```

## GitHub App Configuration

See [GitHub App Config](github-app-config.md) for details.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

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
  version = "~> 5.0"

  name = "runs-on-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
  public_subnets  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]

  enable_nat_gateway = true
  single_nat_gateway = true # 'false' for High Availability

  enable_dns_hostnames = true
  enable_dns_support   = true

  # S3 gateway endpoint is free and recommended
  enable_s3_endpoint = true

  # Interface endpoints below cost ~$7/mo each.
  # Enable only if you're using private networking for full intra-VPC traffic.
  enable_ecr_api_endpoint     = false
  enable_ecr_dkr_endpoint     = false
  enable_ec2_endpoint         = false
  enable_logs_endpoint        = false
  enable_ssm_endpoint         = false
  enable_ssmmessages_endpoint = false
}

module "runs-on" {
  source  = "runs-on/runs-on/aws"
  version = "v2.12.7"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnets
  private_subnet_ids = module.vpc.private_subnets

  private_mode     = "true"
  enable_efs       = true
  enable_ecr       = true
  enable_dashboard = true
}
```
