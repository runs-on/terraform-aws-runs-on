package test

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestScenarioBasic tests the basic deployment scenario with all security and compliance validations
func TestScenarioBasic(t *testing.T) {
	t.Parallel()

	config := DefaultScenarioConfig()
	config.EnableEFS = false
	config.EnableECR = false

	// Deploy VPC first
	vpcOptions := &terraform.Options{
		TerraformDir:    "./fixtures/vpc",
		TerraformBinary: "tofu",
		Vars:            config.ToVPCVars(),
		NoColor:         true,
	}
	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Get VPC outputs
	vpcID := terraform.Output(t, vpcOptions, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOptions, "public_subnets")

	// Deploy runs-on module (root module)
	moduleOptions := &terraform.Options{
		TerraformDir:    "../",
		TerraformBinary: "tofu",
		Vars:            config.ToModuleVars(vpcID, publicSubnets, nil),
		NoColor:         true,
	}
	defer terraform.Destroy(t, moduleOptions)
	terraform.InitAndApply(t, moduleOptions)

	// Get outputs
	stackName := terraform.Output(t, moduleOptions, "stack_name")
	appRunnerURL := terraform.Output(t, moduleOptions, "apprunner_service_url")
	configBucket := terraform.Output(t, moduleOptions, "config_bucket_name")
	cacheBucket := terraform.Output(t, moduleOptions, "cache_bucket_name")
	loggingBucket := terraform.Output(t, moduleOptions, "logging_bucket_name")
	ec2RoleName := terraform.Output(t, moduleOptions, "ec2_instance_role_name")
	logGroupName := terraform.Output(t, moduleOptions, "log_group_name")

	// ===== OUTPUT VALIDATIONS =====
	t.Run("Outputs", func(t *testing.T) {
		assert.NotEmpty(t, stackName, "Stack name should not be empty")
		assert.NotEmpty(t, appRunnerURL, "App Runner URL should not be empty")
		assert.Contains(t, appRunnerURL, "awsapprunner.com", "Should be a valid App Runner URL")
		assert.NotEmpty(t, configBucket, "Config bucket should not be empty")
		assert.NotEmpty(t, cacheBucket, "Cache bucket should not be empty")
		assert.NotEmpty(t, loggingBucket, "Logging bucket should not be empty")
		assert.NotEmpty(t, ec2RoleName, "EC2 role name should not be empty")
	})

	// ===== SECURITY VALIDATIONS =====
	t.Run("Security/S3Encryption", func(t *testing.T) {
		ValidateS3BucketEncryption(t, configBucket)
		ValidateS3BucketEncryption(t, cacheBucket)
		ValidateS3BucketEncryption(t, loggingBucket)
	})

	t.Run("Security/S3AccessLogging", func(t *testing.T) {
		ValidateS3BucketLogging(t, configBucket, loggingBucket)
		ValidateS3BucketLogging(t, cacheBucket, loggingBucket)
	})

	t.Run("Security/S3PublicAccessBlocked", func(t *testing.T) {
		ValidateS3BucketPublicAccessBlocked(t, configBucket)
		ValidateS3BucketPublicAccessBlocked(t, cacheBucket)
		ValidateS3BucketPublicAccessBlocked(t, loggingBucket)
	})

	t.Run("Security/IAMMinimalPermissions", func(t *testing.T) {
		ValidateIAMRoleNotOverlyPermissive(t, ec2RoleName)
	})

	// ===== COMPLIANCE VALIDATIONS =====
	t.Run("Compliance/S3Versioning", func(t *testing.T) {
		ValidateS3BucketVersioning(t, configBucket, "Enabled")
		ValidateS3BucketVersioning(t, cacheBucket, "Suspended") // Cache doesn't need versioning
		ValidateS3BucketVersioning(t, loggingBucket, "Enabled")
	})

	t.Run("Compliance/LogRetention", func(t *testing.T) {
		ValidateCloudWatchLogRetention(t, logGroupName)
	})

	// ===== ADVANCED VALIDATIONS =====
	t.Run("Advanced/AppRunnerHealth", func(t *testing.T) {
		ValidateAppRunnerHealth(t, appRunnerURL, 10)
	})

	// ===== FUNCTIONAL VALIDATIONS =====
	// These tests launch an EC2 instance and verify it can actually use the infrastructure
	// Note: IAM policy allows:
	//   - Cache bucket: read/write to cache/* prefix, read from runners/${aws:userid}/*
	//   - Config bucket: read-only from agents/* prefix
	t.Run("Functional", func(t *testing.T) {
		// Get launch template ID for functional tests
		launchTemplateID := terraform.Output(t, moduleOptions, "launch_template_linux_default_id")
		require.NotEmpty(t, launchTemplateID, "Launch template ID should not be empty")

		// Launch shared instance for all functional tests
		instanceID := LaunchTestInstance(t, launchTemplateID, publicSubnets[0])
		defer TerminateTestInstance(t, instanceID)

		// Wait for instance to be SSM-ready
		ready := WaitForInstanceReady(t, instanceID, 5*time.Minute)
		require.True(t, ready, "Instance failed to become SSM-ready within timeout")

		t.Run("S3Access", func(t *testing.T) {
			// Validates all S3 IAM policy permissions:
			// - CAN write/read cache/* in cache bucket
			// - CAN read runners/{own-userid}/* in cache bucket
			// - CAN read agents/* in config bucket
			// - CANNOT write to runners/* or read other users' runners paths
			ValidateS3AccessFromEC2(t, instanceID, cacheBucket, configBucket)
		})

		t.Run("CloudWatchLogging", func(t *testing.T) {
			ValidateEC2CloudWatchLogs(t, instanceID, logGroupName)
		})
	})

	// ===== INTEGRATION TESTS =====
	// End-to-end job execution test
	// Flow: Deploy infra -> User registers app -> Test polls for successful workflow with RunsOn
	t.Run("Integration/JobExecution", func(t *testing.T) {
		testRepo := os.Getenv("RUNS_ON_TEST_REPO")
		testWorkflow := os.Getenv("RUNS_ON_TEST_WORKFLOW")
		t.Logf("RUNS_ON_TEST_REPO = %q", testRepo)
		t.Logf("RUNS_ON_TEST_WORKFLOW = %q", testWorkflow)
		if testRepo == "" {
			t.Skip("RUNS_ON_TEST_REPO not set - skipping integration test")
		}
		if testWorkflow == "" {
			testWorkflow = "test.yml"
		}

		startTime := time.Now()

		// Wait for RunsOn registration by polling for a workflow run with RunsOn in logs
		// User must manually register at the AppRunner URL, then trigger a workflow
		runID := WaitForRunsOnRegistration(t, appRunnerURL, testRepo, testWorkflow, 15*time.Minute)

		// Verify workflow completed successfully
		conclusion := WaitForWorkflowCompletion(t, testRepo, runID, 10*time.Minute)
		assert.Equal(t, "success", conclusion, "Workflow should succeed")

		// Validate runner was launched
		launched := ValidateRunnerLaunched(t, stackName, startTime)
		assert.True(t, launched, "Runner instance should have been launched")
	})

	fmt.Printf("\n✅ Basic scenario deployment successful!\n")
	fmt.Printf("   Stack: %s\n", stackName)
	fmt.Printf("   App Runner: %s\n", appRunnerURL)
}

