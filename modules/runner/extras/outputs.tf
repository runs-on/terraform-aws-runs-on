output "extras" {
  description = "Shared runner extras including cache, EFS, and ECR resources"
  value = {
    cache = {
      bucket_id   = aws_s3_bucket.cache.id
      bucket_arn  = aws_s3_bucket.cache.arn
      bucket_name = aws_s3_bucket.cache.bucket
    }
    efs = {
      enabled           = var.enable_efs
      file_system_id    = var.enable_efs ? local.efs_file_system_id : null
      file_system_arn   = var.enable_efs ? (var.prevent_destroy_optional_resources ? aws_efs_file_system.this_protected[0].arn : aws_efs_file_system.this_unprotected[0].arn) : null
      file_system_dns   = var.enable_efs ? (var.prevent_destroy_optional_resources ? aws_efs_file_system.this_protected[0].dns_name : aws_efs_file_system.this_unprotected[0].dns_name) : null
      security_group_id = var.enable_efs ? aws_security_group.efs[0].id : null
    }
    ecr = {
      enabled         = var.enable_ecr
      repository_arn  = var.enable_ecr ? local.ecr_repository_arn : null
      repository_name = var.enable_ecr ? local.ecr_repository_name : null
      repository_url  = var.enable_ecr ? local.ecr_repository_url : null
    }
    pull_through_cache = {
      enabled           = length(local.ecr_pull_through_cache_rules) > 0
      registry_url      = local.ecr_pull_through_cache_registry_url
      docker_hub_prefix = local.ecr_pull_through_cache_docker_hub_prefix
      rules = {
        for key, rule in local.ecr_pull_through_cache_rules : key => {
          ecr_repository_prefix      = rule.ecr_repository_prefix
          upstream_registry_url      = rule.upstream_registry_url
          upstream_repository_prefix = rule.upstream_repository_prefix
        }
      }
    }
  }
}
