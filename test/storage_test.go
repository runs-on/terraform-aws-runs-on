package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestStorageModuleBucketCreation tests that the storage module creates all required S3 buckets
func TestStorageModuleBucketCreation(t *testing.T) {
	t.Parallel()

	stackName := GetRandomStackName("test-storage")

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/storage",
		Vars: map[string]interface{}{
			"stack_name": stackName,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Validate outputs
	configBucket := terraform.Output(t, terraformOptions, "config_bucket_name")
	cacheBucket := terraform.Output(t, terraformOptions, "cache_bucket_name")
	loggingBucket := terraform.Output(t, terraformOptions, "logging_bucket_name")

	// Assertions
	assert.Contains(t, configBucket, stackName)
	assert.Contains(t, configBucket, "config")
	assert.Contains(t, cacheBucket, stackName)
	assert.Contains(t, cacheBucket, "cache")
	assert.Contains(t, loggingBucket, stackName)
	assert.Contains(t, loggingBucket, "logging")
}

// TestStorageModuleBucketEncryption tests that S3 buckets have encryption enabled
func TestStorageModuleBucketEncryption(t *testing.T) {
	t.Parallel()

	stackName := GetRandomStackName("test-storage-enc")

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/storage",
		Vars: map[string]interface{}{
			"stack_name": stackName,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// TODO: Add AWS SDK validation for bucket encryption
	// This requires importing aws-sdk-go-v2 and checking bucket encryption settings

	// For now, verify buckets were created
	configBucket := terraform.Output(t, terraformOptions, "config_bucket_name")
	assert.NotEmpty(t, configBucket)
}

// TestStorageModuleCacheExpiration tests custom cache expiration settings
func TestStorageModuleCacheExpiration(t *testing.T) {
	t.Parallel()

	stackName := GetRandomStackName("test-storage-cache")
	cacheExpirationDays := 7

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/storage",
		Vars: map[string]interface{}{
			"stack_name":            stackName,
			"cache_expiration_days": cacheExpirationDays,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify cache bucket created
	cacheBucket := terraform.Output(t, terraformOptions, "cache_bucket_name")
	assert.NotEmpty(t, cacheBucket)

	// TODO: Validate lifecycle policy has correct expiration
}
