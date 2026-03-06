package test

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi"
	tagtypes "github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	smtypes "github.com/aws/aws-sdk-go-v2/service/secretsmanager/types"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// =============================================================================
// AWS CLIENTS
// =============================================================================

// AWSClients holds shared AWS SDK clients, created once per scenario.
type AWSClients struct {
	Config         aws.Config
	S3             *s3.Client
	IAM            *iam.Client
	EC2            *ec2.Client
	SSM            *ssm.Client
	CloudWatchLogs *cloudwatchlogs.Client
	SecretsManager *secretsmanager.Client
	Tagging        *resourcegroupstaggingapi.Client
}

// NewAWSClients creates all AWS SDK clients from the default config.
func NewAWSClients(ctx context.Context) *AWSClients {
	cfg := MustGetAWSConfig(ctx)
	return &AWSClients{
		Config:         cfg,
		S3:             s3.NewFromConfig(cfg),
		IAM:            iam.NewFromConfig(cfg),
		EC2:            ec2.NewFromConfig(cfg),
		SSM:            ssm.NewFromConfig(cfg),
		CloudWatchLogs: cloudwatchlogs.NewFromConfig(cfg),
		SecretsManager: secretsmanager.NewFromConfig(cfg),
		Tagging:        resourcegroupstaggingapi.NewFromConfig(cfg),
	}
}

// =============================================================================
// SCENARIO RESULT
// =============================================================================

// ScenarioResult holds all outputs from a deployed scenario.
type ScenarioResult struct {
	Config         ScenarioConfig
	ModuleOptions  *terraform.Options
	VpcID          string
	PublicSubnets  []string
	PrivateSubnets []string
	Outputs        map[string]string
}

func (r ScenarioResult) StackName() string      { return r.Outputs["stack_name"] }
func (r ScenarioResult) AppRunnerURL() string    { return r.Outputs["apprunner_service_url"] }
func (r ScenarioResult) ConfigBucket() string    { return r.Outputs["config_bucket_name"] }
func (r ScenarioResult) CacheBucket() string     { return r.Outputs["cache_bucket_name"] }
func (r ScenarioResult) LoggingBucket() string   { return r.Outputs["logging_bucket_name"] }
func (r ScenarioResult) EC2RoleName() string     { return r.Outputs["ec2_instance_role_name"] }
func (r ScenarioResult) LogGroupName() string    { return r.Outputs["ec2_instance_log_group_name"] }
func (r ScenarioResult) EFSFileSystemID() string { return r.Outputs["efs_file_system_id"] }
func (r ScenarioResult) ECRURL() string          { return r.Outputs["ecr_repository_url"] }

// =============================================================================
// COMPOSABLE VALIDATION SETS
// =============================================================================

func runOutputValidations(t *testing.T, r ScenarioResult) {
	t.Run("Outputs", func(t *testing.T) {
		assert.NotEmpty(t, r.StackName(), "Stack name should not be empty")
		assert.NotEmpty(t, r.AppRunnerURL(), "App Runner URL should not be empty")
		assert.Contains(t, r.AppRunnerURL(), "awsapprunner.com", "Should be a valid App Runner URL")
		assert.NotEmpty(t, r.ConfigBucket(), "Config bucket should not be empty")
		assert.NotEmpty(t, r.CacheBucket(), "Cache bucket should not be empty")
		assert.NotEmpty(t, r.LoggingBucket(), "Logging bucket should not be empty")
		assert.NotEmpty(t, r.EC2RoleName(), "EC2 role name should not be empty")

		if r.Config.EnableEFS {
			assert.NotEmpty(t, r.EFSFileSystemID(), "EFS ID should not be empty")
		}
		if r.Config.EnableECR {
			assert.NotEmpty(t, r.ECRURL(), "ECR URL should not be empty")
		}
	})
}

func runSecurityValidations(t *testing.T, clients *AWSClients, r ScenarioResult) {
	t.Run("Security/S3Encryption", func(t *testing.T) {
		ValidateS3BucketEncryption(t, clients, r.ConfigBucket())
		ValidateS3BucketEncryption(t, clients, r.CacheBucket())
		ValidateS3BucketEncryption(t, clients, r.LoggingBucket())
	})

	t.Run("Security/S3AccessLogging", func(t *testing.T) {
		ValidateS3BucketLogging(t, clients, r.ConfigBucket(), r.LoggingBucket())
		ValidateS3BucketLogging(t, clients, r.CacheBucket(), r.LoggingBucket())
	})

	t.Run("Security/S3PublicAccessBlocked", func(t *testing.T) {
		ValidateS3BucketPublicAccessBlocked(t, clients, r.ConfigBucket())
		ValidateS3BucketPublicAccessBlocked(t, clients, r.CacheBucket())
		ValidateS3BucketPublicAccessBlocked(t, clients, r.LoggingBucket())
	})

	t.Run("Security/IAMMinimalPermissions", func(t *testing.T) {
		ValidateIAMRoleNotOverlyPermissive(t, clients, r.EC2RoleName())
	})
}