// TestScenarioPrivateNetworking tests private networking scenario
// NOTE: Requires NAT gateway - expensive test!
func TestScenarioPrivateNetworking(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping expensive test (requires NAT gateway)")
	}

	config := DefaultScenarioConfig()
	config.EnableNAT = true

	// Deploy VPC with NAT
	vpcOptions := &terraform.Options{
		TerraformDir:    "./fixtures/vpc",
		TerraformBinary: "tofu",
		Vars:            config.ToVPCVars(),
		NoColor:         true,
	}
	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Get VPC outputs
	vpcID := terraform.Output(t, vpcOptions, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOptions, "public_subnets")
	privateSubnets := terraform.OutputList(t, vpcOptions, "private_subnets")

	// Deploy runs-on module with private networking
	moduleOptions := &terraform.Options{
		TerraformDir:    "../",
		TerraformBinary: "tofu",
		Vars:            config.ToModuleVars(vpcID, publicSubnets, privateSubnets),
		NoColor:         true,
	}
	defer terraform.Destroy(t, moduleOptions)
	terraform.InitAndApply(t, moduleOptions)

	// Get outputs
	stackName := terraform.Output(t, moduleOptions, "stack_name")
	appRunnerURL := terraform.Output(t, moduleOptions, "apprunner_service_url")
	configBucket := terraform.Output(t, moduleOptions, "config_bucket_name")
	cacheBucket := terraform.Output(t, moduleOptions, "cache_bucket_name")
	loggingBucket := terraform.Output(t, moduleOptions, "logging_bucket_name")
	ec2RoleName := terraform.Output(t, moduleOptions, "ec2_instance_role_name")
	logGroupName := terraform.Output(t, moduleOptions, "log_group_name")

	// ===== OUTPUT VALIDATIONS =====
	t.Run("Outputs", func(t *testing.T) {
		assert.NotEmpty(t, appRunnerURL, "App Runner URL should not be empty")
		assert.Contains(t, appRunnerURL, "awsapprunner.com")
	})

	// ===== SECURITY VALIDATIONS =====
	t.Run("Security/S3Encryption", func(t *testing.T) {
		ValidateS3BucketEncryption(t, configBucket)
		ValidateS3BucketEncryption(t, cacheBucket)
		ValidateS3BucketEncryption(t, loggingBucket)
	})

	t.Run("Security/IAMMinimalPermissions", func(t *testing.T) {
		ValidateIAMRoleNotOverlyPermissive(t, ec2RoleName)
	})

	// ===== COMPLIANCE VALIDATIONS =====
	t.Run("Compliance/S3Versioning", func(t *testing.T) {
		ValidateS3BucketVersioning(t, configBucket, "Enabled")
		ValidateS3BucketVersioning(t, cacheBucket, "Suspended")
		ValidateS3BucketVersioning(t, loggingBucket, "Enabled")
	})

	t.Run("Compliance/LogRetention", func(t *testing.T) {
		ValidateCloudWatchLogRetention(t, logGroupName)
	})

	// ===== ADVANCED VALIDATIONS =====
	t.Run("Advanced/AppRunnerHealth", func(t *testing.T) {
		ValidateAppRunnerHealth(t, appRunnerURL, 10)
	})

	fmt.Printf("\n✅ Private networking scenario successful!\n")
	fmt.Printf("   Stack: %s\n", stackName)
}

