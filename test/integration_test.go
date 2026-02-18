package test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/go-github/v68/github"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestIntegrationEndToEnd runs an automated end-to-end integration test.
//
// The test uses a fixture with force_destroy_buckets=false so that S3 buckets
// survive `terraform destroy`. This preserves the GitHub App registration
// (stored as app.json in the config bucket) across runs.
//
// First run:
//  1. Deploy infrastructure
//  2. Manually register the RunsOn app at the App Runner URL printed in output
//  3. Test dispatches workflow and monitors completion
//  4. On destroy, everything is cleaned up except S3 buckets
//
// Subsequent runs (automated):
//  1. Deploy infrastructure (terraform reuses existing buckets from state)
//  2. App Runner reads app.json from existing config bucket — operational immediately
//  3. Test dispatches workflow and monitors completion
//  4. Cleanup preserves buckets for next run
//
// Required env vars:
//   - GITHUB_TOKEN: GitHub API token with workflow permissions
//   - RUNS_ON_TEST_REPO: Repository in "owner/repo" format
//   - RUNS_ON_TEST_WORKFLOW: Workflow file name (e.g., "test.yml")
//   - RUNS_ON_LICENSE_KEY: RunsOn license key
//
// Optional env vars:
//   - RUNS_ON_INT_STACK_NAME: Fixed stack name (default: "runs-on-int-test")
//   - AWS_REGION: AWS region (default: "us-east-1")
func TestIntegrationEndToEnd(t *testing.T) {
	t.Parallel()

	// Check required env vars
	requiredEnvVars := []string{"GITHUB_TOKEN", "RUNS_ON_TEST_REPO", "RUNS_ON_TEST_WORKFLOW", "RUNS_ON_LICENSE_KEY"}
	for _, envVar := range requiredEnvVars {
		if os.Getenv(envVar) == "" {
			t.Skipf("Skipping integration test: %s not set", envVar)
		}
	}

	stackName := GetOptionalEnv("RUNS_ON_INT_STACK_NAME", "runs-on-int-test")
	region := GetAWSRegion()

	cfg := DefaultScenarioConfig()

	// Deploy integration fixture (VPC + RunsOn in single state)
	moduleOptions := &terraform.Options{
		TerraformDir:    "./fixtures/integration",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"stack_name":            stackName,
			"github_organization":   cfg.GithubOrg,
			"license_key":           cfg.LicenseKey,
			"email":                 "test@example.com",
			"environment":           "test",
			"force_destroy_buckets": false,
			"aws_region":            region,
		},
		NoColor: true,
	}

	// Use DestroyE to tolerate S3 bucket deletion failures (expected behavior)
	defer func() {
		_, err := terraform.DestroyE(t, moduleOptions)
		if err != nil {
			t.Logf("Partial destroy (expected - S3 buckets preserved for next run): %v", err)
		}
	}()
	terraform.InitAndApply(t, moduleOptions)

	appRunnerURL := terraform.Output(t, moduleOptions, "apprunner_service_url")
	outputStackName := terraform.Output(t, moduleOptions, "stack_name")

	t.Logf("App Runner URL: https://%s", appRunnerURL)
	t.Logf("Stack Name: %s", outputStackName)

	// Health check
	ValidateAppRunnerHealth(t, appRunnerURL, 20)

	// Trigger workflow dispatch
	testRepo := os.Getenv("RUNS_ON_TEST_REPO")
	testWorkflow := os.Getenv("RUNS_ON_TEST_WORKFLOW")

	client, err := getGitHubClient()
	require.NoError(t, err, "Failed to create GitHub client")

	owner, repoName, err := parseRepo(testRepo)
	require.NoError(t, err, "Invalid RUNS_ON_TEST_REPO format")

	startTime := time.Now()

	t.Logf("Dispatching workflow %s on %s/%s...", testWorkflow, owner, repoName)
	_, err = client.Actions.CreateWorkflowDispatchEventByFileName(
		context.Background(), owner, repoName, testWorkflow,
		github.CreateWorkflowDispatchEventRequest{
			Ref: "main",
		},
	)
	require.NoError(t, err, "Failed to trigger workflow dispatch. If this is the first run, register the app at https://%s first.", appRunnerURL)
	t.Logf("Workflow dispatched successfully")

	// Wait for the workflow run to appear
	testID := GetTestID()
	runID, err := WatchForWorkflowRun(t, testRepo, testWorkflow, testID, startTime, 5*time.Minute)
	require.NoError(t, err, "Workflow run not found after dispatch")

	// Monitor job states — detects if RunsOn app isn't registered (jobs stay queued)
	err = MonitorWorkflowJobStates(t, testRepo, runID, 5*time.Minute)
	require.NoError(t, err, "Jobs stuck in queue. If this is the first run, register the RunsOn app at https://%s", appRunnerURL)

	// Wait for workflow completion
	conclusion := WaitForWorkflowCompletion(t, testRepo, runID, 10*time.Minute)
	assert.Equal(t, "success", conclusion, "Workflow should complete successfully")

	// Validate that a runner EC2 instance was launched
	clients := NewAWSClients(context.Background())
	launched := ValidateRunnerLaunched(t, clients, outputStackName, startTime)
	assert.True(t, launched, "Runner instance should have been launched for stack %s", outputStackName)

	t.Logf("Integration test passed! Runner successfully processed workflow job.")
}
