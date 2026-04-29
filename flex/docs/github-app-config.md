# GitHub App Configuration via Terraform

RunsOn requires a GitHub App to receive webhook events and manage runners. By default, RunsOn creates one for you during the web-based setup flow.

If you prefer to create and manage your own GitHub App — for tighter control over permissions, compliance requirements, or automated deployments — you can provide the app credentials directly as Terraform variables. This skips the interactive setup entirely.

## Creating a GitHub App Manually

RunsOn normally creates a private GitHub App for your organization during the web-based setup. If you prefer to create it manually, use the settings below.

### App Settings

| Setting | Value |
|---------|-------|
| App name | `RunsOn [<ORG>]` |
| Homepage URL | `https://runs-on.com` |
| Setup URL | `https://<YOUR_RUNSON_BASE_URL>/setup/success` |
| Public | `false` |

### Webhooks

| Setting | Value |
|---------|-------|
| Webhooks | Enabled |
| Webhook URL | `https://<YOUR_RUNSON_BASE_URL>/` |
| Webhook secret | Set a strong random secret |

### Repository Permissions

| Permission | Access |
|------------|--------|
| Actions | Read and write |
| Administration | Read and write |
| Deployments | Read-only |
| Metadata | Read-only |
| Single file | Read and write (path: `.github/runs-on.yml`) |

### Organization Permissions

| Permission | Access |
|------------|--------|
| Members | Read-only |

### Subscribe to Events

- `workflow_job`
- `workflow_run`
- `meta`

### Post-Creation Steps

1. Generate a private key from the app settings page
2. Note the App ID, Client ID, and Client Secret
3. Install the app on the repositories RunsOn should manage
4. If you use a shared `.github-private` repository for RunsOn configuration, install the app there too

## Terraform Configuration

Once your app is created, pass the credentials as Terraform variables:

```hcl
module "runs-on" {
  source  = "runs-on/runs-on/aws//flex"
  version = "v3.0.2"

  github_organization = "my-org"
  license_key         = "your-license-key"
  email               = "alerts@example.com"

  vpc_id            = "vpc-xxxxxxxx"
  public_subnet_ids = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  github_app_id             = 123456
  github_app_private_key    = file("path/to/private-key.pem")
  github_app_webhook_secret = "your-webhook-secret"
  github_app_client_id      = "Iv1.xxxxxxxxxxxx"
  github_app_client_secret  = "your-client-secret"
}
```

## Variables

| Variable | Description | Sensitive |
|----------|-------------|-----------|
| `github_app_id` | GitHub App ID (numeric) | No |
| `github_app_private_key` | Private key (PEM format) | Yes |
| `github_app_webhook_secret` | Webhook secret | Yes |
| `github_app_client_id` | OAuth Client ID | No |
| `github_app_client_secret` | OAuth Client secret | Yes |

All sensitive values are assembled into a JSON configuration and stored in AWS Secrets Manager. If `github_app_id` is provided along with the other variables, the web-based setup flow is skipped entirely.

## How It Works

The Terraform module assembles the credentials into a JSON payload and stores it as a Secrets Manager secret. When the worker service starts, RunsOn reads this secret and uses it to authenticate with the GitHub API via an [installation token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation). Installation tokens are short-lived (1 hour) and automatically refreshed.

## Webhook URL

Use the stable public RunsOn base URL that fronts your installation, such as the default API Gateway URL or your custom domain. Do not point GitHub directly at an internal service URL, because later changing the ingress layer would force a webhook URL update.

After the first deployment:

1. Get the stable public URL for your installation.
2. Update the GitHub App webhook URL to `https://<YOUR_RUNSON_BASE_URL>/github/webhooks`
3. Update the GitHub App setup URL to `https://<YOUR_RUNSON_BASE_URL>/setup/success`

Once GitHub points at this public URL, you can enable AWS WAF on the API Gateway stage later without changing the GitHub App webhook URL again.