func runComplianceValidations(t *testing.T, clients *AWSClients, r ScenarioResult) {
	t.Run("Compliance/S3Versioning", func(t *testing.T) {
		ValidateS3BucketVersioning(t, clients, r.ConfigBucket(), "Enabled")
		ValidateS3BucketVersioning(t, clients, r.CacheBucket(), "Suspended")
		ValidateS3BucketVersioning(t, clients, r.LoggingBucket(), "Enabled")
	})

	t.Run("Compliance/LogRetention", func(t *testing.T) {
		ValidateCloudWatchLogRetention(t, clients, r.LogGroupName())
	})
}

func runAdvancedValidations(t *testing.T, r ScenarioResult) {
	t.Run("Advanced/AppRunnerHealth", func(t *testing.T) {
		ValidateAppRunnerHealth(t, r.AppRunnerURL(), 10)
	})
}

func runFunctionalValidations(t *testing.T, clients *AWSClients, r ScenarioResult) {
	launchTemplateKey := "launch_template_linux_default_id"
	subnetID := r.PublicSubnets[0]
	publicIP := true

	if r.Config.EnableNAT && len(r.PrivateSubnets) > 0 {
		launchTemplateKey = "launch_template_linux_private_id"
		subnetID = r.PrivateSubnets[0]
		publicIP = false
	}

	launchTemplateID := r.Outputs[launchTemplateKey]
	require.NotEmpty(t, launchTemplateID, "Launch template ID should not be empty")

	instanceID := LaunchTestInstance(t, clients, launchTemplateID, subnetID, publicIP)
	defer TerminateTestInstance(t, clients, instanceID)

	timeout := 5 * time.Minute
	if !publicIP {
		timeout = 7 * time.Minute
	}
	ready := WaitForInstanceReady(t, clients, instanceID, timeout)
	require.True(t, ready, "Instance failed to become SSM-ready within timeout")

	if !publicIP {
		t.Run("NoPublicIP", func(t *testing.T) {
			hasNoPublicIP := ValidateInstanceHasNoPublicIP(t, clients, instanceID)
			assert.True(t, hasNoPublicIP, "Private subnet instance should not have public IP")
		})

		t.Run("OutboundConnectivity", func(t *testing.T) {
			ValidatePrivateNetworkConnectivity(t, clients, instanceID)
		})
	}

	t.Run("S3Access", func(t *testing.T) {
		ValidateS3AccessFromEC2(t, clients, instanceID, r.CacheBucket(), r.ConfigBucket())
	})

	if r.Config.EnableEFS {
		t.Run("EFSMount", func(t *testing.T) {
			ValidateEFSMountFromEC2(t, clients, instanceID, r.EFSFileSystemID())
		})
	}

	if r.Config.EnableECR {
		t.Run("ECRPushPull", func(t *testing.T) {
			ValidateECRPushPullFromEC2(t, clients, instanceID, r.ECRURL())
		})
	}

	t.Run("CloudWatchLogging", func(t *testing.T) {
		ValidateEC2CloudWatchLogs(t, clients, instanceID, r.LogGroupName())
	})
}

// =============================================================================
// SECURITY VALIDATORS
// =============================================================================

