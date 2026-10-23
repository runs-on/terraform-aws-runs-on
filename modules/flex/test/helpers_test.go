package test

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"testing"
	"time"

	"github.com/google/go-github/v88/github"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/runs-on/terraform-aws-runs-on/modules/flex/test/internal/validationimage"
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

// The janitor's run-scoped cleanup (tools/terratest-janitor) parses this
// layout to find the stacks of one CI job.
func TestTerratestStateKeyScopesCIStacksToTheirJob(t *testing.T) {
	t.Setenv("GITHUB_RUN_ID", "24502906202")
	t.Setenv("GITHUB_JOB", "terraform-deploy-smoke")
	if got, want := terratestStateKey("test-24502906202-82a60efe", "module"), "terratest/24502906202/terraform-deploy-smoke/test-24502906202-82a60efe/module.tfstate"; got != want {
		t.Errorf("CI key = %q, want %q", got, want)
	}

	t.Setenv("GITHUB_RUN_ID", "")
	t.Setenv("GITHUB_JOB", "")
	if got, want := terratestStateKey("test-1776289229-0a1b2c3d", "vpc"), "terratest/local/test-1776289229-0a1b2c3d/vpc.tfstate"; got != want {
		t.Errorf("local key = %q, want %q", got, want)
	}
}

func TestModuleVarsIncludeReferencedECRPullThroughCacheRules(t *testing.T) {
	cfg := DefaultScenarioConfig()
	cfg.ECRPullThroughCacheRules = map[string]map[string]string{
		"docker_hub": {
			"ecr_repository_prefix":      "docker-hub",
			"upstream_registry_url":      "registry-1.docker.io",
			"upstream_repository_prefix": "",
		},
	}

	vars := cfg.ToModuleVars("vpc-123", []string{"subnet-public"}, nil)
	rules, ok := vars["ecr_pull_through_cache_rules"].(map[string]map[string]string)
	if !ok {
		t.Fatalf("ecr_pull_through_cache_rules = %#v, want rule map", vars["ecr_pull_through_cache_rules"])
	}
	if got := rules["docker_hub"]["ecr_repository_prefix"]; got != "docker-hub" {
		t.Fatalf("docker_hub prefix = %q, want docker-hub", got)
	}
}

func TestGetGithubOrgPrefersExplicitOrg(t *testing.T) {
	t.Setenv("GITHUB_ORG", "explicit-org")
	t.Setenv("RUNS_ON_TEST_REPO", "runs-on/monorepo")

	if got := getGithubOrg(); got != "explicit-org" {
		t.Fatalf("getGithubOrg() = %q, want explicit-org", got)
	}
}

func TestGetGithubOrgFallsBackToTestRepoOwner(t *testing.T) {
	t.Setenv("GITHUB_ORG", "")
	t.Setenv("RUNS_ON_TEST_REPO", "runs-on/monorepo")

	if got := getGithubOrg(); got != "runs-on" {
		t.Fatalf("getGithubOrg() = %q, want runs-on", got)
	}
}

func TestGetGithubOrgMissingSourceReturnsEmpty(t *testing.T) {
	t.Setenv("GITHUB_ORG", "")
	t.Setenv("RUNS_ON_TEST_REPO", "")

	if got := getGithubOrg(); got != "" {
		t.Fatalf("getGithubOrg() = %q, want empty", got)
	}
}

func TestRequiredValidationEnvRequiresGithubOrgSource(t *testing.T) {
	t.Setenv("GITHUB_ORG", "")
	t.Setenv("RUNS_ON_TEST_REPO", "")

	required, err := requiredValidationEnvVars("basic", validationimage.EnvModeDirect)
	if err != nil {
		t.Fatalf("requiredValidationEnvVars() error = %v", err)
	}

	missing := validationimage.MissingEnvVars(required, os.Getenv)
	if !slices.Contains(missing, "GITHUB_ORG or RUNS_ON_TEST_REPO") {
		t.Fatalf("missing env vars = %#v, want GITHUB_ORG or RUNS_ON_TEST_REPO", missing)
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
