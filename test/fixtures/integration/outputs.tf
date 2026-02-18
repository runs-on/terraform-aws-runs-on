output "apprunner_service_url" {
  value = module.runs_on.apprunner_service_url
}

output "stack_name" {
  value = module.runs_on.stack_name
}

output "config_bucket_name" {
  value = module.runs_on.config_bucket_name
}

output "cache_bucket_name" {
  value = module.runs_on.cache_bucket_name
}
