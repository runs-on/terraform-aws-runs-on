variable "stack_name" {
  type    = string
  default = "runs-on-int-test"
}

variable "github_organization" {
  type = string
}

variable "license_key" {
  type      = string
  sensitive = true
}

variable "email" {
  type    = string
  default = "test@example.com"
}

variable "environment" {
  type    = string
  default = "test"
}

variable "force_destroy_buckets" {
  type    = bool
  default = false
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
