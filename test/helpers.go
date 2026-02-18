package test

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	ssmtypes "github.com/aws/aws-sdk-go-v2/service/ssm/types"
	"github.com/google/go-github/v68/github"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
	"golang.org/x/oauth2"
)

// GetTestID generates a unique test ID for resource naming (Unix timestamp in seconds)
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

	// App version overrides (optional - empty means use module defaults)
	AppImage string
	AppTag   string

	// ForceDestroyBuckets controls whether S3 buckets can be force-destroyed on terraform destroy.
	// Set to false for integration tests that preserve buckets across runs.
	ForceDestroyBuckets bool

	// FixedStackName overrides the auto-generated stack name.
	// Used by integration tests that need a stable stack name across runs.
	FixedStackName string
}

// DefaultScenarioConfig returns config with sensible test defaults
func DefaultScenarioConfig() ScenarioConfig {
	return ScenarioConfig{
		TestID:              GetTestID(),
		GithubOrg:           getGithubOrg(),
		LicenseKey:          GetOptionalEnv("RUNS_ON_LICENSE_KEY", "test-license"),
		AWSRegion:           GetOptionalEnv("AWS_REGION", "us-east-1"),
		AppImage:            os.Getenv("RUNS_ON_APP_IMAGE"),
		AppTag:              os.Getenv("RUNS_ON_APP_TAG"),
		ForceDestroyBuckets: true,
	}
}

// getGithubOrg extracts the GitHub organization from RUNS_ON_TEST_REPO or GITHUB_ORG.
// Priority: GITHUB_ORG > RUNS_ON_TEST_REPO (owner part) > "test-org"
func getGithubOrg() string {
	if org := os.Getenv("GITHUB_ORG"); org != "" {
		return org
	}
	if testRepo := os.Getenv("RUNS_ON_TEST_REPO"); testRepo != "" {
		parts := strings.Split(testRepo, "/")
		if len(parts) >= 1 && parts[0] != "" {
			return parts[0]
		}
	}
	return "test-org"
}

// StackName returns the stack name for this config.
func (c ScenarioConfig) StackName() string {
	if c.FixedStackName != "" {
		return c.FixedStackName
	}
	return fmt.Sprintf("test-%s", c.TestID)
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
		"stack_name":                         c.StackName(),
		"github_organization":                c.GithubOrg,
		"license_key":                        c.LicenseKey,
		"vpc_id":                             vpcID,
		"public_subnet_ids":                  publicSubnets,
		"enable_efs":                         c.EnableEFS,
		"enable_ecr":                         c.EnableECR,
		"environment":                        "test",
		"email":                              "test@example.com",
		"log_retention_days":                 1,
		"cache_expiration_days":              1,
		"detailed_monitoring_enabled":        false,
		"app_cpu":                            1024,
		"app_memory":                         2048,
		"force_destroy_buckets":              c.ForceDestroyBuckets,
		"force_delete_ecr":                   true,
		"prevent_destroy_optional_resources": false,
	}

	if c.AppImage != "" {
		vars["app_image"] = c.AppImage
	}
	if c.AppTag != "" {
		vars["app_tag"] = c.AppTag
	}

	if len(privateSubnets) > 0 && c.EnableNAT {
		vars["private_subnet_ids"] = privateSubnets
	}

	return vars
}

// =============================================================================
// AWS SDK HELPERS
// =============================================================================

// GetAWSConfig creates a reusable AWS config for SDK v2
func GetAWSConfig(ctx context.Context) (aws.Config, error) {
	return config.LoadDefaultConfig(ctx,
		config.WithRegion(GetAWSRegion()),
	)
}

// MustGetAWSConfig creates a reusable AWS config, panicking on error
func MustGetAWSConfig(ctx context.Context) aws.Config {
	cfg, err := GetAWSConfig(ctx)
	if err != nil {
		panic(fmt.Sprintf("failed to load AWS config: %v", err))
	}
	return cfg
}

