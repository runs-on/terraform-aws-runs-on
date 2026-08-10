package test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	ssmtypes "github.com/aws/aws-sdk-go-v2/service/ssm/types"
	ghinstallation "github.com/bradleyfalzon/ghinstallation/v2"
	"github.com/google/go-github/v84/github"
	"github.com/gruntwork-io/terratest/modules/files"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/joho/godotenv"
	"github.com/runs-on/terraform-aws-runs-on/modules/flex/test/internal/validationimage"
	"github.com/stretchr/testify/require"
	"golang.org/x/oauth2"
)

func init() {
	// Load .env file if present (does not override existing env vars)
	_ = godotenv.Load()
}

// GetTestID generates a unique test ID for resource naming.
// In CI, include the workflow run id plus a stable per-job hash so concurrent jobs
// in the same run do not try to create the same stack and budget names.
func GetTestID() string {
	if runID := strings.TrimSpace(os.Getenv("GITHUB_RUN_ID")); runID != "" {
		if job := strings.TrimSpace(os.Getenv("GITHUB_JOB")); job != "" {
			hasher := fnv.New32a()
			_, _ = hasher.Write([]byte(job))
			if attempt := strings.TrimSpace(os.Getenv("GITHUB_RUN_ATTEMPT")); attempt != "" {
				_, _ = hasher.Write([]byte{0})
				_, _ = hasher.Write([]byte(attempt))
			}
			return fmt.Sprintf("%s-%08x", runID, hasher.Sum32())
		}
		if attempt := strings.TrimSpace(os.Getenv("GITHUB_RUN_ATTEMPT")); attempt != "" {
			return fmt.Sprintf("%s-%s", runID, attempt)
		}
		return runID
	}

	now := time.Now()
	return fmt.Sprintf("%d-%08x", now.Unix(), uint32(now.UnixNano()))
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
	TestID      string
	GithubOrg   string
	LicenseKey  string
	Environment string
	CreatedAt   time.Time
	EnableEFS   bool
	EnableECR   bool
	EnableNAT   bool
	PrivateMode string // "false", "true", "always", "only" — implies EnableNAT when not "false"
	AWSRegion   string

	// App version overrides are injected by the caller or the ci-image Make targets.
	AppImage         string
	AppTag           string
	AppECRRepository string // private ECR image URL (overrides AppImage when set)

	// ForceDestroyBuckets controls whether S3 buckets can be force-destroyed on terraform destroy.
	// Set to false for integration tests that preserve buckets across runs.
	ForceDestroyBuckets bool

	// FixedStackName overrides the auto-generated stack name.
	// Used by integration tests that need a stable stack name across runs.
	FixedStackName string

	// GitHub App credentials (optional). When GithubAppID is set, credentials are
	// passed to Terraform as github_app_* variables, creating a Secrets Manager
	// secret so the server skips web-based GitHub App registration.
	GithubAppID            int64
	GithubAppPrivateKey    string
	GithubAppWebhookSecret string
	GithubAppClientID      string
	GithubAppClientSecret  string
}

// DefaultScenarioConfig returns config with sensible test defaults
func DefaultScenarioConfig() ScenarioConfig {
	testID := GetTestID()
	createdAt := time.Now().UTC().Truncate(time.Second)
	return ScenarioConfig{
		TestID:              testID,
		GithubOrg:           getGithubOrg(),
		LicenseKey:          strings.TrimSpace(os.Getenv("RUNS_ON_LICENSE_KEY")),
		Environment:         fmt.Sprintf("test-%s", testID),
		CreatedAt:           createdAt,
		AWSRegion:           GetOptionalEnv("AWS_REGION", "us-east-1"),
		AppImage:            strings.TrimSpace(os.Getenv("RUNS_ON_APP_IMAGE")),
		AppTag:              strings.TrimSpace(os.Getenv("RUNS_ON_APP_TAG")),
		AppECRRepository:    os.Getenv("RUNS_ON_APP_ECR_URL"),
		ForceDestroyBuckets: true,
	}
}

