variable "stack_name" {
  type        = string
  description = "Name/tag prefix for the syncer's own resources (role, function, log group, schedule)."
}

variable "name_suffix" {
  type        = string
  description = "Suffix appended to stack_name for this component's resource names."
  default     = "ami-sync"
}

variable "images" {
  type = list(object({
    name         = string
    architecture = optional(string, "x86_64")
  }))
  description = <<-EOT
    Images to sync. Each entry is a source AMI name glob plus architecture. The
    Lambda copies the most-recent matching source AMI and prunes older synced
    copies of the same name+architecture down to `retention`. Defaults to the
    current ubuntu24-full family (x64 + arm64). Names assume the default
    RUNS_ON_AMI_PREFIX (runs-on-v2.2); override this list if your stack overrides
    the prefix. See README for how the default evolves across releases.
  EOT
  default = [
    { name = "runs-on-v2.2-ubuntu24-full-x64-*", architecture = "x86_64" },
    { name = "runs-on-v2.2-ubuntu24-full-arm64-*", architecture = "arm64" },
  ]
}

variable "source_region" {
  type        = string
  description = "Region RunsOn publishes AMIs to; the copy source. The Lambda no-ops when this equals the deployment region."
  default     = "us-east-1"
}

variable "source_owner" {
  type        = string
  description = "AWS account that owns the public RunsOn AMIs."
  default     = "135269210855"
}

variable "schedule_expression" {
  type        = string
  description = "EventBridge Scheduler expression controlling how often the sync runs."
  default     = "cron(30 0 * * ? *)"
}

variable "kms_key_id" {
  type        = string
  description = <<-EOT
    How copied snapshots are encrypted at rest. Accepts:
    - "" (default): no explicit encryption. Copies inherit the region's behavior
      (unencrypted, or the account default if EBS encryption-by-default is on).
      Runner root volumes are still encrypted at launch via the product's
      block-device override, so this does not weaken runtime encryption.
    - "default": discover the region's EBS default key and encrypt with it. Works
      whether that default is the AWS-managed key or a customer-managed CMK; the
      module resolves it and grants the role the needed KMS permissions.
    - "aws/ebs" (or "alias/aws/ebs"): encrypt with the AWS-managed EBS key. Use
      this when an SCP requires encryption but it is not the region default.
    - An explicit key ARN (arn:aws:kms:...:key/<id>): encrypt with that key.

    Decrypt-at-launch needs no extra setup for the AWS-managed key or the account
    default CMK (the EC2/Spot/Fleet service-linked roles already have access); a
    different third-party CMK requires the usual key-policy/grant changes.
  EOT
  default     = ""
}

variable "retention" {
  type        = number
  description = "Number of newest synced copies to keep per image family; older copies are deregistered and their snapshots deleted."
  default     = 2
}

variable "enabled" {
  type        = bool
  description = "Whether to deploy the syncer. Deploying it is a conscious operator choice (one shared syncer per account+region)."
  default     = false
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to the module's own resources AND merged into the copied image/snapshot tags at create time (pass your stack's tags map to satisfy a tag-enforcing SCP)."
  default     = {}
}

variable "log_retention_in_days" {
  type        = number
  description = "CloudWatch Logs retention for the Lambda's log group."
  default     = 14
}
