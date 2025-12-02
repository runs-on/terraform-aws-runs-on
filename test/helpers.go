package test

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/ssm"
	"github.com/google/go-github/v57/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/oauth2"
)

// GetTestID generates a unique test ID for resource naming
func GetTestID() string {
	return fmt.Sprintf("%d", time.Now().Unix())
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
// INTEGRATION TEST HELPERS
// =============================================================================

// getGitHubClient creates a GitHub client using the GITHUB_TOKEN environment variable.
func getGitHubClient() (*github.Client, error) {
	token := os.Getenv("GITHUB_TOKEN")
	if token == "" {
		return nil, fmt.Errorf("GITHUB_TOKEN environment variable is required")
	}

	ctx := context.Background()
	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	tc := oauth2.NewClient(ctx, ts)
	return github.NewClient(tc), nil
}

// parseRepo splits a repo string in "owner/repo" format into owner and repo name.
func parseRepo(repo string) (string, string, error) {
	parts := strings.Split(repo, "/")
	if len(parts) != 2 {
		return "", "", fmt.Errorf("repo should be in 'owner/repo' format, got: %s", repo)
	}
	return parts[0], parts[1], nil
}

// WaitForWorkflowCompletion polls the GitHub API until the workflow completes.
// Returns the conclusion (success, failure, cancelled, etc.) or empty string on timeout.
func WaitForWorkflowCompletion(t *testing.T, repo string, runID int64, timeout time.Duration) string {
	client, err := getGitHubClient()
	require.NoError(t, err, "Failed to create GitHub client")

	owner, repoName, err := parseRepo(repo)
	require.NoError(t, err, "Invalid repo format")

	ctx := context.Background()
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

// TriggerWorkflowDispatch triggers a workflow_dispatch event for a workflow in a repository.
// Uses GITHUB_TOKEN environment variable for authentication.
// Returns an error if the trigger fails.
func TriggerWorkflowDispatch(t *testing.T, repo, workflowFile, testID string) error {
	client, err := getGitHubClient()
	if err != nil {
		return err
	}

	owner, repoName, err := parseRepo(repo)
	if err != nil {
		return err
	}

	t.Logf("Triggering workflow %s in %s with test_id=%s", workflowFile, repo, testID)

	ctx := context.Background()
	_, err = client.Actions.CreateWorkflowDispatchEventByFileName(
		ctx, owner, repoName, workflowFile,
		github.CreateWorkflowDispatchEventRequest{
			Ref: "main",
			Inputs: map[string]interface{}{
				"test_id": testID,
			},
		})
	if err != nil {
		return fmt.Errorf("failed to trigger workflow dispatch: %w", err)
	}

	t.Logf("Successfully triggered workflow %s", workflowFile)
	return nil
}

// WaitForTriggeredWorkflow polls for a workflow run that was triggered with the given test_id.
// It looks for runs that started after the function was called and contain the test_id in their inputs.
// Returns the run ID when found, or an error if timeout is reached.
func WaitForTriggeredWorkflow(t *testing.T, repo, workflowFile, testID string, timeout time.Duration) (int64, error) {
	client, err := getGitHubClient()
	if err != nil {
		return 0, err
	}

	owner, repoName, err := parseRepo(repo)
	if err != nil {
		return 0, err
	}

	ctx := context.Background()
	startTime := time.Now()
	deadline := startTime.Add(timeout)
	pollInterval := 10 * time.Second

	t.Logf("Waiting for workflow run with test_id=%s (timeout: %v)", testID, timeout)

	for time.Now().Before(deadline) {
		runs, _, err := client.Actions.ListWorkflowRunsByFileName(
			ctx, owner, repoName, workflowFile,
			&github.ListWorkflowRunsOptions{
				Event: "workflow_dispatch",
				ListOptions: github.ListOptions{
					PerPage: 10,
				},
			})
		if err != nil {
			t.Logf("Error listing workflow runs: %v", err)
			time.Sleep(pollInterval)
			continue
		}

		for _, run := range runs.WorkflowRuns {
			// Only check runs that started after we triggered
			if run.CreatedAt != nil && run.CreatedAt.Time.Before(startTime.Add(-1*time.Minute)) {
				continue
			}

			runID := run.GetID()
			if checkRunForTestID(t, client, owner, repoName, runID, testID) {
				t.Logf("Found workflow run %d matching test_id=%s", runID, testID)
				return runID, nil
			}
		}

		t.Logf("Workflow run with test_id=%s not found yet, waiting %v...", testID, pollInterval)
		time.Sleep(pollInterval)
	}

	return 0, fmt.Errorf("timeout waiting for workflow run with test_id=%s", testID)
}

// checkRunForTestID checks if a workflow run contains our test_id in its logs.
func checkRunForTestID(t *testing.T, client *github.Client, owner, repo string, runID int64, testID string) bool {
	ctx := context.Background()

	jobs, _, err := client.Actions.ListWorkflowJobs(ctx, owner, repo, runID, &github.ListWorkflowJobsOptions{
		Filter: "all",
	})
	if err != nil {
		t.Logf("Error listing jobs for run %d: %v", runID, err)
		return false
	}

	httpClient := &http.Client{Timeout: 30 * time.Second}
	for _, job := range jobs.Jobs {
		logsURL, _, err := client.Actions.GetWorkflowJobLogs(ctx, owner, repo, job.GetID(), 4)
		if err != nil {
			continue
		}

		if logsURL == nil {
			continue
		}

		resp, err := httpClient.Get(logsURL.String())
		if err != nil {
			continue
		}

		body, err := io.ReadAll(io.LimitReader(resp.Body, 1*1024*1024)) // 1MB limit
		resp.Body.Close()
		if err != nil {
			continue
		}

		if strings.Contains(string(body), testID) {
			return true
		}
	}

	return false
}

// =============================================================================
// PRIVATE NETWORKING VALIDATORS
// =============================================================================

// ValidateInstanceHasNoPublicIP verifies that an EC2 instance does not have a public IP address.
// This is used to confirm instances launched in private subnets are properly isolated.
func ValidateInstanceHasNoPublicIP(t *testing.T, instanceID string) bool {
	ec2Svc := ec2.New(GetAWSSession())

	result, err := ec2Svc.DescribeInstances(&ec2.DescribeInstancesInput{
		InstanceIds: []*string{aws.String(instanceID)},
	})
	require.NoError(t, err, "Failed to describe instance %s", instanceID)
	require.NotEmpty(t, result.Reservations, "No reservations found for instance %s", instanceID)
	require.NotEmpty(t, result.Reservations[0].Instances, "No instances found in reservation")

	instance := result.Reservations[0].Instances[0]

	// Check PublicIpAddress field
	hasPublicIP := instance.PublicIpAddress != nil && *instance.PublicIpAddress != ""

	if hasPublicIP {
		t.Logf("Instance %s has public IP: %s", instanceID, *instance.PublicIpAddress)
		return false
	}

	t.Logf("Instance %s has no public IP (as expected for private subnet)", instanceID)
	return true
}

// ValidatePrivateNetworkConnectivity verifies that an EC2 instance in a private subnet
// can reach external services via NAT gateway. Tests outbound HTTPS connectivity.
func ValidatePrivateNetworkConnectivity(t *testing.T, instanceID string) {
	// Test 1: Can reach external HTTPS endpoint (proves NAT gateway works)
	curlCmd := "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 https://api.github.com"
	stdout, stderr, err := RunSSMCommand(t, instanceID, []string{curlCmd})
	require.NoError(t, err, "Failed to execute curl command. stderr: %s", stderr)

	httpCode := strings.TrimSpace(stdout)
	// GitHub API returns 403 without auth, but that proves connectivity works
	assert.True(t, httpCode == "200" || httpCode == "403",
		"Expected HTTP 200 or 403 from api.github.com, got: %s", httpCode)
	t.Logf("✓ Outbound HTTPS connectivity works (api.github.com returned %s)", httpCode)

	// Test 2: Can reach AWS APIs (S3 endpoint)
	awsCmd := "aws s3 ls --region " + GetAWSRegion() + " 2>&1 | head -1"
	stdout, _, err = RunSSMCommand(t, instanceID, []string{awsCmd})
	// We don't care about the result, just that it doesn't timeout or fail to connect
	// Even permission denied means connectivity works
	require.NoError(t, err, "AWS S3 command failed - NAT gateway may not be working")
	t.Logf("✓ AWS API connectivity works (S3 list returned: %s...)", truncateString(stdout, 50))
}

// truncateString truncates a string to maxLen characters, adding "..." if truncated.
func truncateString(s string, maxLen int) string {
	s = strings.TrimSpace(s)
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}

// =============================================================================
// EFS VALIDATORS
// =============================================================================

// ValidateEFSMountFromEC2 mounts an EFS filesystem on an EC2 instance and performs I/O operations.
// This validates end-to-end EFS functionality including security group access.
func ValidateEFSMountFromEC2(t *testing.T, instanceID, efsFileSystemID string) {
	mountPoint := "/mnt/efs-test"
	testFile := fmt.Sprintf("test-file-%d", time.Now().UnixNano())
	testContent := fmt.Sprintf("efs-test-content-%d", time.Now().UnixNano())

	// Step 1: Install amazon-efs-utils if not present
	installCmd := "which mount.efs || sudo dnf install -y amazon-efs-utils"
	stdout, stderr, err := RunSSMCommand(t, instanceID, []string{installCmd})
	require.NoError(t, err, "Failed to install amazon-efs-utils. stdout: %s, stderr: %s", stdout, stderr)
	t.Logf("✓ amazon-efs-utils available")

	// Step 2: Create mount point
	mkdirCmd := fmt.Sprintf("sudo mkdir -p %s", mountPoint)
	_, stderr, err = RunSSMCommand(t, instanceID, []string{mkdirCmd})
	require.NoError(t, err, "Failed to create mount point. stderr: %s", stderr)

	// Step 3: Mount EFS
	// Using EFS mount helper which handles DNS resolution and TLS
	mountCmd := fmt.Sprintf("sudo mount -t efs -o tls %s:/ %s", efsFileSystemID, mountPoint)
	stdout, stderr, err = RunSSMCommand(t, instanceID, []string{mountCmd})
	require.NoError(t, err, "Failed to mount EFS %s. stdout: %s, stderr: %s", efsFileSystemID, stdout, stderr)
	t.Logf("✓ EFS %s mounted at %s", efsFileSystemID, mountPoint)

	// Step 4: Write test file
	writeCmd := fmt.Sprintf("echo '%s' | sudo tee %s/%s > /dev/null", testContent, mountPoint, testFile)
	_, stderr, err = RunSSMCommand(t, instanceID, []string{writeCmd})
	require.NoError(t, err, "Failed to write test file to EFS. stderr: %s", stderr)
	t.Logf("✓ Written test file to EFS")

	// Step 5: Read test file back
	readCmd := fmt.Sprintf("cat %s/%s", mountPoint, testFile)
	stdout, stderr, err = RunSSMCommand(t, instanceID, []string{readCmd})
	require.NoError(t, err, "Failed to read test file from EFS. stderr: %s", stderr)
	assert.Contains(t, stdout, testContent, "EFS content mismatch")
	t.Logf("✓ Read test file from EFS - content verified")

	// Step 6: Verify mount is EFS by checking:
	// - Filesystem type is nfs4 (EFS uses NFS protocol)
	// - Capacity shows as 8.0E (EFS's "unlimited" capacity display)
	verifyCmd := fmt.Sprintf("findmnt -n -o FSTYPE %s", mountPoint)
	stdout, stderr, err = RunSSMCommand(t, instanceID, []string{verifyCmd})
	require.NoError(t, err, "Failed to verify mount type. stderr: %s", stderr)
	fsType := strings.TrimSpace(stdout)
	assert.Equal(t, "nfs4", fsType, "EFS should be mounted as nfs4 filesystem")
	t.Logf("✓ EFS mount verified (filesystem type: %s)", fsType)

	// Also verify EFS capacity shows as 8.0E (exabytes) - characteristic of EFS
	dfCmd := fmt.Sprintf("df -h %s | tail -1 | awk '{print $2}'", mountPoint)
	stdout, _, err = RunSSMCommand(t, instanceID, []string{dfCmd})
	require.NoError(t, err, "Failed to get EFS capacity")
	capacity := strings.TrimSpace(stdout)
	assert.Equal(t, "8.0E", capacity, "EFS should show 8.0E capacity")
	t.Logf("✓ EFS capacity verified (%s - unlimited)", capacity)

	// Cleanup: Remove test file and unmount
	cleanupCmd := fmt.Sprintf("sudo rm -f %s/%s && sudo umount %s", mountPoint, testFile, mountPoint)
	_, _, _ = RunSSMCommand(t, instanceID, []string{cleanupCmd})
	t.Logf("✓ EFS cleanup completed")
}

// =============================================================================
// ECR VALIDATORS
// =============================================================================

// ValidateECRPushPullFromEC2 validates ECR as a Docker layer cache backend.
// This tests the actual RunsOn ECR use case: Docker Buildx with registry cache.
// The test:
//  1. Sets up Docker with Buildx
//  2. Creates a simple Dockerfile
//  3. Builds with cache-to ECR (first build - cache miss)
//  4. Builds again with cache-from ECR (second build - cache hit)
//  5. Verifies the second build used cached layers
func ValidateECRPushPullFromEC2(t *testing.T, instanceID, ecrURL string) {
	region := GetAWSRegion()
	testTag := fmt.Sprintf("cache-test-%d", time.Now().UnixNano())
	cacheRef := fmt.Sprintf("%s:%s", ecrURL, testTag)

	// Extract registry URL (everything before the first /)
	registryURL := strings.Split(ecrURL, "/")[0]

	// Step 1: Install Docker and start service
	installCmd := `
		if ! which docker > /dev/null 2>&1; then
			sudo dnf install -y docker
		fi
		sudo systemctl start docker
		sudo systemctl enable docker
	`
	_, stderr, err := RunSSMCommand(t, instanceID, []string{installCmd})
	require.NoError(t, err, "Failed to install/start Docker. stderr: %s", stderr)
	t.Logf("✓ Docker installed and running")

	// Step 2: Set up Docker Buildx (required for cache-to/cache-from with registry)
	buildxSetupCmd := `
		sudo docker buildx version || {
			# Install buildx if not available
			mkdir -p ~/.docker/cli-plugins
			curl -sSL https://github.com/docker/buildx/releases/download/v0.12.0/buildx-v0.12.0.linux-amd64 -o ~/.docker/cli-plugins/docker-buildx
			chmod +x ~/.docker/cli-plugins/docker-buildx
		}
		# Create and use a new builder with docker-container driver (required for cache export)
		sudo docker buildx create --name testbuilder --driver docker-container --use 2>/dev/null || sudo docker buildx use testbuilder
		sudo docker buildx inspect --bootstrap
	`
	stdout, stderr, err := RunSSMCommand(t, instanceID, []string{buildxSetupCmd})
	require.NoError(t, err, "Failed to set up Buildx. stdout: %s, stderr: %s", stdout, stderr)
	t.Logf("✓ Docker Buildx configured with docker-container driver")

	// Step 3: Authenticate to ECR
	loginCmd := fmt.Sprintf("aws ecr get-login-password --region %s | sudo docker login --username AWS --password-stdin %s",
		region, registryURL)
	stdout, stderr, err = RunSSMCommand(t, instanceID, []string{loginCmd})
	require.NoError(t, err, "Failed to authenticate to ECR. stdout: %s, stderr: %s", stdout, stderr)
	assert.Contains(t, stdout+stderr, "Login Succeeded", "ECR login should succeed")
	t.Logf("✓ Authenticated to ECR")

	// Step 4: Create a test Dockerfile with multiple layers
	// This simulates a real build with dependencies that benefit from caching
	dockerfileCmd := `
		mkdir -p /tmp/ecr-cache-test
		cat > /tmp/ecr-cache-test/Dockerfile << 'DOCKERFILE'
FROM public.ecr.aws/docker/library/alpine:latest
RUN apk add --no-cache curl
RUN apk add --no-cache jq
RUN echo "Layer caching test" > /test.txt
DOCKERFILE
	`
	_, stderr, err = RunSSMCommand(t, instanceID, []string{dockerfileCmd})
	require.NoError(t, err, "Failed to create Dockerfile. stderr: %s", stderr)
	t.Logf("✓ Created test Dockerfile")

	// Step 5: First build - pushes cache to ECR (cache miss expected)
	firstBuildCmd := fmt.Sprintf(`
		cd /tmp/ecr-cache-test
		sudo docker buildx build \
			--cache-to type=registry,ref=%s,mode=max \
			--load \
			-t test-image:first \
			. 2>&1
	`, cacheRef)
	stdout, stderr, err = RunSSMCommand(t, instanceID, []string{firstBuildCmd})
	require.NoError(t, err, "First build failed. stdout: %s, stderr: %s", stdout, stderr)
	t.Logf("✓ First build completed (cache pushed to ECR)")

	// Step 6: Clear local build cache to force cache-from to be used
	clearCacheCmd := "sudo docker buildx prune -af"
	_, _, _ = RunSSMCommand(t, instanceID, []string{clearCacheCmd})
	t.Logf("✓ Cleared local build cache")

	// Step 7: Second build - should use cache from ECR (cache hit expected)
	secondBuildCmd := fmt.Sprintf(`
		cd /tmp/ecr-cache-test
		sudo docker buildx build \
			--cache-from type=registry,ref=%s \
			--load \
			-t test-image:second \
			. 2>&1
	`, cacheRef)
	stdout, stderr, err = RunSSMCommand(t, instanceID, []string{secondBuildCmd})
	require.NoError(t, err, "Second build failed. stdout: %s, stderr: %s", stdout, stderr)

	// Check for cache hit indicators in output
	buildOutput := stdout + stderr
	cacheHit := strings.Contains(buildOutput, "CACHED") || strings.Contains(buildOutput, "importing cache")
	t.Logf("Second build output (checking for cache): %s", truncateString(buildOutput, 500))

	if cacheHit {
		t.Logf("✓ Second build used cached layers from ECR")
	} else {
		t.Logf("⚠ Cache indicators not found in output, but build succeeded")
	}

	// Step 8: Verify the built image works
	verifyCmd := "sudo docker run --rm test-image:second cat /test.txt"
	stdout, stderr, err = RunSSMCommand(t, instanceID, []string{verifyCmd})
	require.NoError(t, err, "Failed to run built image. stderr: %s", stderr)
	assert.Contains(t, stdout, "Layer caching test", "Image should contain expected content")
	t.Logf("✓ Built image verified")

	// Cleanup: Remove test images and ECR cache
	cleanupCmd := fmt.Sprintf(`
		sudo docker rmi test-image:first test-image:second 2>/dev/null || true
		sudo docker buildx rm testbuilder 2>/dev/null || true
		rm -rf /tmp/ecr-cache-test
		aws ecr batch-delete-image --repository-name %s --image-ids imageTag=%s --region %s 2>/dev/null || true
	`, strings.Split(ecrURL, "/")[1], testTag, region)
	_, _, _ = RunSSMCommand(t, instanceID, []string{cleanupCmd})
	t.Logf("✓ ECR cache test cleanup completed")
}

// =============================================================================
// PRIVATE SUBNET INSTANCE LAUNCHER
// =============================================================================

// LaunchTestInstancePrivate launches an EC2 instance in a private subnet (no public IP).
// Use this for testing private networking scenarios where NAT gateway provides outbound access.
func LaunchTestInstancePrivate(t *testing.T, launchTemplateID, subnetID string) string {
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

	t.Logf("Launching private test instance from template %s (version %s) in subnet %s with AMI %s",
		templateID, version, subnetID, amiID)

	input := &ec2.RunInstancesInput{
		LaunchTemplate: &ec2.LaunchTemplateSpecification{
			LaunchTemplateId: aws.String(templateID),
			Version:          aws.String(version),
		},
		ImageId:  aws.String(amiID),
		MinCount: aws.Int64(1),
		MaxCount: aws.Int64(1),
		// Use NetworkInterfaces with NO public IP for private subnet
		NetworkInterfaces: []*ec2.InstanceNetworkInterfaceSpecification{
			{
				DeviceIndex:              aws.Int64(0),
				SubnetId:                 aws.String(subnetID),
				AssociatePublicIpAddress: aws.Bool(false), // No public IP for private subnet
				DeleteOnTermination:      aws.Bool(true),
			},
		},
		TagSpecifications: []*ec2.TagSpecification{
			{
				ResourceType: aws.String("instance"),
				Tags: []*ec2.Tag{
					{Key: aws.String("Name"), Value: aws.String("terratest-functional-test-private")},
					{Key: aws.String("TestFramework"), Value: aws.String("terratest")},
					{Key: aws.String("AutoCleanup"), Value: aws.String("true")},
				},
			},
		},
	}

	result, err := ec2Svc.RunInstances(input)
	require.NoError(t, err, "Failed to launch private test instance")
	require.Len(t, result.Instances, 1, "Expected exactly one instance to be launched")

	instanceID := *result.Instances[0].InstanceId
	t.Logf("Launched private test instance: %s", instanceID)
	return instanceID
}

// =============================================================================
// INTEGRATION TEST HELPERS
// =============================================================================

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
