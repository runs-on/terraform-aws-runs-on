# modules/optional/ecr.tf
# ECR repository for ephemeral Docker image storage

###########################
# ECR Repository
###########################

# ECR with prevent_destroy enabled (for production)
resource "aws_ecr_repository" "ephemeral_protected" {
  count = var.enable_ecr && var.prevent_destroy ? 1 : 0

  name                 = "${var.stack_name}-ephemeral-registry"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-ephemeral-registry"
      Environment = var.environment
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

# ECR without prevent_destroy (for non-production/testing)
resource "aws_ecr_repository" "ephemeral_unprotected" {
  count = var.enable_ecr && !var.prevent_destroy ? 1 : 0

  name                 = "${var.stack_name}-ephemeral-registry"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.stack_name}-ephemeral-registry"
      Environment = var.environment
    }
  )
}

locals {
  ecr_repository_name = var.enable_ecr ? (
    var.prevent_destroy ? aws_ecr_repository.ephemeral_protected[0].name : aws_ecr_repository.ephemeral_unprotected[0].name
  ) : ""
  ecr_repository_arn = var.enable_ecr ? (
    var.prevent_destroy ? aws_ecr_repository.ephemeral_protected[0].arn : aws_ecr_repository.ephemeral_unprotected[0].arn
  ) : ""
  ecr_repository_url = var.enable_ecr ? (
    var.prevent_destroy ? aws_ecr_repository.ephemeral_protected[0].repository_url : aws_ecr_repository.ephemeral_unprotected[0].repository_url
  ) : ""
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
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
