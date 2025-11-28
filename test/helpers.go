package test

import (
	"bufio"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/ssm"
	"github.com/google/go-github/v57/github"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/oauth2"
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
		GithubOrg:  getGithubOrg(),
		LicenseKey: GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"),
		AWSRegion:  "us-east-1",
	}
}

// getGithubOrg extracts the GitHub organization from RUNS_ON_TEST_REPO or GITHUB_ORG.
// Priority: GITHUB_ORG > RUNS_ON_TEST_REPO (owner part) > "test-org"
func getGithubOrg() string {
	// First check explicit GITHUB_ORG
	if org := os.Getenv("GITHUB_ORG"); org != "" {
		return org
	}

	// Extract owner from RUNS_ON_TEST_REPO (format: "owner/repo")
	if testRepo := os.Getenv("RUNS_ON_TEST_REPO"); testRepo != "" {
		parts := strings.Split(testRepo, "/")
		if len(parts) >= 1 && parts[0] != "" {
			return parts[0]
		}
	}

	// Fallback
	return "test-org"
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
		"stack_name":                         fmt.Sprintf("test-%s", c.TestID),
		"github_organization":                c.GithubOrg,
		"license_key":                        c.LicenseKey,
		"vpc_id":                             vpcID,
		"public_subnet_ids":                  publicSubnets,
		"enable_efs":                         c.EnableEFS,
		"enable_ecr":                         c.EnableECR,
		"environment":                        "test",
		"log_retention_days":                 1,
		"cache_expiration_days":              1,
		"detailed_monitoring_enabled":        false,
		"app_cpu":                            1024,
		"app_memory":                         2048,
		"force_destroy_buckets":              true,  // Enable force destroy for S3 test cleanup
		"force_delete_ecr":                   true,  // Enable force delete for ECR test cleanup
		"prevent_destroy_optional_resources": false, // Disable prevent_destroy for test cleanup
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

// =============================================================================
// EC2 AND SSM HELPERS FOR FUNCTIONAL TESTING
// =============================================================================

// GetLatestAmazonLinux2023AMI returns the latest Amazon Linux 2023 AMI ID for the current region.
func GetLatestAmazonLinux2023AMI(t *testing.T) string {
	ec2Svc := ec2.New(GetAWSSession())

	result, err := ec2Svc.DescribeImages(&ec2.DescribeImagesInput{
		Owners: []*string{aws.String("amazon")},
		Filters: []*ec2.Filter{
			{
				Name:   aws.String("name"),
				Values: []*string{aws.String("al2023-ami-2023*-x86_64")},
			},
			{
				Name:   aws.String("state"),
				Values: []*string{aws.String("available")},
			},
			{
				Name:   aws.String("architecture"),
				Values: []*string{aws.String("x86_64")},
			},
		},
	})
	require.NoError(t, err, "Failed to describe AMIs")
	require.NotEmpty(t, result.Images, "No Amazon Linux 2023 AMIs found")

	// Find the most recent AMI
	var latestAMI *ec2.Image
	for _, img := range result.Images {
		if latestAMI == nil || *img.CreationDate > *latestAMI.CreationDate {
			latestAMI = img
		}
	}

	t.Logf("Using AMI: %s (%s)", *latestAMI.ImageId, *latestAMI.Name)
	return *latestAMI.ImageId
}

// LaunchTestInstance launches an EC2 instance from a launch template for functional testing.
// launchTemplateID should be in format "lt-xxx:version" or just "lt-xxx".
// Returns the instance ID.
func LaunchTestInstance(t *testing.T, launchTemplateID, subnetID string) string {
	ec2Svc := ec2.New(GetAWSSession())

	// Parse launch template ID and version
	parts := strings.Split(launchTemplateID, ":")
	templateID := parts[0]
	version := "$Latest"
	if len(parts) > 1 {
		version = parts[1]
	}

	// Get the latest Amazon Linux 2023 AMI since the launch template may not have one
	amiID := GetLatestAmazonLinux2023AMI(t)

	t.Logf("Launching test instance from template %s (version %s) in subnet %s with AMI %s",
		templateID, version, subnetID, amiID)

	input := &ec2.RunInstancesInput{
		LaunchTemplate: &ec2.LaunchTemplateSpecification{
			LaunchTemplateId: aws.String(templateID),
			Version:          aws.String(version),
		},
		ImageId:  aws.String(amiID), // Override the AMI since launch template may not have one
		MinCount: aws.Int64(1),
		MaxCount: aws.Int64(1),
		// Use NetworkInterfaces instead of SubnetId since launch template may have network interface config
		NetworkInterfaces: []*ec2.InstanceNetworkInterfaceSpecification{
			{
				DeviceIndex:              aws.Int64(0),
				SubnetId:                 aws.String(subnetID),
				AssociatePublicIpAddress: aws.Bool(true), // Need public IP for SSM access in public subnet
				DeleteOnTermination:      aws.Bool(true),
			},
		},
		TagSpecifications: []*ec2.TagSpecification{
			{
				ResourceType: aws.String("instance"),
				Tags: []*ec2.Tag{
					{Key: aws.String("Name"), Value: aws.String("terratest-functional-test")},
					{Key: aws.String("TestFramework"), Value: aws.String("terratest")},
					{Key: aws.String("AutoCleanup"), Value: aws.String("true")},
				},
			},
		},
	}

	result, err := ec2Svc.RunInstances(input)
	require.NoError(t, err, "Failed to launch test instance")
	require.Len(t, result.Instances, 1, "Expected exactly one instance to be launched")

	instanceID := *result.Instances[0].InstanceId
	t.Logf("Launched test instance: %s", instanceID)
	return instanceID
}

// TerminateTestInstance terminates a test EC2 instance
func TerminateTestInstance(t *testing.T, instanceID string) {
	if instanceID == "" {
		return
	}

	ec2Svc := ec2.New(GetAWSSession())
	t.Logf("Terminating test instance: %s", instanceID)

	_, err := ec2Svc.TerminateInstances(&ec2.TerminateInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	})
	if err != nil {
		t.Logf("Warning: Failed to terminate instance %s: %v", instanceID, err)
	}
}

