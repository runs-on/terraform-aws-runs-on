# WAF (Web Application Firewall)

Enable AWS WAF to protect only the webhook ingestion endpoint at `/github/webhooks`.

For `github.com`, RunsOn can manage the default Web ACL for you and refresh GitHub webhook IP ranges every hour. If you provide `public_ingress_web_acl_arn`, RunsOn will associate that ACL instead of creating a managed one.

For GitHub Enterprise Server, automatic GitHub IP synchronization is not supported. If `enable_waf = true`, you must also set `public_ingress_web_acl_arn`.

## Behavior

When RunsOn manages the ACL:

1. Requests whose path does not end with `/github/webhooks` are allowed.
2. Requests to `/github/webhooks` are allowed only from GitHub webhook IP ranges.
3. The GitHub IP sync Lambda seeds the IP sets on first deploy and refreshes them every hour after that.

If `enable_admin_routes = false`, the admin Lambda exposure is removed entirely, including `/`, `/setup`, `/setup/{proxy+}`, and `/readyz`.

## Example

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.0.6"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  enable_waf = true
}
```

## User-Managed ACL Override

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//modules/flex"
  version = "v3.0.6"

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