// TestScenarioEFSEnabled tests EFS-enabled scenario
func TestScenarioEFSEnabled(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping EFS test in short mode")
	}

	config := DefaultScenarioConfig()
	config.EnableEFS = true

	// Deploy VPC
	vpcOptions := &terraform.Options{
		TerraformDir:    "./fixtures/vpc",
		TerraformBinary: "tofu",
		Vars:            config.ToVPCVars(),
		NoColor:         true,
	}
	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Get VPC outputs
	vpcID := terraform.Output(t, vpcOptions, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOptions, "public_subnets")

	// Deploy runs-on module with EFS enabled
	moduleOptions := &terraform.Options{
		TerraformDir:    "../",
		TerraformBinary: "tofu",
		Vars:            config.ToModuleVars(vpcID, publicSubnets, nil),
		NoColor:         true,
	}
	defer terraform.Destroy(t, moduleOptions)
	terraform.InitAndApply(t, moduleOptions)

	// Get outputs
	stackName := terraform.Output(t, moduleOptions, "stack_name")
	appRunnerURL := terraform.Output(t, moduleOptions, "apprunner_service_url")
	configBucket := terraform.Output(t, moduleOptions, "config_bucket_name")
	cacheBucket := terraform.Output(t, moduleOptions, "cache_bucket_name")
	loggingBucket := terraform.Output(t, moduleOptions, "logging_bucket_name")
	ec2RoleName := terraform.Output(t, moduleOptions, "ec2_instance_role_name")
	efsFileSystemID := terraform.Output(t, moduleOptions, "efs_file_system_id")
	logGroupName := terraform.Output(t, moduleOptions, "log_group_name")

	// ===== OUTPUT VALIDATIONS =====
	t.Run("Outputs", func(t *testing.T) {
		assert.NotEmpty(t, appRunnerURL, "App Runner URL should not be empty")
		assert.NotEmpty(t, efsFileSystemID, "EFS ID should not be empty when EFS is enabled")
	})

	// ===== SECURITY VALIDATIONS =====
	t.Run("Security/S3Encryption", func(t *testing.T) {
		ValidateS3BucketEncryption(t, configBucket)
		ValidateS3BucketEncryption(t, cacheBucket)
		ValidateS3BucketEncryption(t, loggingBucket)
	})

	t.Run("Security/IAMMinimalPermissions", func(t *testing.T) {
		ValidateIAMRoleNotOverlyPermissive(t, ec2RoleName)
	})

	// ===== COMPLIANCE VALIDATIONS =====
	t.Run("Compliance/S3Versioning", func(t *testing.T) {
		ValidateS3BucketVersioning(t, configBucket, "Enabled")
		ValidateS3BucketVersioning(t, cacheBucket, "Suspended")
		ValidateS3BucketVersioning(t, loggingBucket, "Enabled")
	})

	t.Run("Compliance/LogRetention", func(t *testing.T) {
		ValidateCloudWatchLogRetention(t, logGroupName)
	})

	fmt.Printf("\n✅ EFS-enabled scenario successful!\n")
	fmt.Printf("   Stack: %s\n", stackName)
	fmt.Printf("   EFS: %s\n", efsFileSystemID)
}

