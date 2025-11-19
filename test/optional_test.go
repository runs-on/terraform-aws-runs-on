package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestOptionalModuleEFSDisabled tests that no EFS resources are created when disabled
func TestOptionalModuleEFSDisabled(t *testing.T) {
	t.Parallel()

	stackName := GetRandomStackName("test-optional-noefs")

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/optional",
		Vars: map[string]interface{}{
			"stack_name": stackName,
			"enable_efs": false,
			"enable_ecr": false,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify no EFS created
	efsID := terraform.Output(t, terraformOptions, "efs_id")
	assert.Empty(t, efsID, "EFS ID should be empty when disabled")
}

// TestOptionalModuleECRDisabled tests that no ECR resources are created when disabled
func TestOptionalModuleECRDisabled(t *testing.T) {
	t.Parallel()

	stackName := GetRandomStackName("test-optional-noecr")

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/optional",
		Vars: map[string]interface{}{
			"stack_name": stackName,
			"enable_efs": false,
			"enable_ecr": false,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify no ECR created
	ecrURL := terraform.Output(t, terraformOptions, "ecr_repository_url")
	assert.Empty(t, ecrURL, "ECR URL should be empty when disabled")
}

// TestOptionalModuleEFSEnabled tests EFS creation when enabled
// NOTE: This test requires VPC and subnets, use integration tests instead
func TestOptionalModuleEFSEnabled(t *testing.T) {
	t.Skip("Skipping - requires VPC infrastructure. Use integration tests or Terragrunt scenarios instead.")
}

// TestOptionalModuleECREnabled tests ECR creation when enabled
func TestOptionalModuleECREnabled(t *testing.T) {
	t.Parallel()

	stackName := GetRandomStackName("test-optional-ecr")

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/optional",
		Vars: map[string]interface{}{
			"stack_name": stackName,
			"enable_efs": false,
			"enable_ecr": true,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify ECR created
	ecrURL := terraform.Output(t, terraformOptions, "ecr_repository_url")
	ecrARN := terraform.Output(t, terraformOptions, "ecr_repository_arn")

	assert.NotEmpty(t, ecrURL, "ECR URL should not be empty when enabled")
	assert.Contains(t, ecrURL, stackName, "ECR URL should contain stack name")
	assert.NotEmpty(t, ecrARN, "ECR ARN should not be empty when enabled")
	assert.Contains(t, ecrARN, "arn:aws:ecr", "ECR ARN should be valid")
}
