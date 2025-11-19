package test

import (
	"testing"
)

// TestComputeModuleIAMRoleCreation tests IAM role creation
// NOTE: Compute module requires dependencies from storage module
// Use integration tests or Terragrunt scenarios for complete testing
func TestComputeModuleIAMRoleCreation(t *testing.T) {
	t.Skip("Skipping - compute module requires storage module outputs. Use integration tests instead.")
}

// TestComputeModuleLaunchTemplatesPublicOnly tests launch template creation with public subnets only
func TestComputeModuleLaunchTemplatesPublicOnly(t *testing.T) {
	t.Skip("Skipping - compute module requires storage module outputs. Use integration tests instead.")
}

// TestComputeModuleLaunchTemplatesWithPrivate tests launch template creation with private subnets
func TestComputeModuleLaunchTemplatesWithPrivate(t *testing.T) {
	t.Skip("Skipping - compute module requires storage module outputs. Use integration tests instead.")
}

// TestComputeModuleEFSIntegration tests EFS integration in compute module
func TestComputeModuleEFSIntegration(t *testing.T) {
	t.Skip("Skipping - use full-featured scenario test instead")
}

// TestComputeModuleECRIntegration tests ECR integration in compute module
func TestComputeModuleECRIntegration(t *testing.T) {
	t.Skip("Skipping - use ecr-enabled scenario test instead")
}

// NOTE: Compute module tests are better suited for integration/scenario tests
// because the module has dependencies on storage and optional modules.
// See scenarios_test.go for complete testing of compute module functionality.