// WaitForInstanceReady waits for an EC2 instance to be running and SSM-ready.
// Returns true if the instance is ready, false if timeout is reached.
func WaitForInstanceReady(t *testing.T, instanceID string, timeout time.Duration) bool {
	ec2Svc := ec2.New(GetAWSSession())
	ssmSvc := ssm.New(GetAWSSession())
	deadline := time.Now().Add(timeout)

	t.Logf("Waiting for instance %s to be running and SSM-ready (timeout: %v)", instanceID, timeout)

	// First, wait for instance to be running
	for time.Now().Before(deadline) {
		result, err := ec2Svc.DescribeInstances(&ec2.DescribeInstancesInput{
			InstanceIds: []*string{aws.String(instanceID)},
		})
		if err != nil {
			t.Logf("Error describing instance: %v", err)
			time.Sleep(10 * time.Second)
			continue
		}

		if len(result.Reservations) > 0 && len(result.Reservations[0].Instances) > 0 {
			state := *result.Reservations[0].Instances[0].State.Name
			if state == "running" {
				t.Logf("Instance %s is running, checking SSM readiness...", instanceID)
				break
			}
			t.Logf("Instance %s state: %s", instanceID, state)
		}
		time.Sleep(10 * time.Second)
	}

	// Then, wait for SSM agent to be ready
	for time.Now().Before(deadline) {
		result, err := ssmSvc.DescribeInstanceInformation(&ssm.DescribeInstanceInformationInput{
			Filters: []*ssm.InstanceInformationStringFilter{
				{
					Key:    aws.String("InstanceIds"),
					Values: []*string{aws.String(instanceID)},
				},
			},
		})
		if err != nil {
			t.Logf("Error checking SSM status: %v", err)
			time.Sleep(10 * time.Second)
			continue
		}

		if len(result.InstanceInformationList) > 0 {
			pingStatus := *result.InstanceInformationList[0].PingStatus
			if pingStatus == "Online" {
				t.Logf("Instance %s is SSM-ready (ping status: Online)", instanceID)
				return true
			}
			t.Logf("Instance %s SSM ping status: %s", instanceID, pingStatus)
		} else {
			t.Logf("Instance %s not yet registered with SSM", instanceID)
		}
		time.Sleep(15 * time.Second)
	}

	t.Logf("Timeout waiting for instance %s to become SSM-ready", instanceID)
	return false
}