func requireValidationEnv(t *testing.T, scenario string, mode validationimage.EnvMode) {
	t.Helper()

	required, err := requiredValidationEnvVars(scenario, mode)
	require.NoError(t, err)

	missing := validationimage.MissingEnvVars(required, os.Getenv)
	require.Emptyf(
		t,
		missing,
		"missing required env vars for %s validation: %s",
		scenario,
		strings.Join(missing, ", "),
	)
}

func requiredValidationEnvVars(scenario string, mode validationimage.EnvMode) ([]string, error) {
	required, err := validationimage.RequiredEnvVars(scenario, mode)
	if err != nil {
		return nil, err
	}
	if missingGithubOrgSource() {
		required = append(required, "GITHUB_ORG or RUNS_ON_TEST_REPO")
	}
	return required, nil
}

func missingGithubOrgSource() bool {
	return strings.TrimSpace(os.Getenv("GITHUB_ORG")) == "" && strings.TrimSpace(os.Getenv("RUNS_ON_TEST_REPO")) == ""
}

// getGithubOrg extracts the GitHub organization from RUNS_ON_TEST_REPO or GITHUB_ORG.
// Priority: GITHUB_ORG > RUNS_ON_TEST_REPO (owner part).
func getGithubOrg() string {
	if org := strings.TrimSpace(os.Getenv("GITHUB_ORG")); org != "" {
		return org
	}
	if testRepo := strings.TrimSpace(os.Getenv("RUNS_ON_TEST_REPO")); testRepo != "" {
		parts := strings.Split(testRepo, "/")
		if len(parts) >= 1 {
			return strings.TrimSpace(parts[0])
		}
	}
	return ""
}

// StackName returns the stack name for this config.
func (c ScenarioConfig) StackName() string {
	if c.FixedStackName != "" {
		return c.FixedStackName
	}
	return fmt.Sprintf("test-%s", c.TestID)
}

func (c ScenarioConfig) UsesDeclarativeGitHubApp() bool {
	return c.GithubAppID != 0
}

// ToVPCVars converts config to VPC module variables
func (c ScenarioConfig) ToVPCVars() map[string]any {
	return map[string]any{
		"test_id":    c.TestID,
		"aws_region": c.AWSRegion,
		"enable_nat": c.EnableNAT,
		"test_tags":  c.TestTags(),
	}
}

func (c ScenarioConfig) TestTags() map[string]string {
	tags := map[string]string{
		"CreatedAt": c.CreatedAt.UTC().Format(time.RFC3339),
	}

	addEnvTag(tags, "GithubRunId", "GITHUB_RUN_ID")
	addEnvTag(tags, "GithubRunAttempt", "GITHUB_RUN_ATTEMPT")
	addEnvTag(tags, "GithubJob", "GITHUB_JOB")

	return tags
}

func addEnvTag(tags map[string]string, tagKey, envKey string) {
	if value := strings.TrimSpace(os.Getenv(envKey)); value != "" {
		tags[tagKey] = value
	}
}

// ToModuleVars converts config to runs-on root module variables
func (c ScenarioConfig) ToModuleVars(vpcID string, publicSubnets, privateSubnets []string) map[string]any {
	vars := map[string]any{
		"stack_name":                         c.StackName(),
		"github_organization":                c.GithubOrg,
		"license_key":                        c.LicenseKey,
		"vpc_id":                             vpcID,
		"public_subnet_ids":                  publicSubnets,
		"enable_efs":                         c.EnableEFS,
		"enable_ecr":                         c.EnableECR,
		"environment":                        c.Environment,
		"email":                              "test@example.com",
		"log_retention_days":                 1,
		"cache_expiration_days":              1,
		"app_size":                           "medium",
		"force_destroy_buckets":              c.ForceDestroyBuckets,
		"prevent_destroy_optional_resources": false,
	}

	if c.AppImage != "" {
		vars["app_image"] = c.AppImage
	}
	if c.AppTag != "" {
		vars["app_tag"] = c.AppTag
	}
	if c.AppECRRepository != "" {
		vars["app_ecr_repository_url"] = c.AppECRRepository
	}

	if c.PrivateMode != "" && c.PrivateMode != "false" {
		vars["private_mode"] = c.PrivateMode
		vars["private_mode_delay"] = "60s"
	}

	if len(privateSubnets) > 0 && c.EnableNAT {
		vars["private_subnet_ids"] = privateSubnets
	}

	if c.GithubAppID != 0 {
		vars["github_app_id"] = c.GithubAppID
		vars["github_app_client_id"] = c.GithubAppClientID
	}

	return vars
}

