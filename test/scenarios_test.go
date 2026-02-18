package test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestScenarioBasic tests the basic deployment scenario with all validations.
func TestScenarioBasic(t *testing.T) {
	cfg := DefaultScenarioConfig()

	runScenario(t, cfg, func(t *testing.T, r ScenarioResult) {
		clients := NewAWSClients(context.Background())

		runOutputValidations(t, r)
		runSecurityValidations(t, clients, r)
		runComplianceValidations(t, clients, r)
		runWiringValidations(t, clients, r)
		runTaggingValidations(t, clients, r)
		runAdvancedValidations(t, r)

		t.Run("Functional", func(t *testing.T) {
			runFunctionalValidations(t, clients, r)
		})

		runIntegrationTest(t, clients, r)

		fmt.Printf("\nBasic scenario deployment successful!\n")
		fmt.Printf("   Stack: %s\n", r.StackName())
		fmt.Printf("   App Runner: %s\n", r.AppRunnerURL())
	})
}

// TestScenarioFullFeatured tests full-featured scenario with all options (NAT + EFS + ECR).
func TestScenarioFullFeatured(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping expensive full-featured test (requires NAT + EFS + ECR)")
	}

	cfg := DefaultScenarioConfig()
	cfg.EnableNAT = true
	cfg.EnableEFS = true
	cfg.EnableECR = true

	runScenario(t, cfg, func(t *testing.T, r ScenarioResult) {
		clients := NewAWSClients(context.Background())

		runOutputValidations(t, r)
		runSecurityValidations(t, clients, r)
		runComplianceValidations(t, clients, r)
		runWiringValidations(t, clients, r)
		runTaggingValidations(t, clients, r)
		runAdvancedValidations(t, r)

		t.Run("Functional", func(t *testing.T) {
			runFunctionalValidations(t, clients, r)
		})

		runIntegrationTest(t, clients, r)

		fmt.Printf("\nFull-featured deployment successful!\n")
		fmt.Printf("   Stack: %s\n", r.StackName())
		fmt.Printf("   App Runner: %s\n", r.AppRunnerURL())
		fmt.Printf("   EFS: %s\n", r.EFSFileSystemID())
		fmt.Printf("   ECR: %s\n", r.ECRURL())
	})
}

// runIntegrationTest runs the observer-mode integration test if env vars are set.
func runIntegrationTest(t *testing.T, clients *AWSClients, r ScenarioResult) {
	t.Run("Integration/JobExecution", func(t *testing.T) {
		if os.Getenv("GITHUB_TOKEN") == "" {
			t.Skip("GITHUB_TOKEN not set")
		}

		testRepo := os.Getenv("RUNS_ON_TEST_REPO")
		if testRepo == "" {
			testRepo = os.Getenv("GITHUB_REPOSITORY")
		}
		if testRepo == "" {
			t.Skip("RUNS_ON_TEST_REPO or GITHUB_REPOSITORY not set")
		}

		testWorkflow := os.Getenv("RUNS_ON_TEST_WORKFLOW")
		if testWorkflow == "" {
			t.Skip("RUNS_ON_TEST_WORKFLOW not set")
		}

		testID := GetTestID()
		startTime := time.Now()

		ValidateAppRunnerHealth(t, r.AppRunnerURL(), 20)

		t.Log("=======================================================")
		t.Log("INTEGRATION TEST - OBSERVER MODE")
		t.Log("=======================================================")
		t.Logf("App Runner URL: https://%s", r.AppRunnerURL())
		t.Logf("Test Repo: %s", testRepo)
		t.Logf("Workflow: %s", testWorkflow)
		t.Log("")
		t.Log("Steps:")
		t.Log("  1. Register RunsOn app at the URL above")
		t.Log("  2. Trigger a workflow_dispatch run for the workflow above")
		t.Log("  3. Test will detect the run and monitor to completion")
		t.Log("")
		t.Logf("To abort: touch /tmp/runson-%s-abort", testID)
		t.Log("=======================================================")

		runID, err := WatchForWorkflowRun(t, testRepo, testWorkflow, testID, startTime, 15*time.Minute)
		require.NoError(t, err, "Workflow run not found")

		err = MonitorWorkflowJobStates(t, testRepo, runID, 3*time.Minute)
		require.NoError(t, err, "Job stuck in queue - is the RunsOn app registered?")

		conclusion := WaitForWorkflowCompletion(t, testRepo, runID, 10*time.Minute)
		assert.Equal(t, "success", conclusion, "Workflow should succeed")

		launched := ValidateRunnerLaunched(t, clients, r.StackName(), startTime)
		assert.True(t, launched, "Runner instance should have been launched")
	})
}
