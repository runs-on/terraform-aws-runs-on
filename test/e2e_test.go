package test

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/google/go-github/v68/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestE2E runs a fully automated, fully ephemeral end-to-end test.
//
// The test deploys fresh infrastructure with pre-configured GitHub App credentials
// (injected via Terraform variables into a Secrets Manager secret). After deployment,
// it updates the GitHub App's webhook URL to point to the new App Runner service,
// triggers a workflow, and verifies the runner processes the job. All infrastructure
// is destroyed on completion.
//
// Authentication uses a GitHub App installation token derived from the App credentials.
// No separate GITHUB_TOKEN or PAT is required.
//
// Required env vars:
//   - RUNS_ON_TEST_REPO: Repository in "owner/repo" format
//   - RUNS_ON_TEST_WORKFLOW: Workflow file name (e.g., "test.yml")
//   - RUNS_ON_LICENSE_KEY: RunsOn license key
//   - GITHUB_APP_ID: GitHub App ID (numeric)
//   - GITHUB_APP_PRIVATE_KEY: GitHub App private key (PEM format)
//   - GITHUB_APP_WEBHOOK_SECRET: GitHub App webhook secret
//   - GITHUB_APP_CLIENT_ID: GitHub App OAuth client ID
//   - GITHUB_APP_CLIENT_SECRET: GitHub App OAuth client secret
func TestE2E(t *testing.T) {
	// Check required env vars
	requiredEnvVars := []string{
		"RUNS_ON_TEST_REPO",
		"RUNS_ON_TEST_WORKFLOW",
		"RUNS_ON_LICENSE_KEY",
		"GITHUB_APP_ID",
		"GITHUB_APP_PRIVATE_KEY",
		"GITHUB_APP_WEBHOOK_SECRET",
		"GITHUB_APP_CLIENT_ID",
		"GITHUB_APP_CLIENT_SECRET",
	}
	for _, envVar := range requiredEnvVars {
		if os.Getenv(envVar) == "" {
			t.Skipf("Skipping integration test: %s not set", envVar)
		}
	}

	// Parse GitHub App ID
	appID, err := strconv.ParseInt(os.Getenv("GITHUB_APP_ID"), 10, 64)
	require.NoError(t, err, "GITHUB_APP_ID must be a valid integer")

	testRepo := os.Getenv("RUNS_ON_TEST_REPO")
	testWorkflow := os.Getenv("RUNS_ON_TEST_WORKFLOW")

	// Build config with GitHub App credentials
	cfg := DefaultScenarioConfig()
	cfg.GithubAppID = appID
	cfg.GithubAppPrivateKey = os.Getenv("GITHUB_APP_PRIVATE_KEY")
	cfg.GithubAppWebhookSecret = os.Getenv("GITHUB_APP_WEBHOOK_SECRET")
	cfg.GithubAppClientID = os.Getenv("GITHUB_APP_CLIENT_ID")
	cfg.GithubAppClientSecret = os.Getenv("GITHUB_APP_CLIENT_SECRET")

	// Scenario config from env vars — controls which features to deploy
	cfg.EnableEFS = os.Getenv("ENABLE_EFS") == "true"
	cfg.EnableECR = os.Getenv("ENABLE_ECR") == "true"
	if pm := os.Getenv("PRIVATE_MODE"); pm != "" && pm != "false" {
		cfg.PrivateMode = pm
		cfg.EnableNAT = true
	}

	// Create GitHub client using App installation token
	owner, repoName, err := parseRepo(testRepo)
	require.NoError(t, err, "Invalid RUNS_ON_TEST_REPO format")

	client, err := getGitHubInstallationClient(cfg.GithubAppID, cfg.GithubAppPrivateKey, owner)
	require.NoError(t, err, "Failed to create GitHub App installation client")

	runScenario(t, cfg, func(t *testing.T, r ScenarioResult) {
		appRunnerURL := r.AppRunnerURL()
		t.Logf("App Runner URL: https://%s", appRunnerURL)

		// 1. Health check — wait for App Runner to be ready
		ValidateAppRunnerHealth(t, appRunnerURL, 20)

		// 2. Update GitHub App webhook URL to point to this deployment
		webhookURL := fmt.Sprintf("https://%s/", appRunnerURL)
		UpdateGitHubAppWebhookURL(t, cfg.GithubAppID, cfg.GithubAppPrivateKey, webhookURL)

		// 3. Trigger workflow dispatch
		startTime := time.Now()

		t.Logf("Dispatching workflow %s on %s/%s...", testWorkflow, owner, repoName)
		_, err = client.Actions.CreateWorkflowDispatchEventByFileName(
			context.Background(), owner, repoName, testWorkflow,
			github.CreateWorkflowDispatchEventRequest{
				Ref: "main",
			},
		)
		require.NoError(t, err, "Failed to trigger workflow dispatch")
		t.Logf("Workflow dispatched successfully")

		// 4. Monitor execution
		testID := GetTestID()
		runID, err := WatchForWorkflowRun(t, client, testRepo, testWorkflow, testID, startTime, 5*time.Minute)
		require.NoError(t, err, "Workflow run not found after dispatch")

		err = MonitorWorkflowJobStates(t, client, testRepo, runID, 5*time.Minute)
		require.NoError(t, err, "Jobs stuck in queue — webhook URL may not have updated correctly")

		conclusion := WaitForWorkflowCompletion(t, client, testRepo, runID, 10*time.Minute)
		assert.Equal(t, "success", conclusion, "Workflow should complete successfully")

		// 5. Validate runner was launched
		clients := NewAWSClients(context.Background())
		launched := ValidateRunnerLaunched(t, clients, r.StackName(), startTime)
		assert.True(t, launched, "Runner instance should have been launched for stack %s", r.StackName())

		// 6. Extract boot timings from job logs
		jobLogs := FetchJobLogs(t, client, testRepo, runID)
		for jobName, logText := range jobLogs {
			if bt := ParseBootTimings(logText); bt != nil {
				t.Logf("Job %q: total=%.2fs, agent-booting-at=%.2fs",
					jobName, bt.TotalDuration, bt.AgentBootingTotal)
			}
		}

		t.Logf("E2E test passed! Runner successfully processed workflow job.")
	})
}