// =============================================================================
// SCENARIO HARNESS
// =============================================================================

// runScenario deploys infrastructure and runs validations, handling all setup and teardown.
func runScenario(t *testing.T, cfg ScenarioConfig, validate func(t *testing.T, r ScenarioResult)) {
	t.Parallel()

	// Deploy VPC fixture
	vpcOptions := &terraform.Options{
		TerraformDir:    "./fixtures/vpc",
		TerraformBinary: "tofu",
		Vars:            cfg.ToVPCVars(),
		NoColor:         true,
	}
	defer terraform.Destroy(t, vpcOptions)
	terraform.InitAndApply(t, vpcOptions)

	vpcID := terraform.Output(t, vpcOptions, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOptions, "public_subnets")
	privateSubnets := terraform.OutputList(t, vpcOptions, "private_subnets")

	// Deploy root module
	moduleOptions := &terraform.Options{
		TerraformDir:    "../",
		TerraformBinary: "tofu",
		Vars:            cfg.ToModuleVars(vpcID, publicSubnets, privateSubnets),
		NoColor:         true,
	}
	defer terraform.Destroy(t, moduleOptions)
	terraform.InitAndApply(t, moduleOptions)

	// Extract all outputs
	outputs := extractOutputs(t, moduleOptions)

	result := ScenarioResult{
		Config:         cfg,
		ModuleOptions:  moduleOptions,
		VpcID:          vpcID,
		PublicSubnets:  publicSubnets,
		PrivateSubnets: privateSubnets,
		Outputs:        outputs,
	}

	validate(t, result)
}

// extractOutputs reads all terraform outputs, tolerating optional null outputs.
func extractOutputs(t *testing.T, opts *terraform.Options) map[string]string {
	outputs := make(map[string]string)
	keys := []string{
		"stack_name", "aws_account_id", "aws_region",
		"config_bucket_name", "cache_bucket_name", "logging_bucket_name",
		"ec2_instance_role_name", "ec2_instance_role_arn", "ec2_instance_profile_arn",
		"ec2_instance_log_group_name",
		"launch_template_linux_default_id", "launch_template_windows_default_id",
		"launch_template_linux_private_id", "launch_template_windows_private_id",
		"apprunner_service_url", "apprunner_service_arn", "apprunner_service_status",
		"apprunner_log_group_name",
		"sns_topic_arn",
		"sqs_queue_main_url", "sqs_queue_jobs_url", "sqs_queue_github_url",
		"sqs_queue_pool_url", "sqs_queue_housekeeping_url", "sqs_queue_termination_url",
		"sqs_queue_events_url",
		"dynamodb_locks_table_name", "dynamodb_workflow_jobs_table_name",
		"dashboard_url", "dashboard_name",
		// Optional outputs (may be null when features disabled)
		"efs_file_system_id", "efs_file_system_dns_name",
		"ecr_repository_url", "ecr_repository_name",
		"waf_web_acl_arn", "waf_web_acl_id",
	}

	for _, key := range keys {
		val, err := terraform.OutputE(t, opts, key)
		if err == nil && val != "" {
			outputs[key] = val
		}
	}
	return outputs
}

// =============================================================================
// EC2 AND SSM HELPERS
// =============================================================================

// GetLatestAmazonLinux2023AMI returns the latest Amazon Linux 2023 AMI ID for the current region.
func GetLatestAmazonLinux2023AMI(t *testing.T, clients *AWSClients) string {
	ctx := context.Background()

	result, err := clients.EC2.DescribeImages(ctx, &ec2.DescribeImagesInput{
		Owners: []string{"amazon"},
		Filters: []ec2types.Filter{
			{Name: aws.String("name"), Values: []string{"al2023-ami-2023*-x86_64"}},
			{Name: aws.String("state"), Values: []string{"available"}},
			{Name: aws.String("architecture"), Values: []string{"x86_64"}},
		},
	})
	require.NoError(t, err, "Failed to describe AMIs")
	require.NotEmpty(t, result.Images, "No Amazon Linux 2023 AMIs found")

	var latestAMI *ec2types.Image
	for i := range result.Images {
		img := &result.Images[i]
		if latestAMI == nil || *img.CreationDate > *latestAMI.CreationDate {
			latestAMI = img
		}
	}

	t.Logf("Using AMI: %s (%s)", *latestAMI.ImageId, *latestAMI.Name)
	return *latestAMI.ImageId
}