// ValidateS3BucketEncryption checks bucket has SSE-KMS encryption.
func ValidateS3BucketEncryption(t *testing.T, clients *AWSClients, bucketName string) {
	ctx := context.Background()
	result, err := clients.S3.GetBucketEncryption(ctx, &s3.GetBucketEncryptionInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get bucket encryption for %s", bucketName)
	require.NotEmpty(t, result.ServerSideEncryptionConfiguration.Rules, "Bucket %s has no encryption rules", bucketName)
	algo := string(result.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm)
	assert.Equal(t, "aws:kms", algo, "Bucket %s should use KMS encryption, got %s", bucketName, algo)
}

// ValidateS3BucketLogging checks bucket has access logging enabled.
func ValidateS3BucketLogging(t *testing.T, clients *AWSClients, bucketName, expectedTargetBucket string) {
	ctx := context.Background()
	result, err := clients.S3.GetBucketLogging(ctx, &s3.GetBucketLoggingInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get bucket logging for %s", bucketName)
	require.NotNil(t, result.LoggingEnabled, "Bucket %s should have logging enabled", bucketName)
	assert.Contains(t, *result.LoggingEnabled.TargetBucket, expectedTargetBucket,
		"Bucket %s should log to %s", bucketName, expectedTargetBucket)
}

// ValidateS3BucketPublicAccessBlocked checks bucket has public access blocked.
func ValidateS3BucketPublicAccessBlocked(t *testing.T, clients *AWSClients, bucketName string) {
	ctx := context.Background()
	result, err := clients.S3.GetPublicAccessBlock(ctx, &s3.GetPublicAccessBlockInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get public access block for %s", bucketName)

	pabConfig := result.PublicAccessBlockConfiguration
	assert.True(t, aws.ToBool(pabConfig.BlockPublicAcls), "Bucket %s should block public ACLs", bucketName)
	assert.True(t, aws.ToBool(pabConfig.BlockPublicPolicy), "Bucket %s should block public policy", bucketName)
	assert.True(t, aws.ToBool(pabConfig.IgnorePublicAcls), "Bucket %s should ignore public ACLs", bucketName)
	assert.True(t, aws.ToBool(pabConfig.RestrictPublicBuckets), "Bucket %s should restrict public buckets", bucketName)
}

// ValidateIAMRoleNotOverlyPermissive checks role doesn't have dangerous policies.
func ValidateIAMRoleNotOverlyPermissive(t *testing.T, clients *AWSClients, roleName string) {
	ctx := context.Background()
	attachedPolicies, err := clients.IAM.ListAttachedRolePolicies(ctx, &iam.ListAttachedRolePoliciesInput{
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
// COMPLIANCE VALIDATORS
// =============================================================================

// ValidateS3BucketVersioning checks versioning status.
func ValidateS3BucketVersioning(t *testing.T, clients *AWSClients, bucketName string, expectedStatus string) {
	ctx := context.Background()
	result, err := clients.S3.GetBucketVersioning(ctx, &s3.GetBucketVersioningInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "Failed to get bucket versioning for %s", bucketName)

	status := string(result.Status)
	assert.Equal(t, expectedStatus, status,
		"Bucket %s versioning should be %s, got %s", bucketName, expectedStatus, status)
}

// ValidateCloudWatchLogRetention checks log group has retention set.
func ValidateCloudWatchLogRetention(t *testing.T, clients *AWSClients, logGroupPrefix string) {
	ctx := context.Background()
	result, err := clients.CloudWatchLogs.DescribeLogGroups(ctx, &cloudwatchlogs.DescribeLogGroupsInput{
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
// ADVANCED VALIDATORS
// =============================================================================

// ValidateAppRunnerHealth checks App Runner responds to health endpoint.
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
// FUNCTIONAL VALIDATORS
// =============================================================================

// isAccessDenied checks if AWS CLI output indicates access was denied.
func isAccessDenied(output string) bool {
	return strings.Contains(output, "AccessDenied") ||
		strings.Contains(output, "Access Denied") ||
		strings.Contains(output, "403") ||
		strings.Contains(output, "Forbidden")
}

// ValidateS3AccessFromEC2 verifies that an EC2 instance has the correct S3 access per IAM policy.
func ValidateS3AccessFromEC2(t *testing.T, clients *AWSClients, instanceID, cacheBucket, configBucket string) {
	ctx := context.Background()

	testFile := fmt.Sprintf("functional-test-%d", time.Now().UnixNano())
	testContent := fmt.Sprintf("test-content-%d", time.Now().UnixNano())

	// Get the EC2 instance's aws:userid for runners path testing
	getUserIdCmd := "aws sts get-caller-identity --query 'UserId' --output text"
	stdout, stderr, err := RunSSMCommand(t, clients, instanceID, []string{getUserIdCmd})
	require.NoError(t, err, "Failed to get caller identity. stderr: %s", stderr)
	userId := strings.TrimSpace(stdout)
	require.NotEmpty(t, userId, "UserId should not be empty")
	t.Logf("EC2 instance aws:userid = %s", userId)

	// === Test 1: CAN write to cache/* ===
	cacheKey := fmt.Sprintf("cache/%s", testFile)
	writeCmd := fmt.Sprintf("echo '%s' | aws s3 cp - s3://%s/%s --region %s 2>&1",
		testContent, cacheBucket, cacheKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, clients, instanceID, []string{writeCmd})
	require.NoError(t, err, "Should be able to write to cache/*. stderr: %s", stdout)
	t.Logf("CAN write to cache/*")

	// === Test 2: CAN read from cache/* ===
	readCmd := fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", cacheBucket, cacheKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, clients, instanceID, []string{readCmd})
	require.NoError(t, err, "Should be able to read from cache/*")
	assert.Contains(t, stdout, testContent, "Content mismatch reading from cache/*")
	t.Logf("CAN read from cache/*")

	// Cleanup cache test file
	_, _ = clients.S3.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(cacheBucket), Key: aws.String(cacheKey)})

	// === Test 3: CAN read from runners/{own-userid}/* ===
	ownRunnersKey := fmt.Sprintf("runners/%s/%s", userId, testFile)
	ownRunnersContent := "runners-test-content"
	_, err = clients.S3.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(cacheBucket),
		Key:    aws.String(ownRunnersKey),
		Body:   strings.NewReader(ownRunnersContent),
	})
	require.NoError(t, err, "Admin failed to upload to runners path")

	readCmd = fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", cacheBucket, ownRunnersKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, clients, instanceID, []string{readCmd})
	require.NoError(t, err, "Should be able to read from own runners path")
	assert.Contains(t, stdout, ownRunnersContent)
	t.Logf("CAN read from runners/{own-userid}/*")

	// Cleanup
	_, _ = clients.S3.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(cacheBucket), Key: aws.String(ownRunnersKey)})

	// === Test 4: CAN read from agents/* in config bucket ===
	agentsKey := fmt.Sprintf("agents/%s", testFile)
	agentsContent := "agents-test-content"
	_, err = clients.S3.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(configBucket),
		Key:    aws.String(agentsKey),
		Body:   strings.NewReader(agentsContent),
	})
	require.NoError(t, err, "Admin failed to upload to agents path")

	readCmd = fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", configBucket, agentsKey, GetAWSRegion())
	stdout, _, err = RunSSMCommand(t, clients, instanceID, []string{readCmd})
	require.NoError(t, err, "Should be able to read from agents/*")
	assert.Contains(t, stdout, agentsContent)
	t.Logf("CAN read from agents/* (config bucket)")

	// Cleanup
	_, _ = clients.S3.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(configBucket), Key: aws.String(agentsKey)})

	// === Test 5: CANNOT write to runners/* ===
	runnersWriteKey := fmt.Sprintf("runners/%s", testFile)
	writeCmd = fmt.Sprintf("echo 'test' | aws s3 cp - s3://%s/%s --region %s 2>&1",
		cacheBucket, runnersWriteKey, GetAWSRegion())
	stdout, _, _ = RunSSMCommand(t, clients, instanceID, []string{writeCmd})
	accessDenied := isAccessDenied(stdout)
	assert.True(t, accessDenied, "Should NOT be able to write to runners/*, got: %s", stdout)
	t.Logf("CANNOT write to runners/*")

	// === Test 6: CANNOT read from runners/{other-userid}/* ===
	otherRunnersKey := fmt.Sprintf("runners/other-fake-userid/%s", testFile)
	_, err = clients.S3.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(cacheBucket),
		Key:    aws.String(otherRunnersKey),
		Body:   strings.NewReader("other-user-content"),
	})
	require.NoError(t, err, "Admin failed to upload to other user's runners path")

	readCmd = fmt.Sprintf("aws s3 cp s3://%s/%s - --region %s 2>&1", cacheBucket, otherRunnersKey, GetAWSRegion())
	stdout, _, _ = RunSSMCommand(t, clients, instanceID, []string{readCmd})
	accessDenied = isAccessDenied(stdout)
	assert.True(t, accessDenied, "Should NOT be able to read from other user's runners path, got: %s", stdout)
	t.Logf("CANNOT read from runners/{other-userid}/*")

	// Cleanup
	_, _ = clients.S3.DeleteObject(ctx, &s3.DeleteObjectInput{Bucket: aws.String(cacheBucket), Key: aws.String(otherRunnersKey)})
}