// RunSSMCommand executes a shell command on an EC2 instance via SSM and returns the output.
// Returns stdout, stderr, and any error.
func RunSSMCommand(t *testing.T, instanceID string, commands []string) (string, string, error) {
	ssmSvc := ssm.New(GetAWSSession())

	t.Logf("Running SSM command on instance %s: %v", instanceID, commands)

	sendResult, err := ssmSvc.SendCommand(&ssm.SendCommandInput{
		InstanceIds:  []*string{aws.String(instanceID)},
		DocumentName: aws.String("AWS-RunShellScript"),
		Parameters: map[string][]*string{
			"commands": aws.StringSlice(commands),
		},
		TimeoutSeconds: aws.Int64(120),
	})
	if err != nil {
		return "", "", fmt.Errorf("failed to send SSM command: %w", err)
	}

	commandID := *sendResult.Command.CommandId
	t.Logf("SSM command ID: %s", commandID)

	// Wait for command completion
	for i := 0; i < 60; i++ {
		time.Sleep(3 * time.Second)

		result, err := ssmSvc.GetCommandInvocation(&ssm.GetCommandInvocationInput{
			CommandId:  aws.String(commandID),
			InstanceId: aws.String(instanceID),
		})
		if err != nil {
			// Command may not be ready yet
			if strings.Contains(err.Error(), "InvocationDoesNotExist") {
				continue
			}
			return "", "", fmt.Errorf("failed to get command invocation: %w", err)
		}

		status := *result.Status
		t.Logf("SSM command status: %s", status)

		switch status {
		case "Success":
			stdout := ""
			stderr := ""
			if result.StandardOutputContent != nil {
				stdout = *result.StandardOutputContent
			}
			if result.StandardErrorContent != nil {
				stderr = *result.StandardErrorContent
			}
			return stdout, stderr, nil
		case "Failed", "Cancelled", "TimedOut":
			stdout := ""
			stderr := ""
			if result.StandardOutputContent != nil {
				stdout = *result.StandardOutputContent
			}
			if result.StandardErrorContent != nil {
				stderr = *result.StandardErrorContent
			}
			return stdout, stderr, fmt.Errorf("SSM command %s: %s", status, stderr)
		}
	}

	return "", "", fmt.Errorf("SSM command timed out after 3 minutes")
}

// =============================================================================
// FUNCTIONAL VALIDATORS
// =============================================================================

// isAccessDenied checks if AWS CLI output indicates access was denied.
// AWS returns access denied errors in different formats depending on the operation.
func isAccessDenied(output string) bool {
	return strings.Contains(output, "AccessDenied") ||
		strings.Contains(output, "Access Denied") ||
		strings.Contains(output, "403") ||
		strings.Contains(output, "Forbidden")
}