// ToModuleEnvVars returns sensitive/multiline values as TF_VAR_ environment variables.
// These can't be passed as -var CLI flags (multiline strings break the command).
func (c ScenarioConfig) ToModuleEnvVars() map[string]string {
	envVars := map[string]string{}
	if c.GithubAppID != 0 {
		envVars["TF_VAR_github_app_private_key"] = c.GithubAppPrivateKey
		envVars["TF_VAR_github_app_webhook_secret"] = c.GithubAppWebhookSecret
		envVars["TF_VAR_github_app_client_secret"] = c.GithubAppClientSecret
	}
	return envVars
}

// =============================================================================
// AWS SDK HELPERS
// =============================================================================

// MustGetAWSConfig creates a reusable AWS config, panicking on error
func MustGetAWSConfig(ctx context.Context) aws.Config {
	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(GetAWSRegion()),
	)
	if err != nil {
		panic(fmt.Sprintf("failed to load AWS config: %v", err))
	}
	return cfg
}

// =============================================================================
// TERRAFORM TEST PATHS
// =============================================================================

type terraformTestPaths struct {
	TerraformRoot string
	VPCFixtureDir string
}

func copyTerraformRoot(t *testing.T, prefix string) string {
	t.Helper()

	safePrefix := strings.NewReplacer("/", "-", "\\", "-", " ", "-").Replace(prefix)
	// Copy the whole terraform workspace so the flex module keeps sibling module
	// and lambda-source references when Terratest runs from an isolated temp dir.
	terraformWorkspace, err := files.CopyTerraformFolderToTemp("../../../", safePrefix)
	require.NoError(t, err, "Failed to copy terraform tree to temp dir")
	return filepath.Join(terraformWorkspace, "modules", "flex")
}

func newScenarioPaths(t *testing.T) terraformTestPaths {
	t.Helper()

	terraformRoot := copyTerraformRoot(t, t.Name())
	return terraformTestPaths{
		TerraformRoot: terraformRoot,
		VPCFixtureDir: filepath.Join(terraformRoot, "test", "fixtures", "vpc"),
	}
}

// =============================================================================
// SCENARIO HARNESS
// =============================================================================

func deployScenario(t *testing.T, cfg ScenarioConfig) ScenarioResult {
	t.Helper()

	paths := newScenarioPaths(t)

	// Deploy VPC fixture
	vpcOptions := &terraform.Options{
		TerraformDir:    paths.VPCFixtureDir,
		TerraformBinary: "tofu",
		Vars:            cfg.ToVPCVars(),
		NoColor:         true,
	}
	t.Cleanup(func() {
		destroyScenario(t, "VPC", vpcOptions)
	})
	initAndApply(t, "VPC", vpcOptions)

	vpcID := terraform.Output(t, vpcOptions, "vpc_id")
	publicSubnets := terraform.OutputList(t, vpcOptions, "public_subnets")
	privateSubnets := terraform.OutputList(t, vpcOptions, "private_subnets")

	// Deploy root module
	moduleOptions := &terraform.Options{
		TerraformDir:    paths.TerraformRoot,
		TerraformBinary: "tofu",
		Vars:            cfg.ToModuleVars(vpcID, publicSubnets, privateSubnets),
		EnvVars:         cfg.ToModuleEnvVars(),
		NoColor:         true,
	}
	t.Cleanup(func() {
		destroyScenario(t, "module", moduleOptions)
	})
	initAndApply(t, "module", moduleOptions)

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

	return result
}

