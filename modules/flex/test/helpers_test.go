package test

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"testing"
	"time"

	"github.com/google/go-github/v84/github"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

func TestGetTestIDUsesPerJobSuffixInCI(t *testing.T) {
	t.Setenv("GITHUB_RUN_ID", "24502906202")
	t.Setenv("GITHUB_RUN_ATTEMPT", "1")
	t.Setenv("GITHUB_JOB", "terraform-deploy-smoke")
	smokeID := GetTestID()

	t.Setenv("GITHUB_JOB", "terraform-integration-e2e")
	integrationID := GetTestID()

	if smokeID == integrationID {
		t.Fatalf("GetTestID() produced the same id for different jobs: %q", smokeID)
	}
}

func TestGetTestIDLocalFormat(t *testing.T) {
	t.Setenv("GITHUB_RUN_ID", "")
	t.Setenv("GITHUB_RUN_ATTEMPT", "")
	t.Setenv("GITHUB_JOB", "")

	id := GetTestID()
	if !regexp.MustCompile(`^\d+-[0-9a-f]{8}$`).MatchString(id) {
		t.Fatalf("GetTestID() = %q, want unix-seconds plus 8 hex digits", id)
	}
}

func TestDefaultScenarioConfigSetsStableCleanupTags(t *testing.T) {
	t.Setenv("GITHUB_RUN_ID", "24502906202")
	t.Setenv("GITHUB_RUN_ATTEMPT", "2")
	t.Setenv("GITHUB_JOB", "terraform-deploy-smoke")

	cfg := DefaultScenarioConfig()
	tags := cfg.TestTags()

	if tags["CreatedAt"] == "" {
		t.Fatal("expected CreatedAt tag")
	}
	if tags["GithubRunId"] != "24502906202" {
		t.Fatalf("GithubRunId = %q", tags["GithubRunId"])
	}
	if tags["GithubRunAttempt"] != "2" {
		t.Fatalf("GithubRunAttempt = %q", tags["GithubRunAttempt"])
	}
	if tags["GithubJob"] != "terraform-deploy-smoke" {
		t.Fatalf("GithubJob = %q", tags["GithubJob"])
	}
}

func TestRepoRootForTestsFindsMonorepoRoot(t *testing.T) {
	repoRoot := repoRootForTests(t)

	if _, err := os.Stat(filepath.Join(repoRoot, "terraform", "modules", "flex", "test")); err != nil {
		t.Fatalf("repoRootForTests() = %q, missing terraform test directory: %v", repoRoot, err)
	}
}

func TestWorkflowRunMatchesSuccessfulIntegrationRun(t *testing.T) {
	startTime := time.Date(2026, 4, 27, 19, 19, 24, 0, time.UTC)
	run := workflowRunFixture(startTime.Add(2*time.Minute), ".github/workflows/terraform-integration-runner.yml")

	if !workflowRunMatches(run, "terraform-integration-runner.yml", "test-25014300664-e564af50", "main", startTime) {
		t.Fatal("expected workflow run to match")
	}
}

func TestWorkflowRunMatchesIgnoresOldRuns(t *testing.T) {
	startTime := time.Date(2026, 4, 27, 19, 19, 24, 0, time.UTC)
	run := workflowRunFixture(startTime.Add(-3*time.Minute), ".github/workflows/terraform-integration-runner.yml")

	if workflowRunMatches(run, "terraform-integration-runner.yml", "test-25014300664-e564af50", "main", startTime) {
		t.Fatal("expected old workflow run to be ignored")
	}
}

func TestWorkflowRunMatchesIgnoresWrongWorkflowPath(t *testing.T) {
	startTime := time.Date(2026, 4, 27, 19, 19, 24, 0, time.UTC)
	run := workflowRunFixture(startTime.Add(time.Minute), ".github/workflows/e2e-test.yml")

	if workflowRunMatches(run, "terraform-integration-runner.yml", "test-25014300664-e564af50", "main", startTime) {
		t.Fatal("expected wrong workflow path to be ignored")
	}
}

func TestWorkflowRunMatchesIgnoresWrongStackEnv(t *testing.T) {
	startTime := time.Date(2026, 4, 27, 19, 19, 24, 0, time.UTC)
	run := workflowRunFixture(startTime.Add(time.Minute), ".github/workflows/terraform-integration-runner.yml")

	if workflowRunMatches(run, "terraform-integration-runner.yml", "test-other", "main", startTime) {
		t.Fatal("expected wrong stack env to be ignored")
	}
}

func TestWorkflowIdentifierMatchesBasenameAndFullPath(t *testing.T) {
	if !workflowIdentifierMatches(".github/workflows/terraform-integration-runner.yml", "terraform-integration-runner.yml") {
		t.Fatal("expected full workflow path to match basename")
	}
	if !workflowIdentifierMatches("terraform-integration-runner.yml", ".github/workflows/terraform-integration-runner.yml") {
		t.Fatal("expected basename to match full workflow path")
	}
}

func TestQuietTerraformOptionsInCIClonesAndDiscardsLogger(t *testing.T) {
	t.Setenv("GITHUB_ACTIONS", "true")

	original := &terraform.Options{TerraformDir: "test-dir", TerraformBinary: "tofu"}
	quiet := quietTerraformOptionsInCI(t, original)

	if quiet == original {
		t.Fatal("expected quiet options to be cloned")
	}
	if quiet.Logger != logger.Discard {
		t.Fatal("expected quiet options to discard Terratest logs")
	}
	if original.Logger != nil {
		t.Fatal("expected original options to remain unmodified")
	}
}

func TestRunnerLaunchValidationStatesIncludeFastShutdownStates(t *testing.T) {
	states := runnerLaunchValidationStates()

	for _, state := range []string{"running", "shutting-down", "terminated", "stopping", "stopped"} {
		if !slices.Contains(states, state) {
			t.Fatalf("expected runner launch validation states to include %q, got %v", state, states)
		}
	}
}

func workflowRunFixture(createdAt time.Time, path string) *github.WorkflowRun {
	return &github.WorkflowRun{
		ID:           new(int64(25014815906)),
		Name:         new("Terraform / Integration Runner"),
		Path:         new(path),
		Event:        new("workflow_dispatch"),
		DisplayTitle: new("Terraform / Integration Runner (test-25014300664-e564af50)"),
		HeadBranch:   new("main"),
		HeadSHA:      new("e1aae998eb2dc74b5ac3dcfdb0804899f0c14f97"),
		HTMLURL:      new("https://github.com/runs-on/server/actions/runs/25014815906"),
		CreatedAt:    &github.Timestamp{Time: createdAt},
		Status:       new("completed"),
		Conclusion:   new("success"),
	}
}
