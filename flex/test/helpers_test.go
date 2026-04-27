package test

import (
	"regexp"
	"testing"
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