// TestScenarioECREnabled tests ECR-enabled scenario
func TestScenarioECREnabled(t *testing.T) {
	t.Parallel()

	config := DefaultScenarioConfig()
	config.EnableECR = true

	// Deploy VPC
	vpcOptions := &terraform.Options{
		TerraformDir:    "./fixtures/vpc",
		TerraformBinary: "tofu",
		Vars:            config.ToVPCVars(),
		NoColor:         true,
	}
	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Get VPC outputs
	vpcID := terraform.Output(t, vpcOptions, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOptions, "public_subnets")

	// Deploy runs-on module with ECR enabled
	moduleOptions := &terraform.Options{
		TerraformDir:    "../",
		TerraformBinary: "tofu",
		Vars:            config.ToModuleVars(vpcID, publicSubnets, nil),
		NoColor:         true,
	}
	defer terraform.Destroy(t, moduleOptions)
	terraform.InitAndApply(t, moduleOptions)

	// Get outputs
	stackName := terraform.Output(t, moduleOptions, "stack_name")
	appRunnerURL := terraform.Output(t, moduleOptions, "apprunner_service_url")
	configBucket := terraform.Output(t, moduleOptions, "config_bucket_name")
	cacheBucket := terraform.Output(t, moduleOptions, "cache_bucket_name")
	loggingBucket := terraform.Output(t, moduleOptions, "logging_bucket_name")
	ec2RoleName := terraform.Output(t, moduleOptions, "ec2_instance_role_name")
	ecrURL := terraform.Output(t, moduleOptions, "ecr_repository_url")
	logGroupName := terraform.Output(t, moduleOptions, "log_group_name")

	// ===== OUTPUT VALIDATIONS =====
	t.Run("Outputs", func(t *testing.T) {
		assert.NotEmpty(t, appRunnerURL, "App Runner URL should not be empty")
		assert.NotEmpty(t, ecrURL, "ECR URL should not be empty when ECR is enabled")
		assert.Contains(t, ecrURL, "ecr", "Should be ECR URL")
	})

	// ===== SECURITY VALIDATIONS =====
	t.Run("Security/S3Encryption", func(t *testing.T) {
		ValidateS3BucketEncryption(t, configBucket)
		ValidateS3BucketEncryption(t, cacheBucket)
		ValidateS3BucketEncryption(t, loggingBucket)
	})

	t.Run("Security/IAMMinimalPermissions", func(t *testing.T) {
		ValidateIAMRoleNotOverlyPermissive(t, ec2RoleName)
	})

	// ===== COMPLIANCE VALIDATIONS =====
	t.Run("Compliance/S3Versioning", func(t *testing.T) {
		ValidateS3BucketVersioning(t, configBucket, "Enabled")
		ValidateS3BucketVersioning(t, cacheBucket, "Suspended")
		ValidateS3BucketVersioning(t, loggingBucket, "Enabled")
	})

	t.Run("Compliance/LogRetention", func(t *testing.T) {
		ValidateCloudWatchLogRetention(t, logGroupName)
	})

	fmt.Printf("\n✅ ECR-enabled scenario successful!\n")
	fmt.Printf("   Stack: %s\n", stackName)
	fmt.Printf("   ECR: %s\n", ecrURL)
}