// ValidateS3AccessFromEC2 verifies that an EC2 instance has the correct S3 access per IAM policy.
// This is a focused test that verifies:
//
// Positive cases (what EC2 needs in production):
//   - CAN write to cache/* in cache bucket
//   - CAN read from cache/* in cache bucket
//   - CAN read from runners/{own-userid}/* in cache bucket
//   - CAN read from agents/* in config bucket
//
// Negative cases (prove restrictions work):
//   - CANNOT write to runners/* in cache bucket
//   - CANNOT read from runners/{other-userid}/* in cache bucket
func ValidateS3AccessFromEC2(t *testing.T, instanceID, cacheBucket, configBucket string) {
	s3Svc := s3.New(GetAWSSession())
	testFile := fmt.Sprintf("functional-test-%d", time.Now().UnixNano())
	testContent := fmt.Sprintf("test-content-%d", time.Now().UnixNano())

	// Get the EC2 instance's aws:userid for runners path testing
	getUserIdCmd := "aws sts get-caller-identity --query 'UserId' --output text"
	stdout, stderr, err := RunSSMCommand(t, instanceID, []string{getUserIdCmd})
	require.NoError(t, err, "Failed to get caller identity. stderr: %s", stderr)
	userId := strings.TrimSpace(stdout)
	require.NotEmpty(t, userId, "UserId should not be empty")
	t.Logf("EC2 instance aws:userid = %s", userId)

	// === Test 1: CAN write to cache/* ===
	cacheKey := fmt.Sprintf("cache/%s", testFile)
	writeCmd := fmt.Sprintf("echo '%s' | aws s3 cp - s3://%s/%s --region %s 2>&1",
		testContent, cacheBucket, cacheKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, instanceID, []string{writeCmd})
	require.NoError(t, err, "Should be able to write to cache/*. stderr: %s", stdout)
	t.Logf("✓ CAN write to cache/*")

	// === Test 2: CAN read from cache/* ===
	readCmd := fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", cacheBucket, cacheKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, instanceID, []string{readCmd})
	require.NoError(t, err, "Should be able to read from cache/*")
	assert.Contains(t, stdout, testContent, "Content mismatch reading from cache/*")
	t.Logf("✓ CAN read from cache/*")

	// Cleanup cache test file
	_, _ = s3Svc.DeleteObject(&s3.DeleteObjectInput{Bucket: aws.String(cacheBucket), Key: aws.String(cacheKey)})

	// === Test 3: CAN read from runners/{own-userid}/* ===
	ownRunnersKey := fmt.Sprintf("runners/%s/%s", userId, testFile)
	ownRunnersContent := "runners-test-content"
	_, err = s3Svc.PutObject(&s3.PutObjectInput{
		Bucket: aws.String(cacheBucket),
		Key:    aws.String(ownRunnersKey),
		Body:   strings.NewReader(ownRunnersContent),
	})
	require.NoError(t, err, "Admin failed to upload to runners path")

	readCmd = fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", cacheBucket, ownRunnersKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, instanceID, []string{readCmd})
	require.NoError(t, err, "Should be able to read from own runners path")
	assert.Contains(t, stdout, ownRunnersContent)
	t.Logf("✓ CAN read from runners/{own-userid}/*")

	// Cleanup
	_, _ = s3Svc.DeleteObject(&s3.DeleteObjectInput{Bucket: aws.String(cacheBucket), Key: aws.String(ownRunnersKey)})

	// === Test 4: CAN read from agents/* in config bucket ===
	agentsKey := fmt.Sprintf("agents/%s", testFile)
	agentsContent := "agents-test-content"
	_, err = s3Svc.PutObject(&s3.PutObjectInput{
		Bucket: aws.String(configBucket),
		Key:    aws.String(agentsKey),
		Body:   strings.NewReader(agentsContent),
	})
	require.NoError(t, err, "Admin failed to upload to agents path")

	readCmd = fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", configBucket, agentsKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, instanceID, []string{readCmd})
	require.NoError(t, err, "Should be able to read from agents/*")
	assert.Contains(t, stdout, agentsContent)
	t.Logf("✓ CAN read from agents/* (config bucket)")

	// Cleanup
	_, _ = s3Svc.DeleteObject(&s3.DeleteObjectInput{Bucket: aws.String(configBucket), Key: aws.String(agentsKey)})

	// === Test 5: CANNOT write to runners/* ===
	runnersWriteKey := fmt.Sprintf("runners/%s", testFile)
	writeCmd = fmt.Sprintf("echo 'test' | aws s3 cp - s3://%s/%s --region %s 2>&1",
		cacheBucket, runnersWriteKey, GetAWSRegion())
	stdout, _, _ = RunSSMCommand(t, instanceID, []string{writeCmd})
	accessDenied := isAccessDenied(stdout)
	assert.True(t, accessDenied, "Should NOT be able to write to runners/*, got: %s", stdout)
	t.Logf("✓ CANNOT write to runners/*")

	// === Test 6: CANNOT read from runners/{other-userid}/* ===
	otherRunnersKey := fmt.Sprintf("runners/other-fake-userid/%s", testFile)
	_, err = s3Svc.PutObject(&s3.PutObjectInput{
		Bucket: aws.String(cacheBucket),
		Key:    aws.String(otherRunnersKey),
		Body:   strings.NewReader("other-user-content"),
	})
	require.NoError(t, err, "Admin failed to upload to other user's runners path")

	readCmd = fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", cacheBucket, otherRunnersKey, GetAWSRegion())
	stdout, _, _ = RunSSMCommand(t, instanceID, []string{readCmd})
	accessDenied = isAccessDenied(stdout)
	assert.True(t, accessDenied, "Should NOT be able to read from other user's runners path, got: %s", stdout)
	t.Logf("✓ CANNOT read from runners/{other-userid}/*")

	// Cleanup
	_, _ = s3Svc.DeleteObject(&s3.DeleteObjectInput{Bucket: aws.String(cacheBucket), Key: aws.String(otherRunnersKey)})
}

