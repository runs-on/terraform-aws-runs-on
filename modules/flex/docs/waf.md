# WAF (Web Application Firewall)

Enable AWS WAF to protect only the webhook ingestion endpoint at `/github/webhooks`.

For `github.com`, RunsOn can manage the default Web ACL for you and refresh GitHub webhook IP ranges every hour. If you provide `public_ingress_web_acl_arn`, RunsOn will associate that ACL instead of creating a managed one.

For GHE.com data residency and GitHub Enterprise Server, automatic GitHub IP synchronization is not supported. If `enable_waf = true`, you must also set `public_ingress_web_acl_arn`.

## Behavior

When RunsOn manages the ACL:

1. Requests whose path does not end with `/github/webhooks` are allowed. If you set `admin_routes_allowed_cidrs`, they are allowed only from those CIDR blocks.
2. Requests to `/github/webhooks` are allowed only from GitHub webhook IP ranges.
3. The GitHub IP sync Lambda seeds the IP sets on first deploy and refreshes them every hour after that.

If `enable_admin_routes = false`, the admin Lambda exposure is removed entirely, including `/`, `/setup`, `/setup/{proxy+}`, and `/readyz`.

## Example

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.6.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_waf = true
}
```

## Restrict The Admin Routes

The admin routes (`/`, `/setup`, `/setup/{proxy+}`, `/readyz`) have no sign-in. To keep them while you limit who can reach them, list your egress CIDR blocks in `admin_routes_allowed_cidrs`. The managed Web ACL then allows those paths only from the listed IPv4 and IPv6 blocks and blocks them from every other source. The webhook rules and the hourly GitHub IP sync do not change.

`admin_routes_allowed_cidrs` needs the RunsOn-managed Web ACL: `enable_waf = true`, an empty `public_ingress_web_acl_arn`, and github.com. The plan fails for any other combination. With a user-managed Web ACL, restrict the admin routes in that ACL.

The public ingress API accepts IPv4 only, so IPv6 entries take effect only if the API also accepts IPv6.

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.6.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_waf                 = true
  admin_routes_allowed_cidrs = ["203.0.113.10/32", "2001:db8:1::/64"]
}
```

## User-Managed ACL Override

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.6.0"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_waf                 = true
  public_ingress_web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/custom/abcd1234"
}
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_waf` | Enable AWS WAF for the public ingress | `false` |
| `public_ingress_web_acl_arn` | Optional user-managed AWS WAFv2 Web ACL ARN to associate with the public ingress | `""` |
| `enable_admin_routes` | Enable the admin Lambda routes (`/`, `/setup`, `/setup/{proxy+}`, `/readyz`) on the public ingress | `true` |
| `admin_routes_allowed_cidrs` | IPv4 and IPv6 CIDR blocks allowed to reach the admin routes through the managed Web ACL. Empty allows every source | `[]` |
