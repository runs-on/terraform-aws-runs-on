# QuickStart Guide

## Setup

```bash
# Install OpenTofu and tools (macOS)
brew install opentofu tflint terraform-docs pre-commit

# Or use make command
make install-tools

# Install pre-commit hooks
pre-commit install
```

## Development Workflow

### 1. Fast Validation (< 20 seconds)

```bash
# Run all fast checks
make quick

# Or individually:
make fmt         # Format code
make validate    # Syntax check
make lint        # TFLint
```

### 2. See What Would Be Created

```bash
# Initialize
tofu init

# Plan (no resources created)
tofu plan \
  -var="github_organization=my-org" \
  -var="license_key=dummy-key" \
  -var="vpc_id=vpc-123" \
  -var="public_subnet_ids=[\"subnet-1\",\"subnet-2\"]" \
  -var="security_group_ids=[\"sg-123\"]"
```

### 3. Deploy Real Resources

```bash
# Create terraform.tfvars with real values
cat > terraform.tfvars <<EOF
github_organization = "my-org"
license_key        = "real-key"
vpc_id             = "vpc-123"
public_subnet_ids  = ["subnet-abc", "subnet-def"]
security_group_ids = ["sg-123"]
EOF

# Apply
tofu apply

# Cleanup
tofu destroy
```

## Module Development

### Building a New Module

```bash
# 1. Create module directory
mkdir -p modules/my-module

# 2. Write module code
vim modules/my-module/main.tf
vim modules/my-module/variables.tf
vim modules/my-module/outputs.tf

# 3. Validate (fast)
cd modules/my-module
tofu init
tofu validate

# 4. Test in root module
cd ../../
tofu plan
```

### Fast Feedback Loop

```bash
# Watch mode - auto-validate on file changes
make watch

# In another terminal, edit files
vim modules/storage/main.tf
# Save -> automatically validated!
```

## Pre-Commit

Before every commit, these checks run automatically:
- OpenTofu format
- OpenTofu validate
- TFLint
- Security scan (Checkov)

Run manually:
```bash
make pre-commit
```

## Makefile Commands

```bash
make help          # Show all commands
make quick         # Fast checks (fmt, validate, lint)
make pre-commit    # All checks before commit
make watch         # Auto-validate on file changes
make clean         # Remove terraform artifacts
```

## Tips

- Use `tofu plan` to see changes before applying
- Only run `tofu apply` when you're confident
- Keep `terraform.tfvars` out of git (sensitive data)
- Use pre-commit hooks to catch errors early
- OpenTofu is compatible with Terraform .tf files