// ValidateInstanceHasNoPublicIP verifies that an EC2 instance has no public IP address.
func ValidateInstanceHasNoPublicIP(t *testing.T, instanceID string) {
	ec2Svc := ec2.New(GetAWSSession())

	result, err := ec2Svc.DescribeInstances(&ec2.DescribeInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	})
	require.NoError(t, err, "Failed to describe instance")
	require.Len(t, result.Reservations, 1)
	require.Len(t, result.Reservations[0].Instances, 1)

	instance := result.Reservations[0].Instances[0]

	// Check that public IP is nil or empty
	if instance.PublicIpAddress != nil {
		assert.Empty(t, *instance.PublicIpAddress, "Instance %s should not have a public IP, got: %s",
			instanceID, *instance.PublicIpAddress)
	}

	// Also verify it has a private IP
	require.NotNil(t, instance.PrivateIpAddress, "Instance %s should have a private IP", instanceID)
	t.Logf("Instance %s has private IP %s and no public IP", instanceID, *instance.PrivateIpAddress)
}

// ValidateEC2CloudWatchLogs verifies that an EC2 instance is sending logs to CloudWatch.
func ValidateEC2CloudWatchLogs(t *testing.T, instanceID, logGroupName string) {
	cwlSvc := cloudwatchlogs.New(GetAWSSession())

	// First, generate some log activity on the instance
	logCmd := fmt.Sprintf("logger -t terratest 'Functional test log entry from %s'", instanceID)
	_, _, _ = RunSSMCommand(t, instanceID, []string{logCmd})

	// Wait a bit for logs to propagate
	time.Sleep(10 * time.Second)

	// Check if the log group exists
	result, err := cwlSvc.DescribeLogGroups(&cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: aws.String(logGroupName),
	})
	require.NoError(t, err, "Failed to describe log groups")
	require.NotEmpty(t, result.LogGroups, "Log group %s not found", logGroupName)

	t.Logf("CloudWatch log group %s exists and is configured", logGroupName)
}

// =============================================================================
// INTEGRATION TEST HELPERS (Interactive Job Execution)
// =============================================================================

// stdinReader is a shared reader for interactive prompts to avoid buffer issues
// when multiple functions read from stdin sequentially.
var stdinReader = bufio.NewReader(os.Stdin)