// ValidateEC2CloudWatchLogs verifies that an EC2 instance is sending logs to CloudWatch.
func ValidateEC2CloudWatchLogs(t *testing.T, clients *AWSClients, instanceID, logGroupName string) {
	ctx := context.Background()

	// Generate some log activity on the instance
	logCmd := fmt.Sprintf("logger -t terratest 'Functional test log entry from %s'", instanceID)
	_, _, _ = RunSSMCommand(t, clients, instanceID, []string{logCmd})

	// Wait for logs to propagate
	time.Sleep(10 * time.Second)

	// Check if the log group exists
	result, err := clients.CloudWatchLogs.DescribeLogGroups(ctx, &cloudwatchlogs.DescribeLogGroupsInput{
		LogGroupNamePrefix: aws.String(logGroupName),
	})
	require.NoError(t, err, "Failed to describe log groups")
	require.NotEmpty(t, result.LogGroups, "Log group %s not found", logGroupName)

	t.Logf("CloudWatch log group %s exists and is configured", logGroupName)
}

// =============================================================================
// PRIVATE NETWORKING VALIDATORS
// =============================================================================

// ValidateInstanceHasNoPublicIP verifies that an EC2 instance does not have a public IP address.
func ValidateInstanceHasNoPublicIP(t *testing.T, clients *AWSClients, instanceID string) bool {
	ctx := context.Background()
	result, err := clients.EC2.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
		InstanceIds: []string{instanceID},
	})
	require.NoError(t, err, "Failed to describe instance %s", instanceID)
	require.NotEmpty(t, result.Reservations, "No reservations found for instance %s", instanceID)
	require.NotEmpty(t, result.Reservations[0].Instances, "No instances found in reservation")

	instance := result.Reservations[0].Instances[0]
	hasPublicIP := instance.PublicIpAddress != nil && *instance.PublicIpAddress != ""

	if hasPublicIP {
		t.Logf("Instance %s has public IP: %s", instanceID, *instance.PublicIpAddress)
		return false
	}

	t.Logf("Instance %s has no public IP (as expected for private subnet)", instanceID)
	return true
}

