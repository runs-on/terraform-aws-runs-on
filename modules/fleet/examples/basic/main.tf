terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "runs_on_fleet" {
  source = "../.."

  stack_name                        = var.stack_name
  github_app_id                     = var.github_app_id
  github_app_private_key            = var.github_app_private_key
  github_enterprise_pat             = var.github_enterprise_pat
  github_base_url                   = var.github_base_url
  github_enterprise_name            = var.github_enterprise_name
  license_key                       = var.license_key
  email                             = var.email
  alert_slack_webhook_url           = var.alert_slack_webhook_url
  integration_step_security_api_key = var.integration_step_security_api_key
  environment                       = var.environment
  app_size                          = var.app_size
  app_capacity_provider             = var.app_capacity_provider
  vpc_id                            = var.vpc_id
  public_subnet_ids                 = var.public_subnet_ids
  private_subnet_ids                = var.private_subnet_ids

  images             = var.images
  runners            = var.runners
  fleets             = var.fleets
  runtime_image      = var.runtime_image
  bootstrap_tag      = var.bootstrap_tag
  app_tag            = var.app_tag
  runner_max_runtime = var.runner_max_runtime
}
