output "base_url" {
  description = "Normalized GitHub web host root URL (https://github.com for the cloud default)."
  value       = local.normalized_base_url
}

output "enterprise_url" {
  description = "Normalized enterprise web host root URL, empty for github.com."
  value       = local.enterprise_url
}

output "platform" {
  description = "GitHub platform classification: github.com, ghe.com, or ghes."
  value       = local.platform
}

output "token_issuer" {
  description = "Actions OIDC token issuer for the classified platform."
  value       = local.token_issuer
}