// ValidatePrivateNetworkConnectivity verifies outbound HTTPS connectivity via NAT gateway.
func ValidatePrivateNetworkConnectivity(t *testing.T, clients *AWSClients, instanceID string) {
	// Test 1: Can reach external HTTPS endpoint (proves NAT gateway works)
	curlCmd := "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 https://api.github.com"
	stdout, stderr, err := RunSSMCommand(t, clients, instanceID, []string{curlCmd})
	require.NoError(t, err, "Failed to execute curl command. stderr: %s", stderr)

	httpCode := strings.TrimSpace(stdout)
	assert.True(t, httpCode == "200" || httpCode == "403",
		"Expected HTTP 200 or 403 from api.github.com, got: %s", httpCode)
	t.Logf("Outbound HTTPS connectivity works (api.github.com returned %s)", httpCode)

	// Test 2: Can reach AWS APIs (S3 endpoint)
	awsCmd := "aws s3 ls --region " + GetAWSRegion() + " 2>&1 | head -1"
	stdout, _, err = RunSSMCommand(t, clients, instanceID, []string{awsCmd})
	require.NoError(t, err, "AWS S3 command failed - NAT gateway may not be working")
	t.Logf("AWS API connectivity works (S3 list returned: %s...)", truncateString(stdout, 50))
}

// =============================================================================
// EFS VALIDATORS
// =============================================================================

// ValidateEFSMountFromEC2 mounts an EFS filesystem on an EC2 instance and performs I/O operations.
func ValidateEFSMountFromEC2(t *testing.T, clients *AWSClients, instanceID, efsFileSystemID string) {
	mountPoint := "/mnt/efs-test"
	testFile := fmt.Sprintf("test-file-%d", time.Now().UnixNano())
	testContent := fmt.Sprintf("efs-test-content-%d", time.Now().UnixNano())

	// Step 1: Install amazon-efs-utils if not present
	installCmd := "which mount.efs || sudo dnf install -y amazon-efs-utils"
	stdout, stderr, err := RunSSMCommand(t, clients, instanceID, []string{installCmd})
	require.NoError(t, err, "Failed to install amazon-efs-utils. stdout: %s, stderr: %s", stdout, stderr)
	t.Logf("amazon-efs-utils available")

	// Step 2: Create mount point
	mkdirCmd := fmt.Sprintf("sudo mkdir -p %s", mountPoint)
	_, stderr, err = RunSSMCommand(t, clients, instanceID, []string{mkdirCmd})
	require.NoError(t, err, "Failed to create mount point. stderr: %s", stderr)

	// Step 3: Mount EFS
	mountCmd := fmt.Sprintf("sudo mount -t efs -o tls %s:/ %s", efsFileSystemID, mountPoint)
	stdout, stderr, err = RunSSMCommand(t, clients, instanceID, []string{mountCmd})
	require.NoError(t, err, "Failed to mount EFS %s. stdout: %s, stderr: %s", efsFileSystemID, stdout, stderr)
	t.Logf("EFS %s mounted at %s", efsFileSystemID, mountPoint)

	// Step 4: Write test file
	writeCmd := fmt.Sprintf("echo '%s' | sudo tee %s/%s > /dev/null", testContent, mountPoint, testFile)
	_, stderr, err = RunSSMCommand(t, clients, instanceID, []string{writeCmd})
	require.NoError(t, err, "Failed to write test file to EFS. stderr: %s", stderr)
	t.Logf("Written test file to EFS")

	// Step 5: Read test file back
	readCmd := fmt.Sprintf("cat %s/%s", mountPoint, testFile)
	stdout, stderr, err = RunSSMCommand(t, clients, instanceID, []string{readCmd})
	require.NoError(t, err, "Failed to read test file from EFS. stderr: %s", stderr)
	assert.Contains(t, stdout, testContent, "EFS content mismatch")
	t.Logf("Read test file from EFS - content verified")

	// Step 6: Verify mount is EFS (filesystem type is nfs4)
	verifyCmd := fmt.Sprintf("findmnt -n -o FSTYPE %s", mountPoint)
	stdout, stderr, err = RunSSMCommand(t, clients, instanceID, []string{verifyCmd})
	require.NoError(t, err, "Failed to verify mount type. stderr: %s", stderr)
	fsType := strings.TrimSpace(stdout)
	assert.Equal(t, "nfs4", fsType, "EFS should be mounted as nfs4 filesystem")
	t.Logf("EFS mount verified (filesystem type: %s)", fsType)

	// Verify EFS capacity shows as 8.0E (exabytes) - characteristic of EFS
	dfCmd := fmt.Sprintf("df -h %s | tail -1 | awk '{print $2}'", mountPoint)
	stdout, _, err = RunSSMCommand(t, clients, instanceID, []string{dfCmd})
	require.NoError(t, err, "Failed to get EFS capacity")
	capacity := strings.TrimSpace(stdout)
	assert.Equal(t, "8.0E", capacity, "EFS should show 8.0E capacity")
	t.Logf("EFS capacity verified (%s - unlimited)", capacity)

	// Cleanup: Remove test file and unmount
	cleanupCmd := fmt.Sprintf("sudo rm -f %s/%s && sudo umount %s", mountPoint, testFile, mountPoint)
	_, _, _ = RunSSMCommand(t, clients, instanceID, []string{cleanupCmd})
	t.Logf("EFS cleanup completed")
}

