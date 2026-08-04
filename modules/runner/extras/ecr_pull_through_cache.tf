locals {
  ecr_pull_through_cache_rules = {
    for key, rule in var.ecr_pull_through_cache_rules : key => {
      ecr_repository_prefix      = trimspace(rule.ecr_repository_prefix)
      upstream_registry_url      = trimspace(rule.upstream_registry_url)
      upstream_repository_prefix = try(trimspace(rule.upstream_repository_prefix), "")
    }
  }

  ecr_pull_through_cache_registry_url = length(local.ecr_pull_through_cache_rules) > 0 ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}" : ""

  # Only an unprefixed Docker Hub rule preserves the one-to-one repository
  # mapping required by the transparent runner-local mirror. Rules with an
  # upstream prefix remain available through explicit ECR image paths.
  ecr_pull_through_cache_docker_hub_prefixes = [
    for rule in local.ecr_pull_through_cache_rules :
    rule.ecr_repository_prefix
    if lower(rule.upstream_registry_url) == "registry-1.docker.io" && rule.upstream_repository_prefix == ""
  ]
  ecr_pull_through_cache_docker_hub_prefix = length(local.ecr_pull_through_cache_docker_hub_prefixes) > 0 ? local.ecr_pull_through_cache_docker_hub_prefixes[0] : ""
}
