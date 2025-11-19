package test

import (
	"fmt"
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestScenarioMinimal tests the minimal deployment scenario with Terragrunt
func TestScenarioMinimal(t *testing.T) {
	t.Parallel()

	testID := GetTestID()
	os.Setenv("TEST_ID", testID)
	os.Setenv("GITHUB_ORG", GetOptionalEnv("GITHUB_ORG", "test-org"))
	os.Setenv("RUNS_ON_LICENSE_KEY", GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"))

	// Deploy VPC first
	vpcOptions := &terraform.Options{
		TerraformDir:    "./live/_shared/vpc",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Deploy minimal scenario
	scenarioOptions := &terraform.Options{
		TerraformDir:    "./live/scenarios/minimal",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, scenarioOptions)
	terraform.InitAndApply(t, scenarioOptions)

	// Validations
	appRunnerURL := terraform.Output(t, scenarioOptions, "app_runner_url")
	assert.NotEmpty(t, appRunnerURL, "App Runner URL should not be empty")
	assert.Contains(t, appRunnerURL, "awsapprunner.com", "Should be a valid App Runner URL")
}

// TestScenarioPublicOnly tests public networking scenario
func TestScenarioPublicOnly(t *testing.T) {
	t.Parallel()

	testID := GetTestID()
	os.Setenv("TEST_ID", testID)
	os.Setenv("GITHUB_ORG", GetOptionalEnv("GITHUB_ORG", "test-org"))
	os.Setenv("RUNS_ON_LICENSE_KEY", GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"))

	// Deploy VPC
	vpcOptions := &terraform.Options{
		TerraformDir:    "./live/_shared/vpc",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Deploy public-only scenario
	scenarioOptions := &terraform.Options{
		TerraformDir:    "./live/scenarios/public-only",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, scenarioOptions)
	terraform.InitAndApply(t, scenarioOptions)

	// Validations
	appRunnerURL := terraform.Output(t, scenarioOptions, "app_runner_url")
	assert.NotEmpty(t, appRunnerURL)

	// TODO: Verify only 2 launch templates created (no private variants)
}

// TestScenarioPrivateNetworking tests private networking scenario
// NOTE: Requires NAT gateway - expensive test!
func TestScenarioPrivateNetworking(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping expensive test in short mode")
	}

	testID := GetTestID()
	os.Setenv("TEST_ID", testID)
	os.Setenv("ENABLE_NAT", "true") // Enable NAT gateway
	os.Setenv("GITHUB_ORG", GetOptionalEnv("GITHUB_ORG", "test-org"))
	os.Setenv("RUNS_ON_LICENSE_KEY", GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"))

	// Deploy VPC with NAT
	vpcOptions := &terraform.Options{
		TerraformDir:    "./live/_shared/vpc",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Deploy private networking scenario
	scenarioOptions := &terraform.Options{
		TerraformDir:    "./live/scenarios/private-networking",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, scenarioOptions)
	terraform.InitAndApply(t, scenarioOptions)

	// Validations
	appRunnerURL := terraform.Output(t, scenarioOptions, "app_runner_url")
	assert.NotEmpty(t, appRunnerURL)

	// TODO: Verify 4 launch templates created (Linux/Windows x Public/Private)
	// TODO: Verify VPC connector created
}

// TestScenarioEFSEnabled tests EFS-enabled scenario
func TestScenarioEFSEnabled(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping in short mode")
	}

	testID := GetTestID()
	os.Setenv("TEST_ID", testID)
	os.Setenv("GITHUB_ORG", GetOptionalEnv("GITHUB_ORG", "test-org"))
	os.Setenv("RUNS_ON_LICENSE_KEY", GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"))

	// Deploy VPC
	vpcOptions := &terraform.Options{
		TerraformDir:    "./live/_shared/vpc",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Deploy EFS scenario
	scenarioOptions := &terraform.Options{
		TerraformDir:    "./live/scenarios/efs-enabled",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, scenarioOptions)
	terraform.InitAndApply(t, scenarioOptions)

	// Validations
	efsID := terraform.Output(t, scenarioOptions, "efs_id")
	assert.NotEmpty(t, efsID, "EFS ID should not be empty")

	// TODO: Verify EFS mount targets created
	// TODO: Verify EFS security group rules
}

// TestScenarioECREnabled tests ECR-enabled scenario
func TestScenarioECREnabled(t *testing.T) {
	t.Parallel()

	testID := GetTestID()
	os.Setenv("TEST_ID", testID)
	os.Setenv("GITHUB_ORG", GetOptionalEnv("GITHUB_ORG", "test-org"))
	os.Setenv("RUNS_ON_LICENSE_KEY", GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"))

	// Deploy VPC
	vpcOptions := &terraform.Options{
		TerraformDir:    "./live/_shared/vpc",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Deploy ECR scenario
	scenarioOptions := &terraform.Options{
		TerraformDir:    "./live/scenarios/ecr-enabled",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, scenarioOptions)
	terraform.InitAndApply(t, scenarioOptions)

	// Validations
	ecrURL := terraform.Output(t, scenarioOptions, "ecr_repository_url")
	assert.NotEmpty(t, ecrURL, "ECR URL should not be empty")
	assert.Contains(t, ecrURL, "ecr", "Should be ECR URL")
}

// TestScenarioFullFeatured tests full-featured scenario with all options
// NOTE: Most expensive test - requires NAT + EFS + ECR
func TestScenarioFullFeatured(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping expensive full-featured test in short mode")
	}

	testID := GetTestID()
	os.Setenv("TEST_ID", testID)
	os.Setenv("ENABLE_NAT", "true")
	os.Setenv("GITHUB_ORG", GetOptionalEnv("GITHUB_ORG", "test-org"))
	os.Setenv("RUNS_ON_LICENSE_KEY", GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"))

	// Deploy VPC with NAT
	vpcOptions := &terraform.Options{
		TerraformDir:    "./live/_shared/vpc",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Deploy full-featured scenario
	scenarioOptions := &terraform.Options{
		TerraformDir:    "./live/scenarios/full-featured",
		TerraformBinary: "terragrunt",
		NoColor:         true,
	}

	defer terraform.Destroy(t, scenarioOptions)
	terraform.InitAndApply(t, scenarioOptions)

	// Comprehensive validations
	appRunnerURL := terraform.Output(t, scenarioOptions, "app_runner_url")
	efsID := terraform.Output(t, scenarioOptions, "efs_id")
	ecrURL := terraform.Output(t, scenarioOptions, "ecr_repository_url")

	assert.NotEmpty(t, appRunnerURL, "App Runner URL should not be empty")
	assert.NotEmpty(t, efsID, "EFS ID should not be empty")
	assert.NotEmpty(t, ecrURL, "ECR URL should not be empty")

	fmt.Printf("\n✅ Full-featured deployment successful!\n")
	fmt.Printf("   App Runner: %s\n", appRunnerURL)
	fmt.Printf("   EFS: %s\n", efsID)
	fmt.Printf("   ECR: %s\n", ecrURL)
}
