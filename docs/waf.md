# WAF (Web Application Firewall)

Enable AWS WAF to restrict App Runner access to GitHub webhook IPs, blocking all other internet traffic.

> **WARNING: Enable WAF only AFTER completing initial GitHub App setup.**
>
> WAF blocks all traffic except GitHub webhook IPs. The setup UI at your App Runner URL
> requires browser access, which WAF will block.

## Deployment Order

1. Deploy with `enable_waf = false` (default)
2. Access App Runner URL to configure GitHub App
3. Set `enable_waf = true` and re-apply

If you need ongoing browser access (e.g., for the metrics dashboard), add your IP to `waf_allowed_ipv4_cidrs`.

## Example

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws"
  version = "v2.12.4"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_waf = true

  # Allow your own IPs for admin access
  waf_allowed_ipv4_cidrs = ["203.0.113.50/32"]
}
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_waf` | Enable AWS WAF for App Runner | `false` |
| `waf_allowed_ipv4_cidrs` | IPv4 CIDRs to allow (in addition to GitHub IPs) | `[]` |
| `waf_allowed_ipv6_cidrs` | IPv6 CIDRs to allow (in addition to GitHub IPs) | `[]` |
