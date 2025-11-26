package test

import (
	"crypto/tls"
	"fmt"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GetTestID generates a unique test ID for resource naming
func GetTestID() string {
	return fmt.Sprintf("%d", time.Now().Unix())
}

// GetRandomStackName generates a random stack name for testing
func GetRandomStackName(prefix string) string {
	return fmt.Sprintf("%s-%s", prefix, random.UniqueId())
}

// GetRequiredEnv gets a required environment variable or fails the test
func GetRequiredEnv(t *testing.T, key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		if fallback != "" {
			t.Logf("WARNING: %s not set, using fallback value", key)
			return fallback
		}
		t.Fatalf("Required environment variable %s is not set", key)
	}
	return value
}

// GetOptionalEnv gets an optional environment variable with a default
func GetOptionalEnv(key string, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

// GetAWSRegion returns the AWS region for tests
func GetAWSRegion() string {
	return GetOptionalEnv("AWS_REGION", "us-east-1")
}

// GetTestTags returns common tags for test resources
func GetTestTags(testName string) map[string]string {
	return map[string]string{
		"TestFramework": "terratest",
		"TestName":      testName,
		"TestID":        GetTestID(),
		"ManagedBy":     "terratest",
		"AutoCleanup":   "true",
	}
}

// =============================================================================
// SCENARIO CONFIGURATION
// =============================================================================

// ScenarioConfig holds common test configuration for all scenarios
type ScenarioConfig struct {
	TestID     string
	GithubOrg  string
	LicenseKey string
	EnableEFS  bool
	EnableECR  bool
	EnableNAT  bool
	AWSRegion  string
}

// DefaultScenarioConfig returns config with sensible test defaults
func DefaultScenarioConfig() ScenarioConfig {
	return ScenarioConfig{
		TestID:     GetTestID(),
		GithubOrg:  GetOptionalEnv("GITHUB_ORG", "test-org"),
		LicenseKey: GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"),
		AWSRegion:  "us-east-1",
	}
}

// ToVPCVars converts config to VPC module variables
func (c ScenarioConfig) ToVPCVars() map[string]interface{} {
	return map[string]interface{}{
		"test_id":    c.TestID,
		"aws_region": c.AWSRegion,
		"enable_nat": c.EnableNAT,
	}
}

// ToModuleVars converts config to runs-on root module variables
func (c ScenarioConfig) ToModuleVars(vpcID string, publicSubnets, privateSubnets []string) map[string]interface{} {
	vars := map[string]interface{}{
		"stack_name":                  fmt.Sprintf("test-%s", c.TestID),
		"github_organization":         c.GithubOrg,
		"license_key":                 c.LicenseKey,
		"vpc_id":                      vpcID,
		"public_subnet_ids":           publicSubnets,
		"enable_efs":                  c.EnableEFS,
		"enable_ecr":                  c.EnableECR,
		"environment":                 "test",
		"log_retention_days":          1,
		"cache_expiration_days":       1,
		"detailed_monitoring_enabled": false,
		"app_cpu":                     1024,
		"app_memory":                  2048,
	}

	if len(privateSubnets) > 0 && c.EnableNAT {
		vars["private_subnet_ids"] = privateSubnets
	}

	return vars
}

// =============================================================================
// AWS SDK HELPERS
// =============================================================================

// GetAWSSession creates a reusable AWS session
func GetAWSSession() *session.Session {
	return session.Must(session.NewSession(&aws.Config{
		Region: aws.String(GetAWSRegion()),
	}))
}

// =============================================================================
// SECURITY VALIDATIONS
// =============================================================================

// ValidateS3BucketEncryption checks bucket has SSE-KMS encryption
func ValidateS3BucketEncryption(t *testing.T, bucketName string) {
	svc := s3.New(GetAWSSession())
	result, err := svc.GetBucketEncryption(&s3.GetBucketEncryptionInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get bucket encryption for %s", bucketName)
	require.NotEmpty(t, result.ServerSideEncryptionConfiguration.Rules, "Bucket %s has no encryption rules", bucketName)
	algo := *result.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm
	assert.Equal(t, "aws:kms", algo, "Bucket %s should use KMS encryption, got %s", bucketName, algo)
}

// ValidateS3BucketLogging checks bucket has access logging enabled
func ValidateS3BucketLogging(t *testing.T, bucketName, expectedTargetBucket string) {
	svc := s3.New(GetAWSSession())
	result, err := svc.GetBucketLogging(&s3.GetBucketLoggingInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get bucket logging for %s", bucketName)
	require.NotNil(t, result.LoggingEnabled, "Bucket %s should have logging enabled", bucketName)
	assert.Contains(t, *result.LoggingEnabled.TargetBucket, expectedTargetBucket,
		"Bucket %s should log to %s", bucketName, expectedTargetBucket)
}

// ValidateS3BucketPublicAccessBlocked checks bucket has public access blocked
func ValidateS3BucketPublicAccessBlocked(t *testing.T, bucketName string) {
	svc := s3.New(GetAWSSession())
	result, err := svc.GetPublicAccessBlock(&s3.GetPublicAccessBlockInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get public access block for %s", bucketName)

	config := result.PublicAccessBlockConfiguration
	assert.True(t, *config.BlockPublicAcls, "Bucket %s should block public ACLs", bucketName)
	assert.True(t, *config.BlockPublicPolicy, "Bucket %s should block public policy", bucketName)
	assert.True(t, *config.IgnorePublicAcls, "Bucket %s should ignore public ACLs", bucketName)
	assert.True(t, *config.RestrictPublicBuckets, "Bucket %s should restrict public buckets", bucketName)
}

// ValidateDynamoDBEncryption checks table has encryption at rest
func ValidateDynamoDBEncryption(t *testing.T, tableName string) {
	svc := dynamodb.New(GetAWSSession())
	result, err := svc.DescribeTable(&dynamodb.DescribeTableInput{
		TableName: aws.String(tableName),
	})
	require.NoError(t, err, "Failed to describe DynamoDB table %s", tableName)

	// DynamoDB has default encryption (AWS owned key) when SSEDescription is nil
	// This is acceptable - it means encryption is enabled with AWS managed keys
	if result.Table.SSEDescription != nil {
		status := *result.Table.SSEDescription.Status
		assert.Contains(t, []string{"ENABLED", "ENABLING"}, status,
			"DynamoDB table %s encryption status should be ENABLED, got %s", tableName, status)
	}
	t.Logf("DynamoDB table %s encryption verified (default AWS encryption)", tableName)
}

// ValidateIAMRoleNotOverlyPermissive checks role doesn't have dangerous policies
func ValidateIAMRoleNotOverlyPermissive(t *testing.T, roleName string) {
	svc := iam.New(GetAWSSession())

	// Check attached managed policies
	attachedPolicies, err := svc.ListAttachedRolePolicies(&iam.ListAttachedRolePoliciesInput{
		RoleName: aws.String(roleName),
	})
	require.NoError(t, err, "Failed to list attached policies for role %s", roleName)

	dangerousPolicies := []string{
		"arn:aws:iam::aws:policy/AdministratorAccess",
		"arn:aws:iam::aws:policy/PowerUserAccess",
		"arn:aws:iam::aws:policy/IAMFullAccess",
	}

	for _, policy := range attachedPolicies.AttachedPolicies {
		for _, dangerous := range dangerousPolicies {
			assert.NotEqual(t, dangerous, *policy.PolicyArn,
				"Role %s should not have %s attached", roleName, dangerous)
		}
	}
	t.Logf("IAM role %s has no overly permissive policies attached", roleName)
}

// =============================================================================
// COMPLIANCE VALIDATIONS
// =============================================================================

// ValidateS3BucketVersioning checks versioning status
func ValidateS3BucketVersioning(t *testing.T, bucketName string, expectedStatus string) {
	svc := s3.New(GetAWSSession())
	result, err := svc.GetBucketVersioning(&s3.GetBucketVersioningInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get bucket versioning for %s", bucketName)

	status := ""
	if result.Status != nil {
		status = *result.Status
	}
	assert.Equal(t, expectedStatus, status,
		"Bucket %s versioning should be %s, got %s", bucketName, expectedStatus, status)
}

// ValidateCloudWatchLogRetention checks log group has retention set
func ValidateCloudWatchLogRetention(t *testing.T, logGroupPrefix string) {
	svc := cloudwatchlogs.New(GetAWSSession())
	result, err := svc.DescribeLogGroups(&cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: aws.String(logGroupPrefix),
	})
	require.NoError(t, err, "Failed to describe log groups with prefix %s", logGroupPrefix)
	require.NotEmpty(t, result.LogGroups, "No log group found with prefix %s", logGroupPrefix)

	for _, lg := range result.LogGroups {
		assert.NotNil(t, lg.RetentionInDays,
			"Log group %s should have retention policy (not infinite)", *lg.LogGroupName)
		t.Logf("Log group %s has retention of %d days", *lg.LogGroupName, *lg.RetentionInDays)
	}
}

// =============================================================================
// ADVANCED VALIDATIONS
// =============================================================================

// ValidateAppRunnerHealth checks App Runner responds to health endpoint
func ValidateAppRunnerHealth(t *testing.T, serviceURL string, maxRetries int) {
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: false},
		},
	}

	healthURL := fmt.Sprintf("https://%s/ping", serviceURL)
	var lastErr error

	for i := 0; i < maxRetries; i++ {
		resp, err := client.Get(healthURL)
		if err != nil {
			lastErr = err
			t.Logf("Health check attempt %d/%d failed: %v", i+1, maxRetries, err)
			time.Sleep(30 * time.Second)
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode == 200 {
			t.Logf("App Runner health check passed after %d attempts", i+1)
			return
		}

		lastErr = fmt.Errorf("unexpected status code: %d", resp.StatusCode)
		t.Logf("Health check attempt %d/%d: status %d", i+1, maxRetries, resp.StatusCode)
		time.Sleep(30 * time.Second)
	}

	require.NoError(t, lastErr, "App Runner health check failed after %d retries", maxRetries)
}