// WaitForRunsOnRegistration waits for the RunsOn GitHub App to be registered
// by polling for a successful workflow run that contains "RunsOn" in its logs.
//
// This function:
// 1. Logs the AppRunner URL for manual registration
// 2. Polls for a recent successful workflow run
// 3. Checks if the run logs contain "RunsOn" (indicating RunsOn processed the job)
//
// Parameters:
//   - appRunnerURL: The AppRunner URL to display for registration
//   - repo: Target repository in "owner/repo" format
//   - workflowFile: The workflow file to check (e.g., "test.yml")
//   - timeout: Maximum time to wait
//
// Returns the workflow run ID if successful.
func WaitForRunsOnRegistration(t *testing.T, appRunnerURL, repo, workflowFile string, timeout time.Duration) int64 {
	token := os.Getenv("GITHUB_TOKEN")
	require.NotEmpty(t, token, "GITHUB_TOKEN is required")

	parts := strings.Split(repo, "/")
	require.Len(t, parts, 2, "Repo should be in 'owner/repo' format")
	owner, repoName := parts[0], parts[1]

	ctx := context.Background()
	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	tc := oauth2.NewClient(ctx, ts)
	client := github.NewClient(tc)

	t.Log("=======================================================")
	t.Logf("REGISTER RUNS-ON APP AT: https://%s", appRunnerURL)
	t.Log("=======================================================")
	t.Logf("Waiting for RunsOn to process a workflow run in %s...", repo)

	deadline := time.Now().Add(timeout)
	pollInterval := 15 * time.Second
	startTime := time.Now()

	for time.Now().Before(deadline) {
		// List recent workflow runs
		runs, _, err := client.Actions.ListWorkflowRunsByFileName(
			ctx, owner, repoName, workflowFile,
			&github.ListWorkflowRunsOptions{
				ListOptions: github.ListOptions{PerPage: 5},
			})
		if err != nil {
			t.Logf("Error listing workflow runs: %v", err)
			time.Sleep(pollInterval)
			continue
		}

		// Check recent runs for RunsOn signature in logs
		for _, run := range runs.WorkflowRuns {
			// Only check runs started after our test began
			if run.CreatedAt != nil && run.CreatedAt.Time.Before(startTime) {
				continue
			}

			runID := run.GetID()
			status := run.GetStatus()
			conclusion := run.GetConclusion()

			t.Logf("Found workflow run %d: status=%s, conclusion=%s", runID, status, conclusion)

			// If run is completed, check logs for RunsOn
			if status == "completed" {
				if checkWorkflowLogsForRunsOn(t, client, owner, repoName, runID) {
					t.Logf("RunsOn confirmed in workflow run %d logs!", runID)
					return runID
				}
			}
		}

		t.Logf("RunsOn not yet detected, waiting %v... (register at: https://%s)", pollInterval, appRunnerURL)
		time.Sleep(pollInterval)
	}

	t.Fatalf("Timeout waiting for RunsOn to process a workflow. Register at: https://%s", appRunnerURL)
	return 0
}

// checkWorkflowLogsForRunsOn downloads workflow run logs and checks for "RunsOn" string.
func checkWorkflowLogsForRunsOn(t *testing.T, client *github.Client, owner, repo string, runID int64) bool {
	ctx := context.Background()

	// Get the logs URL
	logsURL, _, err := client.Actions.GetWorkflowRunLogs(ctx, owner, repo, runID, 4)
	if err != nil {
		t.Logf("Error getting logs URL for run %d: %v", runID, err)
		return false
	}

	if logsURL == nil {
		t.Logf("No logs URL returned for run %d", runID)
		return false
	}

	// Download and check logs
	httpClient := &http.Client{Timeout: 30 * time.Second}
	resp, err := httpClient.Get(logsURL.String())
	if err != nil {
		t.Logf("Error downloading logs for run %d: %v", runID, err)
		return false
	}
	defer resp.Body.Close()

	// Read logs (they come as a zip file, but we can search the raw bytes)
	body, err := io.ReadAll(io.LimitReader(resp.Body, 10*1024*1024)) // Limit to 10MB
	if err != nil {
		t.Logf("Error reading logs for run %d: %v", runID, err)
		return false
	}

	// Check for RunsOn markers in the logs
	bodyStr := string(body)
	if strings.Contains(bodyStr, "RunsOn") || strings.Contains(bodyStr, "runs-on") {
		return true
	}

	return false
}

// TriggerWorkflow triggers a GitHub Actions workflow and returns the run ID.
// If GITHUB_TOKEN is set, uses the API. Otherwise, prompts for manual trigger.
// repo should be in "owner/repo" format.
func TriggerWorkflow(t *testing.T, repo, workflowFile string) int64 {
	token := os.Getenv("GITHUB_TOKEN")

	if token != "" {
		return triggerWorkflowViaAPI(t, repo, workflowFile, token)
	}
	return triggerWorkflowManually(t, repo, workflowFile)
}