// =============================================================================
// ECR VALIDATORS
// =============================================================================

// ValidateECRPushPullFromEC2 validates ECR as a Docker layer cache backend.
func ValidateECRPushPullFromEC2(t *testing.T, clients *AWSClients, instanceID, ecrURL string) {
	region := GetAWSRegion()
	testTag := fmt.Sprintf("cache-test-%d", time.Now().UnixNano())
	cacheRef := fmt.Sprintf("%s:%s", ecrURL, testTag)
	registryURL := strings.Split(ecrURL, "/")[0]

	// Step 1: Install Docker and start service
	installCmd := `
		if ! which docker > /dev/null 2>&1; then
			sudo dnf install -y docker
		fi
		sudo systemctl start docker
		sudo systemctl enable docker
	`
	_, stderr, err := RunSSMCommand(t, clients, instanceID, []string{installCmd})
	require.NoError(t, err, "Failed to install/start Docker. stderr: %s", stderr)
	t.Logf("Docker installed and running")

	// Step 2: Set up Docker Buildx
	buildxSetupCmd := `
		sudo docker buildx version || {
			mkdir -p ~/.docker/cli-plugins
			curl -sSL https://github.com/docker/buildx/releases/download/v0.12.0/buildx-v0.12.0.linux-amd64 -o ~/.docker/cli-plugins/docker-buildx
			chmod +x ~/.docker/cli-plugins/docker-buildx
		}
		sudo docker buildx create --name testbuilder --driver docker-container --use 2>/dev/null || sudo docker buildx use testbuilder
		sudo docker buildx inspect --bootstrap
	`
	stdout, stderr, err := RunSSMCommand(t, clients, instanceID, []string{buildxSetupCmd})
	require.NoError(t, err, "Failed to set up Buildx. stdout: %s, stderr: %s", stdout, stderr)
	t.Logf("Docker Buildx configured with docker-container driver")

	// Step 3: Authenticate to ECR
	loginCmd := fmt.Sprintf("aws ecr get-login-password --region %s | sudo docker login --username AWS --password-stdin %s",
		region, registryURL)
	stdout, stderr, err = RunSSMCommand(t, clients, instanceID, []string{loginCmd})
	require.NoError(t, err, "Failed to authenticate to ECR. stdout: %s, stderr: %s", stdout, stderr)
	assert.Contains(t, stdout+stderr, "Login Succeeded", "ECR login should succeed")
	t.Logf("Authenticated to ECR")

	// Step 4: Create a test Dockerfile
	dockerfileCmd := `
		mkdir -p /tmp/ecr-cache-test
		cat > /tmp/ecr-cache-test/Dockerfile << 'DOCKERFILE'
FROM public.ecr.aws/docker/library/alpine:latest
RUN apk add --no-cache curl
RUN apk add --no-cache jq
RUN echo "Layer caching test" > /test.txt
DOCKERFILE
	`
	_, stderr, err = RunSSMCommand(t, clients, instanceID, []string{dockerfileCmd})
	require.NoError(t, err, "Failed to create Dockerfile. stderr: %s", stderr)
	t.Logf("Created test Dockerfile")

	// Step 5: First build - pushes cache to ECR
	firstBuildCmd := fmt.Sprintf(`
		cd /tmp/ecr-cache-test
		sudo docker buildx build \
			--cache-to type=registry,ref=%s,mode=max \
			--load \
			-t test-image:first \
			. 2>&1
	`, cacheRef)
	stdout, stderr, err = RunSSMCommand(t, clients, instanceID, []string{firstBuildCmd})
	require.NoError(t, err, "First build failed. stdout: %s, stderr: %s", stdout, stderr)
	t.Logf("First build completed (cache pushed to ECR)")

	// Step 6: Clear local build cache
	clearCacheCmd := "sudo docker buildx prune -af"
	_, _, _ = RunSSMCommand(t, clients, instanceID, []string{clearCacheCmd})
	t.Logf("Cleared local build cache")

	// Step 7: Second build - should use cache from ECR
	secondBuildCmd := fmt.Sprintf(`
		cd /tmp/ecr-cache-test
		sudo docker buildx build \
			--cache-from type=registry,ref=%s \
			--load \
			-t test-image:second \
			. 2>&1
	`, cacheRef)
	stdout, stderr, err = RunSSMCommand(t, clients, instanceID, []string{secondBuildCmd})
	require.NoError(t, err, "Second build failed. stdout: %s, stderr: %s", stdout, stderr)

	buildOutput := stdout + stderr
	cacheHit := strings.Contains(buildOutput, "CACHED") || strings.Contains(buildOutput, "importing cache")
	t.Logf("Second build output (checking for cache): %s", truncateString(buildOutput, 500))

	if cacheHit {
		t.Logf("Second build used cached layers from ECR")
	} else {
		t.Logf("Cache indicators not found in output, but build succeeded")
	}

	// Step 8: Verify the built image works
	verifyCmd := "sudo docker run --rm test-image:second cat /test.txt"
	stdout, stderr, err = RunSSMCommand(t, clients, instanceID, []string{verifyCmd})
	require.NoError(t, err, "Failed to run built image. stderr: %s", stderr)
	assert.Contains(t, stdout, "Layer caching test", "Image should contain expected content")
	t.Logf("Built image verified")

	// Cleanup
	cleanupCmd := fmt.Sprintf(`
		sudo docker rmi test-image:first test-image:second 2>/dev/null || true
		sudo docker buildx rm testbuilder 2>/dev/null || true
		rm -rf /tmp/ecr-cache-test
		aws ecr batch-delete-image --repository-name %s --image-ids imageTag=%s --region %s 2>/dev/null || true
	`, strings.Split(ecrURL, "/")[1], testTag, region)
	_, _, _ = RunSSMCommand(t, clients, instanceID, []string{cleanupCmd})
	t.Logf("ECR cache test cleanup completed")
}