// LaunchTestInstance launches an EC2 instance from a launch template for functional testing.
// launchTemplateID should be in format "lt-xxx:version" or just "lt-xxx".
// Set publicIP to true for public subnets (SSM access via internet) or false for private subnets (SSM via NAT).
func LaunchTestInstance(t *testing.T, clients *AWSClients, launchTemplateID, subnetID string, publicIP bool) string {
	ctx := context.Background()

	parts := strings.Split(launchTemplateID, ":")
	templateID := parts[0]
	version := "$Latest"
	if len(parts) > 1 {
		version = parts[1]
	}

	amiID := GetLatestAmazonLinux2023AMI(t, clients)

	instanceType := "public"
	if !publicIP {
		instanceType = "private"
	}
	t.Logf("Launching %s test instance from template %s (version %s) in subnet %s with AMI %s",
		instanceType, templateID, version, subnetID, amiID)

	instanceName := "terratest-functional-test"
	if !publicIP {
		instanceName = "terratest-functional-test-private"
	}

	input := &ec2.RunInstancesInput{
		LaunchTemplate: &ec2types.LaunchTemplateSpecification{
			LaunchTemplateId: aws.String(templateID),
			Version:          aws.String(version),
		},
		ImageId:  aws.String(amiID),
		MinCount: aws.Int32(1),
		MaxCount: aws.Int32(1),
		NetworkInterfaces: []ec2types.InstanceNetworkInterfaceSpecification{
			{
				DeviceIndex:              aws.Int32(0),
				SubnetId:                 aws.String(subnetID),
				AssociatePublicIpAddress: aws.Bool(publicIP),
				DeleteOnTermination:      aws.Bool(true),
			},
		},
		TagSpecifications: []ec2types.TagSpecification{
			{
				ResourceType: ec2types.ResourceTypeInstance,
				Tags: []ec2types.Tag{
					{Key: aws.String("Name"), Value: aws.String(instanceName)},
					{Key: aws.String("TestFramework"), Value: aws.String("terratest")},
					{Key: aws.String("AutoCleanup"), Value: aws.String("true")},
				},
			},
		},
	}

	result, err := clients.EC2.RunInstances(ctx, input)
	require.NoError(t, err, "Failed to launch %s test instance", instanceType)
	require.Len(t, result.Instances, 1, "Expected exactly one instance to be launched")

	instanceID := *result.Instances[0].InstanceId
	t.Logf("Launched %s test instance: %s", instanceType, instanceID)
	return instanceID
}

// TerminateTestInstance terminates a test EC2 instance.
func TerminateTestInstance(t *testing.T, clients *AWSClients, instanceID string) {
	if instanceID == "" {
		return
	}

	ctx := context.Background()
	t.Logf("Terminating test instance: %s", instanceID)

	_, err := clients.EC2.TerminateInstances(ctx, &ec2.TerminateInstancesInput{
		InstanceIds: []string{instanceID},
	})
	if err != nil {
		t.Logf("Warning: Failed to terminate instance %s: %v", instanceID, err)
	}
}