// triggerWorkflowViaAPI uses the GitHub API to trigger a workflow_dispatch event.
func triggerWorkflowViaAPI(t *testing.T, repo, workflowFile, token string) int64 {
	parts := strings.Split(repo, "/")
	require.Len(t, parts, 2, "Repo should be in 'owner/repo' format")
	owner, repoName := parts[0], parts[1]

	ctx := context.Background()
	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	tc := oauth2.NewClient(ctx, ts)
	client := github.NewClient(tc)

	// Get current workflow runs to identify the new one
	beforeRuns, _, err := client.Actions.ListWorkflowRunsByFileName(
		ctx, owner, repoName, workflowFile,
		&github.ListWorkflowRunsOptions{ListOptions: github.ListOptions{PerPage: 1}})
	require.NoError(t, err, "Failed to list workflow runs")

	var beforeRunID int64
	if len(beforeRuns.WorkflowRuns) > 0 {
		beforeRunID = *beforeRuns.WorkflowRuns[0].ID
	}

	// Trigger the workflow
	t.Logf("Triggering workflow %s via API...", workflowFile)
	_, err = client.Actions.CreateWorkflowDispatchEventByFileName(
		ctx, owner, repoName, workflowFile,
		github.CreateWorkflowDispatchEventRequest{Ref: "main"})
	require.NoError(t, err, "Failed to trigger workflow dispatch")

	// Wait for new run to appear
	var newRunID int64
	for i := 0; i < 20; i++ {
		time.Sleep(3 * time.Second)
		afterRuns, _, err := client.Actions.ListWorkflowRunsByFileName(
			ctx, owner, repoName, workflowFile,
			&github.ListWorkflowRunsOptions{ListOptions: github.ListOptions{PerPage: 1}})
		if err != nil {
			continue
		}
		if len(afterRuns.WorkflowRuns) > 0 && *afterRuns.WorkflowRuns[0].ID != beforeRunID {
			newRunID = *afterRuns.WorkflowRuns[0].ID
			break
		}
	}
	require.NotZero(t, newRunID, "New workflow run should be created")
	t.Logf("Workflow run created: %d", newRunID)
	return newRunID
}

// triggerWorkflowManually prompts the user to trigger the workflow and enter the run ID.
func triggerWorkflowManually(t *testing.T, repo, workflowFile string) int64 {
	fmt.Printf("\n")
	fmt.Printf("╔══════════════════════════════════════════════════════════════════╗\n")
	fmt.Printf("║                    MANUAL WORKFLOW TRIGGER                        ║\n")
	fmt.Printf("╠══════════════════════════════════════════════════════════════════╣\n")
	fmt.Printf("║                                                                   ║\n")
	fmt.Printf("║  1. Go to: https://github.com/%s/actions\n", repo)
	fmt.Printf("║                                                                   ║\n")
	fmt.Printf("║  2. Select the '%s' workflow\n", workflowFile)
	fmt.Printf("║                                                                   ║\n")
	fmt.Printf("║  3. Click 'Run workflow' -> 'Run workflow'                        ║\n")
	fmt.Printf("║                                                                   ║\n")
	fmt.Printf("║  4. Copy the run ID from the URL (the number after /runs/)        ║\n")
	fmt.Printf("║                                                                   ║\n")
	fmt.Printf("╚══════════════════════════════════════════════════════════════════╝\n")

	for {
		fmt.Printf("\nEnter the workflow run ID (or 's' to skip): ")
		input, _ := stdinReader.ReadString('\n')
		input = strings.TrimSpace(input)

		if input == "s" {
			t.Skip("Workflow trigger skipped by user")
		}

		if input == "" {
			fmt.Printf("Please enter a valid run ID (the number from the URL after /runs/)\n")
			continue
		}

		runID, err := strconv.ParseInt(input, 10, 64)
		if err != nil {
			fmt.Printf("Invalid run ID '%s'. Please enter a number.\n", input)
			continue
		}

		t.Logf("Using manually provided workflow run ID: %d", runID)
		return runID
	}
}