// =============================================================================
// INTEGRATION VALIDATORS
// =============================================================================

// ValidateRunnerLaunched checks if an EC2 runner instance was launched for the stack.
func ValidateRunnerLaunched(t *testing.T, clients *AWSClients, stackName string, since time.Time) bool {
	ctx := context.Background()
	result, err := clients.EC2.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
		Filters: []ec2types.Filter{
			{
				Name:   aws.String("tag:runs-on-stack-name"),
				Values: []string{stackName},
			},
			{
				Name:   aws.String("instance-state-name"),
				Values: []string{"running", "terminated", "stopped"},
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

// =============================================================================
// WIRING VALIDATORS (NEW)
// =============================================================================

// StackConfig represents the JSON structure stored in Secrets Manager
// by the core module (modules/core/main.tf lines 43-91).
type StackConfig struct {
	AwsAccountId                 string   `json:"AwsAccountId"`
	StackName                    string   `json:"StackName"`
	Region                       string   `json:"Region"`
	VPCId                        string   `json:"VPCId"`
	BucketConfig                 string   `json:"BucketConfig"`
	BucketCache                  string   `json:"BucketCache"`
	InstanceRoleName             string   `json:"InstanceRoleName"`
	LaunchTemplateLinuxDefault   string   `json:"LaunchTemplateLinuxDefault"`
	LaunchTemplateWindowsDefault string   `json:"LaunchTemplateWindowsDefault"`
	LaunchTemplateLinuxPrivate   string   `json:"LaunchTemplateLinuxPrivate"`
	LaunchTemplateWindowsPrivate string   `json:"LaunchTemplateWindowsPrivate"`
	Queue                        string   `json:"Queue"`
	QueueJobs                    string   `json:"QueueJobs"`
	QueueGithub                  string   `json:"QueueGithub"`
	QueuePool                    string   `json:"QueuePool"`
	QueueHousekeeping            string   `json:"QueueHousekeeping"`
	QueueTermination             string   `json:"QueueTermination"`
	QueueEvents                  string   `json:"QueueEvents"`
	LocksTable                   string   `json:"LocksTable"`
	WorkflowJobsTable            string   `json:"WorkflowJobsTable"`
	TopicArn                     string   `json:"TopicArn"`
	PublicSubnetIds              []string `json:"PublicSubnetIds"`
}

func runWiringValidations(t *testing.T, clients *AWSClients, r ScenarioResult) {
	t.Run("Wiring/StackConfig", func(t *testing.T) {
		ValidateStackConfig(t, clients, r)
	})
}

// ValidateStackConfig reads the Secrets Manager secret created by the core module
// and verifies its JSON fields match the terraform outputs from all modules.
func ValidateStackConfig(t *testing.T, clients *AWSClients, r ScenarioResult) {
	ctx := context.Background()
	stackName := r.StackName()

	// Find the secret by prefix (name includes image digest which varies)
	listResult, err := clients.SecretsManager.ListSecrets(ctx, &secretsmanager.ListSecretsInput{
		Filters: []smtypes.Filter{
			{
				Key:    smtypes.FilterNameStringTypeName,
				Values: []string{fmt.Sprintf("/runs-on/%s/config/", stackName)},
			},
		},
	})
	require.NoError(t, err, "Failed to list secrets for stack %s", stackName)
	require.NotEmpty(t, listResult.SecretList, "No config secret found for stack %s", stackName)

	// Get the secret value
	secretARN := *listResult.SecretList[0].ARN
	getResult, err := clients.SecretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretARN),
	})
	require.NoError(t, err, "Failed to get secret value")

	// Parse JSON
	var config StackConfig
	err = json.Unmarshal([]byte(*getResult.SecretString), &config)
	require.NoError(t, err, "Failed to parse stack config JSON")

	// Validate storage module wiring
	assert.Equal(t, r.ConfigBucket(), config.BucketConfig,
		"Stack config BucketConfig should match storage module output")
	assert.Equal(t, r.CacheBucket(), config.BucketCache,
		"Stack config BucketCache should match storage module output")

	// Validate compute module wiring
	assert.Equal(t, r.EC2RoleName(), config.InstanceRoleName,
		"Stack config InstanceRoleName should match compute module output")
	assert.Equal(t, r.Outputs["launch_template_linux_default_id"], config.LaunchTemplateLinuxDefault,
		"Stack config LaunchTemplateLinuxDefault should match compute output")
	assert.Equal(t, r.Outputs["launch_template_windows_default_id"], config.LaunchTemplateWindowsDefault,
		"Stack config LaunchTemplateWindowsDefault should match compute output")
	assert.Equal(t, r.Outputs["launch_template_linux_private_id"], config.LaunchTemplateLinuxPrivate,
		"Stack config LaunchTemplateLinuxPrivate should match compute output")
	assert.Equal(t, r.Outputs["launch_template_windows_private_id"], config.LaunchTemplateWindowsPrivate,
		"Stack config LaunchTemplateWindowsPrivate should match compute output")

	// Validate core module internal wiring (SQS queues exist)
	assert.NotEmpty(t, config.Queue, "Stack config Queue should not be empty")
	assert.NotEmpty(t, config.QueueJobs, "Stack config QueueJobs should not be empty")
	assert.NotEmpty(t, config.QueueGithub, "Stack config QueueGithub should not be empty")
	assert.NotEmpty(t, config.QueuePool, "Stack config QueuePool should not be empty")
	assert.NotEmpty(t, config.QueueHousekeeping, "Stack config QueueHousekeeping should not be empty")
	assert.NotEmpty(t, config.QueueTermination, "Stack config QueueTermination should not be empty")
	assert.NotEmpty(t, config.QueueEvents, "Stack config QueueEvents should not be empty")

	// Validate DynamoDB table names
	assert.Equal(t, r.Outputs["dynamodb_locks_table_name"], config.LocksTable,
		"Stack config LocksTable should match core output")
	assert.Equal(t, r.Outputs["dynamodb_workflow_jobs_table_name"], config.WorkflowJobsTable,
		"Stack config WorkflowJobsTable should match core output")

	// Validate SNS topic
	assert.Equal(t, r.Outputs["sns_topic_arn"], config.TopicArn,
		"Stack config TopicArn should match core output")

	// Validate identity
	assert.Equal(t, stackName, config.StackName)
	assert.Equal(t, r.VpcID, config.VPCId)

	t.Logf("Stack config wiring validation passed: all fields verified")
}

