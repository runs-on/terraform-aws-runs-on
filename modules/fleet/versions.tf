terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}