func integrationScenarioConfigFromEnv(t *testing.T) ScenarioConfig {
	t.Helper()

	appID, err := strconv.ParseInt(os.Getenv("GITHUB_APP_ID"), 10, 64)
	require.NoError(t, err, "GITHUB_APP_ID must be a valid integer")

	cfg := DefaultScenarioConfig()
	cfg.GithubAppID = appID
	cfg.GithubAppPrivateKey = os.Getenv("GITHUB_APP_PRIVATE_KEY")
	cfg.GithubAppWebhookSecret = os.Getenv("GITHUB_APP_WEBHOOK_SECRET")
	cfg.GithubAppClientID = os.Getenv("GITHUB_APP_CLIENT_ID")
	cfg.GithubAppClientSecret = os.Getenv("GITHUB_APP_CLIENT_SECRET")
	cfg.EnableEFS = os.Getenv("ENABLE_EFS") == "true"
	cfg.EnableECR = os.Getenv("ENABLE_ECR") == "true"

	if pm := os.Getenv("PRIVATE_MODE"); pm != "" && pm != "false" {
		cfg.PrivateMode = pm
		cfg.EnableNAT = true
	}

	return cfg
}

func runningInCI() bool {
	return os.Getenv("GITHUB_ACTIONS") == "true"
}

func quietTerraformOptionsInCI(t *testing.T, options *terraform.Options) *terraform.Options {
	t.Helper()

	if !runningInCI() {
		return options
	}

	quietOptions, err := options.Clone()
	require.NoError(t, err, "failed to clone terraform options for quiet command")
	quietOptions.Logger = logger.Discard
	return quietOptions
}

func initAndApply(t *testing.T, name string, options *terraform.Options) {
	t.Helper()

	_, err := terraform.InitE(t, options)
	require.NoError(t, err, "%s init should succeed", name)

	applyOptions := quietTerraformOptionsInCI(t, options)
	out, err := terraform.ApplyE(t, applyOptions)
	if err != nil {
		if strings.TrimSpace(out) != "" {
			t.Logf("%s apply output:\n%s", name, out)
		}
		require.NoErrorf(t, err, "%s apply failed.\nCaptured output:\n%s", name, out)
	}
}

func destroyScenario(t *testing.T, name string, options *terraform.Options) {
	t.Helper()

	destroyOptions := quietTerraformOptionsInCI(t, options)
	out, err := terraform.DestroyE(t, destroyOptions)
	if err != nil {
		if strings.TrimSpace(out) != "" {
			t.Logf("%s destroy output:\n%s", name, out)
		}
		require.NoErrorf(t, err, "%s destroy failed.\nCaptured output:\n%s", name, out)
	}
}