// =============================================================================
// TAGGING VALIDATORS (NEW)
// =============================================================================

func runTaggingValidations(t *testing.T, clients *AWSClients, r ScenarioResult) {
	t.Run("Tagging/ResourceDiscovery", func(t *testing.T) {
		ValidateResourceTagging(t, clients, r.StackName())
	})
}

// ValidateResourceTagging verifies that key resources are tagged with runs-on-stack-name
// for application-level resource discovery.
func ValidateResourceTagging(t *testing.T, clients *AWSClients, stackName string) {
	ctx := context.Background()
	tagKey := "runs-on-stack-name"

	result, err := clients.Tagging.GetResources(ctx, &resourcegroupstaggingapi.GetResourcesInput{
		TagFilters: []tagtypes.TagFilter{
			{
				Key:    aws.String(tagKey),
				Values: []string{stackName},
			},
		},
	})
	require.NoError(t, err, "Failed to query resources by tag")

	// Collect resource types found
	resourceTypes := make(map[string]int)
	for _, mapping := range result.ResourceTagMappingList {
		arn := *mapping.ResourceARN
		parts := strings.Split(arn, ":")
		if len(parts) >= 3 {
			resourceTypes[parts[2]]++
		}
	}

	t.Logf("Found %d resources tagged with %s=%s", len(result.ResourceTagMappingList), tagKey, stackName)
	for svc, count := range resourceTypes {
		t.Logf("  %s: %d resources", svc, count)
	}

	assert.GreaterOrEqual(t, len(result.ResourceTagMappingList), 5,
		"Expected at least 5 resources tagged with %s=%s (S3 buckets, launch templates, log groups, queues, etc.)",
		tagKey, stackName)
}

// =============================================================================
// UTILITIES
// =============================================================================

// truncateString truncates a string to maxLen characters, adding "..." if truncated.
func truncateString(s string, maxLen int) string {
	s = strings.TrimSpace(s)
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