// TestScenarioFullFeatured tests full-featured scenario with all options
// NOTE: Most expensive test - requires NAT + EFS + ECR
func TestScenarioFullFeatured(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping expensive full-featured test (requires NAT + EFS + ECR)")
	}

	config := DefaultScenarioConfig()
	config.EnableNAT = true
	config.EnableEFS = true
	config.EnableECR = true

	// Deploy VPC with NAT
	vpcOptions := &terraform.Options{
		TerraformDir:    "./fixtures/vpc",
		TerraformBinary: "tofu",
		Vars:            config.ToVPCVars(),
		NoColor:         true,
	}
	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	// Get VPC outputs
	vpcID := terraform.Output(t, vpcOptions, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOptions, "public_subnets")
	privateSubnets := terraform.OutputList(t, vpcOptions, "private_subnets")

	// Deploy runs-on module with all features
	moduleOptions := &terraform.Options{
		TerraformDir:    "../",
		TerraformBinary: "tofu",
		Vars:            config.ToModuleVars(vpcID, publicSubnets, privateSubnets),
		NoColor:         true,
	}
	defer terraform.Destroy(t, moduleOptions)
	terraform.InitAndApply(t, moduleOptions)

	// Get outputs
	stackName := terraform.Output(t, moduleOptions, "stack_name")
	appRunnerURL := terraform.Output(t, moduleOptions, "apprunner_service_url")
	configBucket := terraform.Output(t, moduleOptions, "config_bucket_name")
	cacheBucket := terraform.Output(t, moduleOptions, "cache_bucket_name")
	loggingBucket := terraform.Output(t, moduleOptions, "logging_bucket_name")
	ec2RoleName := terraform.Output(t, moduleOptions, "ec2_instance_role_name")
	efsFileSystemID := terraform.Output(t, moduleOptions, "efs_file_system_id")
	ecrURL := terraform.Output(t, moduleOptions, "ecr_repository_url")
	logGroupName := terraform.Output(t, moduleOptions, "log_group_name")

	// ===== OUTPUT VALIDATIONS =====
	t.Run("Outputs", func(t *testing.T) {
		assert.NotEmpty(t, appRunnerURL, "App Runner URL should not be empty")
		assert.NotEmpty(t, efsFileSystemID, "EFS ID should not be empty")
		assert.NotEmpty(t, ecrURL, "ECR URL should not be empty")
	})

	// ===== SECURITY VALIDATIONS =====
	t.Run("Security/S3Encryption", func(t *testing.T) {
		ValidateS3BucketEncryption(t, configBucket)
		ValidateS3BucketEncryption(t, cacheBucket)
		ValidateS3BucketEncryption(t, loggingBucket)
	})

	t.Run("Security/S3AccessLogging", func(t *testing.T) {
		ValidateS3BucketLogging(t, configBucket, loggingBucket)
		ValidateS3BucketLogging(t, cacheBucket, loggingBucket)
	})

	t.Run("Security/S3PublicAccessBlocked", func(t *testing.T) {
		ValidateS3BucketPublicAccessBlocked(t, configBucket)
		ValidateS3BucketPublicAccessBlocked(t, cacheBucket)
		ValidateS3BucketPublicAccessBlocked(t, loggingBucket)
	})

	t.Run("Security/IAMMinimalPermissions", func(t *testing.T) {
		ValidateIAMRoleNotOverlyPermissive(t, ec2RoleName)
	})

	// ===== COMPLIANCE VALIDATIONS =====
	t.Run("Compliance/S3Versioning", func(t *testing.T) {
		ValidateS3BucketVersioning(t, configBucket, "Enabled")
		ValidateS3BucketVersioning(t, cacheBucket, "Suspended")
		ValidateS3BucketVersioning(t, loggingBucket, "Enabled")
	})

	t.Run("Compliance/LogRetention", func(t *testing.T) {
		ValidateCloudWatchLogRetention(t, logGroupName)
	})

	// ===== ADVANCED VALIDATIONS =====
	t.Run("Advanced/AppRunnerHealth", func(t *testing.T) {
		ValidateAppRunnerHealth(t, appRunnerURL, 10)
	})

	fmt.Printf("\n✅ Full-featured deployment successful!\n")
	fmt.Printf("   Stack: %s\n", stackName)
	fmt.Printf("   App Runner: %s\n", appRunnerURL)
	fmt.Printf("   EFS: %s\n", efsFileSystemID)
	fmt.Printf("   ECR: %s\n", ecrURL)
}
