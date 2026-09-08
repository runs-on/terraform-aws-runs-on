terraform {
  required_version = ">= 1.5.7"
}

# Single source of truth for GitHub platform classification in Terraform.
# Keep this aligned with the Go resolver in pkg/githubplatform/platform.go:
# both accept web host roots, the public/GHE.com API hosts, and a terminal
# GHES /api/v3 path, and both derive the same Actions OIDC token issuer.
locals {
  raw = trimsuffix(trimspace(var.base_url), "/")
  # Tolerate a terminal /api/v3 path before host classification so an
  # api.SUBDOMAIN.ghe.com URL with an /api/v3 path still classifies as GHE.com,
  # mirroring the Go resolver's hostname-first check.
  raw_without_api_path = trimsuffix(local.raw, "/api/v3")
  # Match GHE.com hosts on the parsed-hostname shape the Go resolver uses:
  # web or api. host with an optional explicit port. GitHub's cloud hosts only
  # serve HTTPS on 443, so the port is dropped from the derived endpoints.
  ghe_com_matches   = regexall("^https://(?:api\\.)?([^./:]+)\\.ghe\\.com(?::\\d+)?$", lower(local.raw_without_api_path))
  ghe_com_subdomain = length(local.ghe_com_matches) > 0 ? local.ghe_com_matches[0][0] : ""
  host_root_url     = local.ghe_com_subdomain != "" ? "https://${local.ghe_com_subdomain}.ghe.com" : local.raw_without_api_path
  # Compare the public GitHub hosts without an explicit port, mirroring the Go
  # resolver's hostname switch; GHES host roots keep any custom port.
  host_root_without_port = replace(lower(local.host_root_url), "/:[0-9]+$/", "")
  normalized_base_url    = local.host_root_without_port == "" || contains(["https://github.com", "https://api.github.com", "https://www.github.com"], local.host_root_without_port) ? "https://github.com" : local.host_root_url
  enterprise_url         = local.normalized_base_url == "https://github.com" ? "" : local.normalized_base_url
  platform = local.enterprise_url == "" ? "github.com" : (
    local.ghe_com_subdomain != "" ? "ghe.com" : "ghes"
  )
  token_issuer = local.platform == "github.com" ? "https://token.actions.githubusercontent.com" : (
    local.platform == "ghe.com" ? "https://token.actions.${local.ghe_com_subdomain}.ghe.com" : "${local.enterprise_url}/_services/token"
  )
}
