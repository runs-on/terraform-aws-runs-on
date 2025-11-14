# .tflint.hcl
# TFLint configuration for RunsOn OpenTofu module

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Terraform naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Ensure all variables are documented
rule "terraform_documented_variables" {
  enabled = true
}

# Ensure all outputs are documented
rule "terraform_documented_outputs" {
  enabled = true
}

# Detect unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Require specific module version
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"
}

# Ensure module version is set
rule "terraform_module_version" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# Type constraints for variables
rule "terraform_typed_variables" {
  enabled = true
}

# AWS specific rules
rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Name", "Environment"]
}
