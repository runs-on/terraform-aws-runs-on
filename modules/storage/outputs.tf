# modules/storage/outputs.tf
# Output values from the storage module

output "config_bucket_id" {
  description = "ID of the S3 bucket for configuration storage"
  value       = aws_s3_bucket.config.id
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket for configuration storage"
  value       = aws_s3_bucket.config.arn
}

output "config_bucket_name" {
  description = "Name of the S3 bucket for configuration storage"
  value       = aws_s3_bucket.config.bucket
}

output "cache_bucket_id" {
  description = "ID of the S3 bucket for cache storage"
  value       = aws_s3_bucket.cache.id
}

output "cache_bucket_arn" {
  description = "ARN of the S3 bucket for cache storage"
  value       = aws_s3_bucket.cache.arn
}

output "cache_bucket_name" {
  description = "Name of the S3 bucket for cache storage"
  value       = aws_s3_bucket.cache.bucket
}

output "logging_bucket_id" {
  description = "ID of the S3 bucket for access logs"
  value       = aws_s3_bucket.logging.id
}

output "logging_bucket_arn" {
  description = "ARN of the S3 bucket for access logs"
  value       = aws_s3_bucket.logging.arn
}

output "logging_bucket_name" {
  description = "Name of the S3 bucket for access logs"
  value       = aws_s3_bucket.logging.bucket
}