// WaitForInstanceReady waits for an EC2 instance to be running and SSM-ready.
// Returns true if the instance is ready, false if timeout is reached.
func WaitForInstanceReady(t *testing.T, clients *AWSClients, instanceID string, timeout time.Duration) bool {
	ctx := context.Background()
	deadline := time.Now().Add(timeout)

	t.Logf("Waiting for instance %s to be running and SSM-ready (timeout: %v)", instanceID, timeout)

	// Wait for instance to be running
	for time.Now().Before(deadline) {
		result, err := clients.EC2.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
			InstanceIds: []string{instanceID},
		})
		if err != nil {
			t.Logf("Error describing instance: %v", err)
			time.Sleep(10 * time.Second)
			continue
		}

		if len(result.Reservations) > 0 && len(result.Reservations[0].Instances) > 0 {
			state := result.Reservations[0].Instances[0].State.Name
			if state == ec2types.InstanceStateNameRunning {
				t.Logf("Instance %s is running, checking SSM readiness...", instanceID)
				break
			}
			t.Logf("Instance %s state: %s", instanceID, state)
		}
		time.Sleep(10 * time.Second)
	}

	// Wait for SSM agent to be ready
	for time.Now().Before(deadline) {
		result, err := clients.SSM.DescribeInstanceInformation(ctx, &ssm.DescribeInstanceInformationInput{
			Filters: []ssmtypes.InstanceInformationStringFilter{
				{
					Key:    aws.String("InstanceIds"),
					Values: []string{instanceID},
				},
			},
		})
		if err != nil {
			t.Logf("Error checking SSM status: %v", err)
			time.Sleep(10 * time.Second)
			continue
		}

		if len(result.InstanceInformationList) > 0 {
			pingStatus := result.InstanceInformationList[0].PingStatus
			if pingStatus == ssmtypes.PingStatusOnline {
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
func RunSSMCommand(t *testing.T, clients *AWSClients, instanceID string, commands []string) (string, string, error) {
	ctx := context.Background()

	t.Logf("Running SSM command on instance %s: %v", instanceID, commands)

	sendResult, err := clients.SSM.SendCommand(ctx, &ssm.SendCommandInput{
		InstanceIds:  []string{instanceID},
		DocumentName: aws.String("AWS-RunShellScript"),
		Parameters: map[string][]string{
			"commands": commands,
		},
		TimeoutSeconds: aws.Int32(120),
	})
	if err != nil {
		return "", "", fmt.Errorf("failed to send SSM command: %w", err)
	}

	commandID := *sendResult.Command.CommandId
	t.Logf("SSM command ID: %s", commandID)

	// Wait for command completion
	for i := 0; i < 60; i++ {
		time.Sleep(3 * time.Second)

		result, err := clients.SSM.GetCommandInvocation(ctx, &ssm.GetCommandInvocationInput{
			CommandId:  aws.String(commandID),
			InstanceId: aws.String(instanceID),
		})
		if err != nil {
			if strings.Contains(err.Error(), "InvocationDoesNotExist") {
				continue
			}
			return "", "", fmt.Errorf("failed to get command invocation: %w", err)
		}

		status := result.Status
		t.Logf("SSM command status: %s", status)

		switch status {
		case ssmtypes.CommandInvocationStatusSuccess:
			stdout := aws.ToString(result.StandardOutputContent)
			stderr := aws.ToString(result.StandardErrorContent)
			return stdout, stderr, nil
		case ssmtypes.CommandInvocationStatusFailed, ssmtypes.CommandInvocationStatusCancelled, ssmtypes.CommandInvocationStatusTimedOut:
			stdout := aws.ToString(result.StandardOutputContent)
			stderr := aws.ToString(result.StandardErrorContent)
			return stdout, stderr, fmt.Errorf("SSM command %s: %s", status, stderr)
		}
	}

	return "", "", fmt.Errorf("SSM command timed out after 3 minutes")
}

// =============================================================================
// GITHUB HELPERS
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

// WatchForWorkflowRun watches for workflow_dispatch runs of a specific workflow file.
// User registers the app and triggers the workflow manually; test detects and monitors.
func WatchForWorkflowRun(t *testing.T, repo, workflowFile, testID string, startTime time.Time, timeout time.Duration) (int64, error) {
	client, err := getGitHubClient()
	if err != nil {
		return 0, fmt.Errorf("failed to create GitHub client: %w", err)
	}

	owner, repoName, err := parseRepo(repo)
	if err != nil {
		return 0, fmt.Errorf("invalid repo format: %w", err)
	}

	ctx := context.Background()
	deadline := time.Now().Add(timeout)
	pollInterval := 15 * time.Second
	abortFile := fmt.Sprintf("/tmp/runson-%s-abort", testID)

	t.Logf("Watching for workflow_dispatch runs of %s (timeout: %v)", workflowFile, timeout)
	t.Logf("To abort gracefully: touch %s", abortFile)

	for time.Now().Before(deadline) {
		if _, err := os.Stat(abortFile); err == nil {
			os.Remove(abortFile)
			return 0, fmt.Errorf("test aborted by user (detected %s)", abortFile)
		}

		runs, _, err := client.Actions.ListWorkflowRunsByFileName(
			ctx, owner, repoName, workflowFile,
			&github.ListWorkflowRunsOptions{
				Event:       "workflow_dispatch",
				ListOptions: github.ListOptions{PerPage: 10},
			})
		if err != nil {
			t.Logf("Error listing workflow runs: %v (retrying...)", err)
			time.Sleep(pollInterval)
			continue
		}

		for _, run := range runs.WorkflowRuns {
			if run.CreatedAt != nil && run.CreatedAt.Time.After(startTime.Add(-1*time.Minute)) {
				runID := run.GetID()
				status := run.GetStatus()
				t.Logf("Found workflow run %d (status: %s, created: %s)",
					runID, status, run.CreatedAt.Time.Format(time.RFC3339))
				return runID, nil
			}
		}

		remaining := time.Until(deadline)
		t.Logf("No matching workflow runs yet, watching... (%v remaining)", remaining.Round(time.Second))
		time.Sleep(pollInterval)
	}

	return 0, fmt.Errorf("timeout waiting for workflow run of %s", workflowFile)
}

// MonitorWorkflowJobStates monitors job states and detects stuck "queued" jobs.
// Returns nil when any job reaches "in_progress" or "completed" (runner picked it up).
// Returns error if all jobs stay "queued" longer than queuedTimeout.
func MonitorWorkflowJobStates(t *testing.T, repo string, runID int64, queuedTimeout time.Duration) error {
	client, err := getGitHubClient()
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	owner, repoName, err := parseRepo(repo)
	if err != nil {
		return fmt.Errorf("invalid repo format: %w", err)
	}

	ctx := context.Background()
	deadline := time.Now().Add(queuedTimeout)
	pollInterval := 10 * time.Second

	t.Logf("Monitoring workflow run %d for job state transitions...", runID)
	t.Logf("Will fail if jobs stay 'queued' longer than %v (indicates no runner available)", queuedTimeout)

	for time.Now().Before(deadline) {
		jobs, _, err := client.Actions.ListWorkflowJobs(ctx, owner, repoName, runID, &github.ListWorkflowJobsOptions{
			Filter: "all",
		})
		if err != nil {
			t.Logf("Error listing jobs: %v (retrying...)", err)
			time.Sleep(pollInterval)
			continue
		}

		if len(jobs.Jobs) == 0 {
			t.Logf("No jobs found yet, waiting...")
			time.Sleep(pollInterval)
			continue
		}

		jobStates := make(map[string]int)
		for _, job := range jobs.Jobs {
			status := job.GetStatus()
			jobStates[status]++

			if status == "in_progress" || status == "completed" {
				runnerName := ""
				if job.RunnerName != nil {
					runnerName = *job.RunnerName
				}
				t.Logf("Job '%s' is %s (runner: %s) - runner is working!",
					job.GetName(), status, runnerName)
				return nil
			}
		}

		elapsed := time.Since(deadline.Add(-queuedTimeout))
		t.Logf("Job states: %v (queued for %v)", jobStates, elapsed.Round(time.Second))
		time.Sleep(pollInterval)
	}

	return fmt.Errorf("jobs stuck in 'queued' state for %v - likely no runner available (is the RunsOn app registered?)", queuedTimeout)
}
