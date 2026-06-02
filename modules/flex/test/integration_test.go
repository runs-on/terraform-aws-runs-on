package test

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/google/go-github/v84/github"
	"github.com/runs-on/terraform-aws-runs-on/modules/flex/test/internal/validationimage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestIntegrationEndToEnd runs a fully automated, fully ephemeral end-to-end test.
//
// The test deploys fresh infrastructure with pre-configured GitHub App credentials
// (injected via Terraform variables into a Secrets Manager secret). After deployment,
// it updates the GitHub App's webhook URL to point to the new public ingress,
// triggers a workflow, and verifies the runner processes the job. All infrastructure
// is destroyed on completion.
//
// Authentication uses a GitHub token for Actions API calls when available and falls back
// to a GitHub App installation token derived from the App credentials otherwise.
//
// Required env vars:
//   - RUNS_ON_TEST_REPO: Repository in "owner/repo" format
//   - RUNS_ON_TEST_WORKFLOW: Workflow file name (e.g., "test.yml")
//   - RUNS_ON_TEST_WORKFLOW_REF: Optional git ref containing the workflow file (defaults to "main")
//   - RUNS_ON_TEST_WORKFLOW_INPUTS: Optional JSON object of workflow_dispatch inputs
//   - RUNS_ON_LICENSE_KEY: RunsOn license key
//   - GITHUB_APP_ID: GitHub App ID (numeric)
//   - GITHUB_APP_PRIVATE_KEY: GitHub App private key (PEM format)
//   - GITHUB_APP_WEBHOOK_SECRET: GitHub App webhook secret
//   - GITHUB_APP_CLIENT_ID: GitHub App OAuth client ID
//   - GITHUB_APP_CLIENT_SECRET: GitHub App OAuth client secret
func TestIntegrationEndToEnd(t *testing.T) {
	requireValidationEnv(t, validationimage.ScenarioIntegration, validationimage.EnvModeDirect)

	testRepo := os.Getenv("RUNS_ON_TEST_REPO")
	testWorkflow := os.Getenv("RUNS_ON_TEST_WORKFLOW")
	testWorkflowRef := strings.TrimSpace(os.Getenv("RUNS_ON_TEST_WORKFLOW_REF"))
	if testWorkflowRef == "" {
		testWorkflowRef = "main"
	}
	testWorkflowInputs := map[string]any{}
	workflowInputsJSON := strings.TrimSpace(os.Getenv("RUNS_ON_TEST_WORKFLOW_INPUTS"))
	if workflowInputsJSON != "" {
		err := json.Unmarshal([]byte(workflowInputsJSON), &testWorkflowInputs)
		require.NoError(t, err, "RUNS_ON_TEST_WORKFLOW_INPUTS must be a valid JSON object")
	}

	cfg := integrationScenarioConfigFromEnv(t)
	if strings.HasSuffix(testWorkflow, "terraform-integration-runner.yml") || strings.HasSuffix(testWorkflow, "e2e-environments.yml") {
		if _, ok := testWorkflowInputs["stack_env"]; !ok {
			testWorkflowInputs["stack_env"] = cfg.Environment
		}
	}
	if strings.HasSuffix(testWorkflow, "e2e-environments.yml") {
		if _, ok := testWorkflowInputs["product"]; !ok {
			testWorkflowInputs["product"] = "flex"
		}
	}

	// Create GitHub client for workflow APIs
	owner, repoName, err := parseRepo(testRepo)
	require.NoError(t, err, "Invalid RUNS_ON_TEST_REPO format")
	requireGitHubAppRepositoryAccess(t, cfg.GithubAppID, cfg.GithubAppPrivateKey, owner, repoName)

	client, err := getGitHubActionsClient(cfg.GithubAppID, cfg.GithubAppPrivateKey, owner)
	require.NoError(t, err, "Failed to create GitHub Actions client")

	result := deployScenario(t, cfg)
	ingressURL := result.IngressURL()
	t.Logf("Ingress URL: %s", ingressURL)

	// 1. Health check — wait for the public ingress to be ready
	ValidateConfiguredIngressReadiness(t, ingressURL, 20)

	// 2. Update GitHub App webhook URL to point to this deployment
	webhookURL := fmt.Sprintf("%s/github/webhooks", strings.TrimRight(ingressURL, "/"))
	UpdateGitHubAppWebhookURL(t, cfg.GithubAppID, cfg.GithubAppPrivateKey, webhookURL)

	// 3. Trigger workflow dispatch
	startTime := time.Now()

	t.Logf("Dispatching workflow %s on %s/%s at ref %s...", testWorkflow, owner, repoName, testWorkflowRef)
	_, _, err = client.Actions.CreateWorkflowDispatchEventByFileName(
		context.Background(), owner, repoName, testWorkflow,
		github.CreateWorkflowDispatchEventRequest{
			Ref:    testWorkflowRef,
			Inputs: testWorkflowInputs,
		},
	)
	require.NoError(t, err, "Failed to trigger workflow dispatch")
	t.Logf("Workflow dispatched successfully")

	// 4. Monitor execution
	testID := GetTestID()
	stackEnv, _ := testWorkflowInputs["stack_env"].(string)
	runID, err := WatchForWorkflowRun(t, client, testRepo, testWorkflow, testID, stackEnv, testWorkflowRef, startTime, 5*time.Minute)
	require.NoError(t, err, "Workflow run not found after dispatch")

	// Fresh ephemeral stacks can rely on repo discovery before webhook-delivered
	// workflow-job history has populated the workflow jobs store.
	err = MonitorWorkflowJobStates(t, client, testRepo, runID, 5*time.Minute)
	require.NoError(t, err, "Jobs stuck in queue — webhook URL may not have updated correctly")

	conclusion := WaitForWorkflowCompletion(t, client, testRepo, runID, 10*time.Minute)
	assert.Equal(t, "success", conclusion, "Workflow should complete successfully")

	// 5. Validate runner was launched
	clients := NewAWSClients(context.Background())
	launched := ValidateRunnerLaunched(t, clients, result.StackName(), startTime)
	assert.True(t, launched, "Runner instance should have been launched for stack %s", result.StackName())

	// 6. Extract boot timings from job logs
	jobLogs := FetchJobLogs(t, client, testRepo, runID)
	for jobName, logText := range jobLogs {
		if bt := ParseBootTimings(logText); bt != nil {
			t.Logf("Job %q: total=%.2fs, agent-booting-at=%.2fs",
				jobName, bt.TotalDuration, bt.AgentBootingTotal)
		}
	}

	// 7. Validate roc against the deployed stack and a real workflow job.
	rocPath := buildRocBinary(t)
	selectedJob := selectRunsOnWorkflowJob(t, client, testRepo, runID)
	selectedJobID := fmt.Sprintf("%d", selectedJob.GetID())
	selectedJobURL := selectedJob.GetHTMLURL()
	require.NotEmpty(t, selectedJobURL, "Selected workflow job should include a GitHub Actions job URL")
	sinceArg := sinceArgFromStart(startTime)

	doctorOutput := waitForROCCheck(t, 2*time.Minute, 10*time.Second, func() (string, error) {
		return runROCCommand(t, rocPath, result.StackName(), 2*time.Minute, "stack", "doctor", "--since", sinceArg)
	}, func(output string) error {
		archivePath := extractDoctorArchivePath(output)
		if archivePath == "" {
			return fmt.Errorf("doctor output did not contain archive path")
		}

		result, files := readDoctorArchive(t, archivePath)
		applicationLog, ok := files["logs/application.log"]
		if !ok {
			return fmt.Errorf("doctor archive did not contain logs/application.log")
		}
		if strings.TrimSpace(applicationLog) == "" {
			return fmt.Errorf("doctor archive contained an empty application log")
		}

		requiredChecks := map[string]bool{
			"Service running":             false,
			"Service endpoint accessible": false,
			"Service readiness":           false,
			"Application logs fetched":    false,
		}
		for _, check := range result.Checks {
			if _, ok := requiredChecks[check.Name]; !ok {
				continue
			}
			if check.Status != "✅" {
				return fmt.Errorf("doctor check %q was %s", check.Name, check.Status)
			}
			requiredChecks[check.Name] = true
		}
		for name, seen := range requiredChecks {
			if !seen {
				return fmt.Errorf("doctor archive missing check %q", name)
			}
		}
		return nil
	})
	t.Logf("roc stack doctor output:\n%s", doctorOutput)

	stackLogsOutput := waitForROCCheck(t, 2*time.Minute, 10*time.Second, func() (string, error) {
		return runROCCommand(t, rocPath, result.StackName(), 2*time.Minute, "stack", "logs", "--since", sinceArg, "--no-color")
	}, func(output string) error {
		if !strings.Contains(output, "flexd/") {
			return fmt.Errorf("stack logs did not include ECS application log streams")
		}
		if !strings.Contains(output, fmt.Sprintf("\"run_id\":%d", runID)) {
			return fmt.Errorf("stack logs did not include the workflow run ID %d", runID)
		}
		return nil
	})
	t.Logf("roc stack logs output:\n%s", stackLogsOutput)

	jobLogsOutput := waitForROCCheck(t, 2*time.Minute, 10*time.Second, func() (string, error) {
		return runROCCommand(t, rocPath, result.StackName(), 2*time.Minute, "logs", selectedJobURL, "--no-color")
	}, func(output string) error {
		if !strings.Contains(output, "flexd/") {
			return fmt.Errorf("job logs did not include application log streams")
		}
		if !strings.Contains(output, selectedJobID) {
			return fmt.Errorf("job logs did not include selected job ID %s", selectedJobID)
		}
		if !regexp.MustCompile(`\[(i-[^]/]+/)`).MatchString(output) {
			return fmt.Errorf("job logs did not include EC2 instance log streams")
		}
		return nil
	})
	t.Logf("roc logs %s output:\n%s", selectedJobID, jobLogsOutput)

	t.Logf("Integration test passed! Runner successfully processed workflow job.")
}
