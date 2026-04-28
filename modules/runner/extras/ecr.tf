###########################
# ECR Repository
###########################

resource "random_id" "ephemeral_registry" {
  count = var.enable_ecr ? 1 : 0

  byte_length = 4
}

# ECR with prevent_destroy enabled (for production)
resource "aws_ecr_repository" "ephemeral_protected" {
  count = var.enable_ecr && var.prevent_destroy_optional_resources ? 1 : 0

  name                 = local.ecr_repository_name_generated
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
      Name = "${var.stack_name}-ephemeral-registry"
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

# ECR without prevent_destroy (for non-production/testing)
resource "aws_ecr_repository" "ephemeral_unprotected" {
  count = var.enable_ecr && !var.prevent_destroy_optional_resources ? 1 : 0

  name                 = local.ecr_repository_name_generated
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_delete_ecr

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
  ecr_repository_name = var.enable_ecr ? (
    var.prevent_destroy_optional_resources ? aws_ecr_repository.ephemeral_protected[0].name : aws_ecr_repository.ephemeral_unprotected[0].name
  ) : ""
  ecr_repository_arn = var.enable_ecr ? (
    var.prevent_destroy_optional_resources ? aws_ecr_repository.ephemeral_protected[0].arn : aws_ecr_repository.ephemeral_unprotected[0].arn
  ) : ""
  ecr_repository_url = var.enable_ecr ? (
    var.prevent_destroy_optional_resources ? aws_ecr_repository.ephemeral_protected[0].repository_url : aws_ecr_repository.ephemeral_unprotected[0].repository_url
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