// extractOutputs reads all terraform outputs at once via `tofu output -json`.
// This avoids per-key queries that fail fatally for optional null outputs.
func extractOutputs(t *testing.T, opts *terraform.Options) map[string]any {
	outputs := make(map[string]any)

	jsonStr := terraform.RunTerraformCommand(t, opts, "output", "-json")

	var raw map[string]struct {
		Value any `json:"value"`
	}
	err := json.Unmarshal([]byte(jsonStr), &raw)
	require.NoError(t, err, "Failed to parse terraform output JSON")

	for key, entry := range raw {
		outputs[key] = entry.Value
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
	for range 60 {
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

// getGitHubInstallationClient creates a GitHub client authenticated as a GitHub App installation.
// It uses the App's private key to mint a JWT, finds the installation for the given org,
// and returns a client that auto-refreshes installation access tokens.
func getGitHubInstallationClient(appID int64, privateKey, owner string) (*github.Client, error) {
	appTransport, err := ghinstallation.NewAppsTransport(
		http.DefaultTransport, appID, []byte(privateKey),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create GitHub App JWT transport: %w", err)
	}

	appClient := github.NewClient(&http.Client{Transport: appTransport})
	installation, _, err := appClient.Apps.FindOrganizationInstallation(
		context.Background(), owner,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to find installation for org %s: %w", owner, err)
	}

	itr := ghinstallation.NewFromAppsTransport(appTransport, installation.GetID())
	return github.NewClient(&http.Client{Transport: itr}), nil
}

func requireGitHubAppRepositoryAccess(t *testing.T, appID int64, privateKey, owner, repo string) {
	t.Helper()

	transport, err := ghinstallation.NewAppsTransport(
		http.DefaultTransport, appID, []byte(privateKey),
	)
	require.NoError(t, err, "Failed to create GitHub App JWT transport")

	client := github.NewClient(&http.Client{Transport: transport})
	installation, _, err := client.Apps.FindRepositoryInstallation(context.Background(), owner, repo)
	if err == nil {
		t.Logf("GitHub App installation %d can access %s/%s", installation.GetID(), owner, repo)
		return
	}

	var ghErr *github.ErrorResponse
	if errors.As(err, &ghErr) && ghErr.Response != nil && ghErr.Response.StatusCode == http.StatusNotFound {
		require.FailNowf(
			t,
			"configured GitHub App cannot access integration test repository",
			"Configured GitHub App %d cannot access %s/%s. Fix the app installation or repository selection before running the integration test.",
			appID,
			owner,
			repo,
		)
	}

	require.NoErrorf(t, err, "Failed to verify GitHub App access to %s/%s", owner, repo)
}

// getGitHubActionsClient prefers GITHUB_TOKEN when available because workflow dispatch
// permissions may differ from the GitHub App installation token used for webhook updates.
func getGitHubActionsClient(appID int64, privateKey, owner string) (*github.Client, error) {
	token := strings.TrimSpace(os.Getenv("GITHUB_TOKEN"))
	if token == "" {
		return getGitHubInstallationClient(appID, privateKey, owner)
	}

	tokenSource := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	return github.NewClient(oauth2.NewClient(context.Background(), tokenSource)), nil
}

// UpdateGitHubAppWebhookURL authenticates as a GitHub App using JWT and updates
// the App's webhook URL via PATCH /app/hook/config.
func UpdateGitHubAppWebhookURL(t *testing.T, appID int64, privateKey string, webhookURL string) {
	t.Helper()

	transport, err := ghinstallation.NewAppsTransport(
		http.DefaultTransport, appID, []byte(privateKey),
	)
	require.NoError(t, err, "Failed to create GitHub App JWT transport")

	client := github.NewClient(&http.Client{Transport: transport})
	_, _, err = client.Apps.UpdateHookConfig(
		context.Background(),
		&github.HookConfig{URL: new(webhookURL)},
	)
	require.NoError(t, err, "Failed to update GitHub App webhook URL")
	t.Logf("Updated GitHub App webhook URL to: %s", webhookURL)
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
func WaitForWorkflowCompletion(t *testing.T, client *github.Client, repo string, runID int64, timeout time.Duration) string {
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
func WatchForWorkflowRun(t *testing.T, client *github.Client, repo, workflowFile, testID, expectedStackEnv, expectedRef string, startTime time.Time, timeout time.Duration) (int64, error) {
	owner, repoName, err := parseRepo(repo)
	if err != nil {
		return 0, fmt.Errorf("invalid repo format: %w", err)
	}

	ctx := context.Background()
	deadline := time.Now().Add(timeout)
	pollInterval := 15 * time.Second
	abortFile := fmt.Sprintf("/tmp/runson-%s-abort", testID)
	var latestRuns []*github.WorkflowRun

	t.Logf("Watching for workflow_dispatch runs of %s (timeout: %v)", workflowFile, timeout)
	t.Logf("To abort gracefully: touch %s", abortFile)

	for time.Now().Before(deadline) {
		if _, err := os.Stat(abortFile); err == nil {
			os.Remove(abortFile)
			return 0, fmt.Errorf("test aborted by user (detected %s)", abortFile)
		}

		runs, _, err := client.Actions.ListRepositoryWorkflowRuns(
			ctx, owner, repoName,
			&github.ListWorkflowRunsOptions{
				Event:       "workflow_dispatch",
				ListOptions: github.ListOptions{PerPage: 50},
			})
		if err != nil {
			t.Logf("Error listing workflow runs: %v (retrying...)", err)
			time.Sleep(pollInterval)
			continue
		}
		latestRuns = runs.WorkflowRuns

		for _, run := range runs.WorkflowRuns {
			if workflowRunMatches(run, workflowFile, expectedStackEnv, expectedRef, startTime) {
				runID := run.GetID()
				status := run.GetStatus()
				t.Logf("Found workflow run %d (status: %s, created: %s, url: %s)",
					runID, status, run.CreatedAt.Time.Format(time.RFC3339), run.GetHTMLURL())
				return runID, nil
			}
		}

		remaining := time.Until(deadline)
		t.Logf("No matching workflow runs yet, watching... (%v remaining)", remaining.Round(time.Second))
		time.Sleep(pollInterval)
	}

	logWorkflowRunCandidates(t, latestRuns, workflowFile, startTime)
	return 0, fmt.Errorf("timeout waiting for workflow run of %s", workflowFile)
}

func workflowRunMatches(run *github.WorkflowRun, workflowFile, expectedStackEnv, expectedRef string, startTime time.Time) bool {
	if run == nil {
		return false
	}
	if run.GetEvent() != "workflow_dispatch" {
		return false
	}
	if !workflowIdentifierMatches(run.GetPath(), workflowFile) && !workflowIdentifierMatches(run.GetName(), workflowFile) {
		return false
	}
	if run.CreatedAt == nil || run.CreatedAt.Time.Before(startTime.Add(-2*time.Minute)) {
		return false
	}
	if expectedStackEnv != "" && !strings.Contains(run.GetDisplayTitle(), expectedStackEnv) && !strings.Contains(run.GetName(), expectedStackEnv) {
		return false
	}
	if expectedRef != "" && run.GetHeadBranch() != "" && normalizeGitHubRef(expectedRef) != run.GetHeadBranch() {
		return false
	}
	return true
}

func workflowIdentifierMatches(identifier, workflowFile string) bool {
	identifier = normalizeWorkflowIdentifier(identifier)
	workflowFile = normalizeWorkflowIdentifier(workflowFile)
	if identifier == "" || workflowFile == "" {
		return false
	}
	return identifier == workflowFile || filepath.Base(identifier) == filepath.Base(workflowFile)
}

func normalizeWorkflowIdentifier(identifier string) string {
	identifier = strings.TrimSpace(identifier)
	identifier = strings.TrimPrefix(identifier, "./")
	identifier = strings.TrimPrefix(identifier, ".github/workflows/")
	return identifier
}

func normalizeGitHubRef(ref string) string {
	ref = strings.TrimSpace(ref)
	ref = strings.TrimPrefix(ref, "refs/heads/")
	ref = strings.TrimPrefix(ref, "refs/tags/")
	return ref
}

func logWorkflowRunCandidates(t *testing.T, runs []*github.WorkflowRun, workflowFile string, startTime time.Time) {
	t.Helper()

	if len(runs) == 0 {
		t.Logf("No workflow_dispatch runs were returned while waiting for %s", workflowFile)
		return
	}

	t.Logf("Latest workflow_dispatch runs considered for %s since %s:", workflowFile, startTime.Add(-2*time.Minute).UTC().Format(time.RFC3339))
	for i, run := range runs {
		if i >= 10 {
			t.Logf("... %d more runs omitted", len(runs)-i)
			return
		}
		created := ""
		if run.CreatedAt != nil {
			created = run.CreatedAt.Time.Format(time.RFC3339)
		}
		t.Logf(
			"run id=%d url=%s path=%s name=%q title=%q branch=%s sha=%s created=%s status=%s conclusion=%s",
			run.GetID(),
			run.GetHTMLURL(),
			run.GetPath(),
			run.GetName(),
			run.GetDisplayTitle(),
			run.GetHeadBranch(),
			run.GetHeadSHA(),
			created,
			run.GetStatus(),
			run.GetConclusion(),
		)
	}
}

// MonitorWorkflowJobStates monitors job states and detects stuck "queued" jobs.
// Returns nil when any job reaches "in_progress" or "completed" (runner picked it up).
// Returns error if all jobs stay "queued" longer than queuedTimeout.
func MonitorWorkflowJobStates(t *testing.T, client *github.Client, repo string, runID int64, queuedTimeout time.Duration) error {
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

// BootTimings holds timing data extracted from workflow job logs.
type BootTimings struct {
	TotalDuration     float64 // seconds, from "Timings - X.XXs" group header
	AgentBootingTotal float64 // seconds, Total column on the agent-booting row
}

var (
	reTimingsHeader = regexp.MustCompile(`Timings.*?-\s+(\d+\.?\d*)s`)
	reTimingValue   = regexp.MustCompile(`(\d+\.?\d*)s`)
)

// FetchJobLogs retrieves the raw log text for each job in a workflow run.
// Returns a map of job name to log text.
func FetchJobLogs(t *testing.T, client *github.Client, repo string, runID int64) map[string]string {
	t.Helper()

	owner, repoName, err := parseRepo(repo)
	require.NoError(t, err, "Invalid repo format")

	ctx := context.Background()

	jobs, _, err := client.Actions.ListWorkflowJobs(ctx, owner, repoName, runID, &github.ListWorkflowJobsOptions{
		Filter: "all",
	})
	require.NoError(t, err, "Failed to list workflow jobs for run %d", runID)

	logs := make(map[string]string)
	for _, job := range jobs.Jobs {
		jobName := job.GetName()
		logURL, _, err := client.Actions.GetWorkflowJobLogs(ctx, owner, repoName, job.GetID(), 2)
		if err != nil {
			t.Logf("Warning: failed to get log URL for job %q: %v", jobName, err)
			continue
		}

		resp, err := http.Get(logURL.String()) // #nosec G107 -- URL from GitHub API
		if err != nil {
			t.Logf("Warning: failed to fetch logs for job %q: %v", jobName, err)
			continue
		}
		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			t.Logf("Warning: failed to read log body for job %q: %v", jobName, err)
			continue
		}

		logs[jobName] = string(body)
		t.Logf("Fetched %d bytes of logs for job %q", len(body), jobName)
	}

	return logs
}

// ParseBootTimings extracts boot timing data from a workflow job's raw log text.
// Returns nil if no timing data is found.
func ParseBootTimings(logText string) *BootTimings {
	bt := &BootTimings{}
	found := false

	// Extract total duration from "::group::⏱️ Timings - X.XXs" header
	if m := reTimingsHeader.FindStringSubmatch(logText); len(m) > 1 {
		if v, err := strconv.ParseFloat(m[1], 64); err == nil {
			bt.TotalDuration = v
			found = true
		}
	}

	// Find the agent-booting row and extract the Total column (last Xs value on the line)
	for line := range strings.SplitSeq(logText, "\n") {
		if strings.Contains(line, "agent-booting") {
			matches := reTimingValue.FindAllStringSubmatch(line, -1)
			if len(matches) > 0 {
				last := matches[len(matches)-1]
				if v, err := strconv.ParseFloat(last[1], 64); err == nil {
					bt.AgentBootingTotal = v
					found = true
				}
			}
			break
		}
	}

	if !found {
		return nil
	}
	return bt
}
