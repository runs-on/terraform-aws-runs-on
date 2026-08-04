###########################
# ECR Repository
###########################

resource "random_id" "ephemeral_registry" {
  count = var.enable_ecr ? 1 : 0

  byte_length = 4
}

resource "aws_ecr_repository" "ephemeral" {
  count = var.enable_ecr ? 1 : 0

  name                 = local.ecr_repository_name_generated
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ephemeral-registry"
    }
  )
}

locals {
  ecr_repository_name_generated = var.enable_ecr ? "runs-on-${random_id.ephemeral_registry[0].hex}-ephemeral-registry" : ""
  ecr_repository_name           = var.enable_ecr ? aws_ecr_repository.ephemeral[0].name : ""
  ecr_repository_arn            = var.enable_ecr ? aws_ecr_repository.ephemeral[0].arn : ""
  ecr_repository_url            = var.enable_ecr ? aws_ecr_repository.ephemeral[0].repository_url : ""
}

###########################
# ECR Lifecycle Policy
###########################

resource "aws_ecr_lifecycle_policy" "ephemeral" {
  count = var.enable_ecr ? 1 : 0

  repository = local.ecr_repository_name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire images older than 10 days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