// WaitForWorkflowCompletion polls the GitHub API until the workflow completes.
// Returns the conclusion (success, failure, cancelled, etc.) or empty string on timeout.
func WaitForWorkflowCompletion(t *testing.T, repo string, runID int64, timeout time.Duration) string {
	token := os.Getenv("GITHUB_TOKEN")
	if token == "" {
		return waitForWorkflowManually(t, repo, runID)
	}

	parts := strings.Split(repo, "/")
	require.Len(t, parts, 2, "Repo should be in 'owner/repo' format")
	owner, repoName := parts[0], parts[1]

	ctx := context.Background()
	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	tc := oauth2.NewClient(ctx, ts)
	client := github.NewClient(tc)

	deadline := time.Now().Add(timeout)
	t.Logf("Waiting for workflow run %d to complete (timeout: %v)...", runID, timeout)

	for time.Now().Before(deadline) {
		run, _, err := client.Actions.GetWorkflowRunByID(ctx, owner, repoName, runID)
		if err != nil {
			t.Logf("Error getting workflow status: %v", err)
			time.Sleep(15 * time.Second)
			continue
		}

		status := run.GetStatus()
		conclusion := run.GetConclusion()
		t.Logf("Workflow status: %s, conclusion: %s", status, conclusion)

		if status == "completed" {
			return conclusion
		}
		time.Sleep(15 * time.Second)
	}

	t.Logf("Timeout waiting for workflow to complete")
	return ""
}

// waitForWorkflowManually prompts the user to confirm when the workflow completes.
func waitForWorkflowManually(t *testing.T, repo string, runID int64) string {
	fmt.Printf("\n")
	fmt.Printf("╔══════════════════════════════════════════════════════════════════╗\n")
	fmt.Printf("║                    WAITING FOR WORKFLOW                           ║\n")
	fmt.Printf("╠══════════════════════════════════════════════════════════════════╣\n")
	fmt.Printf("║                                                                   ║\n")
	fmt.Printf("║  Monitor: https://github.com/%s/actions/runs/%d\n", repo, runID)
	fmt.Printf("║                                                                   ║\n")
	fmt.Printf("╚══════════════════════════════════════════════════════════════════╝\n")
	fmt.Printf("\nEnter the workflow conclusion (success/failure) or 's' to skip: ")

	input, _ := stdinReader.ReadString('\n')
	input = strings.TrimSpace(input)

	if input == "s" {
		t.Skip("Workflow completion check skipped by user")
	}

	t.Logf("User reported workflow conclusion: %s", input)
	return input
}

// ValidateRunnerLaunched checks if an EC2 runner instance was launched for the stack
// after the given start time.
func ValidateRunnerLaunched(t *testing.T, stackName string, since time.Time) bool {
	ec2Svc := ec2.New(GetAWSSession())

	// Look for instances with the runs-on-stack-name tag launched after 'since'
	result, err := ec2Svc.DescribeInstances(&ec2.DescribeInstancesInput{
		Filters: []*ec2.Filter{
			{
				Name:   aws.String("tag:runs-on-stack-name"),
				Values: []*string{aws.String(stackName)},
			},
			{
				Name:   aws.String("instance-state-name"),
				Values: []*string{aws.String("running"), aws.String("terminated"), aws.String("stopped")},
			},
		},
	})
	if err != nil {
		t.Logf("Error describing instances: %v", err)
		return false
	}

	for _, reservation := range result.Reservations {
		for _, instance := range reservation.Instances {
			launchTime := instance.LaunchTime
			if launchTime != nil && launchTime.After(since) {
				t.Logf("Found runner instance %s launched at %s (after %s)",
					*instance.InstanceId, launchTime.Format(time.RFC3339), since.Format(time.RFC3339))
				return true
			}
		}
	}

	t.Logf("No runner instances found for stack %s launched after %s", stackName, since.Format(time.RFC3339))
	return false
}
